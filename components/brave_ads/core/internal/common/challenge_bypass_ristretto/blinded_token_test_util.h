/* Copyright (c) 2022 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_BRAVE_ADS_CORE_INTERNAL_COMMON_CHALLENGE_BYPASS_RISTRETTO_BLINDED_TOKEN_TEST_UTIL_H_
#define BRAVE_COMPONENTS_BRAVE_ADS_CORE_INTERNAL_COMMON_CHALLENGE_BYPASS_RISTRETTO_BLINDED_TOKEN_TEST_UTIL_H_

#include "brave/components/brave_ads/core/internal/common/challenge_bypass_ristretto/blinded_token.h"

namespace brave_ads::cbr::test {

BlindedToken GetBlindedToken();
BlindedToken GetInvalidBlindedToken();
BlindedTokenList GetBlindedTokens();
BlindedTokenList GetInvalidBlindedTokens();

}  // namespace brave_ads::cbr::test

#endif  // BRAVE_COMPONENTS_BRAVE_ADS_CORE_INTERNAL_COMMON_CHALLENGE_BYPASS_RISTRETTO_BLINDED_TOKEN_TEST_UTIL_H_
