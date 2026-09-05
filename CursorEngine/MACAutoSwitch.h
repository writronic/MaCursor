#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MACPreferencesAutoSwitchRulesKey;
extern NSString * const MACPreferencesAppOverrideKey;
extern NSString * const MACPreferencesAppOverrideBaseKey;
extern NSString * const MACAutoSwitchDidChangeNotification;
extern NSString * const MACAutoSwitchAppliedThemeDidChangeNotification;

typedef NS_ENUM(NSInteger, MACAppSwitchAction) {
    MACAppSwitchActionNone = 0,
    MACAppSwitchActionApplyOverride,
    MACAppSwitchActionRevert,
};

extern NSString * MACAutoSwitchThemePathForIdentifier(NSString *identifier);

extern NSString * _Nullable MACAutoSwitchResolveScheduleTheme(NSArray * _Nullable rules, NSInteger nowMinutes);
extern NSInteger MACAutoSwitchMinutesUntilNextBoundary(NSArray * _Nullable rules, NSInteger nowMinutes);
extern NSInteger MACAutoSwitchCurrentMinuteOfDay(void);
extern NSDictionary * _Nullable MACAutoSwitchReadConfig(void);
extern NSString * _Nullable MACAutoSwitchResolveThemeIdentifier(NSDictionary * _Nullable config, NSInteger nowMinutes);

extern BOOL MACAutoSwitchAppRulesActive(NSDictionary * _Nullable config);
extern NSString * _Nullable MACAutoSwitchThemeForBundleID(NSDictionary * _Nullable config, NSString * _Nullable bundleID);
extern MACAppSwitchAction MACAutoSwitchAppActionForState(NSString * _Nullable ruleTheme, NSString * _Nullable activeOverride);
extern void MACAutoSwitchHandleFrontmostApp(NSString * _Nullable bundleID);
extern void MACAutoSwitchClearAppOverride(void);
extern void MACAutoSwitchRecoverBaseThemeIfNeeded(void);

extern BOOL MACAutoSwitchMatchesSystemAppearance(NSDictionary * _Nullable config);
extern NSString * _Nullable MACAutoSwitchThemeForAppearance(NSDictionary * _Nullable config, BOOL isDark);
extern BOOL MACAutoSwitchIsSystemInDarkMode(void);

extern NSString * _Nullable MACAutoSwitchPendingIdentifier(NSString * _Nullable desired, NSString * _Nullable current);
extern NSString * _Nullable MACAutoSwitchLaunchThemeIdentifier(NSDictionary * _Nullable config, NSInteger nowMinutes, NSString * _Nullable storedIdentifier);
extern BOOL MACAutoSwitchApplyIfNeeded(void);
extern void MACAutoSwitchForceVisualRefresh(void);

NS_ASSUME_NONNULL_END
