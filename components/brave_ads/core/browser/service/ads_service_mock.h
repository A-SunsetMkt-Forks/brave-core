/* Copyright (c) 2022 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_BRAVE_ADS_CORE_BROWSER_SERVICE_ADS_SERVICE_MOCK_H_
#define BRAVE_COMPONENTS_BRAVE_ADS_CORE_BROWSER_SERVICE_ADS_SERVICE_MOCK_H_

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "brave/components/brave_ads/core/browser/service/ads_service.h"
#include "brave/components/brave_ads/core/mojom/brave_ads.mojom-forward.h"
#include "testing/gmock/include/gmock/gmock.h"

namespace brave_ads {

class AdsServiceMock : public AdsService {
 public:
  AdsServiceMock();

  AdsServiceMock(const AdsServiceMock&) = delete;
  AdsServiceMock& operator=(const AdsServiceMock&) = delete;

  ~AdsServiceMock() override;

  MOCK_METHOD(void,
              AddBatAdsObserver,
              (mojo::PendingRemote<bat_ads::mojom::BatAdsObserver>));

  MOCK_METHOD(bool, IsBrowserUpgradeRequiredToServeAds, (), (const));

  MOCK_METHOD(int64_t, GetMaximumNotificationAdsPerHour, (), (const));

  MOCK_METHOD(void, OnNotificationAdShown, (const std::string&));
  MOCK_METHOD(void, OnNotificationAdClosed, (const std::string&, bool));
  MOCK_METHOD(void, OnNotificationAdClicked, (const std::string&));

  MOCK_METHOD(void, GetInternals, (GetInternalsCallback));

  MOCK_METHOD(void, GetDiagnostics, (GetDiagnosticsCallback));

  MOCK_METHOD(void, GetStatementOfAccounts, (GetStatementOfAccountsCallback));

  MOCK_METHOD(void,
              MaybeServeInlineContentAd,
              (const std::string&, MaybeServeInlineContentAdCallback));
  MOCK_METHOD(void,
              TriggerInlineContentAdEvent,
              (const std::string&,
               const std::string&,
               mojom::InlineContentAdEventType,
               TriggerAdEventCallback));

  MOCK_METHOD(std::optional<NewTabPageAdInfo>,
              MaybeGetPrefetchedNewTabPageAd,
              ());
  MOCK_METHOD(void, PrefetchNewTabPageAd, ());
  MOCK_METHOD(void, MaybeServeNewTabPageAd, (MaybeServeNewTabPageAdCallback));
  MOCK_METHOD(void,
              TriggerNewTabPageAdEvent,
              (const std::string&,
               const std::string&,
               bool,
               mojom::NewTabPageAdEventType,
               TriggerAdEventCallback));
  MOCK_METHOD(void,
              OnFailedToPrefetchNewTabPageAd,
              (const std::string&, const std::string&));
  MOCK_METHOD(void,
              ParseAndSaveNewTabPageAds,
              (base::Value::Dict, ParseAndSaveNewTabPageAdsCallback));

  MOCK_METHOD(void,
              TriggerPromotedContentAdEvent,
              (const std::string&,
               const std::string&,
               mojom::PromotedContentAdEventType,
               TriggerAdEventCallback));

  MOCK_METHOD(void,
              MaybeGetSearchResultAd,
              (const std::string&, MaybeGetSearchResultAdCallback));
  MOCK_METHOD(void,
              TriggerSearchResultAdEvent,
              (mojom::CreativeSearchResultAdInfoPtr,
               mojom::SearchResultAdEventType,
               TriggerAdEventCallback));

  MOCK_METHOD(void,
              PurgeOrphanedAdEventsForType,
              (mojom::AdType, PurgeOrphanedAdEventsForTypeCallback));

  MOCK_METHOD(void,
              GetAdHistory,
              (base::Time, base::Time, GetAdHistoryForUICallback));

  MOCK_METHOD(void, ClearData, (ClearDataCallback));

  MOCK_METHOD(void,
              ToggleLikeAd,
              (mojom::ReactionInfoPtr, ToggleReactionCallback));
  MOCK_METHOD(void,
              ToggleDislikeAd,
              (mojom::ReactionInfoPtr, ToggleReactionCallback));
  MOCK_METHOD(void,
              ToggleLikeSegment,
              (mojom::ReactionInfoPtr, ToggleReactionCallback));
  MOCK_METHOD(void,
              ToggleDislikeSegment,
              (mojom::ReactionInfoPtr, ToggleReactionCallback));
  MOCK_METHOD(void,
              ToggleSaveAd,
              (mojom::ReactionInfoPtr, ToggleReactionCallback));
  MOCK_METHOD(void,
              ToggleMarkAdAsInappropriate,
              (mojom::ReactionInfoPtr, ToggleReactionCallback));

  MOCK_METHOD(void,
              NotifyTabTextContentDidChange,
              (int32_t, const std::vector<GURL>&, const std::string&));
  MOCK_METHOD(void,
              NotifyTabHtmlContentDidChange,
              (int32_t, const std::vector<GURL>&, const std::string&));
  MOCK_METHOD(void, NotifyTabDidStartPlayingMedia, (int32_t));
  MOCK_METHOD(void, NotifyTabDidStopPlayingMedia, (int32_t));
  MOCK_METHOD(void,
              NotifyTabDidChange,
              (int32_t, const std::vector<GURL>&, bool, bool, bool));
  MOCK_METHOD(void, NotifyTabDidLoad, (int32_t, int));
  MOCK_METHOD(void, NotifyDidCloseTab, (int32_t));
  MOCK_METHOD(void, NotifyUserGestureEventTriggered, (int32_t));
  MOCK_METHOD(void, NotifyBrowserDidBecomeActive, ());
  MOCK_METHOD(void, NotifyBrowserDidResignActive, ());

  MOCK_METHOD(void, NotifyDidSolveAdaptiveCaptcha, ());
};

}  // namespace brave_ads

#endif  // BRAVE_COMPONENTS_BRAVE_ADS_CORE_BROWSER_SERVICE_ADS_SERVICE_MOCK_H_
