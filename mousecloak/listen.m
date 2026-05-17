#import "listen.h"
#import "apply.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MCPrefs.h"
#import "MCDefs.h"
#import <Cocoa/Cocoa.h>
#import "scale.h"
#import "hotkeys.h"

NSString *appliedThemePathForUser(NSString *user) {
    NSString *home = NSHomeDirectoryForUser(user);
    NSString *ident =     MCDefaultFor(MCPreferencesAppliedCursorKey, user, (NSString *)kCFPreferencesCurrentHost);
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
    } else {
        MCFinalizeCursorApply(MCCursorRefreshScaleBumpSmall);
    }
    
    setCursorScale(defaultCursorScale());
    
    CFRelease(currentConsoleUser);
}

static dispatch_source_t sReconfigTimer = NULL;

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
        MCFinalizeCursorApply(MCCursorRefreshScaleBumpLarge);
        sReconfigTimer = NULL;
    });
    dispatch_resume(sReconfigTimer);
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
    
    applyThemeAtPath(appliedThemePathForUser(NSUserName()));
    setCursorScale(defaultCursorScale());
    
    registerHotKeysFromPreferences();
    
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDistributedCenter(),
        NULL,
        shortcutsDidChangeCallback,
        CFSTR("MCShortcutsDidChange"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    MMLog(BOLD CYAN "Listening for Shortcut config changes" RESET);
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    
    [NSApp run];

    CFRunLoopSourceInvalidate(rls);
    CFRelease(rls);
    CFRelease(keys);
    CFRelease(key);
    CFRelease(store);
}
