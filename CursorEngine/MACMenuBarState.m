#import "MACMenuBarState.h"
#import "MACCursorDefs.h"
#import "MACAutoSwitch.h"
#import <sys/stat.h>

NSString * const MACMenuBarThemeIdentifierKey = @"identifier";
NSString * const MACMenuBarThemeNameKey = @"name";
NSString * const MACHelperBundleIdentifier = @"com.writronic.macursor.helper";
NSString * const MACHelperBundleName = @"MaCursorHelper";
NSString * const MACAppBundleIdentifier = @"com.writronic.macursor";
NSString * const MACPreferencesShowMenuBarIconKey = @"MACShowMenuBarIcon";
NSString * const MACPreferencesPendingOpenSettingsKey = @"MACPendingOpenSettings";
NSString * const MACPreferencesPendingFFMAccessWindowKey = @"MACPendingFFMAccessWindow";
NSString * const MACMenuBarDidChangeNotification = @"MACMenuBarDidChange";
NSString * const MACOpenSettingsRequestedNotification = @"MACOpenSettingsRequested";
NSString * const MACFocusFollowsMouseShowAccessWindowNotification = @"MACFocusFollowsMouseShowAccessWindow";

static NSString * _Nullable nonEmptyString(id candidate) {
    if (![candidate isKindOfClass:[NSString class]]) return nil;
    return [(NSString *)candidate length] > 0 ? (NSString *)candidate : nil;
}

static NSDictionary * _Nullable catalogEntryForThemeFile(NSString *path) {
    static NSMutableDictionary<NSString *, NSDictionary *> *cache = nil;
    if (cache == nil) cache = [NSMutableDictionary dictionary];

    NSDate *modified = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL][NSFileModificationDate];
    if (modified == nil) return nil;

    NSDictionary *cached = cache[path];
    if (cached && [cached[@"modified"] isEqualToDate:modified]) {
        return [cached[@"entry"] isKindOfClass:[NSDictionary class]] ? cached[@"entry"] : nil;
    }

    NSDictionary *entry = nil;
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    NSString *identifier = [plist isKindOfClass:[NSDictionary class]]
        ? nonEmptyString(plist[MACCursorDictionaryIdentifierKey]) : nil;
    if (identifier != nil) {
        entry = @{ MACMenuBarThemeIdentifierKey: identifier,
                   MACMenuBarThemeNameKey: nonEmptyString(plist[MACCursorDictionaryThemeNameKey]) ?: identifier };
    }
    cache[path] = @{ @"modified": modified, @"entry": entry ?: [NSNull null] };
    return entry;
}

NSArray<NSDictionary *> * MACMenuBarThemeCatalogAtPath(NSString * _Nullable directory) {
    NSMutableArray<NSDictionary *> *catalog = [NSMutableArray array];
    if (nonEmptyString(directory) == nil) return catalog;

    NSArray<NSString *> *names = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:(NSString *)directory error:NULL];
    if (![names isKindOfClass:[NSArray class]]) return catalog;

    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray<NSString *> *sorted = [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];

    for (NSString *name in sorted) {
        if ([name hasPrefix:@"."]) continue;
        if (![[name pathExtension] isEqualToString:@"cursor"]) continue;

        NSDictionary *entry = catalogEntryForThemeFile([(NSString *)directory stringByAppendingPathComponent:name]);
        if (entry == nil) continue;
        NSString *identifier = entry[MACMenuBarThemeIdentifierKey];
        if ([seen containsObject:identifier]) continue;
        [seen addObject:identifier];
        [catalog addObject:entry];
    }

    return catalog;
}

NSArray<NSDictionary *> * MACMenuBarThemeCatalog(void) {
    NSURL *appSupportURL = [[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask].firstObject;
    if (appSupportURL == nil) return @[];
    return MACMenuBarThemeCatalogAtPath([appSupportURL.path stringByAppendingPathComponent:@"MaCursor/cursors"]);
}

NSString * _Nullable MACMenuBarVisibleThemeIdentifier(NSString * _Nullable appliedIdentifier,
                                                      NSString * _Nullable activeOverride) {
    NSString *override = nonEmptyString(activeOverride);
    if (override != nil) return override;
    return nonEmptyString(appliedIdentifier);
}

static NSMutableDictionary * mutableConfig(NSDictionary * _Nullable config) {
    if (![config isKindOfClass:[NSDictionary class]]) return [NSMutableDictionary dictionary];
    return [config mutableCopy];
}

NSDictionary * MACMenuBarConfigBySettingSwitchByApp(NSDictionary * _Nullable config, BOOL enabled) {
    NSMutableDictionary *updated = mutableConfig(config);
    updated[@"switchByApp"] = @(enabled);
    return updated;
}

NSDictionary * MACMenuBarConfigBySettingRule(NSDictionary * _Nullable config,
                                             NSString * _Nullable bundleIdentifier,
                                             NSString * _Nullable displayName,
                                             NSString * _Nullable themeIdentifier) {
    NSMutableDictionary *updated = mutableConfig(config);
    NSString *bundle = nonEmptyString(bundleIdentifier);
    if (bundle == nil) return updated;

    id existing = updated[@"appRules"];
    NSMutableArray *rules = [existing isKindOfClass:[NSArray class]]
        ? [(NSArray *)existing mutableCopy]
        : [NSMutableArray array];

    NSString *theme = nonEmptyString(themeIdentifier);
    NSString *name = nonEmptyString(displayName);

    for (NSUInteger index = 0; index < rules.count; index++) {
        id candidate = rules[index];
        if (![candidate isKindOfClass:[NSDictionary class]]) continue;
        if (![nonEmptyString(((NSDictionary *)candidate)[@"bundleIdentifier"]) isEqualToString:bundle]) continue;

        NSMutableDictionary *rule = [(NSDictionary *)candidate mutableCopy];
        if (nonEmptyString(rule[@"id"]) == nil) rule[@"id"] = [[NSUUID UUID] UUIDString];
        if (theme != nil) {
            rule[@"themeIdentifier"] = theme;
        } else {
            [rule removeObjectForKey:@"themeIdentifier"];
        }
        if (name != nil) rule[@"displayName"] = name;
        rules[index] = rule;
        updated[@"appRules"] = rules;
        return updated;
    }

    NSMutableDictionary *rule = [NSMutableDictionary dictionary];
    rule[@"id"] = [[NSUUID UUID] UUIDString];
    rule[@"bundleIdentifier"] = bundle;
    if (theme != nil) rule[@"themeIdentifier"] = theme;
    if (name != nil) rule[@"displayName"] = name;
    [rules addObject:rule];
    updated[@"appRules"] = rules;
    return updated;
}

NSString * _Nullable MACMenuBarRuleThemeForBundleID(NSDictionary * _Nullable config,
                                                    NSString * _Nullable bundleIdentifier) {
    NSString *bundle = nonEmptyString(bundleIdentifier);
    if (bundle == nil) return nil;
    if (![config isKindOfClass:[NSDictionary class]]) return nil;

    id existing = config[@"appRules"];
    if (![existing isKindOfClass:[NSArray class]]) return nil;

    for (id candidate in (NSArray *)existing) {
        if (![candidate isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *rule = (NSDictionary *)candidate;
        if (![nonEmptyString(rule[@"bundleIdentifier"]) isEqualToString:bundle]) continue;
        return nonEmptyString(rule[@"themeIdentifier"]);
    }
    return nil;
}

BOOL MACMenuBarWriteConfig(NSDictionary * _Nullable config) {
    if (![config isKindOfClass:[NSDictionary class]]) return NO;
    if (![NSJSONSerialization isValidJSONObject:config]) return NO;

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:config options:0 error:&error];
    if (data == nil || error != nil) return NO;

    MACSetDefault(data, MACPreferencesAutoSwitchRulesKey);

    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:MACAutoSwitchDidChangeNotification
                      object:nil
                    userInfo:nil
          deliverImmediately:YES];
    return YES;
}

BOOL MACMenuBarIsHelperBundleIdentifier(NSString * _Nullable bundleIdentifier) {
    NSString *bundle = nonEmptyString(bundleIdentifier);
    if (bundle == nil) return NO;
    return [bundle caseInsensitiveCompare:MACHelperBundleIdentifier] == NSOrderedSame;
}

static NSString *sLastForegroundBundleID = nil;

void MACMenuBarNoteForegroundBundleID(NSString * _Nullable bundleIdentifier) {
    NSString *bundle = nonEmptyString(bundleIdentifier);
    if (bundle == nil) return;
    if (MACMenuBarIsHelperBundleIdentifier(bundle)) return;
    sLastForegroundBundleID = [bundle copy];
}

NSString * _Nullable MACMenuBarLastForegroundBundleID(void) {
    return sLastForegroundBundleID;
}

NSString * const MACCursorPreferencesDidChangeNotification = @"MACCursorPreferencesDidChange";

const double MACMenuBarMinCursorScale = 0.5;
const double MACMenuBarMaxCursorScale = 4.0;

NSDictionary * MACMenuBarFFMConfigBySettingEnabled(NSDictionary * _Nullable config, BOOL enabled) {
    NSMutableDictionary *updated = mutableConfig(config);
    updated[@"enabled"] = @(enabled);
    return updated;
}

NSString * const MACPreferencesMenuBarPanelBackgroundKey = @"MACMenuBarPanelBackground";
const double MACMenuBarPanelBackgroundDefault = 0.5;

double MACMenuBarPanelBackgroundLevel(id _Nullable stored) {
    if (![stored isKindOfClass:[NSNumber class]]) return MACMenuBarPanelBackgroundDefault;
    double level = [(NSNumber *)stored doubleValue];
    if (isnan(level) || isinf(level)) return MACMenuBarPanelBackgroundDefault;
    return MIN(1.0, MAX(0.0, level));
}

double MACMenuBarPanelGlassAlpha(double level) {
    return MIN(1.0, MAX(0.0, level / MACMenuBarPanelBackgroundDefault));
}

double MACMenuBarPanelBackdropAlpha(double level) {
    return MIN(1.0, MAX(0.0, (level - MACMenuBarPanelBackgroundDefault) / (1.0 - MACMenuBarPanelBackgroundDefault)));
}

NSString * const MACPreferencesFavoriteThemesKey = @"MACFavoriteThemes";

NSArray<NSString *> * MACMenuBarFavoriteThemeIdentifiers(id _Nullable stored) {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    if (![stored isKindOfClass:[NSArray class]]) return identifiers;
    for (id candidate in (NSArray *)stored) {
        NSString *identifier = nonEmptyString(candidate);
        if (identifier == nil || [identifiers containsObject:identifier]) continue;
        [identifiers addObject:identifier];
    }
    return identifiers;
}

NSArray<NSDictionary *> * MACMenuBarFavoriteCatalog(NSArray<NSDictionary *> * _Nullable catalog,
                                                    id _Nullable stored) {
    NSMutableArray<NSDictionary *> *favorites = [NSMutableArray array];
    NSSet<NSString *> *wanted = [NSSet setWithArray:MACMenuBarFavoriteThemeIdentifiers(stored)];
    if (wanted.count == 0 || ![catalog isKindOfClass:[NSArray class]]) return favorites;
    for (NSDictionary *entry in catalog) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *identifier = nonEmptyString(entry[MACMenuBarThemeIdentifierKey]);
        if (identifier != nil && [wanted containsObject:identifier]) [favorites addObject:entry];
    }
    return favorites;
}

double MACMenuBarClampCursorScale(double scale) {
    if (isnan(scale) || isinf(scale)) return 1.0;
    if (scale < MACMenuBarMinCursorScale) return MACMenuBarMinCursorScale;
    if (scale > MACMenuBarMaxCursorScale) return MACMenuBarMaxCursorScale;
    return scale;
}

NSAppearanceName _Nullable MACMenuBarAppearanceNameForMode(id _Nullable mode) {
    if (![mode isKindOfClass:[NSNumber class]]) return nil;
    switch ([(NSNumber *)mode integerValue]) {
        case 1: return NSAppearanceNameAqua;
        case 2: return NSAppearanceNameDarkAqua;
        default: return nil;
    }
}

BOOL MACMenuBarClickIsSecondary(NSEventType type, NSEventModifierFlags flags) {
    if (type == NSEventTypeRightMouseUp || type == NSEventTypeRightMouseDown) return YES;
    return type == NSEventTypeLeftMouseUp && (flags & NSEventModifierFlagControl) != 0;
}

NSData * _Nullable MACMenuBarThemeThumbnailData(NSDictionary * _Nullable theme,
                                                 NSUInteger * _Nullable outFrameCount) {
    if (outFrameCount) *outFrameCount = 1;
    if (![theme isKindOfClass:[NSDictionary class]]) return nil;
    id cursors = theme[MACCursorDictionaryCursorsKey];
    if (![cursors isKindOfClass:[NSDictionary class]]) return nil;

    NSDictionary *entry = nil;
    for (NSString *identifier in @[@"com.apple.coregraphics.Arrow", @"com.apple.coregraphics.ArrowS"]) {
        id candidate = ((NSDictionary *)cursors)[identifier];
        if (![candidate isKindOfClass:[NSDictionary class]]) continue;
        id reps = ((NSDictionary *)candidate)[MACCursorDictionaryRepresentationsKey];
        if (![reps isKindOfClass:[NSArray class]] || [(NSArray *)reps count] == 0) continue;
        entry = candidate;
        break;
    }
    if (entry == nil) return nil;

    NSData *best = nil;
    for (id rep in entry[MACCursorDictionaryRepresentationsKey]) {
        if (![rep isKindOfClass:[NSData class]]) continue;
        if (best == nil || [(NSData *)rep length] > best.length) best = rep;
    }
    if (best == nil) return nil;

    id frames = entry[MACCursorDictionaryFrameCountKey];
    if (outFrameCount && [frames isKindOfClass:[NSNumber class]] && [frames integerValue] > 1) {
        *outFrameCount = (NSUInteger)[frames integerValue];
    }
    return best;
}

NSImage * _Nullable MACMenuBarThumbnailImageFromData(NSData * _Nullable data, NSUInteger frameCount) {
    if (data.length == 0) return nil;
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:(NSData *)data];
    if (rep == nil || rep.CGImage == NULL) return nil;

    NSInteger width = rep.pixelsWide;
    NSInteger height = rep.pixelsHigh;
    if (width <= 0 || height <= 0) return nil;

    NSUInteger frames = MAX(frameCount, (NSUInteger)1);
    NSInteger frameHeight = frames > 1 ? MAX(height / (NSInteger)frames, (NSInteger)1) : height;
    CGImageRef source = rep.CGImage;
    CGImageRef cropped = frames > 1
        ? CGImageCreateWithImageInRect(source, CGRectMake(0, 0, width, frameHeight))
        : CGImageRetain(source);
    if (cropped == NULL) return nil;

    NSBitmapImageRep *frameRep = [[NSBitmapImageRep alloc] initWithCGImage:cropped];
    CGImageRelease(cropped);
    if (frameRep == nil) return nil;
    NSSize points = NSMakeSize(width / 2.0, frameHeight / 2.0);
    frameRep.size = points;
    NSImage *image = [[NSImage alloc] initWithSize:points];
    [image addRepresentation:frameRep];
    return image;
}

NSImage * _Nullable MACMenuBarThumbnailImageForThemeAtPath(NSString * _Nullable path) {
    if (nonEmptyString(path) == nil) return nil;
    NSDictionary *theme = [NSDictionary dictionaryWithContentsOfFile:(NSString *)path];
    NSUInteger frames = 1;
    NSData *data = MACMenuBarThemeThumbnailData(theme, &frames);
    return MACMenuBarThumbnailImageFromData(data, frames);
}

NSString * const MACPreferencesHelperBuildKey = @"MACHelperBuild";

NSString * _Nullable MACHelperBuildIdentityAtPath(NSString * _Nullable path) {
    struct stat info;
    if (nonEmptyString(path) == nil || stat(((NSString *)path).fileSystemRepresentation, &info) != 0) return nil;
    return [NSString stringWithFormat:@"%lld:%llu:%lld.%09ld",
            (long long)info.st_dev, (unsigned long long)info.st_ino,
            (long long)info.st_ctimespec.tv_sec, (long)info.st_ctimespec.tv_nsec];
}

BOOL MACHelperNeedsRestart(BOOL running,
                           NSString * _Nullable runningBuild,
                           NSString * _Nullable bundledBuild) {
    if (bundledBuild == nil) return NO;
    if (!running) return YES;
    return ![bundledBuild isEqualToString:runningBuild ?: @""];
}
