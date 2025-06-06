/* Copyright (c) 2022 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/components/brave_ads/core/internal/user_engagement/conversions/resource/conversion_resource_info.h"

#include <string>

#include "brave/components/brave_ads/core/internal/user_engagement/conversions/conversions_feature.h"
#include "brave/components/brave_ads/core/internal/user_engagement/conversions/resource/conversion_resource_id_pattern_search_in_types.h"

namespace brave_ads {

namespace {

constexpr char kSearchInUrlRedirectType[] = "url";
constexpr char kSearchInHtmlType[] = "html";

}  // namespace

ConversionResourceInfo::ConversionResourceInfo() = default;

ConversionResourceInfo::ConversionResourceInfo(
    ConversionResourceInfo&& other) noexcept = default;

ConversionResourceInfo& ConversionResourceInfo::operator=(
    ConversionResourceInfo&& other) noexcept = default;

ConversionResourceInfo::~ConversionResourceInfo() = default;

// static
std::optional<ConversionResourceInfo> ConversionResourceInfo::CreateFromValue(
    const base::Value::Dict dict) {
  ConversionResourceInfo conversions;

  if (std::optional<int> version = dict.FindInt("version")) {
    if (version != kConversionResourceVersion.Get()) {
      return std::nullopt;
    }
    conversions.version = version;
  }

  const auto* conversion_id_patterns_dict =
      dict.FindDict("conversion_id_patterns");
  if (!conversion_id_patterns_dict) {
    return std::nullopt;
  }

  for (const auto [url_pattern, conversion_id_pattern] :
       *conversion_id_patterns_dict) {
    const base::Value::Dict* conversion_id_pattern_dict =
        conversion_id_pattern.GetIfDict();

    if (!conversion_id_pattern_dict) {
      return std::nullopt;
    }

    const std::string* const id_pattern =
        conversion_id_pattern_dict->FindString("id_pattern");
    if (!id_pattern || id_pattern->empty()) {
      return std::nullopt;
    }

    const std::string* const search_in =
        conversion_id_pattern_dict->FindString("search_in");
    if (!search_in) {
      return std::nullopt;
    }

    ConversionResourceIdPatternSearchInType search_in_type =
        ConversionResourceIdPatternSearchInType::kDefault;  // kHtmlMetaTag
    if (*search_in == kSearchInUrlRedirectType) {
      search_in_type = ConversionResourceIdPatternSearchInType::kUrlRedirect;
    } else if (*search_in == kSearchInHtmlType) {
      search_in_type = ConversionResourceIdPatternSearchInType::kHtml;
    }

    conversions.id_patterns[url_pattern] = {url_pattern, search_in_type,
                                            *id_pattern};
  }

  return conversions;
}

}  // namespace brave_ads
