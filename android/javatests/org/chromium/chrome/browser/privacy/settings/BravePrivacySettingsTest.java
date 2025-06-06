/* Copyright (c) 2021 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.privacy.settings;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;

import androidx.test.filters.SmallTest;

import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.runner.RunWith;

import org.chromium.base.ThreadUtils;
import org.chromium.base.test.util.Batch;
import org.chromium.chrome.browser.prefetch.settings.PreloadPagesSettingsBridge;
import org.chromium.chrome.browser.prefetch.settings.PreloadPagesState;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.settings.SettingsActivityTestRule;
import org.chromium.chrome.test.ChromeJUnit4ClassRunner;
import org.chromium.chrome.test.ChromeTabbedActivityTestRule;

/** Checks if changes have been made to the Chromium privacy settings */
@Batch(Batch.PER_CLASS)
@RunWith(ChromeJUnit4ClassRunner.class)
public class BravePrivacySettingsTest {
    // Chromium Prefs that are being checked
    private static final String PREF_CAN_MAKE_PAYMENT = "can_make_payment";
    private static final String PREF_NETWORK_PREDICTIONS = "preload_pages";
    private static final String PREF_SECURE_DNS = "secure_dns";
    private static final String PREF_DO_NOT_TRACK = "do_not_track";
    private static final String PREF_SAFE_BROWSING = "safe_browsing";
    private static final String PREF_SYNC_AND_SERVICES_LINK = "sync_and_services_link";
    private static final String PREF_CLEAR_BROWSING_DATA = "clear_browsing_data";
    private static final String PREF_HTTPS_FIRST_MODE_LEGACY = "https_first_mode_legacy";
    private static final String PREF_HTTPS_FIRST_MODE = "https_first_mode";
    private static final String PREF_HTTPS_UPGRADE = "https_upgrade";
    private static final String PREF_FORGET_FIRST_PARTY_STORAGE = "forget_first_party_storage";
    private static final String PREF_INCOGNITO_LOCK = "incognito_lock";
    private static final String PREF_SURVEY_PANELIST = "survey_panelist";
    private static final String PREF_SURVEY_PANELIST_LEARN_MORE = "survey_panelist_learn_more";
    private static final String PREF_PASSWORD_LEAK_DETECTION = "password_leak_detection";
    private static final String PREF_INCOGNITO_TRACKING_PROTECTIONS =
            "incognito_tracking_protections";
    private static final String PREF_ADVANCED_PROTECTION_INFO = "advanced_protection_info";

    private static final int BRAVE_PRIVACY_SETTINGS_NUMBER_OF_ITEMS = 30;

    private int mItemsLeft;

    @Rule
    public ChromeTabbedActivityTestRule mActivityTestRule = new ChromeTabbedActivityTestRule();

    @Rule
    public SettingsActivityTestRule<BravePrivacySettings> mSettingsActivityTestRule =
            new SettingsActivityTestRule<>(BravePrivacySettings.class);
    private BravePrivacySettings mFragment;

    @Before
    public void setUp() {
        mSettingsActivityTestRule.startSettingsActivity();
        mFragment = (BravePrivacySettings) mSettingsActivityTestRule.getFragment();
        mItemsLeft = mFragment.getPreferenceScreen().getPreferenceCount();
    }

    @Test
    @SmallTest
    public void testParentItems() {
        checkPreferenceExists(PREF_CAN_MAKE_PAYMENT);
        checkPreferenceExists(PREF_CLEAR_BROWSING_DATA);
        checkPreferenceExists(PREF_DO_NOT_TRACK);
        checkPreferenceExists(PREF_HTTPS_FIRST_MODE_LEGACY);
        checkPreferenceExists(PREF_HTTPS_FIRST_MODE);
        checkPreferenceExists(PREF_HTTPS_UPGRADE);
        checkPreferenceExists(PREF_FORGET_FIRST_PARTY_STORAGE);
        checkPreferenceExists(PREF_SAFE_BROWSING);
        checkPreferenceExists(PREF_SECURE_DNS);
        checkPreferenceExists(PREF_INCOGNITO_LOCK);
        checkPreferenceExists(PREF_SURVEY_PANELIST);
        checkPreferenceExists(PREF_SURVEY_PANELIST_LEARN_MORE);

        checkPreferenceRemoved(PREF_NETWORK_PREDICTIONS);
        checkPreferenceRemoved(PREF_SYNC_AND_SERVICES_LINK);
        checkPreferenceRemoved(PREF_PASSWORD_LEAK_DETECTION);

        checkPreferenceVisibility(PREF_INCOGNITO_TRACKING_PROTECTIONS, false);
        checkPreferenceVisibility(PREF_ADVANCED_PROTECTION_INFO, false);

        assertEquals(BRAVE_PRIVACY_SETTINGS_NUMBER_OF_ITEMS, mItemsLeft);
    }

    private void checkPreferenceExists(String pref) {
        assertNotEquals(null, mFragment.findPreference(pref));
        mItemsLeft--;
    }

    private void checkPreferenceRemoved(String pref) {
        assertEquals(null, mFragment.findPreference(pref));
        mItemsLeft--;
    }

    private void checkPreferenceVisibility(String pref, boolean expectedVisibility) {
        assertEquals(expectedVisibility, mFragment.findPreference(pref).isVisible());
    }

    @Test
    @SmallTest
    public void testDisabledOptions() {
        ThreadUtils.runOnUiThreadBlocking(
                () -> {
                    assertFalse(
                            PreloadPagesSettingsBridge.getState(
                                            ProfileManager.getLastUsedRegularProfile())
                                    != PreloadPagesState.NO_PRELOADING);
                });
    }
}
