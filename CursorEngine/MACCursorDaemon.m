#import "MACCursorDaemon.h"
#import "MACCursorActions.h"
#import "MACCursorDefs.h"
#import "MACAutoSwitch.h"
#import "MACFocusFollowsMouse.h"
#import "MACMenuBarState.h"
#import "MACMenuBar.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

static const OSType kMACHotKeySignature = 'MACR';

static NSString * _Nullable menuBarSafeFrontmostBundleID(void) {
    NSString *cached = MACMenuBarLastForegroundBundleID();
    if (cached.length > 0) return cached;
    NSString *live = [[NSWorkspace sharedWorkspace] frontmostApplication].bundleIdentifier;
    return MACMenuBarIsHelperBundleIdentifier(live) ? nil : live;
}

static NSMutableDictionary<NSNumber *, NSString *> *sRegisteredThemes = nil;

static NSMutableArray *sRegisteredRefs = nil;

static BOOL sHandlerInstalled = NO;

static EventHandlerRef sEventHandlerRef = NULL;

static void systemAppearanceDidChange(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *config = MACAutoSwitchReadConfig();
        if (!MACAutoSwitchMatchesSystemAppearance(config)) return;
        MMLog(BOLD CYAN "System appearance changed, re-resolving auto-switch" RESET);
        if (MACAutoSwitchApplyIfNeeded()) {
            MACAutoSwitchForceVisualRefresh();
        }
    });
}

@interface MACSystemAppearanceWatcher : NSObject
@end

@implementation MACSystemAppearanceWatcher

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    systemAppearanceDidChange();
}

@end

static void interfaceThemeChangedCallback(CFNotificationCenterRef center,
    void *observer, CFNotificationName name, const void *object,
    CFDictionaryRef userInfo)
{
    systemAppearanceDidChange();
}

static MACSystemAppearanceWatcher *sAppearanceWatcher = nil;

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
        MACAutoSwitchForceVisualRefresh();
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
        MACFocusFollowsMouseStop();
        CFRelease(currentConsoleUser);
        return;
    }

    NSString *appliedPath = appliedThemePathForUser((__bridge NSString *)currentConsoleUser);
    MMLog(BOLD GREEN "User Space Changed to %s, applying cursor theme..." RESET, [(__bridge NSString *)currentConsoleUser UTF8String]);
    MACAutoSwitchClearAppOverride();
    if (!applyThemeAtPath(appliedPath)) {
        MMLog(BOLD RED "Application of cursor theme failed" RESET);
    }

    MACAutoSwitchApplyIfNeeded();
    MACAutoSwitchHandleFrontmostApp(menuBarSafeFrontmostBundleID());

    assertPreferredCursorScale();

    MACFocusFollowsMouseStop();
    MACFocusFollowsMouseStart();

    CFRelease(currentConsoleUser);
}

static dispatch_source_t sReconfigTimer = NULL;
static dispatch_source_t sActivationTimer = NULL;

static void appActivationCallback(NSNotification *note) {
    NSRunningApplication *activated = note.userInfo[NSWorkspaceApplicationKey];
    NSString *bundleID = activated.bundleIdentifier;

    if (MACMenuBarIsHelperBundleIdentifier(bundleID)) {
        MACFocusFollowsMouseCancelPendingRaise();
        MMLog("Menu bar activation, keeping the current cursor override");
        return;
    }
    MACMenuBarNoteForegroundBundleID(bundleID);

    if (MACFocusFollowsMouseConsumeRecentRaise(bundleID)) {
        MMLog("App activation caused by focus follows mouse, skipping cursor re-assert");
        return;
    }
    MACFocusFollowsMouseCancelPendingRaise();

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
        MACAutoSwitchHandleFrontmostApp(bundleID);
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
        MACAutoSwitchClearAppOverride();
        applyThemeAtPath(appliedThemePathForUser(NSUserName()));
        MACAutoSwitchApplyIfNeeded();
        MACAutoSwitchHandleFrontmostApp(menuBarSafeFrontmostBundleID());
        assertPreferredCursorScale();
        sReconfigTimer = NULL;
    });
    dispatch_resume(sReconfigTimer);
}

static dispatch_source_t sScheduleTimer = NULL;

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

    if (MACAutoSwitchMatchesSystemAppearance(config)) {
        MMLog(BOLD CYAN "Auto-switch follows the system appearance, no timer scheduled" RESET);
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
            MACAutoSwitchForceVisualRefresh();
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
    MMLog(BOLD CYAN "Auto-switch config changed, re-resolving" RESET);
    if (MACAutoSwitchApplyIfNeeded()) {
        MACAutoSwitchForceVisualRefresh();
    }
    MACAutoSwitchHandleFrontmostApp(menuBarSafeFrontmostBundleID());
    rescheduleAutoSwitchTimer();
}

static void menuBarDidChangeCallback(CFNotificationCenterRef center,
    void *observer, CFNotificationName name, const void *object,
    CFDictionaryRef userInfo)
{
    MMLog(BOLD CYAN "Menu bar visibility preference changed" RESET);
    MACMenuBarApplyVisibilityPreference();
}

static void focusFollowsMouseDidChangeCallback(CFNotificationCenterRef center,
    void *observer, CFNotificationName name, const void *object,
    CFDictionaryRef userInfo)
{
    MMLog(BOLD CYAN "Focus follows mouse config changed, restarting" RESET);
    MACFocusFollowsMouseConfigDidChange();
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
    MACSetDefault(MACHelperBuildIdentityAtPath([NSBundle mainBundle].executablePath), MACPreferencesHelperBuildKey);

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
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    sAppearanceWatcher = [MACSystemAppearanceWatcher new];
    [NSApp addObserver:sAppearanceWatcher
            forKeyPath:@"effectiveAppearance"
               options:0
               context:NULL];

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDistributedCenter(),
        NULL,
        interfaceThemeChangedCallback,
        CFSTR("AppleInterfaceThemeChangedNotification"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    MMLog(BOLD CYAN "Listening for system appearance changes" RESET);

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

    MACAutoSwitchRecoverBaseThemeIfNeeded();
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
        menuBarDidChangeCallback,
        (__bridge CFStringRef)MACMenuBarDidChangeNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    MMLog(BOLD CYAN "Listening for Menu bar visibility changes" RESET);

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDistributedCenter(),
        NULL,
        focusFollowsMouseDidChangeCallback,
        (__bridge CFStringRef)MACFocusFollowsMouseDidChangeNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    MMLog(BOLD CYAN "Listening for Focus follows mouse config changes" RESET);

    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            MACFocusFollowsMouseNoteSpaceChange();
        }];
    MMLog(BOLD CYAN "Listening for Space changes" RESET);

    [[[NSWorkspace sharedWorkspace] notificationCenter]
        addObserverForName:NSWorkspaceDidWakeNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            MMLog(BOLD CYAN "Woke from sleep, re-resolving auto-switch" RESET);
            if (MACAutoSwitchApplyIfNeeded()) {
                MACAutoSwitchForceVisualRefresh();
            }
            MACAutoSwitchHandleFrontmostApp(menuBarSafeFrontmostBundleID());
            assertPreferredCursorScale();
            rescheduleAutoSwitchTimer();
            MACFocusFollowsMouseStop();
            MACFocusFollowsMouseStart();
        }];
    MMLog(BOLD CYAN "Listening for Wake notifications" RESET);

    MACAutoSwitchApplyIfNeeded();
    MACMenuBarNoteForegroundBundleID(menuBarSafeFrontmostBundleID());
    MACAutoSwitchHandleFrontmostApp(menuBarSafeFrontmostBundleID());
    rescheduleAutoSwitchTimer();
    MACFocusFollowsMouseStart();
    MACFocusFollowsMouseSyncTrust();
    MACMenuBarStart();

    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);

    [NSApp run];

    CFRunLoopSourceInvalidate(rls);
    CFRelease(rls);
    CFRelease(keys);
    CFRelease(key);
    CFRelease(store);
}
