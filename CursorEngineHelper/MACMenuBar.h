#pragma once

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern void MACMenuBarStart(void);
extern void MACMenuBarApplyVisibilityPreference(void);

extern NSString * MACMenuBarLocalized(NSString *key);
extern NSBundle * _Nullable MACMenuBarParentAppBundle(void);
extern NSImage * _Nullable MACMenuBarBrandImage(void);

@interface MACMenuBarPanelSnapshot : NSObject
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *catalog;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *favorites;
@property (nonatomic, copy, nullable) NSString *appliedIdentifier;
@property (nonatomic, copy, nullable) NSString *overrideIdentifier;
@property (nonatomic, copy, nullable) NSString *frontBundleIdentifier;
@property (nonatomic, copy, nullable) NSString *frontDisplayName;
@property (nonatomic, strong, nullable) NSImage *frontIcon;
@property (nonatomic, copy, nullable) NSString *frontRuleThemeIdentifier;
@property (nonatomic) BOOL switchByApp;
@property (nonatomic) BOOL cursorShadow;
@property (nonatomic) BOOL focusFollowsMouse;
@property (nonatomic) BOOL accessibilityTrusted;
@property (nonatomic) double cursorScale;
@property (nonatomic) double panelBackdropAlpha;
@end

extern MACMenuBarPanelSnapshot * MACMenuBarCurrentSnapshot(void);
extern NSImage * _Nullable MACMenuBarThumbnailForTheme(NSString *identifier);

extern void MACMenuBarApplyTheme(NSString *identifier);
extern void MACMenuBarRestoreSystemCursors(void);
extern void MACMenuBarSetSwitchByApp(BOOL enabled);
extern void MACMenuBarSetFrontAppRule(NSString * _Nullable themeIdentifier);
extern void MACMenuBarPreviewCursorScale(double scale);
extern void MACMenuBarCommitCursorScale(double scale);
extern void MACMenuBarSetCursorShadow(BOOL enabled);
extern void MACMenuBarSetFocusFollowsMouse(BOOL enabled);
extern void MACMenuBarRequestFocusFollowsMouseAccess(void);
extern void MACMenuBarOpenAccessibilitySettings(void);

NS_ASSUME_NONNULL_END
