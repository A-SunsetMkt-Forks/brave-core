/* Copyright (c) 2024 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/components/brave_wallet/browser/bitcoin/bitcoin_hardware_keyring.h"

#include <array>
#include <memory>
#include <optional>
#include <utility>

#include "base/check.h"
#include "base/notimplemented.h"
#include "base/types/cxx23_to_underlying.h"
#include "brave/components/brave_wallet/browser/internal/hd_key.h"
#include "brave/components/brave_wallet/common/bitcoin_utils.h"
#include "brave/components/brave_wallet/common/common_utils.h"

namespace brave_wallet {

BitcoinHardwareKeyring::BitcoinHardwareKeyring(mojom::KeyringId keyring_id)
    : BitcoinBaseKeyring(keyring_id) {
  CHECK(IsBitcoinHardwareKeyring(keyring_id_));
}

BitcoinHardwareKeyring::~BitcoinHardwareKeyring() = default;

bool BitcoinHardwareKeyring::AddAccount(uint32_t account,
                                        const std::string& payload) {
  if (accounts_.contains(account)) {
    return false;
  }
  auto parsed_key = HDKey::GenerateFromExtendedKey(payload);
  if (!parsed_key) {
    return false;
  }

  if (IsTestnet() &&
      parsed_key->version != base::to_underlying(ExtendedKeyVersion::kTpub)) {
    return false;
  }
  if (!IsTestnet() &&
      parsed_key->version != base::to_underlying(ExtendedKeyVersion::kXpub)) {
    return false;
  }

  accounts_[account] = std::move(parsed_key->hdkey);
  return true;
}

bool BitcoinHardwareKeyring::RemoveAccount(uint32_t account) {
  return accounts_.erase(account) > 0;
}

mojom::BitcoinAddressPtr BitcoinHardwareKeyring::GetAddress(
    uint32_t account,
    const mojom::BitcoinKeyId& key_id) {
  auto hd_key = DeriveKey(account, key_id);
  if (!hd_key) {
    return nullptr;
  }

  return mojom::BitcoinAddress::New(
      PubkeyToSegwitAddress(hd_key->GetPublicKeyBytes(), IsTestnet()),
      key_id.Clone());
}

std::optional<std::vector<uint8_t>> BitcoinHardwareKeyring::GetPubkey(
    uint32_t account,
    const mojom::BitcoinKeyId& key_id) {
  auto hd_key = DeriveKey(account, key_id);
  if (!hd_key) {
    return std::nullopt;
  }

  return hd_key->GetPublicKeyBytes();
}

std::optional<std::vector<uint8_t>> BitcoinHardwareKeyring::SignMessage(
    uint32_t account,
    const mojom::BitcoinKeyId& key_id,
    base::span<const uint8_t, 32> message) {
  NOTIMPLEMENTED();
  return std::nullopt;
}

HDKey* BitcoinHardwareKeyring::GetAccountByIndex(uint32_t account) {
  if (!accounts_.contains(account)) {
    return nullptr;
  }
  return accounts_[account].get();
}

std::unique_ptr<HDKey> BitcoinHardwareKeyring::DeriveKey(
    uint32_t account,
    const mojom::BitcoinKeyId& key_id) {
  auto* account_key = GetAccountByIndex(account);
  if (!account_key) {
    return nullptr;
  }

  DCHECK(key_id.change == 0 || key_id.change == 1);

  return account_key->DeriveChildFromPath(
      std::array{DerivationIndex::Normal(key_id.change),
                 DerivationIndex::Normal(key_id.index)});
}

}  // namespace brave_wallet
