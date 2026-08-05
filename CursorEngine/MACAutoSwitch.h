#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MACPreferencesAutoSwitchRulesKey;
extern NSString * const MACAutoSwitchDidChangeNotification;
extern NSString * const MACAutoSwitchAppliedThemeDidChangeNotification;

extern NSString * MACAutoSwitchThemePathForIdentifier(NSString *identifier);

extern NSString * _Nullable MACAutoSwitchResolveScheduleTheme(NSArray * _Nullable rules, NSInteger nowMinutes);
extern NSString * _Nullable MACAutoSwitchResolveAppearanceTheme(NSArray * _Nullable rules, BOOL darkAppearance);
extern NSInteger MACAutoSwitchMinutesUntilNextBoundary(NSArray * _Nullable rules, NSInteger nowMinutes);
extern NSInteger MACAutoSwitchCurrentMinuteOfDay(void);
extern NSDictionary * _Nullable MACAutoSwitchReadConfig(void);
extern BOOL MACAutoSwitchUsesSystemAppearance(NSDictionary * _Nullable config);
extern BOOL MACAutoSwitchSystemUsesDarkAppearance(void);
extern BOOL MACAutoSwitchUsesColorAdjustment(NSDictionary * _Nullable config);
extern NSString * _Nullable MACAutoSwitchResolveThemeIdentifier(NSDictionary * _Nullable config, NSInteger nowMinutes);

extern NSString * _Nullable MACAutoSwitchPendingIdentifier(NSString * _Nullable desired, NSString * _Nullable current);
extern BOOL MACAutoSwitchApplyIfNeeded(void);
extern BOOL MACAutoSwitchReapplyCurrentConfiguration(void);

NS_ASSUME_NONNULL_END
