#import "MACCursorDaemon.h"
#import "MACCursorActions.h"
#import "MACCursorDefs.h"
#import "MACAutoSwitch.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

static const OSType kMACHotKeySignature = 'MACR';

static NSMutableDictionary<NSNumber *, NSString *> *sRegisteredThemes = nil;

static NSMutableArray *sRegisteredRefs = nil;

static BOOL sHandlerInstalled = NO;

static EventHandlerRef sEventHandlerRef = NULL;

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

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MACWindowDismissDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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

    if (hotKeyID.signature != kMACHotKeySignature) {
        return eventNotHandledErr;
    }

    NSString *themeId = sRegisteredThemes[@(hotKeyID.id)];
    if (!themeId) {
        MMLog(BOLD YELLOW "Hotkey %u fired but no theme mapping found" RESET, hotKeyID.id);
        return eventNotHandledErr;
    }

    NSString *path = MACAutoSwitchThemePathForIdentifier(themeId);
    MMLog(BOLD GREEN "Hotkey %u fired, applying theme: %s" RESET,
          hotKeyID.id, [themeId UTF8String]);

    if (!applyThemeAtPath(path)) {
        MMLog(BOLD RED "Failed to apply theme for hotkey %u" RESET, hotKeyID.id);
    } else {
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
        CFSTR("MACFavoriteCursors"), CFSTR("com.writronic.MaCursor"));

    if (!rawValue) {
        MMLog(BOLD YELLOW "No MACFavoriteCursors found in preferences" RESET);
        return;
    }

    NSData *jsonData = nil;
    if ([rawValue isKindOfClass:[NSData class]]) {
        jsonData = (NSData *)rawValue;
    } else {
        MMLog(BOLD RED "MACFavoriteCursors is not NSData, got %s" RESET,
              [NSStringFromClass([rawValue class]) UTF8String]);
        return;
    }

    NSError *jsonError = nil;
    NSArray *slots = [NSJSONSerialization JSONObjectWithData:jsonData
                                                    options:0
                                                      error:&jsonError];
    if (jsonError || ![slots isKindOfClass:[NSArray class]]) {
        MMLog(BOLD RED "Failed to parse MACFavoriteCursors JSON: %s" RESET,
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
        hotKeyID.signature = kMACHotKeySignature;
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

NSString *appliedThemePathForUser(NSString *user) {
    NSString *home = NSHomeDirectoryForUser(user);
    NSString *ident =     MACDefaultFor(MACPreferencesAppliedCursorKey, user, (NSString *)kCFPreferencesCurrentHost);
    NSString *appSupport = [home stringByAppendingPathComponent:@"Library/Application Support"];
    return [[[appSupport stringByAppendingPathComponent:@"MaCursor/cursors"] stringByAppendingPathComponent:ident] stringByAppendingPathExtension:@"cursor"];
}

static void UserSpaceChanged(SCDynamicStoreRef	store, CFArrayRef changedKeys, void *info) {
    CFStringRef currentConsoleUser = SCDynamicStoreCopyConsoleUser(store, NULL, NULL);

    MMLog("Current user is %s", [(__bridge NSString *)currentConsoleUser UTF8String]);

    if (!currentConsoleUser) return;
    if (CFEqual(currentConsoleUser, CFSTR("loginwindow"))) {
        CFRelease(currentConsoleUser);
        return;
    }

    NSString *appliedPath = appliedThemePathForUser((__bridge NSString *)currentConsoleUser);
    MMLog(BOLD GREEN "User Space Changed to %s, applying cursor theme..." RESET, [(__bridge NSString *)currentConsoleUser UTF8String]);
    if (!applyThemeAtPath(appliedPath)) {
        MMLog(BOLD RED "Application of cursor theme failed" RESET);
    }

    MACAutoSwitchApplyIfNeeded();

    assertPreferredCursorScale();

    CFRelease(currentConsoleUser);
}

static dispatch_source_t sReconfigTimer = NULL;
static dispatch_source_t sActivationTimer = NULL;

static void appActivationCallback(NSNotification *note) {
    if (sActivationTimer) {
        dispatch_source_cancel(sActivationTimer);
        sActivationTimer = NULL;
    }

    sActivationTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_main_queue());
    dispatch_source_set_timer(sActivationTimer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
        DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(sActivationTimer, ^{
        MMLog("App activation detected — re-asserting cursor override");
        MACFinalizeCursorApply(MACCursorRefreshScaleBumpSmall);
        sActivationTimer = NULL;
    });
    dispatch_resume(sActivationTimer);
}

void reconfigurationCallback(CGDirectDisplayID display,
    	CGDisplayChangeSummaryFlags flags,
    	void *userInfo) {
    MMLog("Reconfigure user space (debouncing)");

    if (sReconfigTimer) {
        dispatch_source_cancel(sReconfigTimer);
        sReconfigTimer = NULL;
    }

    sReconfigTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_main_queue());
    dispatch_source_set_timer(sReconfigTimer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(sReconfigTimer, ^{
        MMLog("Reconfigure debounce fired — applying theme");
        applyThemeAtPath(appliedThemePathForUser(NSUserName()));
        MACAutoSwitchApplyIfNeeded();
        assertPreferredCursorScale();
        sReconfigTimer = NULL;
    });
    dispatch_resume(sReconfigTimer);
}

static dispatch_source_t sScheduleTimer = NULL;
static dispatch_source_t sAutoSwitchConfigTimer = NULL;

static void rescheduleAutoSwitchTimer(void) {
    if (sScheduleTimer) {
        dispatch_source_cancel(sScheduleTimer);
        sScheduleTimer = NULL;
    }

    NSDictionary *config = MACAutoSwitchReadConfig();
    if (![config[@"enabled"] boolValue]) {
        MMLog(BOLD CYAN "Auto-switch disabled, no timer scheduled" RESET);
        return;
    }
    if (MACAutoSwitchUsesSystemAppearance(config)) {
        MMLog(BOLD CYAN "Auto-switch follows system appearance, no time timer scheduled" RESET);
        return;
    }

    NSInteger minutes = MACAutoSwitchMinutesUntilNextBoundary(
        config[@"scheduleRules"], MACAutoSwitchCurrentMinuteOfDay());
    if (minutes < 0) {
        MMLog(BOLD CYAN "Auto-switch has no usable rules, no timer scheduled" RESET);
        return;
    }

    int64_t seconds = (int64_t)minutes * 60;
    sScheduleTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_main_queue());
    dispatch_source_set_timer(sScheduleTimer,
        dispatch_time(DISPATCH_TIME_NOW, seconds * NSEC_PER_SEC),
        DISPATCH_TIME_FOREVER, (uint64_t)(5 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(sScheduleTimer, ^{
        MMLog(BOLD CYAN "Auto-switch boundary reached" RESET);
        if (MACAutoSwitchApplyIfNeeded()) {
            forceCursorVisualRefresh();
        }
        rescheduleAutoSwitchTimer();
    });
    dispatch_resume(sScheduleTimer);
    MMLog(BOLD CYAN "Auto-switch timer set for %ld minutes from now" RESET, (long)minutes);
}

static void autoSwitchDidChangeCallback(CFNotificationCenterRef center,
    void *observer, CFNotificationName name, const void *object,
    CFDictionaryRef userInfo)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sAutoSwitchConfigTimer) {
            dispatch_source_cancel(sAutoSwitchConfigTimer);
            sAutoSwitchConfigTimer = NULL;
        }

        sAutoSwitchConfigTimer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(
            sAutoSwitchConfigTimer,
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
            DISPATCH_TIME_FOREVER, 0);
        dispatch_source_set_event_handler(sAutoSwitchConfigTimer, ^{
            MMLog(BOLD CYAN "Auto-switch config changed, re-resolving" RESET);
            if (MACAutoSwitchReapplyCurrentConfiguration()) {
                forceCursorVisualRefresh();
            }
            rescheduleAutoSwitchTimer();
            sAutoSwitchConfigTimer = NULL;
        });
        dispatch_resume(sAutoSwitchConfigTimer);
    });
}

static void systemAppearanceDidChangeCallback(CFNotificationCenterRef center,
    void *observer, CFNotificationName name, const void *object,
    CFDictionaryRef userInfo)
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSDictionary *config = MACAutoSwitchReadConfig();
        if (!MACAutoSwitchUsesSystemAppearance(config)) return;

        MMLog(BOLD CYAN "System appearance changed, re-resolving cursor theme" RESET);
        if (MACAutoSwitchApplyIfNeeded()) {
            forceCursorVisualRefresh();
        }
    });
}

static void systemColorsDidChangeCallback(NSNotification *note) {
    NSDictionary *config = MACAutoSwitchReadConfig();
    BOOL followsAppearance = MACAutoSwitchUsesSystemAppearance(config);
    BOOL followsAccent = MACAutoSwitchUsesColorAdjustment(config)
        && [config[@"followsSystemAccent"] boolValue];
    if (!followsAppearance && !followsAccent) return;

    MMLog(BOLD CYAN "System colors changed, re-resolving cursor theme" RESET);
    if (MACAutoSwitchReapplyCurrentConfiguration()) {
        forceCursorVisualRefresh();
    }
}

static void shortcutsDidChangeCallback(CFNotificationCenterRef center,
    void *observer, CFNotificationName name, const void *object,
    CFDictionaryRef userInfo)
{
    MMLog(BOLD CYAN "Shortcut config changed, re-registering hotkeys..." RESET);
    CFPreferencesSynchronize(CFSTR("com.writronic.MaCursor"),
        kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    unregisterAllHotKeys();
    registerHotKeysFromPreferences();
}

void listener(void) {
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("com.apple.dts.ConsoleUser"), UserSpaceChanged, NULL);
    if (!store) {
        MMLog(BOLD RED "Failed to create SCDynamicStore" RESET);
        return;
    }

    CFStringRef key = SCDynamicStoreKeyCreateConsoleUser(NULL);
    if (!key) {
        MMLog(BOLD RED "Failed to create console user key" RESET);
        CFRelease(store);
        return;
    }

    CFArrayRef keys = CFArrayCreate(NULL, (const void **)&key, 1, &kCFTypeArrayCallBacks);
    if (!keys) {
        MMLog(BOLD RED "Failed to create notification keys array" RESET);
        CFRelease(key);
        CFRelease(store);
        return;
    }

    Boolean success = SCDynamicStoreSetNotificationKeys(store, keys, NULL);
    if (!success) {
        MMLog(BOLD RED "Failed to set notification keys" RESET);
        CFRelease(keys);
        CFRelease(key);
        CFRelease(store);
        return;
    }

    [NSApplication sharedApplication];

    CGDisplayRegisterReconfigurationCallback(reconfigurationCallback, NULL);
    MMLog(BOLD CYAN "Listening for Display changes" RESET);

    CFRunLoopSourceRef rls = SCDynamicStoreCreateRunLoopSource(NULL, store, 0);
    if (!rls) {
        MMLog(BOLD RED "Failed to create run loop source" RESET);
        CFRelease(keys);
        CFRelease(key);
        CFRelease(store);
        return;
    }
    MMLog(BOLD CYAN "Listening for User changes" RESET);

    NSString *systemDefaultPath = MACSystemDefaultCursorPath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:systemDefaultPath]) {
        MMLog("Helper: Capturing system default cursors before first apply...");
        MACCaptureSystemDefaults(systemDefaultPath);
    }

    applyThemeAtPath(appliedThemePathForUser(NSUserName()));
    assertPreferredCursorScale();

    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserverForName:NSWorkspaceDidActivateApplicationNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            appActivationCallback(note);
        }];
    MMLog(BOLD CYAN "Listening for App activation changes" RESET);

    registerHotKeysFromPreferences();

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDistributedCenter(),
        NULL,
        shortcutsDidChangeCallback,
        CFSTR("MACShortcutsDidChange"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    MMLog(BOLD CYAN "Listening for Shortcut config changes" RESET);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDistributedCenter(),
        NULL,
        autoSwitchDidChangeCallback,
        (__bridge CFStringRef)MACAutoSwitchDidChangeNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    MMLog(BOLD CYAN "Listening for Auto-switch config changes" RESET);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDistributedCenter(),
        NULL,
        systemAppearanceDidChangeCallback,
        CFSTR("AppleInterfaceThemeChangedNotification"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    MMLog(BOLD CYAN "Listening for System appearance changes" RESET);

    [[NSNotificationCenter defaultCenter]
        addObserverForName:NSSystemColorsDidChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            systemColorsDidChangeCallback(note);
        }];
    MMLog(BOLD CYAN "Listening for System accent color changes" RESET);

    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserverForName:NSWorkspaceDidWakeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            MMLog(BOLD CYAN "Woke from sleep, re-resolving auto-switch" RESET);
            if (MACAutoSwitchApplyIfNeeded()) {
                forceCursorVisualRefresh();
            }
            assertPreferredCursorScale();
            rescheduleAutoSwitchTimer();
        }];
    MMLog(BOLD CYAN "Listening for Wake notifications" RESET);

    MACAutoSwitchApplyIfNeeded();
    rescheduleAutoSwitchTimer();

    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);

    [NSApp run];

    CFRunLoopSourceInvalidate(rls);
    CFRelease(rls);
    CFRelease(keys);
    CFRelease(key);
    CFRelease(store);
}
