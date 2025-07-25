/* Copyright (c) 2020 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#define StarView BraveStarView
#define BRAVE_BOOKMARK_BUBBLE_VIEW_SHOW_BUBBLE_SET_ARROW \
  bubble->SetArrow(views::BubbleBorder::TOP_LEFT);

#include <chrome/browser/ui/views/bookmarks/bookmark_bubble_view.cc>

#undef BRAVE_BOOKMARK_BUBBLE_VIEW_SHOW_BUBBLE_SET_ARROW
#undef StarView
