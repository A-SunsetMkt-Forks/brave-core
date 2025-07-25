/* Copyright (c) 2023 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "base/feature_override.h"
#include "build/build_config.h"

#include <content/common/features.cc>

namespace features {

OVERRIDE_FEATURE_DEFAULT_STATES({{
    // This feature should not be enabled when kFencedFrames is disabled.
    {kPrivacySandboxAdsAPIsM1Override, base::FEATURE_DISABLED_BY_DEFAULT},
}});

}  // namespace features
