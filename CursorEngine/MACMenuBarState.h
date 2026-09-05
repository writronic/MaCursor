#pragma once

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MACMenuBarThemeIdentifierKey;
extern NSString * const MACMenuBarThemeNameKey;
extern NSString * const MACHelperBundleIdentifier;
extern NSString * const MACHelperBundleName;
extern NSString * const MACAppBundleIdentifier;
extern NSString * const MACPreferencesShowMenuBarIconKey;
extern NSString * const MACPreferencesPendingOpenSettingsKey;
extern NSString * const MACPreferencesPendingFFMAccessWindowKey;
extern NSString * const MACMenuBarDidChangeNotification;
extern NSString * const MACOpenSettingsRequestedNotification;
extern NSString * const MACFocusFollowsMouseShowAccessWindowNotification;

extern NSArray<NSDictionary *> * MACMenuBarThemeCatalogAtPath(NSString * _Nullable directory);
extern NSArray<NSDictionary *> * MACMenuBarThemeCatalog(void);

extern NSString * _Nullable MACMenuBarVisibleThemeIdentifier(NSString * _Nullable appliedIdentifier,
                                                             NSString * _Nullable activeOverride);

extern NSDictionary * MACMenuBarConfigBySettingSwitchByApp(NSDictionary * _Nullable config, BOOL enabled);

extern NSDictionary * MACMenuBarConfigBySettingRule(NSDictionary * _Nullable config,
                                                    NSString * _Nullable bundleIdentifier,
                                                    NSString * _Nullable displayName,
                                                    NSString * _Nullable themeIdentifier);

extern NSString * _Nullable MACMenuBarRuleThemeForBundleID(NSDictionary * _Nullable config,
                                                           NSString * _Nullable bundleIdentifier);

extern BOOL MACMenuBarWriteConfig(NSDictionary * _Nullable config);

extern BOOL MACMenuBarIsHelperBundleIdentifier(NSString * _Nullable bundleIdentifier);

extern void MACMenuBarNoteForegroundBundleID(NSString * _Nullable bundleIdentifier);
extern NSString * _Nullable MACMenuBarLastForegroundBundleID(void);

extern NSString * const MACCursorPreferencesDidChangeNotification;

extern NSDictionary * MACMenuBarFFMConfigBySettingEnabled(NSDictionary * _Nullable config, BOOL enabled);

extern NSString * const MACPreferencesMenuBarPanelBackgroundKey;
extern const double MACMenuBarPanelBackgroundDefault;
extern double MACMenuBarPanelBackgroundLevel(id _Nullable stored);
extern double MACMenuBarPanelGlassAlpha(double level);
extern double MACMenuBarPanelBackdropAlpha(double level);

extern const double MACMenuBarMinCursorScale;
extern const double MACMenuBarMaxCursorScale;
extern double MACMenuBarClampCursorScale(double scale);

extern NSAppearanceName _Nullable MACMenuBarAppearanceNameForMode(id _Nullable mode);

extern BOOL MACMenuBarClickIsSecondary(NSEventType type, NSEventModifierFlags flags);

extern NSData * _Nullable MACMenuBarThemeThumbnailData(NSDictionary * _Nullable theme,
                                                        NSUInteger * _Nullable outFrameCount);
extern NSImage * _Nullable MACMenuBarThumbnailImageFromData(NSData * _Nullable data, NSUInteger frameCount);
extern NSImage * _Nullable MACMenuBarThumbnailImageForThemeAtPath(NSString * _Nullable path);

extern NSString * const MACPreferencesFavoriteThemesKey;
extern NSArray<NSString *> * MACMenuBarFavoriteThemeIdentifiers(id _Nullable stored);
extern NSArray<NSDictionary *> * MACMenuBarFavoriteCatalog(NSArray<NSDictionary *> * _Nullable catalog,
                                                           id _Nullable stored);

extern NSString * const MACPreferencesHelperBuildKey;
extern NSString * _Nullable MACHelperBuildIdentityAtPath(NSString * _Nullable path);
extern BOOL MACHelperNeedsRestart(BOOL running,
                                  NSString * _Nullable runningBuild,
                                  NSString * _Nullable bundledBuild);

NS_ASSUME_NONNULL_END
