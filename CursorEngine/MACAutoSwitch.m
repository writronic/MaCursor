#import "MACAutoSwitch.h"
#import "MACCursorDefs.h"
#import "MACCursorActions.h"
#import <AppKit/AppKit.h>

NSString * const MACPreferencesAutoSwitchRulesKey = @"MACAutoSwitchRules";
NSString * const MACPreferencesAppOverrideKey = @"MACAutoSwitchAppOverride";
NSString * const MACPreferencesAppOverrideBaseKey = @"MACAutoSwitchAppOverrideBase";
NSString * const MACAutoSwitchDidChangeNotification = @"MACAutoSwitchDidChange";
NSString * const MACAutoSwitchAppliedThemeDidChangeNotification = @"MACAutoSwitchAppliedThemeDidChange";

NSString * MACAutoSwitchThemePathForIdentifier(NSString *identifier) {
    NSURL *appSupportURL = [[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask].firstObject;
    return [[[appSupportURL.path stringByAppendingPathComponent:@"MaCursor/cursors"]
        stringByAppendingPathComponent:identifier]
        stringByAppendingPathExtension:@"cursor"];
}

static BOOL usableRule(id candidate, NSString **outTheme, NSInteger *outMinutes) {
    if (![candidate isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *dict = (NSDictionary *)candidate;

    id theme = dict[@"themeIdentifier"];
    if (![theme isKindOfClass:[NSString class]]) return NO;
    if ([(NSString *)theme length] == 0) return NO;

    id minutes = dict[@"startMinutes"];
    if (![minutes isKindOfClass:[NSNumber class]]) return NO;
    if (strcmp([(NSNumber *)minutes objCType], @encode(BOOL)) == 0) return NO;
    NSInteger value = [(NSNumber *)minutes integerValue];
    if (value < 0 || value > 1439) return NO;

    if (outTheme) *outTheme = (NSString *)theme;
    if (outMinutes) *outMinutes = value;
    return YES;
}

NSString * _Nullable MACAutoSwitchResolveScheduleTheme(NSArray * _Nullable rules, NSInteger nowMinutes) {
    if (![rules isKindOfClass:[NSArray class]] || rules.count == 0) return nil;

    NSString *passedTheme = nil;
    NSInteger passedMinutes = -1;
    NSString *latestTheme = nil;
    NSInteger latestMinutes = -1;

    for (id candidate in rules) {
        NSString *theme = nil;
        NSInteger minutes = 0;
        if (!usableRule(candidate, &theme, &minutes)) continue;

        if (minutes >= latestMinutes) {
            latestMinutes = minutes;
            latestTheme = theme;
        }
        if (minutes <= nowMinutes && minutes >= passedMinutes) {
            passedMinutes = minutes;
            passedTheme = theme;
        }
    }

    return passedTheme ?: latestTheme;
}

NSInteger MACAutoSwitchMinutesUntilNextBoundary(NSArray * _Nullable rules, NSInteger nowMinutes) {
    if (![rules isKindOfClass:[NSArray class]] || rules.count == 0) return -1;

    NSInteger best = -1;
    for (id candidate in rules) {
        NSInteger minutes = 0;
        if (!usableRule(candidate, NULL, &minutes)) continue;

        NSInteger delta = minutes - nowMinutes;
        if (delta <= 0) delta += 1440;
        if (best < 0 || delta < best) best = delta;
    }
    return best;
}

NSInteger MACAutoSwitchCurrentMinuteOfDay(void) {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *parts = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                          fromDate:[NSDate date]];
    return parts.hour * 60 + parts.minute;
}

NSDictionary * _Nullable MACAutoSwitchReadConfig(void) {
    CFPreferencesSynchronize((__bridge CFStringRef)kMACDomain,
                             kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    id raw = (__bridge_transfer id)CFPreferencesCopyAppValue(
        (__bridge CFStringRef)MACPreferencesAutoSwitchRulesKey,
        (__bridge CFStringRef)kMACDomain);
    if (![raw isKindOfClass:[NSData class]]) return nil;

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:(NSData *)raw options:0 error:&error];
    if (error || ![parsed isKindOfClass:[NSDictionary class]]) return nil;
    return (NSDictionary *)parsed;
}

static BOOL usableAppRule(id candidate, NSString **outTheme, NSString **outBundle) {
    if (![candidate isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *dict = (NSDictionary *)candidate;

    id theme = dict[@"themeIdentifier"];
    if (![theme isKindOfClass:[NSString class]]) return NO;
    if ([(NSString *)theme length] == 0) return NO;

    id bundle = dict[@"bundleIdentifier"];
    if (![bundle isKindOfClass:[NSString class]]) return NO;
    if ([(NSString *)bundle length] == 0) return NO;

    if (outTheme) *outTheme = (NSString *)theme;
    if (outBundle) *outBundle = (NSString *)bundle;
    return YES;
}

BOOL MACAutoSwitchAppRulesActive(NSDictionary * _Nullable config) {
    if (![config isKindOfClass:[NSDictionary class]]) return NO;

    id flag = config[@"switchByApp"];
    if (![flag isKindOfClass:[NSNumber class]] || ![flag boolValue]) return NO;

    id rules = config[@"appRules"];
    if (![rules isKindOfClass:[NSArray class]]) return NO;
    for (id candidate in (NSArray *)rules) {
        if (usableAppRule(candidate, NULL, NULL)) return YES;
    }
    return NO;
}

NSString * _Nullable MACAutoSwitchThemeForBundleID(NSDictionary * _Nullable config, NSString * _Nullable bundleID) {
    if (bundleID.length == 0) return nil;
    if (!MACAutoSwitchAppRulesActive(config)) return nil;

    for (id candidate in (NSArray *)config[@"appRules"]) {
        NSString *theme = nil;
        NSString *bundle = nil;
        if (!usableAppRule(candidate, &theme, &bundle)) continue;
        if ([bundle isEqualToString:bundleID]) return theme;
    }
    return nil;
}

BOOL MACAutoSwitchMatchesSystemAppearance(NSDictionary * _Nullable config) {
    if (![config isKindOfClass:[NSDictionary class]]) return NO;
    id flag = config[@"matchSystemAppearance"];
    if (![flag isKindOfClass:[NSNumber class]]) return NO;
    return [flag boolValue];
}

NSString * _Nullable MACAutoSwitchThemeForAppearance(NSDictionary * _Nullable config, BOOL isDark) {
    if (![config isKindOfClass:[NSDictionary class]]) return nil;
    id identifier = config[isDark ? @"darkThemeIdentifier" : @"lightThemeIdentifier"];
    if (![identifier isKindOfClass:[NSString class]]) return nil;
    return [(NSString *)identifier length] > 0 ? (NSString *)identifier : nil;
}

BOOL MACAutoSwitchIsSystemInDarkMode(void) {
    NSApplication *app = NSApp;
    if (app != nil && app.appearance == nil) {
        NSAppearanceName match = [app.effectiveAppearance
            bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [match isEqualToString:NSAppearanceNameDarkAqua];
    }

    CFPreferencesSynchronize(kCFPreferencesAnyApplication,
                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    id style = (__bridge_transfer id)CFPreferencesCopyValue(CFSTR("AppleInterfaceStyle"),
        kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (![style isKindOfClass:[NSString class]]) return NO;
    return [(NSString *)style caseInsensitiveCompare:@"dark"] == NSOrderedSame;
}

NSString * _Nullable MACAutoSwitchResolveThemeIdentifier(NSDictionary * _Nullable config, NSInteger nowMinutes) {
    if (![config isKindOfClass:[NSDictionary class]]) return nil;
    id enabledFlag = config[@"enabled"];
    if (![enabledFlag isKindOfClass:[NSNumber class]] || ![enabledFlag boolValue]) return nil;
    if (MACAutoSwitchMatchesSystemAppearance(config)) {
        return MACAutoSwitchThemeForAppearance(config, MACAutoSwitchIsSystemInDarkMode());
    }
    return MACAutoSwitchResolveScheduleTheme(config[@"scheduleRules"], nowMinutes);
}

NSString * _Nullable MACAutoSwitchPendingIdentifier(NSString * _Nullable desired, NSString * _Nullable current) {
    if (desired.length == 0) return nil;
    if (current.length > 0 && [desired isEqualToString:current]) return nil;
    return desired;
}

NSString * _Nullable MACAutoSwitchLaunchThemeIdentifier(NSDictionary * _Nullable config, NSInteger nowMinutes, NSString * _Nullable storedIdentifier) {
    NSString *resolved = MACAutoSwitchResolveThemeIdentifier(config, nowMinutes);
    if (resolved.length > 0) return resolved;
    if (![storedIdentifier isKindOfClass:[NSString class]]) return nil;
    return storedIdentifier.length > 0 ? storedIdentifier : nil;
}

void MACAutoSwitchForceVisualRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSPoint loc = [NSEvent mouseLocation];
        NSRect windowRect = NSMakeRect(loc.x, loc.y, 1, 1);

        NSWindow *invisibleWindow = [[NSWindow alloc] initWithContentRect:windowRect
                                                                styleMask:NSWindowStyleMaskBorderless
                                                                  backing:NSBackingStoreBuffered
                                                                    defer:NO];
        [invisibleWindow setReleasedWhenClosed:NO];
        [invisibleWindow setOpaque:NO];
        [invisibleWindow setBackgroundColor:[NSColor clearColor]];
        [invisibleWindow setIgnoresMouseEvents:NO];
        [invisibleWindow setLevel:NSFloatingWindowLevel];
        [invisibleWindow setHasShadow:NO];

        [invisibleWindow orderFront:nil];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MACWindowDismissDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [invisibleWindow close];
        });
    });

    MMLog(BOLD CYAN "Forcing visual refresh via Invisible Window trick" RESET);
}

static NSString * _Nullable MACAutoSwitchActiveAppOverride(void) {
    id stored = MACDefault(MACPreferencesAppOverrideKey);
    if (![stored isKindOfClass:[NSString class]]) return nil;
    return [(NSString *)stored length] > 0 ? (NSString *)stored : nil;
}

BOOL MACAutoSwitchApplyIfNeeded(void) {
    NSDictionary *config = MACAutoSwitchReadConfig();
    NSString *desired = MACAutoSwitchResolveThemeIdentifier(config, MACAutoSwitchCurrentMinuteOfDay());

    id stored = MACDefault(MACPreferencesAppliedCursorKey);
    NSString *current = [stored isKindOfClass:[NSString class]] ? (NSString *)stored : nil;

    NSString *pending = MACAutoSwitchPendingIdentifier(desired, current);
    if (!pending) return NO;

    NSString *path = MACAutoSwitchThemePathForIdentifier(pending);
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        MMLog(BOLD YELLOW "Auto-switch target %s is missing on disk, keeping current cursor" RESET,
              [pending UTF8String]);
        return NO;
    }

    if (MACAutoSwitchActiveAppOverride()) {
        MACSetDefault(pending, MACPreferencesAppliedCursorKey);
        MMLog(BOLD CYAN "Auto-switch recorded %s as the base theme, app override stays on screen" RESET,
              [pending UTF8String]);
        [[NSDistributedNotificationCenter defaultCenter]
            postNotificationName:MACAutoSwitchAppliedThemeDidChangeNotification
                          object:nil
                        userInfo:nil
              deliverImmediately:YES];
        return NO;
    }

    if (!applyThemeAtPath(path)) {
        MMLog(BOLD RED "Auto-switch failed to apply %s" RESET, [pending UTF8String]);
        return NO;
    }

    MACSetDefault(pending, MACPreferencesAppliedCursorKey);
    MMLog(BOLD GREEN "Auto-switch applied %s" RESET, [pending UTF8String]);

    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:MACAutoSwitchAppliedThemeDidChangeNotification
                      object:nil
                    userInfo:nil
          deliverImmediately:YES];
    return YES;
}

MACAppSwitchAction MACAutoSwitchAppActionForState(NSString * _Nullable ruleTheme, NSString * _Nullable activeOverride) {
    if (ruleTheme.length > 0) {
        if (activeOverride.length > 0 && [ruleTheme isEqualToString:activeOverride]) {
            return MACAppSwitchActionNone;
        }
        return MACAppSwitchActionApplyOverride;
    }
    return activeOverride.length > 0 ? MACAppSwitchActionRevert : MACAppSwitchActionNone;
}

static NSString * _Nullable MACAutoSwitchStoredString(NSString *key) {
    id stored = MACDefault(key);
    if (![stored isKindOfClass:[NSString class]]) return nil;
    return [(NSString *)stored length] > 0 ? (NSString *)stored : nil;
}

void MACAutoSwitchClearAppOverride(void) {
    MACSetDefault(nil, MACPreferencesAppOverrideKey);
    MACSetDefault(nil, MACPreferencesAppOverrideBaseKey);
}

void MACAutoSwitchRecoverBaseThemeIfNeeded(void) {
    NSString *snapshot = MACAutoSwitchStoredString(MACPreferencesAppOverrideBaseKey);
    if (snapshot) {
        MACSetDefault(snapshot, MACPreferencesAppliedCursorKey);
        MMLog(BOLD YELLOW "Recovered base theme %s after an interrupted app override" RESET,
              [snapshot UTF8String]);
    }
    MACAutoSwitchClearAppOverride();
}

static BOOL applyIdentifierIfOnDisk(NSString *identifier) {
    NSString *path = MACAutoSwitchThemePathForIdentifier(identifier);
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        MMLog(BOLD YELLOW "App-switch target %s is missing on disk, keeping current cursor" RESET,
              [identifier UTF8String]);
        return NO;
    }
    if (!applyThemeAtPath(path)) {
        MMLog(BOLD RED "App-switch failed to apply %s" RESET, [identifier UTF8String]);
        return NO;
    }
    return YES;
}

void MACAutoSwitchHandleFrontmostApp(NSString * _Nullable bundleID) {
    NSDictionary *config = MACAutoSwitchReadConfig();
    NSString *ruleTheme = MACAutoSwitchThemeForBundleID(config, bundleID);
    NSString *override = MACAutoSwitchActiveAppOverride();

    switch (MACAutoSwitchAppActionForState(ruleTheme, override)) {
        case MACAppSwitchActionNone:
            return;
        case MACAppSwitchActionApplyOverride: {
            NSString *base = MACAutoSwitchStoredString(MACPreferencesAppOverrideBaseKey)
                ?: MACAutoSwitchStoredString(MACPreferencesAppliedCursorKey);
            if (base) MACSetDefault(base, MACPreferencesAppOverrideBaseKey);
            if (!applyIdentifierIfOnDisk(ruleTheme)) return;
            MACSetDefault(base, MACPreferencesAppliedCursorKey);
            MACSetDefault(ruleTheme, MACPreferencesAppOverrideKey);
            MMLog(BOLD GREEN "App switch applied %s for %s" RESET,
                  [ruleTheme UTF8String], [bundleID UTF8String]);
            MACAutoSwitchForceVisualRefresh();
            return;
        }
        case MACAppSwitchActionRevert: {
            NSString *storedId = MACAutoSwitchStoredString(MACPreferencesAppOverrideBaseKey)
                ?: MACAutoSwitchStoredString(MACPreferencesAppliedCursorKey);
            NSString *desired = MACAutoSwitchLaunchThemeIdentifier(config, MACAutoSwitchCurrentMinuteOfDay(), storedId);
            if (desired.length > 0) {
                if (!applyIdentifierIfOnDisk(desired)) return;
                MMLog(BOLD GREEN "App switch reverted to %s" RESET, [desired UTF8String]);
            } else {
                NSError *error = nil;
                if (!resetAllCursors(&error)) {
                    MMLog(BOLD RED "App switch could not restore the system cursors: %s" RESET,
                          [error.localizedDescription UTF8String]);
                    return;
                }
                MMLog(BOLD GREEN "App switch reverted to the system cursors" RESET);
            }
            MACAutoSwitchClearAppOverride();
            MACAutoSwitchForceVisualRefresh();
            return;
        }
    }
}
