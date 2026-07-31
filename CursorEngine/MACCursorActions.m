#import "MACCursorActions.h"
#import "MACCursorDefs.h"

static NSSet *gThemeProvidedIdentifiers = nil;

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
            if (fh == 0 || fh * fc > sh) { allRebuilt = NO; break; }

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

                if (fh == 0 || fh * fc > sh) {
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

    return applyCursorForIdentifier(fc, fd, hotSpot, size, images, identifier, 0);
}

BOOL applyTheme(NSDictionary *dictionary) {
    @autoreleasepool {
        NSDictionary *cursors = dictionary[MACCursorDictionaryCursorsKey];
        NSString *name = dictionary[MACCursorDictionaryThemeNameKey];
        NSNumber *version = dictionary[MACCursorDictionaryThemeVersionKey];

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

void MACFinalizeCursorApply(float scaleBump) {
    CGSSetDockCursorOverride(CGSMainConnectionID(), true);

    float scale;
    CGSGetCursorScale(CGSMainConnectionID(), &scale);
    CGSSetCursorScale(CGSMainConnectionID(), scale + scaleBump);
    CGSSetCursorScale(CGSMainConnectionID(), scale);

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

NSError *createCursorTheme(NSString *input, NSString *output) {
    NSDictionary *theme = createCursorThemeFromDirectory(input);

    if (!theme) {
        return [NSError errorWithDomain:MACErrorDomain code:MACErrorInvalidThemeCode userInfo:@{
                                                                                              NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to create cursor theme file", nil),
                                                                                              NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Unable to create a cursor theme from the directory specified.", nil) }];
    }

    NSError *writeError = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:theme
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:&writeError];
    if (!plistData) {
        return [NSError errorWithDomain:MACErrorDomain code:MACErrorWriteFailCode userInfo:@{
                                                                                           NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to create cursor theme file", nil),
                                                                                           NSLocalizedFailureReasonErrorKey: writeError.localizedDescription ?: @"Serialization failed" }];
    }
    if (![plistData writeToFile:output options:NSDataWritingAtomic error:&writeError]) {
        return [NSError errorWithDomain:MACErrorDomain code:MACErrorWriteFailCode userInfo:@{
                                                                                           NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to create cursor theme file", nil),
                                                                                           NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat: NSLocalizedString(@"The destination, %@, is not writable.", nil), output] }];
    }

    return nil;
}

NSDictionary *createCursorThemeFromDirectory(NSString *path) {
    NSFileManager *manager = [NSFileManager defaultManager];

    BOOL isDir;
    BOOL exists = [manager fileExistsAtPath:path isDirectory:&isDir];

    if (!exists || !isDir)
        return nil;

    NSArray *contents = [manager contentsOfDirectoryAtPath:path error:nil];

    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    CGFloat version = 0.0;

    MMLog(BOLD "Enter metadata for cursor theme:" RESET);
    NSString *creator = MMGet(@"Creator");
    NSString *identifier = MMGet(@"Identifier");
    NSString *name = MMGet(@"Theme Name");
    MMLog("Theme Version: ");
    if (scanf("%lf", &version) != 1) {
        MMLog(BOLD RED "Invalid version input" RESET);
        return nil;
    }
    NSString *hidpi = MMGet(@"HiDPI? (y/n)");

    MMLog("");

    BOOL HiDPI = [hidpi isEqualToString:@"y"];

    [dictionary setObject:creator forKey:MACCursorDictionaryCreatorKey];
    [dictionary setObject:identifier forKey:MACCursorDictionaryIdentifierKey];
    [dictionary setObject:name forKey:MACCursorDictionaryThemeNameKey];
    [dictionary setObject:@(version) forKey:MACCursorDictionaryThemeVersionKey];
    [dictionary setObject:@(HiDPI) forKey:MACCursorDictionaryHiDPIKey];
    [dictionary setObject:[[NSUUID UUID] UUIDString] forKey:MACCursorDictionaryUUIDKey];

    NSMutableDictionary *cursors = [NSMutableDictionary dictionary];

    for (NSString *subpath in contents) {
        NSString *fullPath = [path stringByAppendingPathComponent:subpath];

        [manager fileExistsAtPath:fullPath isDirectory:&isDir];

        if (!isDir)
            continue;

        NSString *ident = subpath;
        NSMutableDictionary *data = [NSMutableDictionary dictionary];

        NSUInteger fC;
        CGFloat hotX, hotY, pW, pH, fD;
        printf(BOLD "Need metadata for %s." RESET, [ident cStringUsingEncoding:NSUTF8StringEncoding]);
        printf("X Hotspot: ");
        if (scanf("%lf", &hotX) != 1) {
            MMLog(BOLD RED "Invalid hotspot X input" RESET);
            return nil;
        }
        printf("Y Hotspot: ");
        if (scanf("%lf", &hotY) != 1) {
            MMLog(BOLD RED "Invalid hotspot Y input" RESET);
            return nil;
        }
        printf("Points Wide: ");
        if (scanf("%lf", &pW) != 1) {
            MMLog(BOLD RED "Invalid width input" RESET);
            return nil;
        }
        printf("Points High: ");
        if (scanf("%lf", &pH) != 1) {
            MMLog(BOLD RED "Invalid height input" RESET);
            return nil;
        }
        printf("Frame Count: ");
        unsigned long tempFC;
        if (scanf("%lu", &tempFC) != 1) {
            MMLog(BOLD RED "Invalid frame count input" RESET);
            return nil;
        }
        fC = (NSUInteger)tempFC;
        printf("Frame Duration: ");
        if (scanf("%lf", &fD) != 1) {
            MMLog(BOLD RED "Invalid frame duration input" RESET);
            return nil;
        }

        NSMutableArray *representations = [NSMutableArray array];
        NSArray *repNames = [manager contentsOfDirectoryAtPath:fullPath error:nil];
        for (NSString *rep in repNames) {
            NSString *repPath = [fullPath stringByAppendingPathComponent:rep];

            [manager fileExistsAtPath:repPath isDirectory:&isDir];
            if (isDir || [rep isEqualToString:@".DS_Store"])
                continue;

            NSBitmapImageRep *image = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:repPath]];
            if (image) {
                NSData *pngData = [image.ensuredSRGBSpace representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                [representations addObject:pngData];
            }

        }

        [data setObject:@(hotX) forKey:MACCursorDictionaryHotSpotXKey];
        [data setObject:@(hotY) forKey:MACCursorDictionaryHotSpotYKey];
        [data setObject:@(pW) forKey:MACCursorDictionaryPointsWideKey];
        [data setObject:@(pH) forKey:MACCursorDictionaryPointsHighKey];
        [data setObject:@(fC) forKey:MACCursorDictionaryFrameCountKey];
        [data setObject:@(fD) forKey:MACCursorDictionaryFrameDurationKey];

        [data setObject:representations forKey:MACCursorDictionaryRepresentationsKey];
        [cursors setObject:data forKey:ident];
    }

    if (cursors.count == 0)
        return nil;

    [dictionary setObject:cursors forKey:MACCursorDictionaryCursorsKey];

    return dictionary;
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

BOOL dumpCursorsToFile(NSString *path, BOOL (^progress)(NSUInteger current, NSUInteger total)) {
    MMLog("Dumping cursors...");

    float originalScale;
    CGSGetCursorScale(CGSMainConnectionID(), &originalScale);

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

    CGSSetCursorScale(CGSMainConnectionID(), originalScale);
    CGSShowCursor(CGSMainConnectionID());

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

void exportCursorTheme(NSDictionary *theme, NSString *destination) {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *cursors = theme[MACCursorDictionaryCursorsKey];
    for (NSString *key in cursors) {
        NSArray *reps = cursors[key][MACCursorDictionaryRepresentationsKey];
        for (NSUInteger idx = 0; idx < reps.count; idx++) {
            NSData *data = reps[idx];
            [data writeToFile:[destination stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%lu.png", key, (unsigned long)idx]] atomically:NO];
        }
    }
}

BOOL resetAllCursors(NSError **error) {
    MMLog("Restoring cursors...");

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

        float scale;
        CGSGetCursorScale(cid, &scale);
        CGSSetCursorScale(cid, scale + MACCursorRefreshScaleBumpSmall);
        CGSSetCursorScale(cid, scale);

        MMLog("Tahoe: Disabled dock cursor override and forced cursor refresh");
    }

    MACSetDefault(NULL, MACPreferencesAppliedCursorKey);

    MMLog(BOLD GREEN "Successfully restored all cursors from disk." RESET);
    return YES;
}

float cursorScale() {
    float value;
    CGSGetCursorScale(CGSMainConnectionID(), &value);
    return value;
}

float defaultCursorScale() {
    float scale = [MACDefault(MACPreferencesCursorScaleKey) floatValue];
    if (scale < 1.0f || scale > MACMaxDefaultCursorScale)
        scale = 1;
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
