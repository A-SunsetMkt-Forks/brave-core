/* Copyright (c) 2020 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.ntp_background_images;

import androidx.annotation.Nullable;

import org.jni_zero.CalledByNative;
import org.jni_zero.NativeMethods;

import org.chromium.base.ObserverList;
import org.chromium.base.ThreadUtils;
import org.chromium.chrome.browser.BraveRewardsNativeWorker;
import org.chromium.chrome.browser.ntp_background_images.model.BackgroundImage;
import org.chromium.chrome.browser.ntp_background_images.model.ImageCredit;
import org.chromium.chrome.browser.ntp_background_images.model.NTPImage;
import org.chromium.chrome.browser.ntp_background_images.model.TopSite;
import org.chromium.chrome.browser.ntp_background_images.model.Wallpaper;
import org.chromium.chrome.browser.ntp_background_images.util.NewTabPageListener;
import org.chromium.chrome.browser.profiles.Profile;

import java.util.ArrayList;
import java.util.List;

public class NTPBackgroundImagesBridge {
    private long mNativeNTPBackgroundImagesBridge;
    private final ObserverList<NTPBackgroundImageServiceObserver> mObservers =
            new ObserverList<NTPBackgroundImageServiceObserver>();
    private static final List<TopSite> sTopSites = new ArrayList<>();
    private static NewTabPageListener sNewTabPageListener;

    public abstract static class NTPBackgroundImageServiceObserver {
        public abstract void onUpdated();
    }

    public NTPBackgroundImagesBridge(long nativeNTPBackgroundImagesBridge) {
        ThreadUtils.assertOnUiThread();
        mNativeNTPBackgroundImagesBridge = nativeNTPBackgroundImagesBridge;
    }

    @CalledByNative
    private static NTPBackgroundImagesBridge create(long nativeNTPBackgroundImagesBridge) {
        return new NTPBackgroundImagesBridge(nativeNTPBackgroundImagesBridge);
    }

    /**
     * Destroys this instance so no further calls can be executed.
     */
    @CalledByNative
    public void destroy() {
        mNativeNTPBackgroundImagesBridge = 0;
        mObservers.clear();
    }

    /**
     * @param observer The observer to be added.
     */
    public void addObserver(NTPBackgroundImageServiceObserver observer) {
        mObservers.addObserver(observer);
    }

    /**
     * @param observer The observer to be removed.
     */
    public void removeObserver(NTPBackgroundImageServiceObserver observer) {
        mObservers.removeObserver(observer);
    }

    public static boolean enableSponsoredImages() {
        BraveRewardsNativeWorker braveRewardsNativeWorker = BraveRewardsNativeWorker.getInstance();
        return braveRewardsNativeWorker != null && braveRewardsNativeWorker.isSupported();
    }

    public static NTPBackgroundImagesBridge getInstance(Profile profile) {
        return NTPBackgroundImagesBridgeJni.get().getInstance(profile);
    }

    @Nullable
    public NTPImage getCurrentWallpaper() {
        ThreadUtils.assertOnUiThread();
        if (enableSponsoredImages()) {
            return NTPBackgroundImagesBridgeJni.get().getCurrentWallpaper(
                mNativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge.this);
        } else {
            return null;
        }
    }

    public void registerPageView() {
        NTPBackgroundImagesBridgeJni.get().registerPageView(
                mNativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge.this);
    }

    public void wallpaperLogoClicked(Wallpaper wallpaper) {
        NTPBackgroundImagesBridgeJni.get()
                .wallpaperLogoClicked(
                        mNativeNTPBackgroundImagesBridge,
                        NTPBackgroundImagesBridge.this,
                        wallpaper.getWallpaperId(),
                        wallpaper.getCreativeInstanceId(),
                        wallpaper.getLogoDestinationUrl(),
                        wallpaper.shouldMetricsFallbackToP3a());
    }

    public boolean isSuperReferral() {
        return NTPBackgroundImagesBridgeJni.get().isSuperReferral(
                mNativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge.this);
    }

    public String getSuperReferralThemeName() {
        return NTPBackgroundImagesBridgeJni.get().getSuperReferralThemeName(
                mNativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge.this);
    }

    public String getSuperReferralCode() {
        return NTPBackgroundImagesBridgeJni.get().getSuperReferralCode(
                mNativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge.this);
    }

    public void getTopSites() {
        sTopSites.clear();
        NTPBackgroundImagesBridgeJni.get()
                .getTopSites(mNativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge.this);
    }

    public String getReferralApiKey() {
        return NTPBackgroundImagesBridgeJni.get().getReferralApiKey(
                mNativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge.this);
    }

    public void setNewTabPageListener(NewTabPageListener newTabPageListener) {
        sNewTabPageListener = newTabPageListener;
    }

    @CalledByNative
    public static void loadTopSitesData(
            String name, String destinationUrl, String backgroundColor, String imagePath) {
        sTopSites.add(new TopSite(name, destinationUrl, backgroundColor, imagePath));
    }

    @CalledByNative
    public static void topSitesLoaded() {
        sNewTabPageListener.updateTopSites(sTopSites);
    }

    @CalledByNative
    public static BackgroundImage createWallpaper(String imagePath, String author, String link) {
        return new BackgroundImage(imagePath, 0, 0, new ImageCredit(author, link));
    }

    @CalledByNative
    public static Wallpaper createBrandedWallpaper(
            String imagePath,
            int focalPointX,
            int focalPointY,
            String logoPath,
            String logoDestinationUrl,
            String themeName,
            boolean isSponsored,
            String creativeInstanceId,
            String wallpaperId,
            boolean isRichMedia,
            boolean shouldMetricsFallbackToP3a) {
        return new Wallpaper(
                imagePath,
                focalPointX,
                focalPointY,
                logoPath,
                logoDestinationUrl,
                themeName,
                isSponsored,
                creativeInstanceId,
                wallpaperId,
                isRichMedia,
                shouldMetricsFallbackToP3a);
    }

    @CalledByNative
    public void onUpdated() {
        for (NTPBackgroundImageServiceObserver observer : mObservers) {
            observer.onUpdated();
        }
    }

    @NativeMethods
    interface Natives {
        NTPBackgroundImagesBridge getInstance(Profile profile);

        NTPImage getCurrentWallpaper(
                long nativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge caller);

        void registerPageView(
                long nativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge caller);

        void wallpaperLogoClicked(
                long nativeNTPBackgroundImagesBridge,
                NTPBackgroundImagesBridge caller,
                String wallpaperId,
                String creativeInstanceId,
                String destinationUrl,
                boolean shouldMetricsFallbackToP3a);

        void getTopSites(long nativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge caller);

        boolean isSuperReferral(
                long nativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge caller);

        String getSuperReferralThemeName(
                long nativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge caller);

        String getSuperReferralCode(
                long nativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge caller);

        String getReferralApiKey(
                long nativeNTPBackgroundImagesBridge, NTPBackgroundImagesBridge caller);
    }
}
