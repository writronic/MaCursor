#import "create.h"
#import "MCDefs.h"
#import "NSBitmapImageRep+ColorSpace.h"

NSError *createCursorTheme(NSString *input, NSString *output) {
    NSDictionary *theme = createCursorThemeFromDirectory(input);
    
    if (!theme) {
        return [NSError errorWithDomain:MCErrorDomain code:MCErrorInvalidThemeCode userInfo:@{
                                                                                              NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to create cursor theme file", nil),
                                                                                              NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Unable to create a cursor theme from the directory specified.", nil) }];
    }
    
    NSError *writeError = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:theme
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:&writeError];
    if (!plistData) {
        return [NSError errorWithDomain:MCErrorDomain code:MCErrorWriteFailCode userInfo:@{
                                                                                           NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to create cursor theme file", nil),
                                                                                           NSLocalizedFailureReasonErrorKey: writeError.localizedDescription ?: @"Serialization failed" }];
    }
    if (![plistData writeToFile:output options:NSDataWritingAtomic error:&writeError]) {
        return [NSError errorWithDomain:MCErrorDomain code:MCErrorWriteFailCode userInfo:@{
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
    [dictionary setObject:@(MCCursorCreatorVersion) forKey:MCCursorDictionaryVersionKey];
    [dictionary setObject:@(MCCursorParserVersion) forKey:MCCursorDictionaryMinimumVersionKey];
    
    CGFloat version = 0.0;
    
    MMLog(BOLD "Enter metadata for cursor theme:" RESET);
    NSString *author = MMGet(@"Author");
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
    
    [dictionary setObject:author forKey:MCCursorDictionaryAuthorKey];
    [dictionary setObject:identifier forKey:MCCursorDictionaryIdentifierKey];
    [dictionary setObject:name forKey:MCCursorDictionaryThemeNameKey];
    [dictionary setObject:@(version) forKey:MCCursorDictionaryThemeVersionKey];
    [dictionary setObject:@NO forKey:MCCursorDictionaryCloudKey];
    [dictionary setObject:@(HiDPI) forKey:MCCursorDictionaryHiDPIKey];
    
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
        
        [data setObject:@(hotX) forKey:MCCursorDictionaryHotSpotXKey];
        [data setObject:@(hotY) forKey:MCCursorDictionaryHotSpotYKey];
        [data setObject:@(pW) forKey:MCCursorDictionaryPointsWideKey];
        [data setObject:@(pH) forKey:MCCursorDictionaryPointsHighKey];
        [data setObject:@(fC) forKey:MCCursorDictionaryFrameCountKey];
        [data setObject:@(fD) forKey:MCCursorDictionaryFrameDurationKey];
        
        [data setObject:representations forKey:MCCursorDictionaryRepresentationsKey];
        [cursors setObject:data forKey:ident];
    }
    
    if (cursors.count == 0)
        return nil;
    
    [dictionary setObject:cursors forKey:MCCursorDictionaryCursorsKey];
    
    return dictionary;
}

NSDictionary *processedCursorThemeWithIdentifier(NSString *identifier) {
    NSMutableDictionary *dict = cursorThemeWithIdentifier(identifier).mutableCopy;
    if (!dict)
        return nil;
    
    NSDictionary *cursors = dict[MCCursorDictionaryRepresentationsKey];
    NSMutableArray *reps = [NSMutableArray array];
    
    for (id image in cursors) {
        CGImageRef im = (__bridge CGImageRef)image;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:im];
    
        [reps addObject:pngDataForImage(rep.ensuredSRGBSpace)];
    }
    
    dict[MCCursorDictionaryRepresentationsKey] = reps;
    return dict;
}

BOOL dumpCursorsToFile(NSString *path, BOOL (^progress)(NSUInteger current, NSUInteger total)) {
    MMLog("Dumping cursors...");
        
    float originalScale;
    CGSGetCursorScale(CGSMainConnectionID(), &originalScale);
    
    CGSSetCursorScale(CGSMainConnectionID(), MCDumpCursorScale);
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
    theme[MCCursorDictionaryAuthorKey] = @"Apple, Inc.";
    theme[MCCursorDictionaryThemeNameKey] = @"Cursor Dump";
    theme[MCCursorDictionaryThemeVersionKey] = @1.0;
    theme[MCCursorDictionaryCloudKey] = @NO;
    theme[MCCursorDictionaryCursorsKey] = cursors;
    theme[MCCursorDictionaryHiDPIKey] = @YES;
    theme[MCCursorDictionaryIdentifierKey] = [NSString stringWithFormat:@"com.writronic.macursor.dump"];
    theme[MCCursorDictionaryVersionKey] = @(MCCursorCreatorVersion);
    theme[MCCursorDictionaryMinimumVersionKey] = @(MCCursorParserVersion);
    
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

    NSDictionary *cursors = theme[MCCursorDictionaryCursorsKey];
    for (NSString *key in cursors) {
        NSArray *reps = cursors[key][MCCursorDictionaryRepresentationsKey];
        for (NSUInteger idx = 0; idx < reps.count; idx++) {
            NSData *data = reps[idx];
            [data writeToFile:[destination stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%lu.png", key, (unsigned long)idx]] atomically:NO];
        }
    }
}
