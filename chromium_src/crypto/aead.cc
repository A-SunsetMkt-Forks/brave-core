/* Copyright (c) 2021 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#define BRAVE_NONCE_LENGTH \
  if (nonce_length_)       \
    return nonce_length_;

#include <crypto/aead.cc>
#undef BRAVE_NONCE_LENGTH
