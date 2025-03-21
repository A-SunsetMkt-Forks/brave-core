/* Copyright (c) 2024 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/web_discovery/web_discovery_service_factory.h"

#include "base/path_service.h"
#include "brave/browser/brave_search/backup_results_service_factory.h"
#include "brave/components/web_discovery/browser/web_discovery_service.h"
#include "brave/components/web_discovery/common/features.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile_selections.h"
#include "chrome/common/chrome_paths.h"
#include "components/user_prefs/user_prefs.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/storage_partition.h"

namespace web_discovery {

WebDiscoveryService* WebDiscoveryServiceFactory::GetForBrowserContext(
    content::BrowserContext* context) {
  return static_cast<WebDiscoveryService*>(
      GetInstance()->GetServiceForBrowserContext(context, true));
}

WebDiscoveryServiceFactory* WebDiscoveryServiceFactory::GetInstance() {
  static base::NoDestructor<WebDiscoveryServiceFactory> instance;
  return instance.get();
}

WebDiscoveryServiceFactory::WebDiscoveryServiceFactory()
    : ProfileKeyedServiceFactory("WebDiscoveryService",
                                 CreateProfileSelections()) {
  DependsOn(brave_search::BackupResultsServiceFactory::GetInstance());
}

WebDiscoveryServiceFactory::~WebDiscoveryServiceFactory() = default;

// static
ProfileSelections WebDiscoveryServiceFactory::CreateProfileSelections() {
  if (!base::FeatureList::IsEnabled(features::kBraveWebDiscoveryNative)) {
    return ProfileSelections::BuildNoProfilesSelected();
  }
  return ProfileSelections::BuildForRegularProfile();
}

std::unique_ptr<KeyedService>
WebDiscoveryServiceFactory::BuildServiceInstanceForBrowserContext(
    content::BrowserContext* context) const {
  auto* default_storage_partition = context->GetDefaultStoragePartition();
  auto shared_url_loader_factory =
      default_storage_partition->GetURLLoaderFactoryForBrowserProcess();
  auto* backup_results_service =
      brave_search::BackupResultsServiceFactory::GetForBrowserContext(context);
  base::FilePath user_data_dir =
      base::PathService::CheckedGet(chrome::DIR_USER_DATA);
  return std::make_unique<WebDiscoveryService>(
      g_browser_process->local_state(), user_prefs::UserPrefs::Get(context),
      user_data_dir, shared_url_loader_factory, backup_results_service);
}

bool WebDiscoveryServiceFactory::ServiceIsCreatedWithBrowserContext() const {
  return true;
}

}  // namespace web_discovery
