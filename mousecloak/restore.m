#import "restore.h"
#import "apply.h"
#import "MCPrefs.h"
#import "MCDefs.h"

BOOL resetAllCursors(NSError **error) {
    MMLog("Restoring cursors...");

    CGSConnectionID cid = CGSMainConnectionID();

    NSString *defaultPath = MCSystemDefaultCursorPath();
    NSData *data = [NSData dataWithContentsOfFile:defaultPath];

    if (!data) {
        MMLog(BOLD RED "SystemDefault.cursor not found at: %s" RESET, defaultPath.UTF8String);
        if (error) {
            *error = [NSError errorWithDomain:@"com.writronic.mousecloak"
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
            *error = [NSError errorWithDomain:@"com.writronic.mousecloak"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"System default cursor file is corrupted."}];
        }
        return NO;
    }

    NSDictionary *cursors = theme[MCCursorDictionaryCursorsKey];
    if (!cursors || cursors.count == 0) {
        MMLog(BOLD RED "SystemDefault.cursor contains no cursor data" RESET);
        if (error) {
            *error = [NSError errorWithDomain:@"com.writronic.mousecloak"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey:
                @"System default cursor file contains no cursor data."}];
        }
        return NO;
    }

    NSUInteger restoredCount = 0;
    for (NSString *key in cursors) {
        NSDictionary *cursorData = cursors[key];
        BOOL success = applyThemeForIdentifier(cursorData, key, YES);
        if (success) {
            restoredCount++;

            NSArray *aliases = MCTahoeCursorAliasesForIdentifier(key);
            for (NSString *alias in aliases) {
                applyThemeForIdentifier(cursorData, alias, YES);
            }
        } else {
            MMLog(BOLD YELLOW "Failed to restore cursor: %s" RESET, key.UTF8String);
        }
    }

    MMLog("Restored %lu/%lu cursors from disk", (unsigned long)restoredCount, (unsigned long)cursors.count);

    CoreCursorUnregisterAll(cid);

    for (int x = 0; x <= MC_MAX_CORE_CURSOR_ID; x++) {
        CoreCursorSet(cid, x);
    }

    CGSSetSystemDefinedCursor(cid, 0);

    if (MCIsTahoeOrLater()) {
        CGSSetDockCursorOverride(cid, false);

        float scale;
        CGSGetCursorScale(cid, &scale);
        CGSSetCursorScale(cid, scale + MCCursorRefreshScaleBumpSmall);
        CGSSetCursorScale(cid, scale);

        MMLog("Tahoe: Disabled dock cursor override and forced cursor refresh");
    }

    MCSetDefault(NULL, MCPreferencesAppliedCursorKey);

    MMLog(BOLD GREEN "Successfully restored all cursors from disk." RESET);
    return YES;
}
