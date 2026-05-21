#import "apply.h"
#import "create.h"
#import "restore.h"
#import "MCPrefs.h"
#import "MCDefs.h"
#import "NSBitmapImageRep+ColorSpace.h"

BOOL applyCursorForIdentifier(NSUInteger frameCount, CGFloat frameDuration, CGPoint hotSpot, CGSize size, NSArray *images, NSString *ident, NSUInteger repeatCount) {
    if (frameCount > MCMaxFrameCount || frameCount < 1) {
        MMLog(BOLD RED "Frame count of %s out of range [1...%lu]", ident.UTF8String, (unsigned long)MCMaxFrameCount);
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


    NSArray *aliases = MCTahoeCursorAliasesForIdentifier(ident);
    for (NSString *alias in aliases) {
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

    return YES;
}

BOOL applyThemeForIdentifier(NSDictionary *cursor, NSString *identifier, BOOL restore) {
    if (!cursor || !identifier) {
        NSLog(@"bad seed");
        return NO;
    }

    BOOL lefty = MCFlag(MCPreferencesHandednessKey);
    BOOL pointer = MCCursorIsPointer(identifier);
    NSNumber *frameCount    = cursor[MCCursorDictionaryFrameCountKey];
    NSNumber *frameDuration = cursor[MCCursorDictionaryFrameDurationKey];
    
    CGPoint hotSpot         = CGPointMake([cursor[MCCursorDictionaryHotSpotXKey] doubleValue],
                                          [cursor[MCCursorDictionaryHotSpotYKey] doubleValue]);
    CGSize size             = CGSizeMake([cursor[MCCursorDictionaryPointsWideKey] doubleValue],
                                         [cursor[MCCursorDictionaryPointsHighKey] doubleValue]);
    NSArray *reps           = cursor[MCCursorDictionaryRepresentationsKey];
    NSMutableArray *images  = [NSMutableArray array];

    if (lefty && !restore && pointer) {
        MMLog("Lefty mode for %s", identifier.UTF8String);
        hotSpot.x = size.width - hotSpot.x - 1;
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

        if (!lefty || restore || !pointer) {
            if (type == CGImageGetTypeID()) {
                [images addObject:object];
                continue;
            }

            CGImageRef cgImg = [rep CGImage];
            CGImageRetain(cgImg);
            [images addObject:(__bridge_transfer id)(cgImg)];
            
        } else {
            NSBitmapImageRep *newRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                               pixelsWide:rep.pixelsWide
                                                                               pixelsHigh:rep.pixelsHigh
                                                                            bitsPerSample:8
                                                                          samplesPerPixel:4
                                                                                 hasAlpha:YES
                                                                                 isPlanar:NO
                                                                           colorSpaceName:NSDeviceRGBColorSpace
                                                                              bytesPerRow:4 * rep.pixelsWide
                                                                             bitsPerPixel:32];
            NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:newRep];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:ctx];
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:rep.pixelsWide yBy:0];
            [transform scaleXBy:-1 yBy:1];
            [transform concat];

            [rep drawInRect:NSMakeRect(0, 0, rep.pixelsWide, rep.pixelsHigh)
                   fromRect:NSZeroRect
                  operation:NSCompositingOperationSourceOver
                   fraction:1.0
             respectFlipped:NO
                      hints:nil];
            [NSGraphicsContext restoreGraphicsState];
            CGImageRef flippedImg = [newRep CGImage];
            CGImageRetain(flippedImg);
            [images addObject:(__bridge_transfer id)(flippedImg)];
        }
    }
    
    NSUInteger fc = frameCount.unsignedIntegerValue;
    CGFloat fd = frameDuration.doubleValue;
    
    if (fc > 1 && images.count >= 1) {
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
                images = splitFrames;
            }
        }
    }
    
    if (images.count > MCMaxFrameCount) {
        NSUInteger originalCount = images.count;
        CGFloat totalDuration = fd * originalCount;
        NSUInteger targetCount = MCMaxFrameCount;
        
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
        NSDictionary *cursors = dictionary[MCCursorDictionaryCursorsKey];
        NSString *name = dictionary[MCCursorDictionaryThemeNameKey];
        NSNumber *version = dictionary[MCCursorDictionaryThemeVersionKey];
        
        resetAllCursors(NULL);
        
        MMLog("Applying cursor theme: %s %.02f", name.UTF8String, version.floatValue);
        
        for (NSString *key in cursors) {
            NSDictionary *theme = cursors[key];
            MMLog("Hooking for %s", key.UTF8String);
            
            BOOL success = applyThemeForIdentifier(theme, key, NO);
            if (!success) {
                MMLog(BOLD YELLOW "Failed to hook identifier %s, continuing with remaining cursors..." RESET, key.UTF8String);
            }
        }
        
        MCSetDefault(dictionary[MCCursorDictionaryIdentifierKey], MCPreferencesAppliedCursorKey);

        MCFinalizeCursorApply(MCCursorRefreshScaleBumpSmall);
        
        MMLog(BOLD GREEN "Applied %s successfully!" RESET, name.UTF8String);
        
        return YES;
    }
}

void MCFinalizeCursorApply(float scaleBump) {
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
