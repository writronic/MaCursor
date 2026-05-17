#import "hotkeys.h"
#import "apply.h"
#import "MCPrefs.h"
#import "MCDefs.h"
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

static const OSType kMCHotKeySignature = 'MCSR';

static NSMutableDictionary<NSNumber *, NSString *> *sRegisteredThemes = nil;

static NSMutableArray *sRegisteredRefs = nil;

static BOOL sHandlerInstalled = NO;

static EventHandlerRef sEventHandlerRef = NULL;

static NSString *themePathForIdentifier(NSString *identifier) {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    return [[[appSupport stringByAppendingPathComponent:@"MaCursor/cursors"]
        stringByAppendingPathComponent:identifier]
        stringByAppendingPathExtension:@"cursor"];
}

static void forceCursorVisualRefresh(void) {
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
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MCWindowDismissDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [invisibleWindow close];
        });
    });
    
    MMLog(BOLD CYAN "Forcing visual refresh via Invisible Window trick" RESET);
}

static OSStatus hotKeyEventHandler(EventHandlerCallRef nextHandler,
                                    EventRef event,
                                    void *userData)
{
    EventHotKeyID hotKeyID;
    OSStatus err = GetEventParameter(event,
                                      kEventParamDirectObject,
                                      typeEventHotKeyID,
                                      NULL,
                                      sizeof(hotKeyID),
                                      NULL,
                                      &hotKeyID);
    if (err != noErr) {
        MMLog(BOLD RED "Failed to get hotkey ID from event: %d" RESET, (int)err);
        return err;
    }
    
    if (hotKeyID.signature != kMCHotKeySignature) {
        return eventNotHandledErr;
    }
    
    NSString *themeId = sRegisteredThemes[@(hotKeyID.id)];
    if (!themeId) {
        MMLog(BOLD YELLOW "Hotkey %u fired but no theme mapping found" RESET, hotKeyID.id);
        return eventNotHandledErr;
    }
    
    NSString *path = themePathForIdentifier(themeId);
    MMLog(BOLD GREEN "Hotkey %u fired, applying theme: %s" RESET,
          hotKeyID.id, [themeId UTF8String]);
    
    if (!applyThemeAtPath(path)) {
        MMLog(BOLD RED "Failed to apply theme for hotkey %u" RESET, hotKeyID.id);
    } else {
        MCFinalizeCursorApply(MCCursorRefreshScaleBumpSmall);
        forceCursorVisualRefresh();
    }
    
    return noErr;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static void installCarbonEventHandlerIfNeeded(void) {
    if (sHandlerInstalled) return;
    
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;
    
    OSStatus err = InstallEventHandler(GetApplicationEventTarget(),
                                        NewEventHandlerUPP(hotKeyEventHandler),
                                        1,
                                        &eventType,
                                        NULL,
                                        &sEventHandlerRef);
    if (err != noErr) {
        MMLog(BOLD RED "Failed to install Carbon event handler: %d" RESET, (int)err);
        return;
    }
    
    sHandlerInstalled = YES;
    MMLog(BOLD CYAN "Carbon hotkey event handler installed" RESET);
}
#pragma clang diagnostic pop

static UInt32 carbonModifiersFromNSModifiers(NSUInteger nsModFlags) {
    UInt32 carbonMods = 0;
    if (nsModFlags & NSEventModifierFlagCommand)  carbonMods |= cmdKey;
    if (nsModFlags & NSEventModifierFlagOption)   carbonMods |= optionKey;
    if (nsModFlags & NSEventModifierFlagControl)  carbonMods |= controlKey;
    if (nsModFlags & NSEventModifierFlagShift)    carbonMods |= shiftKey;
    return carbonMods;
}

void unregisterAllHotKeys(void) {
    if (!sRegisteredRefs || sRegisteredRefs.count == 0) return;
    
    for (NSValue *refValue in sRegisteredRefs) {
        EventHotKeyRef ref = (EventHotKeyRef)[refValue pointerValue];
        OSStatus err = UnregisterEventHotKey(ref);
        if (err != noErr) {
            MMLog(BOLD YELLOW "Warning: UnregisterEventHotKey returned %d" RESET, (int)err);
        }
    }
    
    MMLog(BOLD CYAN "Unregistered %lu hotkeys" RESET, (unsigned long)sRegisteredRefs.count);
    [sRegisteredRefs removeAllObjects];
    [sRegisteredThemes removeAllObjects];
}

void registerHotKeysFromPreferences(void) {
    if (!sRegisteredThemes) sRegisteredThemes = [NSMutableDictionary new];
    if (!sRegisteredRefs) sRegisteredRefs = [NSMutableArray new];
    
    installCarbonEventHandlerIfNeeded();
    
    id rawValue = (__bridge_transfer id)CFPreferencesCopyAppValue(
        CFSTR("MCFavoriteCursors"), CFSTR("com.writronic.MaCursor"));
    
    if (!rawValue) {
        MMLog(BOLD YELLOW "No MCFavoriteCursors found in preferences" RESET);
        return;
    }
    
    NSData *jsonData = nil;
    if ([rawValue isKindOfClass:[NSData class]]) {
        jsonData = (NSData *)rawValue;
    } else {
        MMLog(BOLD RED "MCFavoriteCursors is not NSData, got %s" RESET,
              [NSStringFromClass([rawValue class]) UTF8String]);
        return;
    }
    
    NSError *jsonError = nil;
    NSArray *slots = [NSJSONSerialization JSONObjectWithData:jsonData
                                                    options:0
                                                      error:&jsonError];
    if (jsonError || ![slots isKindOfClass:[NSArray class]]) {
        MMLog(BOLD RED "Failed to parse MCFavoriteCursors JSON: %s" RESET,
              [jsonError.localizedDescription UTF8String]);
        return;
    }
    
    NSUInteger registered = 0;
    
    for (NSUInteger i = 0; i < slots.count; i++) {
        NSDictionary *slot = slots[i];
        if (![slot isKindOfClass:[NSDictionary class]]) continue;
        
        NSString *themeId = slot[@"themeIdentifier"];
        if (!themeId || ![themeId isKindOfClass:[NSString class]]) continue;
        
        NSDictionary *shortcut = slot[@"shortcut"];
        if (!shortcut || ![shortcut isKindOfClass:[NSDictionary class]]) continue;
        
        NSNumber *keyCodeNum = shortcut[@"keyCode"];
        NSNumber *modFlagsNum = shortcut[@"modifierFlagsRaw"];
        if (!keyCodeNum || !modFlagsNum) continue;
        
        UInt32 keyCode = [keyCodeNum unsignedIntValue];
        NSUInteger nsModFlags = [modFlagsNum unsignedIntegerValue];
        
        UInt32 carbonMods = carbonModifiersFromNSModifiers(nsModFlags);
        
        UInt32 hotkeyIndex = (UInt32)(i + 1);
        
        EventHotKeyID hotKeyID;
        hotKeyID.signature = kMCHotKeySignature;
        hotKeyID.id = hotkeyIndex;
        
        EventHotKeyRef hotKeyRef = NULL;
        
        OSStatus err = RegisterEventHotKey(keyCode,
                                            carbonMods,
                                            hotKeyID,
                                            GetApplicationEventTarget(),
                                            0,
                                            &hotKeyRef);
        
        if (err != noErr) {
            MMLog(BOLD RED "RegisterEventHotKey failed for slot %lu (key=%u, mods=0x%X): error %d" RESET,
                  (unsigned long)i, keyCode, carbonMods, (int)err);
            continue;
        }
        
        sRegisteredThemes[@(hotkeyIndex)] = themeId;
        [sRegisteredRefs addObject:[NSValue valueWithPointer:hotKeyRef]];
        registered++;
        
        MMLog(BOLD GREEN "Registered hotkey %u: key=%u carbonMods=0x%X → %s" RESET,
              hotkeyIndex, keyCode, carbonMods, [themeId UTF8String]);
    }
    
    MMLog(BOLD CYAN "Registered %lu hotkeys from preferences" RESET, (unsigned long)registered);
}
