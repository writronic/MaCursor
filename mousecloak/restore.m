#import "restore.h"
#import "apply.h"
#import "MCPrefs.h"
#import "MCDefs.h"

NSString *backupStringForIdentifier(NSString *identifier) {
    return [NSString stringWithFormat:@"com.writronic.macursor.%@", identifier];
}

BOOL backupCursorForIdentifier(NSString *ident, NSError **error) {
    bool registered = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)ident.UTF8String, &registered);
    
    if (!registered) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.writronic.mousecloak"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Cursor '%@' is not registered", ident]}];
        }
        return NO;
    }
    
    NSString *backupIdent = backupStringForIdentifier(ident);
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)backupIdent.UTF8String, &registered);
    
    if (registered)
        return YES;
    
    NSDictionary *theme = cursorThemeWithIdentifier(ident);
    BOOL success = applyThemeForIdentifier(theme, backupIdent, YES);
    if (!success && error) {
        *error = [NSError errorWithDomain:@"com.writronic.mousecloak"
                                     code:-2
                                 userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"Failed to backup cursor '%@'", ident]}];
    }
    return success;
}

BOOL backupAllCursors(NSError **error) {
    bool arrowRegistered = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)backupStringForIdentifier(@"com.apple.coregraphics.Arrow").UTF8String, &arrowRegistered);
    
    if (arrowRegistered) {
        MMLog("Skipping backup, backup already exists");
        return YES;
    }
    NSUInteger i = 0;
    NSString *key = nil;
    BOOL allSucceeded = YES;
    while ((key = defaultCursors[i]) != nil) {
        if (!backupCursorForIdentifier(key, NULL)) {
            allSucceeded = NO;
        }
        i++;
    }
    if (!allSucceeded && error) {
        *error = [NSError errorWithDomain:@"com.writronic.mousecloak"
                                     code:-3
                                 userInfo:@{NSLocalizedDescriptionKey:
            @"One or more cursors failed to backup"}];
    }
    return allSucceeded;
}

static NSDictionary *loadEmbeddedSystemDefaults(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"SystemDefault" ofType:@"cursor"];

    if (!path) {
        NSString *binaryDir = [[[NSProcessInfo processInfo].arguments firstObject] stringByDeletingLastPathComponent];
        path = [binaryDir stringByAppendingPathComponent:@"../Resources/SystemDefault.cursor"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            path = nil;
        }
    }

    if (!path) {
        NSURL *bundleURL = [[NSBundle mainBundle] bundleURL];
        NSURL *mainAppContentsURL = [[[bundleURL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
        NSURL *systemDefaultURL = [[mainAppContentsURL URLByAppendingPathComponent:@"Resources"] URLByAppendingPathComponent:@"SystemDefault.cursor"];
        path = systemDefaultURL.path;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            path = nil;
        }
    }

    if (!path) {
        MMLog(BOLD RED "ERROR: SystemDefault.cursor not found in app bundle" RESET);
        return nil;
    }

    NSData *themeData = [NSData dataWithContentsOfFile:path options:0 error:nil];
    NSDictionary *theme = themeData ? [NSPropertyListSerialization propertyListWithData:themeData options:NSPropertyListImmutable format:NULL error:nil] : nil;
    if (!theme || ![theme isKindOfClass:[NSDictionary class]] || !theme[@"Cursors"]) {
        MMLog(BOLD RED "ERROR: SystemDefault.cursor is invalid or missing Cursors dictionary" RESET);
        return nil;
    }

    NSDictionary *cursors = theme[@"Cursors"];
    MMLog("Loaded %lu embedded system default cursors from %s",
          (unsigned long)cursors.count, path.UTF8String);
    return cursors;
}

static BOOL reRegisterCursorWithEmbeddedDefault(CGSConnectionID cid,
                                                  NSString *cursorName,
                                                  NSDictionary *embeddedCursors) {
    NSDictionary *cursorData = embeddedCursors[cursorName];
    if (!cursorData) {
        return NO;
    }

    NSArray *pngDataArray = cursorData[@"Representations"];
    NSNumber *frameCountNum = cursorData[@"FrameCount"];
    NSNumber *frameDurationNum = cursorData[@"FrameDuration"];
    NSNumber *hotSpotX = cursorData[@"HotSpotX"];
    NSNumber *hotSpotY = cursorData[@"HotSpotY"];
    NSNumber *pointsWide = cursorData[@"PointsWide"];
    NSNumber *pointsHigh = cursorData[@"PointsHigh"];

    if (!pngDataArray || pngDataArray.count == 0 || !frameCountNum || !pointsWide || !pointsHigh) {
        MMLog(BOLD YELLOW "WARNING: Incomplete embedded data for %s" RESET, cursorName.UTF8String);
        return NO;
    }

    CGSize imageSize = CGSizeMake(pointsWide.doubleValue, pointsHigh.doubleValue);
    CGPoint hotSpot = CGPointMake(hotSpotX.doubleValue, hotSpotY.doubleValue);
    NSUInteger frameCount = frameCountNum.unsignedIntegerValue;
    CGFloat frameDuration = frameDurationNum.doubleValue;

    NSMutableArray *cgImages = [NSMutableArray arrayWithCapacity:pngDataArray.count];
    for (NSData *pngData in pngDataArray) {
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pngData);
        if (!provider) continue;

        CGImageRef img = CGImageCreateWithPNGDataProvider(provider, NULL, true, kCGRenderingIntentDefault);
        CGDataProviderRelease(provider);

        if (img) {
            [cgImages addObject:CFBridgingRelease(img)];
        }
    }

    if (cgImages.count == 0) {
        MMLog(BOLD RED "Failed to decode PNG images for %s" RESET, cursorName.UTF8String);
        return NO;
    }

    int seed = 0;
    CGError regErr = CGSRegisterCursorWithImages(cid,
                                                  (char *)cursorName.UTF8String,
                                                  true,
                                                  true,
                                                  imageSize,
                                                  hotSpot,
                                                  frameCount,
                                                  frameDuration,
                                                  (__bridge CFArrayRef)cgImages,
                                                  &seed);

    if (regErr != kCGErrorSuccess) {
        MMLog(BOLD RED "Failed to re-register %s with embedded defaults (err=%d)" RESET,
              cursorName.UTF8String, regErr);
        return NO;
    }

    MMLog("Restored cursor: %s (size=%.0fx%.0f frames=%lu seed=%d)",
          cursorName.UTF8String, imageSize.width, imageSize.height,
          (unsigned long)frameCount, seed);

    if (MCIsTahoeOrLater()) {
        NSArray *aliases = MCTahoeCursorAliasesForIdentifier(cursorName);
        for (NSString *alias in aliases) {
            NSDictionary *aliasData = embeddedCursors[alias];

            CGSize aliasSize = imageSize;
            CGPoint aliasHotSpot = hotSpot;
            NSUInteger aliasFrameCount = frameCount;
            CGFloat aliasFrameDuration = frameDuration;
            NSArray *aliasImages = cgImages;

            if (aliasData) {
                NSArray *aliasPngArray = aliasData[@"Representations"];
                if (aliasPngArray.count > 0) {
                    NSMutableArray *decodedImages = [NSMutableArray arrayWithCapacity:aliasPngArray.count];
                    for (NSData *pngData in aliasPngArray) {
                        CGDataProviderRef prov = CGDataProviderCreateWithCFData((__bridge CFDataRef)pngData);
                        if (!prov) continue;
                        CGImageRef img = CGImageCreateWithPNGDataProvider(prov, NULL, true, kCGRenderingIntentDefault);
                        CGDataProviderRelease(prov);
                        if (img) {
                            [decodedImages addObject:CFBridgingRelease(img)];
                        }
                    }
                    if (decodedImages.count > 0) {
                        aliasImages = decodedImages;
                        aliasSize = CGSizeMake([aliasData[@"PointsWide"] doubleValue],
                                               [aliasData[@"PointsHigh"] doubleValue]);
                        aliasHotSpot = CGPointMake([aliasData[@"HotSpotX"] doubleValue],
                                                    [aliasData[@"HotSpotY"] doubleValue]);
                        aliasFrameCount = [aliasData[@"FrameCount"] unsignedIntegerValue];
                        aliasFrameDuration = [aliasData[@"FrameDuration"] doubleValue];
                    }
                }
            }

            int aliasSeed = 0;
            CGSRegisterCursorWithImages(cid,
                                        (char *)alias.UTF8String,
                                        true, true,
                                        aliasSize, aliasHotSpot,
                                        aliasFrameCount, aliasFrameDuration,
                                        (__bridge CFArrayRef)aliasImages,
                                        &aliasSeed);
        }
    }

    return YES;
}

BOOL resetAllCursors(NSError **error) {
    MMLog("Restoring cursors...");

    NSDictionary *embeddedCursors = loadEmbeddedSystemDefaults();
    if (!embeddedCursors) {
        MMLog(BOLD RED "Cannot restore: no embedded system defaults available." RESET);
        MMLog("Falling back to CoreCursorUnregisterAll only.");
    }

    if (embeddedCursors) {
        NSUInteger i = 0;
        NSString *key = nil;
        while ((key = defaultCursors[i]) != nil) {
            reRegisterCursorWithEmbeddedDefault(CGSMainConnectionID(), key, embeddedCursors);

            NSString *backupKey = backupStringForIdentifier(key);
            CGSRemoveRegisteredCursor(CGSMainConnectionID(), (char *)backupKey.UTF8String, false);

            i++;
        }

        for (NSString *cursorName in embeddedCursors) {
            if ([cursorName hasPrefix:@"com.apple.cursor."]) {
                reRegisterCursorWithEmbeddedDefault(CGSMainConnectionID(), cursorName, embeddedCursors);
            }
        }
    }

    MMLog("Resetting core cursors...");
    CGError unregErr = CoreCursorUnregisterAll(CGSMainConnectionID());
    if (unregErr == kCGErrorSuccess) {
        MCSetDefault(NULL, MCPreferencesAppliedCursorKey);

        for (int x = 0; x <= MC_MAX_CORE_CURSOR_ID; x++) {
            CoreCursorSet(CGSMainConnectionID(), x);
        }

        CGSSetSystemDefinedCursor(CGSMainConnectionID(), 0);

        if (MCIsTahoeOrLater()) {
            CGSSetDockCursorOverride(CGSMainConnectionID(), false);

            float scale;
            CGSGetCursorScale(CGSMainConnectionID(), &scale);
            CGSSetCursorScale(CGSMainConnectionID(), scale + MCCursorRefreshScaleBumpSmall);
            CGSSetCursorScale(CGSMainConnectionID(), scale);

            MMLog("Tahoe: Disabled dock cursor override and forced cursor refresh");
        }

        MMLog(BOLD GREEN "Successfully restored all cursors." RESET);
        return YES;
    } else {
        NSString *desc = [NSString stringWithFormat:@"CoreCursorUnregisterAll failed with error %d", unregErr];
        MMLog(BOLD RED "Received an error while restoring core cursors (err=%d)." RESET, unregErr);
        if (error) {
            *error = [NSError errorWithDomain:@"com.writronic.mousecloak"
                                         code:unregErr
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        return NO;
    }
}
