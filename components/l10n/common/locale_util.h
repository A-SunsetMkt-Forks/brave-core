/* Copyright (c) 2019 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_L10N_COMMON_LOCALE_UTIL_H_
#define BRAVE_COMPONENTS_L10N_COMMON_LOCALE_UTIL_H_

#include <optional>
#include <string>

namespace brave_l10n {

// IMPORTANT: When the locale should match the application locale or an eligible
// string pack for localization use the canonicalized
// l10n_util::GetApplicationLocale.

// Returns the current default locale of the device as a string.
const std::string& GetDefaultLocaleString();

// Returns a lowercase two-letter ISO 639-1 language code for the given locale,
// falling back to "en" if the locale does not contain a language code. See
// https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes.
std::string GetISOLanguageCode(std::string_view locale);

// Returns a lowercase two-letter ISO 639-1 language code for the current
// default locale of the device as a string, falling back to "en" if the locale
// does not contain a language code. See
// https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes.
std::string GetDefaultISOLanguageCodeString();

// Returns an uppercase two-letter ISO 3166-1 alpha-2 country code or UN M.49
// code for the given locale, falling back to "US" if the locale does not
// contain a country code. See
// https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2 or
// https://en.wikipedia.org/wiki/UN_M49.
std::string GetISOCountryCode(std::string_view locale);

// Returns an uppercase two-letter ISO 3166-1 alpha-2 country code or UN M.49
// code for the current default locale of the device as a string, falling back
// to "US" if the locale does not contain a country code. See
// https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2 or
// https://en.wikipedia.org/wiki/UN_M49.
std::string GetDefaultISOCountryCodeString();

}  // namespace brave_l10n

#endif  // BRAVE_COMPONENTS_L10N_COMMON_LOCALE_UTIL_H_
