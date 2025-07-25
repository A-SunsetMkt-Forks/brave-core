// Copyright (c) 2023 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/psst/browser/core/psst_component_installer.h"

#include <memory>
#include <string>
#include <vector>

#include "base/base64.h"
#include "base/containers/to_vector.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/path_service.h"
#include "brave/components/brave_component_updater/browser/brave_on_demand_updater.h"
#include "brave/components/psst/browser/core/psst_rule_registry.h"
#include "brave/components/psst/common/features.h"
#include "components/component_updater/component_installer.h"
#include "components/component_updater/component_updater_paths.h"
#include "components/component_updater/component_updater_service.h"
#include "components/prefs/pref_service.h"
#include "crypto/sha2.h"

using brave_component_updater::BraveOnDemandUpdater;

namespace psst {

// Directory structure of PSST component:
// lhhcaamjbmbijmjbnnodjaknblkiagon/<component version>/
//  |_ manifest.json
//  |_ psst.json
//  |_ scripts/
//    |_ twitter/
//        |_ user.js
//        |_ policy.js
//    |_ linkedin/
//        |_ user.js
//        |_ policy.js
// See psst_rule.cc for the format of psst.json.

class PsstComponentInstallerPolicy
    : public component_updater::ComponentInstallerPolicy {
 public:
  PsstComponentInstallerPolicy();

  PsstComponentInstallerPolicy(const PsstComponentInstallerPolicy&) = delete;
  PsstComponentInstallerPolicy& operator=(const PsstComponentInstallerPolicy&) =
      delete;

  // component_updater::ComponentInstallerPolicy
  bool SupportsGroupPolicyEnabledComponentUpdates() const override;
  bool RequiresNetworkEncryption() const override;
  update_client::CrxInstaller::Result OnCustomInstall(
      const base::Value::Dict& manifest,
      const base::FilePath& install_dir) override;
  void OnCustomUninstall() override;
  bool VerifyInstallation(const base::Value::Dict& manifest,
                          const base::FilePath& install_dir) const override;
  void ComponentReady(const base::Version& version,
                      const base::FilePath& path,
                      base::Value::Dict manifest) override;
  base::FilePath GetRelativeInstallDir() const override;
  void GetHash(std::vector<uint8_t>* hash) const override;
  std::string GetName() const override;
  update_client::InstallerAttributes GetInstallerAttributes() const override;
  bool IsBraveComponent() const override;

 private:
  const std::string component_id_;
  const std::string component_name_;
  std::array<uint8_t, crypto::kSHA256Length> component_hash_;
};

PsstComponentInstallerPolicy::PsstComponentInstallerPolicy()
    : component_id_(kPsstComponentId), component_name_(kPsstComponentName) {
  // Generate hash from public key.
  auto decoded_public_key = base::Base64Decode(kPsstComponentBase64PublicKey);
  CHECK(decoded_public_key);
  component_hash_ = crypto::SHA256Hash(*decoded_public_key);
}

bool PsstComponentInstallerPolicy::SupportsGroupPolicyEnabledComponentUpdates()
    const {
  return true;
}

bool PsstComponentInstallerPolicy::RequiresNetworkEncryption() const {
  return false;
}

update_client::CrxInstaller::Result
PsstComponentInstallerPolicy::OnCustomInstall(
    const base::Value::Dict& manifest,
    const base::FilePath& install_dir) {
  return update_client::CrxInstaller::Result(0);
}

void PsstComponentInstallerPolicy::OnCustomUninstall() {}

void PsstComponentInstallerPolicy::ComponentReady(
    const base::Version& version,
    const base::FilePath& install_dir,
    base::Value::Dict manifest) {
  PsstRuleRegistry::GetInstance()->LoadRules(install_dir, base::NullCallback());
}

bool PsstComponentInstallerPolicy::VerifyInstallation(
    const base::Value::Dict& manifest,
    const base::FilePath& install_dir) const {
  return true;
}

base::FilePath PsstComponentInstallerPolicy::GetRelativeInstallDir() const {
  return base::FilePath::FromUTF8Unsafe(component_id_);
}

void PsstComponentInstallerPolicy::GetHash(std::vector<uint8_t>* hash) const {
  *hash = base::ToVector(component_hash_);
}

std::string PsstComponentInstallerPolicy::GetName() const {
  return component_name_;
}

update_client::InstallerAttributes
PsstComponentInstallerPolicy::GetInstallerAttributes() const {
  return update_client::InstallerAttributes();
}

bool PsstComponentInstallerPolicy::IsBraveComponent() const {
  return true;
}

void RegisterPsstComponent(component_updater::ComponentUpdateService* cus) {
  if (!base::FeatureList::IsEnabled(psst::features::kEnablePsst) || !cus) {
    return;
  }

  auto installer = base::MakeRefCounted<component_updater::ComponentInstaller>(
      std::make_unique<PsstComponentInstallerPolicy>());
  installer->Register(
      // After Register, run the callback with component id.
      cus, base::BindOnce([]() {
        brave_component_updater::BraveOnDemandUpdater::GetInstance()
            ->EnsureInstalled(kPsstComponentId);
      }));
}

}  // namespace psst
