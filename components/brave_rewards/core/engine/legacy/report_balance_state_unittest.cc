/* Copyright (c) 2019 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/components/brave_rewards/core/engine/legacy/report_balance_properties.h"
#include "testing/gtest/include/gtest/gtest.h"

// npm run test -- brave_unit_tests --filter=ReportBalanceStateTest.*

namespace brave_rewards::internal {

TEST(ReportBalanceStateTest, ToJsonSerialization) {
  // Arrange
  ReportBalanceProperties report_balance_properties;
  report_balance_properties.grants = 1;
  report_balance_properties.ad_earnings = 1;
  report_balance_properties.auto_contributions = 1;
  report_balance_properties.recurring_donations = 1;
  report_balance_properties.one_time_donations = 1;

  // Assert
  ReportBalanceProperties expected_report_balance_properties;
  expected_report_balance_properties.FromJson(
      report_balance_properties.ToJson());
  EXPECT_EQ(expected_report_balance_properties, report_balance_properties);
}

TEST(ReportBalanceStateTest, FromJsonDeserialization) {
  // Arrange
  ReportBalanceProperties report_balance;
  report_balance.grants = 1;
  report_balance.ad_earnings = 1;
  report_balance.auto_contributions = 1;
  report_balance.recurring_donations = 1;
  report_balance.one_time_donations = 1;

  const std::string json =
      "{\"grants\":1,\"earning_from_ads\":1,\"auto_contribute\":1,\"recurring_"
      "donation\":1,\"one_time_donation\":1}";  // NOLINT

  // Act
  ReportBalanceProperties expected_report_balance;
  expected_report_balance.FromJson(json);

  // Assert
  EXPECT_EQ(expected_report_balance, report_balance);
}

}  // namespace brave_rewards::internal
