/* Copyright (c) 2021 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/components/brave_wallet/browser/eth_pending_tx_tracker.h"

#include <memory>
#include <optional>
#include <utility>

#include "base/check.h"
#include "brave/components/brave_wallet/browser/eth_nonce_tracker.h"
#include "brave/components/brave_wallet/browser/eth_tx_meta.h"
#include "brave/components/brave_wallet/browser/json_rpc_service.h"
#include "brave/components/brave_wallet/browser/tx_meta.h"
#include "brave/components/brave_wallet/common/brave_wallet.mojom.h"

namespace brave_wallet {

EthPendingTxTracker::EthPendingTxTracker(EthTxStateManager* tx_state_manager,
                                         JsonRpcService* json_rpc_service,
                                         EthNonceTracker* nonce_tracker)
    : tx_state_manager_(tx_state_manager),
      json_rpc_service_(json_rpc_service),
      nonce_tracker_(nonce_tracker),
      weak_factory_(this) {}
EthPendingTxTracker::~EthPendingTxTracker() = default;

bool EthPendingTxTracker::UpdatePendingTransactions(
    const std::optional<std::string>& chain_id,
    std::set<std::string>* pending_chain_ids) {
  CHECK(pending_chain_ids);
  auto pending_transactions = tx_state_manager_->GetTransactionsByStatus(
      chain_id, mojom::TransactionStatus::Submitted, std::nullopt);
  auto signed_transactions = tx_state_manager_->GetTransactionsByStatus(
      chain_id, mojom::TransactionStatus::Signed, std::nullopt);
  pending_transactions.insert(
      pending_transactions.end(),
      std::make_move_iterator(signed_transactions.begin()),
      std::make_move_iterator(signed_transactions.end()));
  for (const auto& pending_transaction : pending_transactions) {
    if (IsNonceTaken(static_cast<const EthTxMeta&>(*pending_transaction))) {
      DropTransaction(pending_transaction.get());
      continue;
    }
    const auto& pending_chain_id = pending_transaction->chain_id();
    pending_chain_ids->emplace(pending_chain_id);
    std::string id = pending_transaction->id();
    json_rpc_service_->GetTransactionReceipt(
        pending_chain_id, pending_transaction->tx_hash(),
        base::BindOnce(&EthPendingTxTracker::OnGetTxReceipt,
                       weak_factory_.GetWeakPtr(), std::move(id)));
  }

  return true;
}

void EthPendingTxTracker::Reset() {
  network_nonce_map_.clear();
  dropped_blocks_counter_.clear();
}

void EthPendingTxTracker::OnGetTxReceipt(const std::string& meta_id,
                                         TransactionReceipt receipt,
                                         mojom::ProviderError error,
                                         const std::string& error_message) {
  if (error != mojom::ProviderError::kSuccess) {
    return;
  }

  std::unique_ptr<EthTxMeta> meta = tx_state_manager_->GetEthTx(meta_id);
  if (!meta) {
    return;
  }
  if (receipt.status) {
    meta->set_tx_receipt(receipt);
    meta->set_status(mojom::TransactionStatus::Confirmed);
    meta->set_confirmed_time(base::Time::Now());
    tx_state_manager_->AddOrUpdateTx(*meta);
  } else if (ShouldTxDropped(*meta)) {
    DropTransaction(meta.get());
  }
}

void EthPendingTxTracker::OnGetNetworkNonce(const std::string& chain_id,
                                            const std::string& address,
                                            uint256_t result,
                                            mojom::ProviderError error,
                                            const std::string& error_message) {
  if (error != mojom::ProviderError::kSuccess) {
    return;
  }

  network_nonce_map_[address][chain_id] = result;
}

void EthPendingTxTracker::OnSendRawTransaction(
    const std::string& tx_hash,
    mojom::ProviderError error,
    const std::string& error_message) {}

bool EthPendingTxTracker::IsNonceTaken(const EthTxMeta& meta) {
  auto confirmed_transactions = tx_state_manager_->GetTransactionsByStatus(
      meta.chain_id(), mojom::TransactionStatus::Confirmed, std::nullopt);
  for (const auto& confirmed_transaction : confirmed_transactions) {
    auto* eth_confirmed_transaction =
        static_cast<EthTxMeta*>(confirmed_transaction.get());
    if (eth_confirmed_transaction->tx()->nonce() == meta.tx()->nonce() &&
        eth_confirmed_transaction->id() != meta.id()) {
      return true;
    }
  }
  return false;
}

bool EthPendingTxTracker::ShouldTxDropped(const EthTxMeta& meta) {
  const std::string& address = meta.from()->address;
  const std::string& chain_id = meta.chain_id();
  auto network_nonce_map_per_chain_id = network_nonce_map_.find(address);
  if (network_nonce_map_per_chain_id == network_nonce_map_.end() ||
      !network_nonce_map_per_chain_id->second.contains(chain_id)) {
    json_rpc_service_->GetEthTransactionCount(
        chain_id, address,
        base::BindOnce(&EthPendingTxTracker::OnGetNetworkNonce,
                       weak_factory_.GetWeakPtr(), chain_id, address));
  } else {
    uint256_t network_nonce = network_nonce_map_[address][chain_id];
    network_nonce_map_per_chain_id->second.erase(chain_id);
    if (network_nonce_map_per_chain_id->second.empty()) {
      network_nonce_map_.erase(address);
    }
    if (meta.tx()->nonce() < network_nonce) {
      return true;
    }
  }

  auto [it, inserted] = dropped_blocks_counter_.try_emplace(meta.tx_hash(), 0);
  uint8_t& count = it->second;

  if (count >= 3) {
    dropped_blocks_counter_.erase(it);
    return true;
  }

  ++count;
  return false;
}

void EthPendingTxTracker::DropTransaction(TxMeta* meta) {
  if (!meta) {
    return;
  }
  tx_state_manager_->DeleteTx(meta->id());
}

}  // namespace brave_wallet
