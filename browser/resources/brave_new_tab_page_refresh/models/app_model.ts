/* Copyright (c) 2025 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import {
  NewTabState,
  NewTabActions,
  defaultNewTabState } from './new_tab'

import {
  BackgroundState,
  BackgroundActions,
  defaultBackgroundState } from './backgrounds'

import {
  SearchState,
  SearchActions,
  defaultSearchState } from './search'

import {
  TopSitesState,
  TopSitesActions,
  defaultTopSitesState } from './top_sites'

export type AppState =
  NewTabState &
  BackgroundState &
  SearchState &
  TopSitesState

export function defaultState(): AppState {
  return {
    ...defaultNewTabState(),
    ...defaultBackgroundState(),
    ...defaultSearchState(),
    ...defaultTopSitesState(),
  }
}

export type AppActions =
  NewTabActions &
  BackgroundActions &
  SearchActions &
  TopSitesActions

export interface AppModel extends AppActions {
  getState: () => AppState
  addListener: (listener: (state: AppState) => void) => () => void
}
