#pragma once

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MACPreferencesFocusFollowsMouseKey;
extern NSString * const MACPreferencesFFMAccessibilityTrustedKey;
extern NSString * const MACFocusFollowsMouseDidChangeNotification;
extern NSString * const MACFocusFollowsMouseStatusDidChangeNotification;

extern const char * const MACFFMTrustProbeArgument;
extern const NSTimeInterval MACFFMTrustPollInterval;
extern const NSInteger MACFFMDefaultDelayMs;
extern const NSInteger MACFFMMaxDelayMs;
extern const CGFloat MACFFMMovementThreshold;
extern const NSTimeInterval MACFFMRecentRaiseWindow;
extern const NSTimeInterval MACFFMSameWindowDebounce;
extern const NSTimeInterval MACFFMGestureCooldown;
extern const NSTimeInterval MACFFMSpaceChangeCooldown;

typedef struct {
    bool disableModifierHeld;
    bool mouseButtonDown;
    bool spaceChangeCooldownActive;
    bool gestureCooldownActive;
    bool frontmostIsDock;
    bool frontmostIsStayFocused;
    bool candidateAlreadyFocused;
    bool candidateIsChildOfFocused;
    bool sameWindowRecentlyRaised;
} MACFFMDecisionInputs;

typedef NS_ENUM(NSInteger, MACFFMTrustAction) {
    MACFFMTrustActionKeep,
    MACFFMTrustActionStart,
    MACFFMTrustActionStop,
};

extern MACFFMTrustAction MACFFMTrustActionFor(BOOL enabled, BOOL running, BOOL trusted);
extern BOOL MACFFMShouldPollForTrust(BOOL enabled, BOOL trusted);

extern NSDictionary * _Nullable MACFFMReadConfig(void);
extern BOOL MACFFMEnabled(NSDictionary * _Nullable config);
extern NSInteger MACFFMDelayMs(NSDictionary * _Nullable config);
extern NSUInteger MACFFMDisableModifierFlag(NSDictionary * _Nullable config);
extern BOOL MACFFMIgnoreSpaceChange(NSDictionary * _Nullable config);
extern NSArray<NSString *> * MACFFMIgnoreBundleIdentifiers(NSDictionary * _Nullable config);
extern NSArray<NSString *> * MACFFMStayFocusedBundleIdentifiers(NSDictionary * _Nullable config);
extern NSArray<NSString *> * MACFFMBuiltInIgnoreBundleIdentifiers(void);

extern CGPoint MACFFMConvertToAXPoint(CGPoint cocoaPoint, CGFloat primaryScreenHeight);
extern BOOL MACFFMRoleIsWindowLike(NSString * _Nullable role);
extern BOOL MACFFMRoleIsAcceptable(NSString * _Nullable role, NSString * _Nullable subrole);
extern BOOL MACFFMBundleListContains(NSArray<NSString *> * _Nullable list, NSString * _Nullable bundleID);
extern BOOL MACFFMMovementExceedsThreshold(CGPoint previous, CGPoint current, CGFloat threshold);
extern BOOL MACFFMWithinInterval(NSTimeInterval earlier, NSTimeInterval now, NSTimeInterval window);
extern BOOL MACFFMShouldSkip(MACFFMDecisionInputs inputs);

extern void MACFFMNoteRaiseAt(NSTimeInterval timestamp, NSString * _Nullable bundleID);
extern BOOL MACFFMConsumeRecentRaiseAt(NSTimeInterval now, NSString * _Nullable bundleID);
extern void MACFocusFollowsMouseNoteRaise(NSString * _Nullable bundleID);
extern BOOL MACFocusFollowsMouseConsumeRecentRaise(NSString * _Nullable bundleID);
extern void MACFocusFollowsMouseCancelPendingRaise(void);

extern void MACFocusFollowsMouseStart(void);
extern void MACFocusFollowsMouseStop(void);
extern BOOL MACFocusFollowsMouseIsRunning(void);
extern void MACFocusFollowsMouseNoteSpaceChange(void);
extern BOOL MACFocusFollowsMouseIsTrusted(void);
extern int MACFocusFollowsMouseTrustProbeMain(void);
extern void MACFocusFollowsMouseSyncTrust(void);
extern void MACFocusFollowsMouseConfigDidChange(void);

NS_ASSUME_NONNULL_END
