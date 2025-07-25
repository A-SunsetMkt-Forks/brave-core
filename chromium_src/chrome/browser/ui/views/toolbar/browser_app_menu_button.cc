/* Copyright (c) 2020 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "chrome/browser/ui/views/toolbar/browser_app_menu_button.h"

#include "brave/browser/ui/toolbar/brave_app_menu_model.h"

#define FromVectorIcon(icon, color) FromVectorIcon(icon, color, GetIconSize())
#define AppMenuModel BraveAppMenuModel
#include <chrome/browser/ui/views/toolbar/browser_app_menu_button.cc>
#undef AppMenuModel
#undef FromVectorIcon
