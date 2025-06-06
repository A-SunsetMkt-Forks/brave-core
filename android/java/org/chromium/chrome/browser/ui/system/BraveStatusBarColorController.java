/* Copyright (c) 2024 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.ui.system;

import android.content.Context;
import android.graphics.Color;
import android.view.Window;

import androidx.annotation.ColorInt;

import org.chromium.base.supplier.ObservableSupplier;
import org.chromium.base.supplier.OneshotSupplier;
import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.browser.ActivityTabProvider;
import org.chromium.chrome.browser.layouts.LayoutManager;
import org.chromium.chrome.browser.lifecycle.ActivityLifecycleDispatcher;
import org.chromium.chrome.browser.theme.TopUiThemeColorProvider;
import org.chromium.chrome.browser.ui.system.StatusBarColorController.StatusBarColorProvider;
import org.chromium.components.browser_ui.desktop_windowing.DesktopWindowStateManager;
import org.chromium.components.browser_ui.edge_to_edge.EdgeToEdgeSystemBarColorHelper;
import org.chromium.ui.util.ColorUtils;

@NullMarked
public class BraveStatusBarColorController extends StatusBarColorController {
    // Will be removed with bytecode patch
    public @ColorInt int mBackgroundColorForNtp;

    public BraveStatusBarColorController(
            Window window,
            boolean isTablet,
            Context context,
            StatusBarColorProvider statusBarColorProvider,
            ObservableSupplier<LayoutManager> layoutManagerSupplier,
            ActivityLifecycleDispatcher activityLifecycleDispatcher,
            ActivityTabProvider tabProvider,
            TopUiThemeColorProvider topUiThemeColorProvider,
            EdgeToEdgeSystemBarColorHelper edgeToEdgeSystemBarColorHelper,
            OneshotSupplier<DesktopWindowStateManager> desktopWindowStateManagerSupplier,
            ObservableSupplier<Integer> overviewColorSupplier) {
        super(
                window,
                isTablet,
                context,
                statusBarColorProvider,
                layoutManagerSupplier,
                activityLifecycleDispatcher,
                tabProvider,
                topUiThemeColorProvider,
                edgeToEdgeSystemBarColorHelper,
                desktopWindowStateManagerSupplier,
                overviewColorSupplier);

        // Dark theme doesn't have the regression, apply adjustment to light one only
        if (!ColorUtils.inNightMode(context)) {
            mBackgroundColorForNtp = Color.WHITE;
        }
    }
}
