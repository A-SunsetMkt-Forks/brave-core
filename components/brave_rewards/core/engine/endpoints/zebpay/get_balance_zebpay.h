/* Copyright (c) 2023 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_BRAVE_REWARDS_CORE_ENGINE_ENDPOINTS_ZEBPAY_GET_BALANCE_ZEBPAY_H_
#define BRAVE_COMPONENTS_BRAVE_REWARDS_CORE_ENGINE_ENDPOINTS_ZEBPAY_GET_BALANCE_ZEBPAY_H_

#include <optional>
#include <string>
#include <vector>

#include "brave/components/brave_rewards/core/engine/endpoints/request_builder.h"
#include "brave/components/brave_rewards/core/engine/endpoints/response_handler.h"
#include "brave/components/brave_rewards/core/engine/endpoints/result_for.h"
#include "brave/components/brave_rewards/core/mojom/rewards_engine_internal.mojom.h"

// GET /api/balance
//
// Request body:
// -
//
// Response body:
// {
//   "BAT": 0
// }

namespace brave_rewards::internal {
class RewardsEngine;

namespace endpoints {

class GetBalanceZebPay;

template <>
struct ResultFor<GetBalanceZebPay> {
  using Value = double;  // balance
  using Error = mojom::GetBalanceZebPayError;
};

class GetBalanceZebPay final : public RequestBuilder,
                               public ResponseHandler<GetBalanceZebPay> {
 public:
  static Result ProcessResponse(RewardsEngine& engine,
                                const mojom::UrlResponse& response);

  GetBalanceZebPay(RewardsEngine& engine, std::string&& token);
  ~GetBalanceZebPay() override;

 private:
  std::optional<std::string> Url() const override;
  mojom::UrlMethod Method() const override;
  std::optional<std::vector<std::string>> Headers(
      const std::string& content) const override;

  std::string token_;
};

}  // namespace endpoints
}  // namespace brave_rewards::internal

#endif  // BRAVE_COMPONENTS_BRAVE_REWARDS_CORE_ENGINE_ENDPOINTS_ZEBPAY_GET_BALANCE_ZEBPAY_H_
