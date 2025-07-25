// Copyright (c) 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/p3a/message_manager.h"

#include <memory>
#include <optional>
#include <string_view>
#include <vector>

#include "base/i18n/time_formatting.h"
#include "base/json/values_util.h"
#include "base/notreached.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/test/bind.h"
#include "base/test/scoped_feature_list.h"
#include "base/test/values_test_util.h"
#include "base/time/time.h"
#include "brave/components/p3a/features.h"
#include "brave/components/p3a/metric_config_utils.h"
#include "brave/components/p3a/metric_log_type.h"
#include "brave/components/p3a/metric_names.h"
#include "brave/components/p3a/p3a_config.h"
#include "brave/components/p3a/p3a_message.h"
#include "brave/components/p3a/p3a_service.h"
#include "brave/components/p3a/pref_names.h"
#include "brave/components/p3a/star_randomness_test_util.h"
#include "components/prefs/scoped_user_pref_update.h"
#include "components/prefs/testing_pref_service.h"
#include "content/public/test/browser_task_environment.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/weak_wrapper_shared_url_loader_factory.h"
#include "services/network/test/test_url_loader_factory.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace p3a {

namespace {

constexpr uint8_t kInitialEpoch = 2;
constexpr size_t kUploadIntervalSeconds = 120;
constexpr base::TimeDelta kEpochLenTimeDelta = base::Days(4);
constexpr char kTestStarRandomnessHost[] = "https://localhost:9443";
constexpr char kTestStarUploadHost[] = "https://localhost:10443";

}  // namespace

class P3AMessageManagerTest : public testing::Test,
                              public MessageManager::Delegate {
 public:
  P3AMessageManagerTest()
      : task_environment_(base::test::TaskEnvironment::TimeSource::MOCK_TIME),
        shared_url_loader_factory_(
            base::MakeRefCounted<network::WeakWrapperSharedURLLoaderFactory>(
                &url_loader_factory_)) {}

  void SetUp() override {
    scoped_feature_list_.InitWithFeatures(
        {features::kConstellationEnclaveAttestation}, {});
    base::Time future_mock_time;
    if (base::Time::FromString("2050-01-04", &future_mock_time)) {
      task_environment_.AdvanceClock(future_mock_time - base::Time::Now());
    }
  }

  std::optional<MetricLogType> GetDynamicMetricLogType(
      std::string_view histogram_name) const override {
    return std::nullopt;
  }

  const MetricConfig* GetMetricConfig(
      std::string_view histogram_name) const override {
    return GetBaseMetricConfig(histogram_name);
  }

  std::optional<MetricLogType> GetLogTypeForHistogram(
      std::string_view histogram_name) const override {
    return GetBaseLogTypeForHistogram(histogram_name);
  }

  void OnRotation(MetricLogType log_type) override {}

  void OnMetricCycled(const std::string& histogram_name) override {}

 protected:
  void SetUpManager() {
    p3a_config_.disable_star_attestation = true;
    p3a_config_.star_randomness_host = kTestStarRandomnessHost;
    p3a_config_.randomize_upload_interval = false;
    p3a_config_.average_upload_interval = base::Seconds(kUploadIntervalSeconds);
    p3a_config_.p3a_constellation_upload_host = kTestStarUploadHost;

    local_state_ = std::make_unique<TestingPrefServiceSimple>();
    P3AService::RegisterPrefs(local_state_->registry(), true);

    current_epoch_ = 0;
    next_epoch_time_ = base::Time::Now() + kEpochLenTimeDelta;

    url_loader_factory_.SetInterceptor(base::BindLambdaForTesting(
        [&](const network::ResourceRequest& request) {
          url_loader_factory_.ClearResponses();

          std::string response = "{}";

          if (request.url.spec().starts_with(kTestStarRandomnessHost)) {
            MetricLogType log_type = ValidateURLAndGetMetricLogType(
                request.url, kTestStarRandomnessHost);

            if (interceptor_invalid_response_from_randomness_) {
              // next epoch time is missing!
              response = base::StrCat(
                  {"{\"currentEpoch\":", base::NumberToString(current_epoch_),
                   "}"});
            } else if (interceptor_invalid_response_from_randomness_non_json_) {
              response = "invalid response that is not json";
            } else if (request.url.spec().ends_with("/info")) {
              EXPECT_EQ(request.method, net::HttpRequestHeaders::kGetMethod);
              std::string next_epoch_time_str =
                  TimeFormatAsIso8601(next_epoch_time_);
              response = HandleInfoRequest(request, log_type, current_epoch_,
                                           next_epoch_time_str.c_str());
              info_request_made_[log_type] = true;
            } else if (request.url.spec().ends_with("/randomness")) {
              response = HandleRandomnessRequest(request, current_epoch_);
              url_loader_factory_.AddResponse(
                  request.url.spec(), response,
                  interceptor_status_code_from_randomness_);

              points_requests_made_[log_type]++;
            }
            url_loader_factory_.AddResponse(
                request.url.spec(), response,
                interceptor_status_code_from_randomness_);
            return;
          } else if (request.url.spec().starts_with(
                         std::string(kTestStarUploadHost))) {
            std::string log_type_str = request.url.path();
            EXPECT_TRUE(base::TrimString(log_type_str, "/", &log_type_str));
            std::optional<MetricLogType> log_type =
                StringToMetricLogType(log_type_str);
            EXPECT_TRUE(log_type.has_value());

            EXPECT_EQ(request.method, net::HttpRequestHeaders::kPostMethod);
            std::string message = std::string(ExtractBodyFromRequest(request));
            EXPECT_EQ(p3a_constellation_sent_messages_[*log_type].find(message),
                      p3a_constellation_sent_messages_[*log_type].end());
            p3a_constellation_sent_messages_[*log_type].insert(message);
          }
          url_loader_factory_.AddResponse(request.url.spec(), response);
        }));

    CreateAndStartManager();
  }

  void CreateAndStartManager() {
    base::Time install_time;
    ASSERT_TRUE(base::Time::FromString("2099-01-01", &install_time));
    message_manager_ = std::make_unique<MessageManager>(
        *local_state_, &p3a_config_, *this, "release", install_time);

    message_manager_->Start(shared_url_loader_factory_);

    task_environment_.RunUntilIdle();
  }

  void ResetInterceptorStores() {
    p3a_constellation_sent_messages_.clear();
    info_request_made_.clear();
    points_requests_made_.clear();
  }

  std::vector<std::string> GetTestHistogramNames(MetricLogType log_type,
                                                 size_t p3a_count) {
    auto histograms_begin = kCollectedExpressHistograms.cbegin();
    auto histograms_end = kCollectedExpressHistograms.cend();
    std::vector<std::string> result;
    size_t p3a_i = 0;
    switch (log_type) {
      case MetricLogType::kExpress:
        histograms_begin = kCollectedExpressHistograms.cbegin();
        histograms_end = kCollectedExpressHistograms.cend();
        break;
      case MetricLogType::kSlow:
        histograms_begin = kCollectedSlowHistograms.cbegin();
        histograms_end = kCollectedSlowHistograms.cend();
        break;
      case MetricLogType::kTypical:
        histograms_begin = kCollectedTypicalHistograms.cbegin();
        histograms_end = kCollectedTypicalHistograms.cend();
        break;
      default:
        NOTREACHED();
    }
    for (auto histogram_i = histograms_begin; histogram_i != histograms_end;
         histogram_i++) {
      if (p3a_i < p3a_count && (histogram_i->first.starts_with("Brave.Core") ||
                                log_type == MetricLogType::kExpress)) {
        result.push_back(std::string(histogram_i->first));
        p3a_i++;
      }

      if (p3a_i >= p3a_count) {
        break;
      }
    }
    return result;
  }

  content::BrowserTaskEnvironment task_environment_;
  base::test::ScopedFeatureList scoped_feature_list_;
  network::TestURLLoaderFactory url_loader_factory_;
  scoped_refptr<network::SharedURLLoaderFactory> shared_url_loader_factory_;
  P3AConfig p3a_config_;
  std::unique_ptr<MessageManager> message_manager_;
  std::unique_ptr<TestingPrefServiceSimple> local_state_;

  base::flat_map<MetricLogType, base::flat_set<std::string>>
      p3a_constellation_sent_messages_;

  bool interceptor_invalid_response_from_randomness_ = false;
  bool interceptor_invalid_response_from_randomness_non_json_ = false;
  net::HttpStatusCode interceptor_status_code_from_randomness_ = net::HTTP_OK;

  base::flat_map<MetricLogType, bool> info_request_made_;
  base::flat_map<MetricLogType, size_t> points_requests_made_;

  uint8_t current_epoch_ = kInitialEpoch;
  base::Time next_epoch_time_;

 private:
  std::string_view ExtractBodyFromRequest(
      const network::ResourceRequest& request) {
    return request.request_body->elements()
        ->at(0)
        .As<network::DataElementBytes>()
        .AsStringPiece();
  }
};

TEST_F(P3AMessageManagerTest, UpdateLogsAndSendConstellation) {
  for (MetricLogType log_type : kAllMetricLogTypes) {
    ResetInterceptorStores();
    SetUpManager();
    ASSERT_TRUE(info_request_made_[log_type]);

    std::vector<std::string> test_histograms =
        GetTestHistogramNames(log_type, 3);

    for (size_t i = 0; i < test_histograms.size(); i++) {
      message_manager_->UpdateMetricValue(test_histograms[i], i + 1);
    }

    task_environment_.FastForwardBy(
        base::Seconds(kUploadIntervalSeconds * 100));

    EXPECT_EQ(points_requests_made_[log_type], 3U);
    EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 3U);

    ResetInterceptorStores();
    current_epoch_++;
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(
        kEpochLenTimeDelta + base::Seconds(kUploadIntervalSeconds * 100));

    ASSERT_TRUE(info_request_made_[log_type]);
    if (log_type != MetricLogType::kExpress) {
      // We can only check non-express metrics, since there are very little
      // non-ephemeral metrics for the express cadence.
      EXPECT_EQ(points_requests_made_[log_type], 3U);
      EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 3U);
    }

    ResetInterceptorStores();
    current_epoch_++;
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(
        kEpochLenTimeDelta + base::Seconds(kUploadIntervalSeconds * 100));

    ASSERT_TRUE(info_request_made_[log_type]);
    if (log_type != MetricLogType::kExpress) {
      // We can only check non-express metrics, since there are very little
      // non-ephemeral metrics for the express cadence.
      EXPECT_EQ(points_requests_made_[log_type], 3U);
      EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 3U);
    }
  }
}

TEST_F(P3AMessageManagerTest, UpdateLogsAndSendConstellationInvalidResponse) {
  for (MetricLogType log_type : kAllMetricLogTypes) {
    ResetInterceptorStores();
    SetUpManager();
    ASSERT_TRUE(info_request_made_[log_type]);

    std::vector<std::string> test_histograms =
        GetTestHistogramNames(log_type, 3);

    for (size_t i = 0; i < test_histograms.size(); i++) {
      message_manager_->UpdateMetricValue(test_histograms[i], i + 1);
    }

    task_environment_.FastForwardBy(
        base::Seconds(kUploadIntervalSeconds * 100));
    EXPECT_EQ(points_requests_made_[log_type], 3U);
    ResetInterceptorStores();

    // server will return invalid response body that is json, but has missing
    // fields
    interceptor_invalid_response_from_randomness_ = true;

    if (log_type != MetricLogType::kSlow) {
      // skip ahead to next epoch, only if log type is not slow
      // (because the max epoch rotation for slow is only 2 epochs)
      current_epoch_++;
    }
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(kEpochLenTimeDelta);

    EXPECT_EQ(points_requests_made_[log_type], 0U);
    // We are at the beginning of the new epoch. measurements from previous
    // epoch should not be sent since we are unable to get the current epoch
    // from the server.
    EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 0U);

    // server will return response body that is not json
    interceptor_invalid_response_from_randomness_ = false;
    interceptor_invalid_response_from_randomness_non_json_ = true;

    if (log_type != MetricLogType::kSlow) {
      // skip ahead to next epoch, only if log type is not slow
      // (because the max epoch rotation for slow is only 2 epochs)
      current_epoch_++;
    }
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(kEpochLenTimeDelta);

    EXPECT_EQ(points_requests_made_[log_type], 0U);
    // no new measurements should have been recorded in the previous epoch.
    EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 0U);

    // restore randomness server functionality
    interceptor_invalid_response_from_randomness_non_json_ = false;

    current_epoch_++;
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(kEpochLenTimeDelta);

    // randomness server is now providing correct response . no new measurements
    // should have been recorded in the previous epoch due to previous
    // unavailability. randomness points should be requested for the current
    // epoch. messages from the first epoch should be sent.
    ASSERT_TRUE(info_request_made_[log_type]);
    if (log_type != MetricLogType::kExpress) {
      // We can only check non-express metrics, since there are very little
      // non-ephemeral metrics for the express cadence.
      EXPECT_EQ(points_requests_made_[log_type], 3U);
      EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 3U);
    }
  }
}

TEST_F(P3AMessageManagerTest,
       UpdateLogsAndSendConstellationInvalidClientRequest) {
  for (MetricLogType log_type : kAllMetricLogTypes) {
    ResetInterceptorStores();
    SetUpManager();
    ASSERT_TRUE(info_request_made_[log_type]);

    std::vector<std::string> test_histograms =
        GetTestHistogramNames(log_type, 3);

    for (size_t i = 0; i < test_histograms.size(); i++) {
      message_manager_->UpdateMetricValue(test_histograms[i], i + 1);
    }

    task_environment_.FastForwardBy(
        base::Seconds(kUploadIntervalSeconds * 100));
    ResetInterceptorStores();

    // server will return HTTP 500 to indicate an invalid client request.
    interceptor_status_code_from_randomness_ = net::HTTP_BAD_REQUEST;

    // skip ahead to next epoch
    if (log_type != MetricLogType::kSlow) {
      // skip ahead to next epoch, only if log type is not slow
      // (because the max epoch rotation for slow is only 2 epochs)
      current_epoch_++;
    }
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(kEpochLenTimeDelta);

    // We are at the beginning of the new epoch. measurements from previous
    // epoch should not be sent since we are unable to get the current epoch
    // from the server.
    EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 0U);

    // restore randomness server functionality
    interceptor_status_code_from_randomness_ = net::HTTP_OK;

    current_epoch_++;
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(kEpochLenTimeDelta);

    // randomness server is now accepting client request. no new measurements
    // should have been recorded in the previous epoch due to previous
    // unavailability. randomness points should be requested for the current
    // epoch. messages from the first epoch should be sent.
    ASSERT_TRUE(info_request_made_[log_type]);
    if (log_type != MetricLogType::kExpress) {
      // We can only check non-express metrics, since there are very little
      // non-ephemeral metrics for the express cadence.
      EXPECT_EQ(points_requests_made_[log_type], 3U);
      EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 3U);
    }
  }
}

TEST_F(P3AMessageManagerTest, UpdateLogsAndSendConstellationUnavailable) {
  for (MetricLogType log_type : kAllMetricLogTypes) {
    interceptor_status_code_from_randomness_ = net::HTTP_OK;
    ResetInterceptorStores();
    SetUpManager();
    ASSERT_TRUE(info_request_made_[log_type]);

    std::vector<std::string> test_histograms =
        GetTestHistogramNames(log_type, 3);

    for (size_t i = 0; i < test_histograms.size(); i++) {
      message_manager_->UpdateMetricValue(test_histograms[i], i + 1);
    }

    task_environment_.FastForwardBy(
        base::Seconds(kUploadIntervalSeconds * 100));
    ResetInterceptorStores();

    // server will return HTTP 500 to indicate unavailability.
    interceptor_status_code_from_randomness_ = net::HTTP_INTERNAL_SERVER_ERROR;

    if (log_type != MetricLogType::kSlow) {
      // skip ahead to next epoch, only if log type is not slow
      // (because the max epoch rotation for slow is only 2 epochs)
      current_epoch_++;
    }
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(kEpochLenTimeDelta);

    // We are at the beginning of the new epoch. measurements from previous
    // epoch should not be sent since we are unable to get the current epoch
    // from the server.
    EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 0U);

    // restore randomness server functionality
    interceptor_status_code_from_randomness_ = net::HTTP_OK;

    ResetInterceptorStores();
    current_epoch_++;
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(kEpochLenTimeDelta);

    // randomness server is now available. no new measurements should have been
    // recorded in the previous epoch due to previous unavailability.
    // randomness points should be requested for the current epoch.
    // messages from the first epoch should be sent.
    ASSERT_TRUE(info_request_made_[log_type]);
    if (log_type != MetricLogType::kExpress) {
      // We can only check non-express metrics, since there are very little
      // non-ephemeral metrics for the express cadence.
      EXPECT_EQ(points_requests_made_[log_type], 3U);
      EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 3U);
    }
  }
}

TEST_F(P3AMessageManagerTest, DoesNotSendRemovedMetricValue) {
  SetUpManager();
  for (MetricLogType log_type : kAllMetricLogTypes) {
    std::vector<std::string> test_histograms =
        GetTestHistogramNames(log_type, 3);

    for (const std::string& histogram_name : test_histograms) {
      message_manager_->UpdateMetricValue(histogram_name, 5);
    }

    for (const std::string& histogram_name : test_histograms) {
      message_manager_->RemoveMetricValue(histogram_name);
    }

    task_environment_.FastForwardBy(
        base::Seconds(kUploadIntervalSeconds * 100));

    EXPECT_EQ(points_requests_made_[log_type], 0U);

    current_epoch_++;
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(
        kEpochLenTimeDelta + base::Seconds(kUploadIntervalSeconds * 100));

    EXPECT_EQ(points_requests_made_[log_type], 0U);
    EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 0U);
  }
}

TEST_F(P3AMessageManagerTest, ShouldNotSendIfDisabled) {
  SetUpManager();
  for (MetricLogType log_type : kAllMetricLogTypes) {
    std::vector<std::string> test_histograms =
        GetTestHistogramNames(log_type, 3);

    for (const std::string& histogram_name : test_histograms) {
      message_manager_->UpdateMetricValue(histogram_name, 5);
    }

    local_state_->SetBoolean(kP3AEnabled, false);
    message_manager_->Stop();

    task_environment_.FastForwardBy(
        base::Seconds(kUploadIntervalSeconds * 100));

    EXPECT_EQ(points_requests_made_[log_type], 0U);
    EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 0U);

    current_epoch_++;
    next_epoch_time_ += kEpochLenTimeDelta;
    task_environment_.FastForwardBy(
        kEpochLenTimeDelta + base::Seconds(kUploadIntervalSeconds * 100));

    EXPECT_EQ(points_requests_made_[log_type], 0U);
    EXPECT_EQ(p3a_constellation_sent_messages_[log_type].size(), 0U);
  }
}

TEST_F(P3AMessageManagerTest, ShouldNotSendIfStopped) {
  SetUpManager();

  message_manager_->Stop();

  task_environment_.FastForwardBy(base::Seconds(kUploadIntervalSeconds * 100));

  EXPECT_TRUE(points_requests_made_.empty());
  EXPECT_TRUE(p3a_constellation_sent_messages_.empty());
}

TEST_F(P3AMessageManagerTest, ActivationDate) {
  SetUpManager();

  MessageMetainfo meta;
  meta.Init(local_state_.get(), "release", base::Time::Now() - base::Days(7));

  std::string_view activation_metric;
  std::string_view non_activation_metric;
  for (const auto& [histogram_name, config] : kCollectedExpressHistograms) {
    if (config && config->record_activation_date) {
      activation_metric = histogram_name;
    } else if (base::StartsWith(histogram_name, "Brave")) {
      non_activation_metric = histogram_name;
    }
  }
  auto activation_date = meta.GetActivationDate(activation_metric);
  auto non_activation_date = meta.GetActivationDate(activation_metric);
  EXPECT_FALSE(activation_date);
  EXPECT_FALSE(non_activation_date);

  auto ref_time = base::Time::Now();

  message_manager_->UpdateMetricValue(activation_metric, 0);
  activation_date = meta.GetActivationDate(activation_metric);
  ASSERT_FALSE(activation_date);

  message_manager_->UpdateMetricValue(activation_metric, 1);

  activation_date = meta.GetActivationDate(activation_metric);
  ASSERT_TRUE(activation_date);
  EXPECT_GE(*activation_date, ref_time);
  EXPECT_LT(*activation_date, ref_time + base::Seconds(30));

  message_manager_->UpdateMetricValue(non_activation_metric, 1);
  activation_date = meta.GetActivationDate(non_activation_metric);
  EXPECT_FALSE(activation_date);

  task_environment_.FastForwardBy(base::Minutes(30));

  message_manager_->UpdateMetricValue(activation_metric, 1);

  // checking activation date to ensure that it did not get updated
  activation_date = meta.GetActivationDate(activation_metric);
  ASSERT_TRUE(activation_date);
  EXPECT_GE(*activation_date, ref_time);
  EXPECT_LT(*activation_date, ref_time + base::Seconds(30));

  CreateAndStartManager();
  // ensure date was not cleared after resetting manager
  activation_date = meta.GetActivationDate(activation_metric);
  ASSERT_TRUE(activation_date);
  EXPECT_GE(*activation_date, ref_time);
  EXPECT_LT(*activation_date, ref_time + base::Seconds(30));
}

TEST_F(P3AMessageManagerTest, ActivationDateCleanup) {
  SetUpManager();

  MessageMetainfo meta;
  meta.Init(local_state_.get(), "release", base::Time::Now() - base::Days(7));

  const char metric_name[] = "Brave.NonExistentMetric";
  auto ref_time = base::Time::Now();
  {
    ScopedDictPrefUpdate update(local_state_.get(), kActivationDatesDictPref);
    update->Set(metric_name, base::TimeToValue(ref_time));
  }

  auto activation_date = meta.GetActivationDate(metric_name);
  ASSERT_TRUE(activation_date);
  EXPECT_EQ(activation_date, ref_time);

  CreateAndStartManager();
  EXPECT_FALSE(meta.GetActivationDate(metric_name));
}

TEST_F(P3AMessageManagerTest, EphemeralMetricOnlySentOnce) {
  SetUpManager();

  ResetInterceptorStores();

  message_manager_->UpdateMetricValue("Brave.Today.UsageDaily", 1);

  task_environment_.FastForwardBy(base::Seconds(kUploadIntervalSeconds * 100));

  EXPECT_EQ(points_requests_made_[MetricLogType::kExpress], 1U);
  EXPECT_EQ(p3a_constellation_sent_messages_[MetricLogType::kExpress].size(),
            1U);

  ResetInterceptorStores();

  current_epoch_++;
  next_epoch_time_ += kEpochLenTimeDelta;
  task_environment_.FastForwardBy(kEpochLenTimeDelta +
                                  base::Seconds(kUploadIntervalSeconds * 100));

  ASSERT_TRUE(info_request_made_[MetricLogType::kExpress]);
  EXPECT_EQ(points_requests_made_[MetricLogType::kExpress], 0U);
  EXPECT_EQ(p3a_constellation_sent_messages_[MetricLogType::kExpress].size(),
            0U);
}

}  // namespace p3a
