#import "MACAutoSwitch.h"
#import "MACCursorDefs.h"
#import "MACCursorActions.h"
#import <AppKit/AppKit.h>

NSString * const MACPreferencesAutoSwitchRulesKey = @"MACAutoSwitchRules";
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

NSString * _Nullable MACAutoSwitchResolveAppearanceTheme(NSArray * _Nullable rules, BOOL darkAppearance) {
    if (![rules isKindOfClass:[NSArray class]] || rules.count == 0) return nil;

    NSString *desiredRole = darkAppearance ? @"night" : @"day";
    NSMutableArray<NSDictionary *> *usableRules = [NSMutableArray array];

    for (id candidate in rules) {
        NSString *theme = nil;
        NSInteger minutes = 0;
        if (!usableRule(candidate, &theme, &minutes)) continue;

        NSDictionary *dict = (NSDictionary *)candidate;
        if ([dict[@"role"] isKindOfClass:[NSString class]]
            && [dict[@"role"] isEqualToString:desiredRole]) {
            return theme;
        }
        [usableRules addObject:dict];
    }

    [usableRules sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"startMinutes"] compare:right[@"startMinutes"]];
    }];
    NSDictionary *fallback = darkAppearance ? usableRules.lastObject : usableRules.firstObject;
    return [fallback[@"themeIdentifier"] isKindOfClass:[NSString class]]
        ? fallback[@"themeIdentifier"] : nil;
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

BOOL MACAutoSwitchUsesSystemAppearance(NSDictionary * _Nullable config) {
    return [config isKindOfClass:[NSDictionary class]]
        && [config[@"followsSystemAppearance"] boolValue];
}

BOOL MACAutoSwitchSystemUsesDarkAppearance(void) {
    CFStringRef globalDomain = CFSTR(".GlobalPreferences");
    CFPreferencesSynchronize(globalDomain,
                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef rawValue = CFPreferencesCopyValue(
        CFSTR("AppleInterfaceStyle"), globalDomain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    BOOL isDark = rawValue
        && CFGetTypeID(rawValue) == CFStringGetTypeID()
        && [(__bridge NSString *)rawValue caseInsensitiveCompare:@"Dark"] == NSOrderedSame;
    if (rawValue) CFRelease(rawValue);
    return isDark;
}

BOOL MACAutoSwitchUsesColorAdjustment(NSDictionary * _Nullable config) {
    return [config isKindOfClass:[NSDictionary class]]
        && [config[@"colorAdjustmentEnabled"] boolValue];
}

NSString * _Nullable MACAutoSwitchResolveThemeIdentifier(NSDictionary * _Nullable config, NSInteger nowMinutes) {
    if (![config isKindOfClass:[NSDictionary class]]) return nil;
    if (![config[@"enabled"] boolValue]) return nil;
    if (MACAutoSwitchUsesSystemAppearance(config)) {
        return MACAutoSwitchResolveAppearanceTheme(
            config[@"scheduleRules"], MACAutoSwitchSystemUsesDarkAppearance());
    }
    return MACAutoSwitchResolveScheduleTheme(config[@"scheduleRules"], nowMinutes);
}

static NSColor *colorFromHexString(NSString *hex, NSColor *fallback) {
    NSString *clean = [[hex ?: @"" stringByReplacingOccurrencesOfString:@"#" withString:@""]
        uppercaseString];
    if (clean.length != 6) return fallback;

    unsigned int value = 0;
    if (![[NSScanner scannerWithString:clean] scanHexInt:&value]) return fallback;
    return [NSColor colorWithSRGBRed:((value >> 16) & 0xFF) / 255.0
                               green:((value >> 8) & 0xFF) / 255.0
                                blue:(value & 0xFF) / 255.0
                               alpha:1.0];
}

static NSColor *resolvedTargetColor(NSDictionary *config) {
    NSColor *base = colorFromHexString(config[@"baseColorHex"],
        [NSColor colorWithSRGBRed:1.0 green:131.0 / 255.0 blue:0 alpha:1]);
    if (![config[@"followsSystemAccent"] boolValue]) return base;

    NSColor *accent = [[NSColor controlAccentColor] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!accent) return base;

    CGFloat amount = [config[@"accentAdaptivity"] respondsToSelector:@selector(doubleValue)]
        ? [config[@"accentAdaptivity"] doubleValue] : 1.0;
    amount = MIN(MAX(amount, 0), 1);

    NSColor *rgbBase = [base colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: base;
    return [NSColor colorWithSRGBRed:rgbBase.redComponent * (1 - amount) + accent.redComponent * amount
                               green:rgbBase.greenComponent * (1 - amount) + accent.greenComponent * amount
                                blue:rgbBase.blueComponent * (1 - amount) + accent.blueComponent * amount
                               alpha:1.0];
}

static NSString *hexStringForColor(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
    return [NSString stringWithFormat:@"%02X%02X%02X",
        (int)lround(MIN(MAX(rgb.redComponent, 0), 1) * 255),
        (int)lround(MIN(MAX(rgb.greenComponent, 0), 1) * 255),
        (int)lround(MIN(MAX(rgb.blueComponent, 0), 1) * 255)];
}

static NSBitmapImageRep *bitmapForPNGData(NSData *data) {
    NSImage *image = [[NSImage alloc] initWithData:data];
    if (!image) return nil;

    NSRect proposed = NSMakeRect(0, 0, image.size.width, image.size.height);
    CGImageRef source = [image CGImageForProposedRect:&proposed context:nil hints:nil];
    if (!source) return nil;
    return [[NSBitmapImageRep alloc] initWithCGImage:source];
}

static BOOL detectFillColor(NSData *pngData, CGFloat *outRed, CGFloat *outGreen, CGFloat *outBlue) {
    NSBitmapImageRep *bitmap = bitmapForPNGData(pngData);
    if (!bitmap) return NO;

    NSUInteger bucketCount = 32 * 32 * 32;
    NSUInteger *counts = calloc(bucketCount, sizeof(NSUInteger));
    if (!counts) return NO;

    unsigned char *pixels = bitmap.bitmapData;
    NSInteger rowBytes = bitmap.bytesPerRow;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        unsigned char *row = pixels + y * rowBytes;
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            unsigned char *pixel = row + x * 4;
            if (pixel[3] < 230) continue;

            CGFloat red = pixel[0] / 255.0;
            CGFloat green = pixel[1] / 255.0;
            CGFloat blue = pixel[2] / 255.0;
            CGFloat maximum = MAX(red, MAX(green, blue));
            CGFloat minimum = MIN(red, MIN(green, blue));
            if (minimum > 0.82 && maximum - minimum < 0.12) continue;

            NSUInteger key = (pixel[0] >> 3) << 10
                | (pixel[1] >> 3) << 5
                | (pixel[2] >> 3);
            counts[key]++;
        }
    }

    NSUInteger bestKey = 0;
    NSUInteger bestCount = 0;
    for (NSUInteger key = 0; key < bucketCount; key++) {
        if (counts[key] > bestCount) {
            bestKey = key;
            bestCount = counts[key];
        }
    }
    free(counts);
    if (bestCount == 0) return NO;

    *outRed = (((bestKey >> 10) & 31) * 8 + 4) / 255.0;
    *outGreen = (((bestKey >> 5) & 31) * 8 + 4) / 255.0;
    *outBlue = ((bestKey & 31) * 8 + 4) / 255.0;
    return YES;
}

static NSData *recoloredPNGData(NSData *pngData,
                                CGFloat sourceRed, CGFloat sourceGreen, CGFloat sourceBlue,
                                NSColor *targetColor) {
    NSBitmapImageRep *bitmap = bitmapForPNGData(pngData);
    if (!bitmap) return pngData;

    NSColor *target = [targetColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: targetColor;
    CGFloat targetRed = target.redComponent;
    CGFloat targetGreen = target.greenComponent;
    CGFloat targetBlue = target.blueComponent;

    unsigned char *pixels = bitmap.bitmapData;
    NSInteger rowBytes = bitmap.bytesPerRow;
    for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
        unsigned char *row = pixels + y * rowBytes;
        for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
            unsigned char *pixel = row + x * 4;
            CGFloat alpha = pixel[3] / 255.0;
            if (alpha < 0.35) continue;

            CGFloat red = pixel[0] / 255.0;
            CGFloat green = pixel[1] / 255.0;
            CGFloat blue = pixel[2] / 255.0;
            CGFloat redDelta = red - sourceRed;
            CGFloat greenDelta = green - sourceGreen;
            CGFloat blueDelta = blue - sourceBlue;
            CGFloat distance = sqrt(redDelta * redDelta
                + greenDelta * greenDelta + blueDelta * blueDelta);
            CGFloat colorWeight = MIN(MAX(1.0 - distance / 0.42, 0), 1);
            CGFloat alphaWeight = MIN(MAX((alpha - 0.35) / 0.55, 0), 1);
            CGFloat weight = colorWeight * alphaWeight;
            if (weight <= 0) continue;

            pixel[0] = (unsigned char)lround((red * (1 - weight) + targetRed * weight) * 255);
            pixel[1] = (unsigned char)lround((green * (1 - weight) + targetGreen * weight) * 255);
            pixel[2] = (unsigned char)lround((blue * (1 - weight) + targetBlue * weight) * 255);
        }
    }

    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] ?: pngData;
}

static NSString *preparedColorAdjustedThemePath(NSString *identifier,
                                                 NSString *sourcePath,
                                                 NSDictionary *config) {
    NSColor *targetColor = resolvedTargetColor(config);
    NSDictionary *attributes = [[NSFileManager defaultManager]
        attributesOfItemAtPath:sourcePath error:nil];
    long long size = [attributes[NSFileSize] longLongValue];
    long long modified = (long long)[attributes[NSFileModificationDate] timeIntervalSince1970];
    NSString *signature = [NSString stringWithFormat:@"%@-%@-%lld-%lld",
        identifier, hexStringForColor(targetColor), size, modified];
    NSString *safeSignature = [signature stringByReplacingOccurrencesOfString:@"/" withString:@"_"];

    NSURL *cachesURL = [[NSFileManager defaultManager]
        URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *cacheDirectory = [cachesURL.path
        stringByAppendingPathComponent:@"com.writronic.MaCursor/AdaptiveCursors"];
    NSString *cachePath = [[cacheDirectory stringByAppendingPathComponent:safeSignature]
        stringByAppendingPathExtension:@"cursor"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) return cachePath;

    NSData *sourceData = [NSData dataWithContentsOfFile:sourcePath];
    if (!sourceData) return sourcePath;

    NSError *plistError = nil;
    NSMutableDictionary *root = [NSPropertyListSerialization
        propertyListWithData:sourceData
        options:NSPropertyListMutableContainersAndLeaves
        format:NULL
        error:&plistError];
    if (![root isKindOfClass:[NSMutableDictionary class]]) return sourcePath;

    NSMutableDictionary *cursors = root[@"Cursors"];
    NSDictionary *arrow = cursors[@"com.apple.coregraphics.Arrow"];
    NSArray *arrowRepresentations = arrow[@"Representations"];
    NSData *sample = [arrowRepresentations.lastObject isKindOfClass:[NSData class]]
        ? arrowRepresentations.lastObject : nil;
    CGFloat sourceRed = 0, sourceGreen = 0, sourceBlue = 0;
    if (!sample || !detectFillColor(sample, &sourceRed, &sourceGreen, &sourceBlue)) {
        return sourcePath;
    }

    [cursors enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if (![value isKindOfClass:[NSMutableDictionary class]]) return;
        NSMutableDictionary *cursor = (NSMutableDictionary *)value;
        NSArray *representations = cursor[@"Representations"];
        if (![representations isKindOfClass:[NSArray class]]) return;

        NSMutableArray *updated = [NSMutableArray arrayWithCapacity:representations.count];
        for (id representation in representations) {
            if ([representation isKindOfClass:[NSData class]]) {
                [updated addObject:recoloredPNGData(
                    representation, sourceRed, sourceGreen, sourceBlue, targetColor)];
            } else {
                [updated addObject:representation];
            }
        }
        cursor[@"Representations"] = updated;
    }];

    NSError *serializationError = nil;
    NSData *adjustedData = [NSPropertyListSerialization
        dataWithPropertyList:root
        format:NSPropertyListBinaryFormat_v1_0
        options:0
        error:&serializationError];
    if (!adjustedData) return sourcePath;

    [[NSFileManager defaultManager] createDirectoryAtPath:cacheDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    if (![adjustedData writeToFile:cachePath options:NSDataWritingAtomic error:nil]) {
        return sourcePath;
    }

    NSArray<NSString *> *cachedFiles = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:cacheDirectory error:nil];
    if (cachedFiles.count > 12) {
        NSArray<NSString *> *sorted = [cachedFiles
            sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
                NSString *leftPath = [cacheDirectory stringByAppendingPathComponent:left];
                NSString *rightPath = [cacheDirectory stringByAppendingPathComponent:right];
                NSDate *leftDate = [[[NSFileManager defaultManager]
                    attributesOfItemAtPath:leftPath error:nil] fileModificationDate];
                NSDate *rightDate = [[[NSFileManager defaultManager]
                    attributesOfItemAtPath:rightPath error:nil] fileModificationDate];
                return [rightDate compare:leftDate];
            }];
        for (NSUInteger index = 12; index < sorted.count; index++) {
            [[NSFileManager defaultManager]
                removeItemAtPath:[cacheDirectory stringByAppendingPathComponent:sorted[index]]
                error:nil];
        }
    }
    return cachePath;
}

NSString * _Nullable MACAutoSwitchPendingIdentifier(NSString * _Nullable desired, NSString * _Nullable current) {
    if (desired.length == 0) return nil;
    if (current.length > 0 && [desired isEqualToString:current]) return nil;
    return desired;
}

static BOOL applyCurrentConfiguration(BOOL force) {
    NSDictionary *config = MACAutoSwitchReadConfig();
    NSString *desired = MACAutoSwitchResolveThemeIdentifier(config, MACAutoSwitchCurrentMinuteOfDay());

    id stored = MACDefault(MACPreferencesAppliedCursorKey);
    NSString *current = [stored isKindOfClass:[NSString class]] ? (NSString *)stored : nil;
    if (desired.length == 0 && (MACAutoSwitchUsesColorAdjustment(config) || force)) {
        desired = current;
    }

    NSString *pending = MACAutoSwitchPendingIdentifier(desired, current);
    if (!pending && !MACAutoSwitchUsesColorAdjustment(config) && !force) return NO;
    NSString *targetIdentifier = pending ?: desired;
    if (targetIdentifier.length == 0) return NO;

    NSString *path = MACAutoSwitchThemePathForIdentifier(targetIdentifier);
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        MMLog(BOLD YELLOW "Auto-switch target %s is missing on disk, keeping current cursor" RESET,
              [targetIdentifier UTF8String]);
        return NO;
    }
    if (MACAutoSwitchUsesColorAdjustment(config)) {
        path = preparedColorAdjustedThemePath(targetIdentifier, path, config);
    }

    if (!applyThemeAtPath(path)) {
        MMLog(BOLD RED "Auto-switch failed to apply %s" RESET, [targetIdentifier UTF8String]);
        return NO;
    }

    MACSetDefault(targetIdentifier, MACPreferencesAppliedCursorKey);
    MMLog(BOLD GREEN "Auto-switch applied %s" RESET, [targetIdentifier UTF8String]);

    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:MACAutoSwitchAppliedThemeDidChangeNotification
                      object:nil
                    userInfo:nil
          deliverImmediately:YES];
    return YES;
}

BOOL MACAutoSwitchApplyIfNeeded(void) {
    return applyCurrentConfiguration(NO);
}

BOOL MACAutoSwitchReapplyCurrentConfiguration(void) {
    return applyCurrentConfiguration(YES);
}
