#import "MACFocusFollowsMouse.h"
#import "MACCursorDefs.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <crt_externs.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

NSString * const MACPreferencesFocusFollowsMouseKey = @"MACFocusFollowsMouse";
NSString * const MACPreferencesFFMAccessibilityTrustedKey = @"MACFFMAccessibilityTrusted";
NSString * const MACFocusFollowsMouseDidChangeNotification = @"MACFocusFollowsMouseDidChange";
NSString * const MACFocusFollowsMouseStatusDidChangeNotification = @"MACFocusFollowsMouseStatusDidChange";

const char * const MACFFMTrustProbeArgument = "--accessibility-probe";
const NSTimeInterval MACFFMTrustPollInterval = 2.0;
const NSInteger MACFFMDefaultDelayMs = 100;
const NSInteger MACFFMMaxDelayMs = 1000;
const CGFloat MACFFMMovementThreshold = 2.0;
const NSTimeInterval MACFFMRecentRaiseWindow = 1.0;
const NSTimeInterval MACFFMSameWindowDebounce = 0.5;
const NSTimeInterval MACFFMGestureCooldown = 0.3;
const NSTimeInterval MACFFMSpaceChangeCooldown = 1.0;

NSDictionary * _Nullable MACFFMReadConfig(void) {
    CFPreferencesSynchronize((__bridge CFStringRef)kMACDomain,
                             kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    id raw = (__bridge_transfer id)CFPreferencesCopyAppValue(
        (__bridge CFStringRef)MACPreferencesFocusFollowsMouseKey,
        (__bridge CFStringRef)kMACDomain);
    if (![raw isKindOfClass:[NSData class]]) return nil;

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:(NSData *)raw options:0 error:&error];
    if (error || ![parsed isKindOfClass:[NSDictionary class]]) return nil;
    return (NSDictionary *)parsed;
}

BOOL MACFFMEnabled(NSDictionary * _Nullable config) {
    if (![config isKindOfClass:[NSDictionary class]]) return NO;
    id flag = config[@"enabled"];
    if (![flag isKindOfClass:[NSNumber class]]) return NO;
    return [flag boolValue];
}

NSInteger MACFFMDelayMs(NSDictionary * _Nullable config) {
    if (![config isKindOfClass:[NSDictionary class]]) return MACFFMDefaultDelayMs;
    id value = config[@"delayMs"];
    if (![value isKindOfClass:[NSNumber class]]) return MACFFMDefaultDelayMs;
    if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return MACFFMDefaultDelayMs;
    NSInteger ms = [(NSNumber *)value integerValue];
    if (ms < 0) return 0;
    if (ms > MACFFMMaxDelayMs) return MACFFMMaxDelayMs;
    return ms;
}

NSUInteger MACFFMDisableModifierFlag(NSDictionary * _Nullable config) {
    NSString *name = nil;
    if ([config isKindOfClass:[NSDictionary class]]) {
        id value = config[@"disableModifier"];
        if ([value isKindOfClass:[NSString class]]) name = (NSString *)value;
    }
    if (name.length == 0) return NSEventModifierFlagControl;
    NSString *lowered = name.lowercaseString;
    if ([lowered isEqualToString:@"off"]) return 0;
    if ([lowered isEqualToString:@"option"]) return NSEventModifierFlagOption;
    return NSEventModifierFlagControl;
}

BOOL MACFFMIgnoreSpaceChange(NSDictionary * _Nullable config) {
    if (![config isKindOfClass:[NSDictionary class]]) return NO;
    id flag = config[@"ignoreSpaceChange"];
    if (![flag isKindOfClass:[NSNumber class]]) return NO;
    return [flag boolValue];
}

static NSArray<NSString *> * _Nullable usableStringList(id candidate) {
    if (![candidate isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id entry in (NSArray *)candidate) {
        if (![entry isKindOfClass:[NSString class]]) continue;
        if ([(NSString *)entry length] == 0) continue;
        [result addObject:(NSString *)entry];
    }
    return result;
}

NSArray<NSString *> * MACFFMIgnoreBundleIdentifiers(NSDictionary * _Nullable config) {
    NSArray<NSString *> *list = nil;
    if ([config isKindOfClass:[NSDictionary class]]) {
        list = usableStringList(config[@"ignoreBundleIdentifiers"]);
    }
    return list ?: @[];
}

NSArray<NSString *> * MACFFMStayFocusedBundleIdentifiers(NSDictionary * _Nullable config) {
    NSArray<NSString *> *list = nil;
    if ([config isKindOfClass:[NSDictionary class]]) {
        list = usableStringList(config[@"stayFocusedBundleIdentifiers"]);
    }
    return list ?: @[@"com.apple.SecurityAgent"];
}

NSArray<NSString *> * MACFFMBuiltInIgnoreBundleIdentifiers(void) {
    return @[@"com.apple.dock",
             @"com.apple.notificationcenterui",
             @"com.apple.controlcenter",
             @"com.apple.WindowManager",
             @"com.apple.Spotlight",
             @"com.writronic.MaCursor",
             @"com.writronic.macursor.helper"];
}

CGPoint MACFFMConvertToAXPoint(CGPoint cocoaPoint, CGFloat primaryScreenHeight) {
    return CGPointMake(cocoaPoint.x, primaryScreenHeight - cocoaPoint.y);
}

BOOL MACFFMRoleIsWindowLike(NSString * _Nullable role) {
    if (role == nil) return NO;
    return [role isEqualToString:@"AXWindow"] ||
           [role isEqualToString:@"AXSheet"] ||
           [role isEqualToString:@"AXDrawer"];
}

BOOL MACFFMRoleIsAcceptable(NSString * _Nullable role, NSString * _Nullable subrole) {
    if (!MACFFMRoleIsWindowLike(role)) return NO;
    if ([subrole isEqualToString:@"AXDesktop"]) return NO;
    return YES;
}

BOOL MACFFMBundleListContains(NSArray<NSString *> * _Nullable list, NSString * _Nullable bundleID) {
    if (bundleID.length == 0) return NO;
    for (NSString *entry in list) {
        if ([entry caseInsensitiveCompare:(NSString *)bundleID] == NSOrderedSame) return YES;
    }
    return NO;
}

BOOL MACFFMMovementExceedsThreshold(CGPoint previous, CGPoint current, CGFloat threshold) {
    CGFloat dx = current.x - previous.x;
    CGFloat dy = current.y - previous.y;
    return (dx * dx + dy * dy) >= (threshold * threshold);
}

BOOL MACFFMWithinInterval(NSTimeInterval earlier, NSTimeInterval now, NSTimeInterval window) {
    if (earlier <= 0) return NO;
    NSTimeInterval delta = now - earlier;
    return delta >= 0 && delta <= window;
}

MACFFMTrustAction MACFFMTrustActionFor(BOOL enabled, BOOL running, BOOL trusted) {
    if (running && (!trusted || !enabled)) return MACFFMTrustActionStop;
    if (!running && enabled && trusted) return MACFFMTrustActionStart;
    return MACFFMTrustActionKeep;
}

BOOL MACFFMShouldPollForTrust(BOOL enabled, BOOL trusted) {
    (void)trusted;
    return enabled;
}

BOOL MACFFMShouldSkip(MACFFMDecisionInputs inputs) {
    return inputs.disableModifierHeld ||
           inputs.mouseButtonDown ||
           inputs.spaceChangeCooldownActive ||
           inputs.gestureCooldownActive ||
           inputs.frontmostIsDock ||
           inputs.frontmostIsStayFocused ||
           inputs.candidateAlreadyFocused ||
           inputs.candidateIsChildOfFocused ||
           inputs.sameWindowRecentlyRaised;
}

static NSTimeInterval sLastFFMRaiseTime = 0;
static NSString *sLastFFMRaiseBundleID = nil;

void MACFFMNoteRaiseAt(NSTimeInterval timestamp, NSString * _Nullable bundleID) {
    sLastFFMRaiseTime = timestamp;
    sLastFFMRaiseBundleID = [bundleID copy];
}

BOOL MACFFMConsumeRecentRaiseAt(NSTimeInterval now, NSString * _Nullable bundleID) {
    if (!MACFFMWithinInterval(sLastFFMRaiseTime, now, MACFFMRecentRaiseWindow)) return NO;
    if (sLastFFMRaiseBundleID.length > 0 && bundleID.length > 0 &&
        ![sLastFFMRaiseBundleID isEqualToString:(NSString *)bundleID]) {
        return NO;
    }
    sLastFFMRaiseTime = 0;
    sLastFFMRaiseBundleID = nil;
    return YES;
}

void MACFocusFollowsMouseNoteRaise(NSString * _Nullable bundleID) {
    MACFFMNoteRaiseAt([NSDate timeIntervalSinceReferenceDate], bundleID);
}

BOOL MACFocusFollowsMouseConsumeRecentRaise(NSString * _Nullable bundleID) {
    return MACFFMConsumeRecentRaiseAt([NSDate timeIntervalSinceReferenceDate], bundleID);
}

static id sMouseMonitor = nil;
static AXUIElementRef sSystemWideElement = NULL;
static NSDictionary *sActiveConfig = nil;
static dispatch_source_t sDwellTimer = NULL;
static CGPoint sDwellAnchor;
static BOOL sHasDwellAnchor = NO;
static NSTimeInterval sLastGestureTime = 0;
static NSTimeInterval sLastSpaceChangeTime = 0;
static CFHashCode sLastRaisedWindowHash = 0;
static NSTimeInterval sLastRaisedWindowTime = 0;
static BOOL sConfigEnabled = NO;
static dispatch_source_t sTrustPollTimer = NULL;

BOOL MACFocusFollowsMouseIsRunning(void) {
    return sMouseMonitor != nil;
}

static BOOL inProcessTrustBit(void) {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @NO};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

int MACFocusFollowsMouseTrustProbeMain(void) {
    return inProcessTrustBit() ? EXIT_SUCCESS : EXIT_FAILURE;
}

static BOOL accessibilityCapabilityIsLive(void) {
    const char *path = [NSBundle mainBundle].executableURL.fileSystemRepresentation;
    if (path == NULL) return inProcessTrustBit();

    char *argv[] = {(char *)path, (char *)MACFFMTrustProbeArgument, NULL};
    pid_t child = 0;
    if (posix_spawn(&child, path, NULL, NULL, argv, *_NSGetEnviron()) != 0) return inProcessTrustBit();

    int status = 0;
    pid_t reaped = 0;
    for (int attempt = 0; attempt < 100; attempt++) {
        reaped = waitpid(child, &status, WNOHANG);
        if (reaped == child) break;
        if (reaped < 0 && errno != EINTR) break;
        usleep(5000);
    }
    if (reaped != child) {
        kill(child, SIGKILL);
        waitpid(child, NULL, 0);
        return inProcessTrustBit();
    }
    if (!WIFEXITED(status)) return inProcessTrustBit();
    return WEXITSTATUS(status) == EXIT_SUCCESS;
}

BOOL MACFocusFollowsMouseIsTrusted(void) {
    return accessibilityCapabilityIsLive();
}

void MACFocusFollowsMouseNoteSpaceChange(void) {
    sLastSpaceChangeTime = [NSDate timeIntervalSinceReferenceDate];
}

static void persistTrust(BOOL trusted) {
    id stored = MACDefault(MACPreferencesFFMAccessibilityTrustedKey);
    if ([stored isKindOfClass:[NSNumber class]] && [stored boolValue] == trusted) return;
    MACSetDefault(@(trusted), MACPreferencesFFMAccessibilityTrustedKey);
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:MACFocusFollowsMouseStatusDidChangeNotification
                      object:nil
                    userInfo:nil
          deliverImmediately:YES];
    MMLog(BOLD CYAN "Focus follows mouse Accessibility access is now %s" RESET, trusted ? "granted" : "missing");
}

static void stopTrustPoll(void) {
    if (sTrustPollTimer) {
        dispatch_source_cancel(sTrustPollTimer);
        sTrustPollTimer = NULL;
    }
}

static void updateTrustPoll(BOOL trusted) {
    if (!MACFFMShouldPollForTrust(sConfigEnabled, trusted)) {
        stopTrustPoll();
        return;
    }
    if (sTrustPollTimer) return;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_main_queue());
    sTrustPollTimer = timer;
    dispatch_source_set_timer(timer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MACFFMTrustPollInterval * NSEC_PER_SEC)),
        (uint64_t)(MACFFMTrustPollInterval * NSEC_PER_SEC), (uint64_t)(0.5 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{
        if (timer != sTrustPollTimer) return;
        MACFocusFollowsMouseSyncTrust();
    });
    dispatch_resume(timer);
}

void MACFocusFollowsMouseSyncTrust(void) {
    BOOL trusted = MACFocusFollowsMouseIsTrusted();
    persistTrust(trusted);
    switch (MACFFMTrustActionFor(sConfigEnabled, MACFocusFollowsMouseIsRunning(), trusted)) {
        case MACFFMTrustActionStart:
            MACFocusFollowsMouseStart();
            break;
        case MACFFMTrustActionStop:
            MACFocusFollowsMouseStop();
            break;
        case MACFFMTrustActionKeep:
            break;
    }
    updateTrustPoll(trusted);
}

void MACFocusFollowsMouseConfigDidChange(void) {
    MACFocusFollowsMouseStop();
    sConfigEnabled = MACFFMEnabled(MACFFMReadConfig());
    MACFocusFollowsMouseSyncTrust();
}

static void cancelDwellTimer(void) {
    if (sDwellTimer) {
        dispatch_source_cancel(sDwellTimer);
        sDwellTimer = NULL;
    }
}

void MACFocusFollowsMouseCancelPendingRaise(void) {
    cancelDwellTimer();
}

static NSString * _Nullable copyStringAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess) return nil;
    if (value == NULL) return nil;
    if (CFGetTypeID(value) != CFStringGetTypeID()) {
        CFRelease(value);
        return nil;
    }
    return (__bridge_transfer NSString *)value;
}

static AXUIElementRef _Nullable copyContainingWindow(AXUIElementRef start) {
    AXUIElementRef current = (AXUIElementRef)CFRetain(start);
    for (NSUInteger hop = 0; hop < 20; hop++) {
        NSString *role = copyStringAttribute(current, kAXRoleAttribute);
        if (MACFFMRoleIsWindowLike(role)) {
            NSString *subrole = copyStringAttribute(current, kAXSubroleAttribute);
            if (MACFFMRoleIsAcceptable(role, subrole)) return current;
            CFRelease(current);
            return NULL;
        }
        CFTypeRef parent = NULL;
        AXError err = AXUIElementCopyAttributeValue(current, kAXParentAttribute, &parent);
        CFRelease(current);
        if (err != kAXErrorSuccess || parent == NULL) return NULL;
        if (CFGetTypeID(parent) != AXUIElementGetTypeID()) {
            CFRelease(parent);
            return NULL;
        }
        current = (AXUIElementRef)parent;
    }
    CFRelease(current);
    return NULL;
}

static BOOL copyWindowFrame(AXUIElementRef window, CGRect *outFrame) {
    CFTypeRef positionValue = NULL;
    CFTypeRef sizeValue = NULL;
    CGPoint origin = CGPointZero;
    CGSize size = CGSizeZero;
    BOOL ok = NO;
    if (AXUIElementCopyAttributeValue(window, kAXPositionAttribute, &positionValue) == kAXErrorSuccess &&
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute, &sizeValue) == kAXErrorSuccess &&
        positionValue != NULL && sizeValue != NULL &&
        AXValueGetValue((AXValueRef)positionValue, kAXValueTypeCGPoint, &origin) &&
        AXValueGetValue((AXValueRef)sizeValue, kAXValueTypeCGSize, &size)) {
        *outFrame = (CGRect){origin, size};
        ok = YES;
    }
    if (positionValue) CFRelease(positionValue);
    if (sizeValue) CFRelease(sizeValue);
    return ok;
}

static void dwellTimerFired(void) {
    NSDictionary *config = sActiveConfig;
    if (!config) return;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSRunningApplication *frontmost = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *frontBundle = frontmost.bundleIdentifier;

    NSUInteger disableFlag = MACFFMDisableModifierFlag(config);
    MACFFMDecisionInputs inputs = {
        .disableModifierHeld = disableFlag != 0 && ([NSEvent modifierFlags] & disableFlag) != 0,
        .mouseButtonDown = [NSEvent pressedMouseButtons] != 0,
        .spaceChangeCooldownActive = MACFFMIgnoreSpaceChange(config) &&
            MACFFMWithinInterval(sLastSpaceChangeTime, now, MACFFMSpaceChangeCooldown),
        .gestureCooldownActive = MACFFMWithinInterval(sLastGestureTime, now, MACFFMGestureCooldown),
        .frontmostIsDock = [frontBundle isEqualToString:@"com.apple.dock"],
        .frontmostIsStayFocused = MACFFMBundleListContains(
            MACFFMStayFocusedBundleIdentifiers(config), frontBundle),
    };
    if (MACFFMShouldSkip(inputs)) return;

    NSScreen *primary = [NSScreen screens].firstObject;
    if (!primary) return;
    CGPoint axPoint = MACFFMConvertToAXPoint([NSEvent mouseLocation], NSHeight(primary.frame));

    if (!sSystemWideElement) return;
    AXUIElementRef hit = NULL;
    AXError hitErr = AXUIElementCopyElementAtPosition(sSystemWideElement,
                                                      (float)axPoint.x, (float)axPoint.y, &hit);
    if (hitErr == kAXErrorAPIDisabled) {
        MACFocusFollowsMouseSyncTrust();
        return;
    }
    if (hitErr != kAXErrorSuccess || hit == NULL) return;

    AXUIElementRef window = copyContainingWindow(hit);
    CFRelease(hit);
    if (!window) return;

    pid_t pid = 0;
    if (AXUIElementGetPid(window, &pid) != kAXErrorSuccess || pid <= 0 ||
        pid == [NSProcessInfo processInfo].processIdentifier) {
        CFRelease(window);
        return;
    }

    NSRunningApplication *owner = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (!owner) {
        CFRelease(window);
        return;
    }
    NSString *ownerBundle = owner.bundleIdentifier;
    if (MACFFMBundleListContains(MACFFMBuiltInIgnoreBundleIdentifiers(), ownerBundle) ||
        MACFFMBundleListContains(MACFFMIgnoreBundleIdentifiers(config), ownerBundle)) {
        CFRelease(window);
        return;
    }

    BOOL alreadyFocused = NO;
    BOOL childOfFocused = NO;
    if (pid == frontmost.processIdentifier) {
        CFTypeRef mainValue = NULL;
        if (AXUIElementCopyAttributeValue(window, kAXMainAttribute, &mainValue) == kAXErrorSuccess &&
            mainValue != NULL) {
            alreadyFocused = CFGetTypeID(mainValue) == CFBooleanGetTypeID() &&
                CFBooleanGetValue((CFBooleanRef)mainValue);
            CFRelease(mainValue);
        }
        if (!alreadyFocused) {
            AXUIElementRef appElement = AXUIElementCreateApplication(pid);
            if (appElement) {
                CFTypeRef focusedWindow = NULL;
                if (AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute,
                                                  &focusedWindow) == kAXErrorSuccess &&
                    focusedWindow != NULL) {
                    if (CFGetTypeID(focusedWindow) == AXUIElementGetTypeID()) {
                        if (CFEqual(focusedWindow, window)) {
                            alreadyFocused = YES;
                        } else {
                            CGRect focusedFrame;
                            CGRect candidateFrame;
                            if (copyWindowFrame((AXUIElementRef)focusedWindow, &focusedFrame) &&
                                copyWindowFrame(window, &candidateFrame)) {
                                childOfFocused = CGRectContainsRect(focusedFrame, candidateFrame);
                            }
                        }
                    }
                    CFRelease(focusedWindow);
                }
                CFRelease(appElement);
            }
        }
    }

    CFHashCode windowHash = CFHash(window);
    inputs.candidateAlreadyFocused = alreadyFocused;
    inputs.candidateIsChildOfFocused = childOfFocused;
    inputs.sameWindowRecentlyRaised = windowHash == sLastRaisedWindowHash &&
        MACFFMWithinInterval(sLastRaisedWindowTime, now, MACFFMSameWindowDebounce);
    if (MACFFMShouldSkip(inputs)) {
        CFRelease(window);
        return;
    }

    if (pid != frontmost.processIdentifier) {
        MACFocusFollowsMouseNoteRaise(ownerBundle);
    }
    AXError raiseErr = AXUIElementPerformAction(window, kAXRaiseAction);
    [owner activateWithOptions:0];
    sLastRaisedWindowHash = windowHash;
    sLastRaisedWindowTime = now;
    if (raiseErr == kAXErrorSuccess) {
        MMLog(BOLD GREEN "Focus follows mouse raised a window of %s" RESET,
              [ownerBundle UTF8String] ?: "unknown");
    } else {
        MMLog(BOLD YELLOW "Focus follows mouse raise action returned %d" RESET, (int)raiseErr);
    }
    CFRelease(window);
}

static void scheduleDwellTimer(NSInteger delayMs) {
    cancelDwellTimer();
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_main_queue());
    sDwellTimer = timer;
    dispatch_source_set_timer(timer,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)delayMs * NSEC_PER_MSEC),
        DISPATCH_TIME_FOREVER, 5 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        if (timer != sDwellTimer) return;
        dispatch_source_cancel(timer);
        sDwellTimer = NULL;
        dwellTimerFired();
    });
    dispatch_resume(timer);
}

static void handleMouseMoved(void) {
    CGPoint location = [NSEvent mouseLocation];
    if (sHasDwellAnchor &&
        !MACFFMMovementExceedsThreshold(sDwellAnchor, location, MACFFMMovementThreshold)) {
        return;
    }
    sDwellAnchor = location;
    sHasDwellAnchor = YES;
    scheduleDwellTimer(MACFFMDelayMs(sActiveConfig));
}

void MACFocusFollowsMouseStart(void) {
    if (sMouseMonitor) return;

    NSDictionary *config = MACFFMReadConfig();
    sConfigEnabled = MACFFMEnabled(config);
    if (!sConfigEnabled) return;
    if (!MACFocusFollowsMouseIsTrusted()) {
        MMLog(BOLD YELLOW "Focus follows mouse is enabled but Accessibility access is missing" RESET);
        updateTrustPoll(NO);
        return;
    }

    sActiveConfig = config;
    if (!sSystemWideElement) sSystemWideElement = AXUIElementCreateSystemWide();
    sHasDwellAnchor = NO;

    sMouseMonitor = [NSEvent
        addGlobalMonitorForEventsMatchingMask:(NSEventMaskMouseMoved | NSEventMaskScrollWheel)
        handler:^(NSEvent *event) {
            if (event.type == NSEventTypeScrollWheel) {
                sLastGestureTime = [NSDate timeIntervalSinceReferenceDate];
                cancelDwellTimer();
                return;
            }
            handleMouseMoved();
        }];
    updateTrustPoll(YES);
    MMLog(BOLD GREEN "Focus follows mouse started (delay %ld ms)" RESET,
          (long)MACFFMDelayMs(sActiveConfig));
}

void MACFocusFollowsMouseStop(void) {
    cancelDwellTimer();
    stopTrustPoll();
    if (sMouseMonitor) {
        [NSEvent removeMonitor:sMouseMonitor];
        sMouseMonitor = nil;
        MMLog(BOLD CYAN "Focus follows mouse stopped" RESET);
    }
    if (sSystemWideElement) {
        CFRelease(sSystemWideElement);
        sSystemWideElement = NULL;
    }
    sActiveConfig = nil;
    sHasDwellAnchor = NO;
}
