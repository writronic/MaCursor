#import "MACCursorActions.h"
#import "MACCursorDefs.h"
#import "MACCursorShadow.h"

static NSSet *gThemeProvidedIdentifiers = nil;
static BOOL gShadowEnabledForApply = NO;

static BOOL MACCursorRequiresFlipForHandMode(NSString *identifier) {
    static NSSet *excludedFromFlip = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        excludedFromFlip = [NSSet setWithArray:@[
            @"com.apple.cursor.29",
            @"com.apple.cursor.33",
            @"com.apple.cursor.35",
            @"com.apple.cursor.37",
            @"com.apple.cursor.30",
            @"com.apple.cursor.34"
        ]];
    });
    return ![excludedFromFlip containsObject:identifier];
}

BOOL applyCursorForIdentifier(NSUInteger frameCount, CGFloat frameDuration, CGPoint hotSpot, CGSize size, NSArray *images, NSString *ident, NSUInteger repeatCount) {
    if (frameCount > MACMaxFrameCount || frameCount < 1) {
        MMLog(BOLD RED "Frame count of %s out of range [1...%lu]", ident.UTF8String, (unsigned long)MACMaxFrameCount);
        return NO;
    }

    const char *identifier = ident.UTF8String;
    int seed = 0;
    CGError err = CGSRegisterCursorWithImages(CGSMainConnectionID(),
                                              (char *)identifier,
                                              true,
                                              true,
                                              size,
                                              hotSpot,
                                              frameCount,
                                              frameDuration,
                                              (__bridge CFArrayRef)images,
                                              &seed);

    if (err != kCGErrorSuccess) {
        return NO;
    }

    int primaryActivateSeed = 0;
    CGSSetRegisteredCursor(CGSMainConnectionID(),
                          (char *)identifier,
                          &primaryActivateSeed);

    NSArray *aliases = MACTahoeCursorAliasesForIdentifier(ident);
    for (NSString *alias in aliases) {
        if ([gThemeProvidedIdentifiers containsObject:alias]) {
            MMLog("Tahoe: skipping alias %s — theme defines it directly", alias.UTF8String);
            continue;
        }
        int aliasSeed = 0;
        CGError aliasErr = CGSRegisterCursorWithImages(CGSMainConnectionID(),
                                                       (char *)alias.UTF8String,
                                                       true,
                                                       true,
                                                       size,
                                                       hotSpot,
                                                       frameCount,
                                                       frameDuration,
                                                       (__bridge CFArrayRef)images,
                                                       &aliasSeed);
        if (aliasErr == kCGErrorSuccess) {
            MMLog("Tahoe: Also registered cursor under alias %s (seed=%d)",
                  alias.UTF8String, aliasSeed);
            int activateSeed = 0;
            CGSSetRegisteredCursor(CGSMainConnectionID(),
                                  (char *)alias.UTF8String,
                                  &activateSeed);
        } else {
            MMLog(BOLD YELLOW "Tahoe: Failed to register alias %s (err=%d)" RESET,
                  alias.UTF8String, aliasErr);
        }
    }

    NSArray *browserAliases = MACBrowserCursorAliasesForIdentifier(ident);
    for (NSString *bAlias in browserAliases) {
        if ([gThemeProvidedIdentifiers containsObject:bAlias]) {
            MMLog("Browser alias: skipping %s → %s — theme defines it directly",
                  ident.UTF8String, bAlias.UTF8String);
            continue;
        }
        int bAliasSeed = 0;
        CGError bErr = CGSRegisterCursorWithImages(CGSMainConnectionID(),
                                                    (char *)bAlias.UTF8String,
                                                    true,
                                                    true,
                                                    size,
                                                    hotSpot,
                                                    frameCount,
                                                    frameDuration,
                                                    (__bridge CFArrayRef)images,
                                                    &bAliasSeed);
        if (bErr == kCGErrorSuccess) {
            MMLog("Browser alias: registered %s → %s (seed=%d)",
                  ident.UTF8String, bAlias.UTF8String, bAliasSeed);
            int bActivateSeed = 0;
            CGSSetRegisteredCursor(CGSMainConnectionID(),
                                  (char *)bAlias.UTF8String,
                                  &bActivateSeed);
        } else {
            MMLog(BOLD YELLOW "Browser alias: failed %s → %s (err=%d)" RESET,
                  ident.UTF8String, bAlias.UTF8String, bErr);
        }
    }

    return YES;
}

BOOL applyThemeForIdentifier(NSDictionary *cursor, NSString *identifier, BOOL restore) {
    if (!cursor || !identifier) {
        NSLog(@"bad seed");
        return NO;
    }

    BOOL lefty = MACFlag(MACPreferencesHandednessKey);
    NSNumber *frameCount    = cursor[MACCursorDictionaryFrameCountKey];
    NSNumber *frameDuration = cursor[MACCursorDictionaryFrameDurationKey];

    CGPoint hotSpot         = CGPointMake([cursor[MACCursorDictionaryHotSpotXKey] doubleValue],
                                          [cursor[MACCursorDictionaryHotSpotYKey] doubleValue]);
    CGSize size             = CGSizeMake([cursor[MACCursorDictionaryPointsWideKey] doubleValue],
                                         [cursor[MACCursorDictionaryPointsHighKey] doubleValue]);
    NSArray *reps           = cursor[MACCursorDictionaryRepresentationsKey];
    NSMutableArray *images  = [NSMutableArray array];

    BOOL applyFlip = lefty && !restore && MACCursorRequiresFlipForHandMode(identifier);
    if (applyFlip) {
        hotSpot.x = size.width - hotSpot.x - 1;
    }

    CGSize declaredSize = size;

    if (size.width > MACMaxCursorPointSize || size.height > MACMaxCursorPointSize) {
        CGFloat excess = MAX(size.width, size.height) / MACMaxCursorPointSize;
        MMLog(BOLD YELLOW "Cursor %s declares %.1fx%.1f points — clamping by %.2fx" RESET,
              identifier.UTF8String, size.width, size.height, excess);
        size.width  /= excess;
        size.height /= excess;
        hotSpot.x   /= excess;
        hotSpot.y   /= excess;
    }

    float renderScale = [MACDefault(MACPreferencesCursorScaleKey) floatValue];
    if (renderScale >= MACMinCursorScale && renderScale < 1.0f) {
        size.width  *= renderScale;
        size.height *= renderScale;
        hotSpot.x   *= renderScale;
        hotSpot.y   *= renderScale;
    }

    for (id object in reps) {
        CFTypeID type = CFGetTypeID((__bridge CFTypeRef)object);
        NSBitmapImageRep *rep;
        if (type == CGImageGetTypeID()) {
            rep = [[NSBitmapImageRep alloc] initWithCGImage:(__bridge CGImageRef)object];
        } else {
            rep = [[NSBitmapImageRep alloc] initWithData:object];
        }
        rep = rep.retaggedSRGBSpace;

        if (!applyFlip) {
            if (type == CGImageGetTypeID()) {
                [images addObject:object];
                continue;
            }

            CGImageRef cgImg = [rep CGImage];
            CGImageRetain(cgImg);
            [images addObject:(__bridge_transfer id)(cgImg)];

        } else {
            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef ctx = CGBitmapContextCreate(NULL,
                rep.pixelsWide, rep.pixelsHigh,
                8, 0, cs,
                (CGBitmapInfo)kCGImageAlphaPremultipliedFirst);
            CGColorSpaceRelease(cs);

            CGContextTranslateCTM(ctx, rep.pixelsWide, 0);
            CGContextScaleCTM(ctx, -1, 1);

            CGImageRef srcImg = [rep CGImage];
            CGContextDrawImage(ctx,
                               CGRectMake(0, 0, rep.pixelsWide, rep.pixelsHigh),
                               srcImg);

            CGImageRef flippedImg = CGBitmapContextCreateImage(ctx);
            CGContextRelease(ctx);
            [images addObject:(__bridge_transfer id)(flippedImg)];
        }
    }

    NSUInteger fc = frameCount.unsignedIntegerValue;
    CGFloat fd = frameDuration.doubleValue;

    NSArray *prepared = MACPrepareCursorImages(images, size, &fc, &fd);

    if (gShadowEnabledForApply && fc <= MACMaxFrameCount) {
        MACShadowMargins shadowMargins;
        NSArray *shadowed = MACShadowedCursorImages(prepared, fc, declaredSize,
                                                    MACShadowParamsDefault, &shadowMargins);
        if (shadowed) {
            CGFloat shadowScale = (declaredSize.width > 0.0) ? (size.width / declaredSize.width) : 1.0;
            MACShadowAdjustRegistration(&size, &hotSpot, shadowMargins, shadowScale);
            return applyCursorForIdentifier(fc, fd, hotSpot, size, shadowed, identifier, 0);
        }
        MMLog(BOLD YELLOW "Shadow skipped for %s (unclassifiable representations)" RESET, identifier.UTF8String);
    }

    return applyCursorForIdentifier(fc, fd, hotSpot, size, prepared, identifier, 0);
}

NSArray *MACPrepareCursorImages(NSArray *images, CGSize size, NSUInteger *frameCount, CGFloat *frameDuration) {
    if (images.count == 0 || frameCount == NULL || frameDuration == NULL) return images;

    NSUInteger fc = *frameCount;
    CGFloat fd = *frameDuration;
    if (fc < 2) return images;

    for (id object in images) {
        if (CFGetTypeID((__bridge CFTypeRef)object) != CGImageGetTypeID()) return images;
    }

    if (images.count == fc && size.width > 0 && size.height > 0) {
        CGImageRef first = (__bridge CGImageRef)images[0];
        size_t fw = CGImageGetWidth(first);
        size_t fh = CGImageGetHeight(first);
        BOOL uniform = (fw > 0 && fh > 0);
        for (id frame in images) {
            CGImageRef img = (__bridge CGImageRef)frame;
            if (CGImageGetWidth(img) != fw || CGImageGetHeight(img) != fh) {
                uniform = NO;
                break;
            }
        }
        if (uniform) {
            CGFloat target = size.width / size.height;
            CGFloat flatAspect = (CGFloat)fw / (CGFloat)fh;
            CGFloat stripFrameAspect = (CGFloat)(fw * fc) / (CGFloat)fh;
            BOOL flatMatches = fabs(flatAspect - target) <= 0.05 * target;
            BOOL stripMatches = fabs(stripFrameAspect - target) <= 0.05 * target;
            if (flatMatches && !stripMatches) {
                CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                CGContextRef ctx = CGBitmapContextCreate(NULL, fw, fh * fc, 8, 0, cs,
                                                         (CGBitmapInfo)kCGImageAlphaPremultipliedFirst);
                CGColorSpaceRelease(cs);
                if (ctx) {
                    CGContextClearRect(ctx, CGRectMake(0, 0, fw, fh * fc));
                    for (NSUInteger i = 0; i < fc; i++) {
                        CGImageRef img = (__bridge CGImageRef)images[i];
                        CGContextDrawImage(ctx, CGRectMake(0, (fc - 1 - i) * fh, fw, fh), img);
                    }
                    CGImageRef strip = CGBitmapContextCreateImage(ctx);
                    CGContextRelease(ctx);
                    if (strip) {
                        images = @[(__bridge_transfer id)strip];
                    }
                }
            }
        }
    }

    if (images.count != fc) {
        NSUInteger mismatched = 0;
        for (id sheet in images) {
            size_t sh = CGImageGetHeight((__bridge CGImageRef)sheet);
            if (sh % fc != 0) mismatched++;
        }
        if (mismatched > 0) {
            MMLog(BOLD YELLOW "%lu of %lu representation heights not divisible by frame count %lu" RESET,
                  (unsigned long)mismatched, (unsigned long)images.count, (unsigned long)fc);
        }
    }

    BOOL sheetsRebuilt = NO;
    if (fc > MACMaxFrameCount && images.count >= 1) {
        NSUInteger targetCount = MACMaxFrameCount;
        NSMutableArray *rebuiltSheets = [NSMutableArray arrayWithCapacity:images.count];
        BOOL allRebuilt = YES;

        for (id sheet in images) {
            CGImageRef sheetImg = (__bridge CGImageRef)sheet;
            size_t sw = CGImageGetWidth(sheetImg);
            size_t sh = CGImageGetHeight(sheetImg);
            size_t fh = sh / fc;
            if (fh == 0) { allRebuilt = NO; break; }

            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef ctx = CGBitmapContextCreate(NULL, sw, fh * targetCount,
                                                     8, 0, cs,
                                                     (CGBitmapInfo)kCGImageAlphaPremultipliedFirst);
            CGColorSpaceRelease(cs);
            if (!ctx) { allRebuilt = NO; break; }
            CGContextClearRect(ctx, CGRectMake(0, 0, sw, fh * targetCount));

            for (NSUInteger i = 0; i < targetCount && allRebuilt; i++) {
                NSUInteger srcIndex = (i * fc) / targetCount;
                CGImageRef frame = CGImageCreateWithImageInRect(sheetImg,
                    CGRectMake(0, srcIndex * fh, sw, fh));
                if (!frame) { allRebuilt = NO; break; }
                CGContextDrawImage(ctx,
                                   CGRectMake(0, (targetCount - 1 - i) * fh, sw, fh),
                                   frame);
                CGImageRelease(frame);
            }

            CGImageRef rebuilt = allRebuilt ? CGBitmapContextCreateImage(ctx) : NULL;
            CGContextRelease(ctx);
            if (!rebuilt) { allRebuilt = NO; break; }
            [rebuiltSheets addObject:(__bridge_transfer id)rebuilt];
        }

        if (allRebuilt && rebuiltSheets.count == images.count) {
            CGFloat totalDuration = fd * fc;
            images = rebuiltSheets;
            fc = targetCount;
            fd = totalDuration / targetCount;
            sheetsRebuilt = YES;
        }
    }

    if (!sheetsRebuilt && fc > MACMaxFrameCount && images.count >= 1) {
        CGImageRef firstSheet = (__bridge CGImageRef)images[0];
        NSUInteger sheetHeight = CGImageGetHeight(firstSheet);
        NSUInteger frameHeight = sheetHeight / fc;

        BOOL isSpriteSheet = (frameHeight > 0 && frameHeight * fc <= sheetHeight);

        if (isSpriteSheet) {
            NSMutableArray *splitFrames = [NSMutableArray arrayWithCapacity:fc * images.count];
            BOOL allSplit = YES;

            for (id sheet in images) {
                CGImageRef sheetImg = (__bridge CGImageRef)sheet;
                NSUInteger sw = CGImageGetWidth(sheetImg);
                NSUInteger sh = CGImageGetHeight(sheetImg);
                NSUInteger fh = sh / fc;

                if (fh == 0) {
                    allSplit = NO;
                    break;
                }

                for (NSUInteger i = 0; i < fc; i++) {
                    CGRect cropRect = CGRectMake(0, i * fh, sw, fh);
                    CGImageRef frame = CGImageCreateWithImageInRect(sheetImg, cropRect);
                    if (frame) {
                        [splitFrames addObject:(__bridge_transfer id)frame];
                    } else {
                        allSplit = NO;
                        break;
                    }
                }
                if (!allSplit) break;
            }

            if (allSplit && splitFrames.count == fc * images.count) {
                NSUInteger repCount = splitFrames.count / fc;
                if (repCount > 1) {
                    NSUInteger offset = fc * (repCount - 1);
                    NSMutableArray *bestRes = [NSMutableArray arrayWithCapacity:fc];
                    for (NSUInteger i = 0; i < fc; i++) {
                        [bestRes addObject:splitFrames[offset + i]];
                    }
                    images = bestRes;
                } else {
                    images = splitFrames;
                }
            }
        }
    }

    if (images.count > MACMaxFrameCount) {
        NSUInteger originalCount = images.count;
        CGFloat totalDuration = fd * originalCount;
        NSUInteger targetCount = MACMaxFrameCount;

        NSMutableArray *downsampled = [NSMutableArray arrayWithCapacity:targetCount];
        for (NSUInteger i = 0; i < targetCount; i++) {
            NSUInteger srcIndex = (i * originalCount) / targetCount;
            [downsampled addObject:images[srcIndex]];
        }

        images = downsampled;
        fc = targetCount;
        fd = totalDuration / targetCount;
    }

    *frameCount = fc;
    *frameDuration = fd;
    return images;
}

BOOL applyTheme(NSDictionary *dictionary) {
    @autoreleasepool {
        NSDictionary *cursors = dictionary[MACCursorDictionaryCursorsKey];
        NSString *name = dictionary[MACCursorDictionaryThemeNameKey];
        NSNumber *version = dictionary[MACCursorDictionaryThemeVersionKey];

        gShadowEnabledForApply = MACFlag(MACPreferencesCursorShadowKey);

        CGSConnectionID cid = CGSMainConnectionID();
        CoreCursorUnregisterAll(cid);
        for (int x = 0; x <= MC_MAX_CORE_CURSOR_ID; x++) {
            CoreCursorSet(cid, x);
        }

        NSString *defaultPath = MACSystemDefaultCursorPath();
        NSData *defaultData = [NSData dataWithContentsOfFile:defaultPath];
        if (defaultData) {
            NSDictionary *defaults = [NSPropertyListSerialization propertyListWithData:defaultData
                                                                              options:NSPropertyListImmutable
                                                                               format:NULL
                                                                                error:NULL];
            NSDictionary *defaultCursors = defaults[MACCursorDictionaryCursorsKey];
            gThemeProvidedIdentifiers = [NSSet setWithArray:defaultCursors.allKeys];
            for (NSString *key in defaultCursors) {
                applyThemeForIdentifier(defaultCursors[key], key, YES);
            }
            gThemeProvidedIdentifiers = nil;
        }

        MMLog("Applying cursor theme: %s %.02f", name.UTF8String, version.floatValue);

        gThemeProvidedIdentifiers = [NSSet setWithArray:cursors.allKeys];
        for (NSString *key in cursors) {
            NSDictionary *theme = cursors[key];
            MMLog("Hooking for %s", key.UTF8String);

            BOOL success = applyThemeForIdentifier(theme, key, NO);
            if (!success) {
                MMLog(BOLD YELLOW "Failed to hook identifier %s, continuing with remaining cursors..." RESET, key.UTF8String);
            }
        }
        gThemeProvidedIdentifiers = nil;
        gShadowEnabledForApply = NO;

        for (NSString *key in cursors) {
            int activateSeed = 0;
            CGSSetRegisteredCursor(CGSMainConnectionID(),
                                  (char *)key.UTF8String,
                                  &activateSeed);
            NSArray *bAliases = MACBrowserCursorAliasesForIdentifier(key);
            for (NSString *alias in bAliases) {
                int aliasSeed = 0;
                CGSSetRegisteredCursor(CGSMainConnectionID(),
                                      (char *)alias.UTF8String,
                                      &aliasSeed);
            }
        }

        MACSetDefault(dictionary[MACCursorDictionaryIdentifierKey], MACPreferencesAppliedCursorKey);

        MACFinalizeCursorApply(MACCursorRefreshScaleBumpSmall);

        MMLog(BOLD GREEN "Applied %s successfully!" RESET, name.UTF8String);

        return YES;
    }
}

static void MACNudgePreferredCursorScale(CGSConnectionID cid, float scaleBump) {
    float live = 1.0f;
    BOOL haveLive = (CGSGetCursorScale(cid, &live) == noErr);
    BOOL dumpInProgress = (haveLive && live == MACDumpCursorScale);

    float scale = 1.0f;
    BOOL haveScale = !dumpInProgress
        && MACResolvePreferredCursorScale(MACDefault(MACPreferencesCursorScaleKey), &scale);
    if (!haveScale) {
        if (!haveLive) return;
        scale = live;
    }

    CGSSetCursorScale(cid, scale + scaleBump);
    CGSSetCursorScale(cid, scale);
}

void MACFinalizeCursorApply(float scaleBump) {
    CGSSetDockCursorOverride(CGSMainConnectionID(), true);

    MACNudgePreferredCursorScale(CGSMainConnectionID(), scaleBump);

    CGSSetSystemDefinedCursor(CGSMainConnectionID(), 0);

    MMLog(BOLD GREEN "Enabled dock cursor override, forced refresh, reset to Arrow" RESET);
}

BOOL applyThemeAtPath(NSString *path) {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    if (!data) {
        MMLog(BOLD RED "Could not read file at %s: %s" RESET, path.UTF8String,
              readError.localizedDescription.UTF8String);
        return NO;
    }
    NSDictionary *theme = [NSPropertyListSerialization propertyListWithData:data
                                                                    options:NSPropertyListImmutable
                                                                     format:NULL
                                                                      error:&readError];
    if (!theme || ![theme isKindOfClass:[NSDictionary class]]) {
        MMLog(BOLD RED "Could not parse valid plist at %s" RESET, path.UTF8String);
        return NO;
    }
    return applyTheme(theme);
}

NSDictionary *processedCursorThemeWithIdentifier(NSString *identifier) {
    NSMutableDictionary *dict = cursorThemeWithIdentifier(identifier).mutableCopy;
    if (!dict)
        return nil;

    NSDictionary *cursors = dict[MACCursorDictionaryRepresentationsKey];
    NSMutableArray *reps = [NSMutableArray array];

    for (id image in cursors) {
        CGImageRef im = (__bridge CGImageRef)image;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:im];

        [reps addObject:pngDataForImage(rep.ensuredSRGBSpace)];
    }

    dict[MACCursorDictionaryRepresentationsKey] = reps;
    return dict;
}

static void MACEndCursorDump(float originalScale) {
    CGSSetCursorScale(CGSMainConnectionID(), originalScale);
    CGSShowCursor(CGSMainConnectionID());
}

BOOL dumpCursorsToFile(NSString *path, BOOL (^progress)(NSUInteger current, NSUInteger total)) {
    MMLog("Dumping cursors...");

    float originalScale = 1.0f;
    if (CGSGetCursorScale(CGSMainConnectionID(), &originalScale) != noErr)
        originalScale = defaultCursorScale();

    CGSSetCursorScale(CGSMainConnectionID(), MACDumpCursorScale);
    CGSHideCursor(CGSMainConnectionID());

    NSUInteger defaultCount = 0;
    while (defaultCursors[defaultCount] != nil) defaultCount++;
    NSInteger total = (NSInteger)defaultCount + (MC_MAX_CORE_CURSOR_ID + 1);
    NSInteger current = 0;

    NSMutableDictionary *cursors = [NSMutableDictionary dictionary];
    NSUInteger i = 0;
    NSString *key = nil;
    while ((key = defaultCursors[i]) != nil) {
        if (progress) {
            current = i;

            if (!progress(current, total)) {
                MACEndCursorDump(originalScale);
                return NO;
            }
        }
        MMLog("Gathering data for %s", key.UTF8String);
        cursors[key] = processedCursorThemeWithIdentifier(key);
        i++;
    }

    for (int x = 0; x <= MC_MAX_CORE_CURSOR_ID; x++) {
        if (progress) {
            current = i + x;

            if (!progress(current, total)) {
                MACEndCursorDump(originalScale);
                return NO;
            }
        }
        NSString *key = [@"com.apple.cursor." stringByAppendingFormat:@"%d", x];
        CoreCursorSet(CGSMainConnectionID(), x);

        NSDictionary *theme = processedCursorThemeWithIdentifier(key);
        if (!theme)
            continue;

        MMLog("Gathering data for %s", key.UTF8String);

        cursors[key] = theme;
    }

    if (progress) {
        progress(total, total);
    }

    NSMutableDictionary *theme = [NSMutableDictionary dictionary];
    theme[MACCursorDictionaryCreatorKey] = @"Apple, Inc.";
    theme[MACCursorDictionaryThemeNameKey] = @"Cursor Dump";
    theme[MACCursorDictionaryThemeVersionKey] = @1.0;
    theme[MACCursorDictionaryCursorsKey] = cursors;
    theme[MACCursorDictionaryHiDPIKey] = @YES;
    theme[MACCursorDictionaryIdentifierKey] = [NSString stringWithFormat:@"com.writronic.macursor.dump"];
    theme[MACCursorDictionaryUUIDKey] = [[NSUUID UUID] UUIDString];

    MACEndCursorDump(originalScale);

    NSError *writeError = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:theme
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:&writeError];
    if (!plistData) {
        MMLog(BOLD RED "Serialization failed: %s" RESET, writeError.localizedDescription.UTF8String);
        return NO;
    }
    return [plistData writeToFile:path options:NSDataWritingAtomic error:nil];
}

BOOL resetAllCursors(NSError **error) {
    MMLog("Restoring cursors...");

    gShadowEnabledForApply = NO;

    CGSConnectionID cid = CGSMainConnectionID();

    NSString *defaultPath = MACSystemDefaultCursorPath();
    NSData *data = [NSData dataWithContentsOfFile:defaultPath];

    if (!data) {
        MMLog(BOLD RED "SystemDefault.cursor not found at: %s" RESET, defaultPath.UTF8String);
        if (error) {
            *error = [NSError errorWithDomain:@"com.writronic.macursor.engine"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"System default cursor file not found. Please restart the app to regenerate it."}];
        }
        return NO;
    }

    NSError *parseError = nil;
    NSDictionary *theme = [NSPropertyListSerialization propertyListWithData:data
                                                                    options:NSPropertyListImmutable
                                                                     format:NULL
                                                                      error:&parseError];
    if (!theme || ![theme isKindOfClass:[NSDictionary class]]) {
        MMLog(BOLD RED "Failed to parse SystemDefault.cursor: %s" RESET,
              parseError.localizedDescription.UTF8String);
        if (error) {
            *error = [NSError errorWithDomain:@"com.writronic.macursor.engine"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"System default cursor file is corrupted."}];
        }
        return NO;
    }

    NSDictionary *cursors = theme[MACCursorDictionaryCursorsKey];
    if (!cursors || cursors.count == 0) {
        MMLog(BOLD RED "SystemDefault.cursor contains no cursor data" RESET);
        if (error) {
            *error = [NSError errorWithDomain:@"com.writronic.macursor.engine"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"System default cursor file contains no cursor data."}];
        }
        return NO;
    }

    CoreCursorUnregisterAll(cid);

    for (int x = 0; x <= MC_MAX_CORE_CURSOR_ID; x++) {
        CoreCursorSet(cid, x);
    }

    NSUInteger restoredCount = 0;
    gThemeProvidedIdentifiers = [NSSet setWithArray:cursors.allKeys];
    for (NSString *key in cursors) {
        NSDictionary *cursorData = cursors[key];
        BOOL success = applyThemeForIdentifier(cursorData, key, YES);
        if (success) {
            restoredCount++;
        } else {
            MMLog(BOLD YELLOW "Failed to restore cursor: %s" RESET, key.UTF8String);
        }
    }
    gThemeProvidedIdentifiers = nil;

    MMLog("Restored %lu/%lu cursors from disk", (unsigned long)restoredCount, (unsigned long)cursors.count);

    CGSSetSystemDefinedCursor(cid, 0);

    if (MACIsTahoeOrLater()) {
        CGSSetDockCursorOverride(cid, false);

        MACNudgePreferredCursorScale(cid, MACCursorRefreshScaleBumpSmall);

        MMLog("Tahoe: Disabled dock cursor override and forced cursor refresh");
    }

    MACSetDefault(NULL, MACPreferencesAppliedCursorKey);

    MMLog(BOLD GREEN "Successfully restored all cursors from disk." RESET);
    return YES;
}

float cursorScale() {
    float value = 1.0f;
    CGSGetCursorScale(CGSMainConnectionID(), &value);
    return value;
}

float defaultCursorScale() {
    float scale = 1.0f;
    MACResolvePreferredCursorScale(MACDefault(MACPreferencesCursorScaleKey), &scale);
    return scale;
}

BOOL setCursorScale(float dbl) {
    if (dbl > MACMaxCursorScale) {
        MMLog("Not a good idea...");
        return NO;
    } else if (dbl < MACMinCursorScale || dbl <= 0) {
        MMLog("Scale below minimum, ignoring.");
        return NO;
    } else if (CGSSetCursorScale(CGSMainConnectionID(), dbl) == noErr) {
        MMLog("Successfully set cursor scale!");
        return YES;
    } else {
        MMLog("Somehow failed to set cursor scale!");
        return NO;
    }
}

BOOL assertPreferredCursorScale(void) {
    float live = 1.0f;
    if (CGSGetCursorScale(CGSMainConnectionID(), &live) == noErr && live == MACDumpCursorScale)
        return NO;

    float scale = 1.0f;
    if (!MACResolvePreferredCursorScale(MACDefault(MACPreferencesCursorScaleKey), &scale))
        return NO;
    return setCursorScale(scale);
}
