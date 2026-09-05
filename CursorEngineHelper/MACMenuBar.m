#import "MACMenuBar.h"
#import "MACMenuBarState.h"
#import "MACCursorDefs.h"
#import "MACCursorActions.h"
#import "MACAutoSwitch.h"
#import "MACFocusFollowsMouse.h"
#import "MaCursorHelper-Swift.h"

static const NSTimeInterval MACMenuBarReopenDebounce = 0.35;
static const unsigned short MACMenuBarEscapeKeyCode = 53;

NSBundle * _Nullable MACMenuBarParentAppBundle(void) {
    NSURL *url = [NSBundle mainBundle].bundleURL;
    for (NSUInteger index = 0; index < 4; index++) {
        url = [url URLByDeletingLastPathComponent];
    }
    NSBundle *bundle = [NSBundle bundleWithURL:url];
    if ([bundle.bundleIdentifier isEqualToString:MACAppBundleIdentifier]) return bundle;
    return nil;
}

NSString * MACMenuBarLocalized(NSString *key) {
    NSBundle *parent = MACMenuBarParentAppBundle();
    if (parent == nil) return key;

    NSString *language = nil;
    id stored = MACDefault(@"MACLanguage");
    if ([stored isKindOfClass:[NSString class]] &&
        [(NSString *)stored length] > 0 &&
        ![(NSString *)stored isEqualToString:@"system"]) {
        language = (NSString *)stored;
    }
    if (language == nil) {
        language = [NSBundle preferredLocalizationsFromArray:parent.localizations].firstObject;
    }
    if (language == nil) return key;

    NSString *path = [parent pathForResource:language ofType:@"lproj"];
    NSBundle *strings = path ? [NSBundle bundleWithPath:path] : nil;
    if (strings == nil) return key;

    return [strings localizedStringForKey:key value:key table:@"Localizable"];
}

NSImage * _Nullable MACMenuBarBrandImage(void) {
    NSBundle *parent = MACMenuBarParentAppBundle();
    NSImage *image = parent ? [parent imageForResource:@"MenuBarIcon"] : nil;
    if (image == nil) {
        image = [NSImage imageWithSystemSymbolName:@"cursorarrow" accessibilityDescription:nil];
    }
    if (image == nil) return nil;
    image.template = YES;
    image.size = NSMakeSize(18.0, 18.0);
    return image;
}

static NSString * _Nullable storedString(NSString *key) {
    id value = MACDefault(key);
    if (![value isKindOfClass:[NSString class]]) return nil;
    return [(NSString *)value length] > 0 ? (NSString *)value : nil;
}

static NSString * _Nullable displayNameForBundleID(NSString * _Nullable bundleID) {
    if (bundleID.length == 0) return nil;
    NSURL *url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:(NSString *)bundleID];
    if (url == nil) return bundleID;
    return [[NSFileManager defaultManager] displayNameAtPath:url.path] ?: bundleID;
}

static NSImage * _Nullable iconForBundleID(NSString * _Nullable bundleID) {
    if (bundleID.length == 0) return nil;
    NSURL *url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:(NSString *)bundleID];
    if (url == nil) return nil;
    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:url.path];
    icon.size = NSMakeSize(32.0, 32.0);
    return icon;
}

static void postDistributed(NSString *name) {
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:name object:nil userInfo:nil deliverImmediately:YES];
}

static double panelBackgroundLevel(void) {
    return MACMenuBarPanelBackgroundLevel(MACDefault(MACPreferencesMenuBarPanelBackgroundKey));
}

static void applyPanelGlassAlpha(NSView * _Nullable contentView, double alpha) {
    NSView *frame = contentView;
    while (frame.superview != nil) frame = frame.superview;
    for (NSView *subview in frame.subviews) {
        if ([NSStringFromClass([subview class]) containsString:@"Glass"]) subview.alphaValue = alpha;
    }
}

static void reapplyVisibleTheme(BOOL restoreWhenNone) {
    NSString *applied = storedString(MACPreferencesAppliedCursorKey);
    NSString *override = storedString(MACPreferencesAppOverrideKey);
    NSString *visible = MACMenuBarVisibleThemeIdentifier(applied, override);
    if (visible == nil) {
        if (restoreWhenNone) {
            NSError *error = nil;
            resetAllCursors(&error);
        }
        return;
    }

    NSString *path = MACAutoSwitchThemePathForIdentifier(visible);
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSString *base = override ? (storedString(MACPreferencesAppOverrideBaseKey) ?: applied) : nil;
    if (!applyThemeAtPath(path)) return;
    if (override) MACSetDefault(base, MACPreferencesAppliedCursorKey);
    MACAutoSwitchForceVisualRefresh();
}

@implementation MACMenuBarPanelSnapshot
@end

MACMenuBarPanelSnapshot * MACMenuBarCurrentSnapshot(void) {
    MACMenuBarPanelSnapshot *snapshot = [MACMenuBarPanelSnapshot new];
    NSDictionary *config = MACAutoSwitchReadConfig();

    snapshot.catalog = MACMenuBarThemeCatalog();
    snapshot.favorites = MACMenuBarFavoriteCatalog(snapshot.catalog, MACDefault(MACPreferencesFavoriteThemesKey));
    snapshot.appliedIdentifier = storedString(MACPreferencesAppliedCursorKey);
    snapshot.overrideIdentifier = storedString(MACPreferencesAppOverrideKey);

    NSString *front = MACMenuBarLastForegroundBundleID();
    snapshot.frontBundleIdentifier = front;
    snapshot.frontDisplayName = displayNameForBundleID(front);
    snapshot.frontIcon = iconForBundleID(front);
    snapshot.frontRuleThemeIdentifier = MACMenuBarRuleThemeForBundleID(config, front);

    snapshot.switchByApp = [config[@"switchByApp"] boolValue];
    snapshot.cursorShadow = MACFlag(MACPreferencesCursorShadowKey);
    snapshot.focusFollowsMouse = MACFFMEnabled(MACFFMReadConfig());
    snapshot.accessibilityTrusted = MACFocusFollowsMouseIsTrusted();

    id scale = MACDefault(MACPreferencesCursorScaleKey);
    snapshot.cursorScale = [scale isKindOfClass:[NSNumber class]]
        ? MACMenuBarClampCursorScale([(NSNumber *)scale doubleValue])
        : 1.0;
    snapshot.panelBackdropAlpha = MACMenuBarPanelBackdropAlpha(panelBackgroundLevel());
    return snapshot;
}

static NSMutableDictionary<NSString *, NSDictionary *> *thumbnailCache(void) {
    static NSMutableDictionary *cache = nil;
    if (cache == nil) cache = [NSMutableDictionary dictionary];
    return cache;
}

NSImage * _Nullable MACMenuBarThumbnailForTheme(NSString *identifier) {
    if (identifier.length == 0) return nil;
    NSString *path = MACAutoSwitchThemePathForIdentifier(identifier);
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    NSDate *modified = attributes[NSFileModificationDate];
    if (modified == nil) return nil;

    NSDictionary *cached = thumbnailCache()[identifier];
    if (cached && [cached[@"modified"] isEqualToDate:modified]) return cached[@"image"];

    NSImage *image = MACMenuBarThumbnailImageForThemeAtPath(path);
    if (image) thumbnailCache()[identifier] = @{ @"modified": modified, @"image": image };
    return image;
}

void MACMenuBarApplyTheme(NSString *identifier) {
    if (identifier.length == 0) return;
    NSString *path = MACAutoSwitchThemePathForIdentifier(identifier);
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    if (!applyThemeAtPath(path)) return;

    MACAutoSwitchClearAppOverride();
    postDistributed(MACAutoSwitchAppliedThemeDidChangeNotification);
}

void MACMenuBarRestoreSystemCursors(void) {
    MACSetDefault(@1.0, MACPreferencesCursorScaleKey);
    MACSetFlag(NO, MACPreferencesHandednessKey);
    MACSetFlag(NO, MACPreferencesCursorShadowKey);
    setCursorScale(1.0f);
    MACAutoSwitchClearAppOverride();
    NSError *error = nil;
    resetAllCursors(&error);
    postDistributed(MACAutoSwitchAppliedThemeDidChangeNotification);
    postDistributed(MACCursorPreferencesDidChangeNotification);
}

void MACMenuBarSetSwitchByApp(BOOL enabled) {
    MACMenuBarWriteConfig(MACMenuBarConfigBySettingSwitchByApp(MACAutoSwitchReadConfig(), enabled));
    MACAutoSwitchHandleFrontmostApp(MACMenuBarLastForegroundBundleID());
}

void MACMenuBarSetFrontAppRule(NSString * _Nullable themeIdentifier) {
    NSString *front = MACMenuBarLastForegroundBundleID();
    if (front.length == 0) return;

    NSString *theme = themeIdentifier.length > 0 ? themeIdentifier : nil;
    NSDictionary *updated = MACMenuBarConfigBySettingRule(MACAutoSwitchReadConfig(), front,
                                                          displayNameForBundleID(front), theme);
    if (![updated[@"switchByApp"] boolValue] && theme != nil) {
        updated = MACMenuBarConfigBySettingSwitchByApp(updated, YES);
    }
    MACMenuBarWriteConfig(updated);
    MACAutoSwitchHandleFrontmostApp(front);
}

void MACMenuBarPreviewCursorScale(double scale) {
    double clamped = MACMenuBarClampCursorScale(scale);
    setCursorScale((float)MAX(1.0, clamped));
}

void MACMenuBarCommitCursorScale(double scale) {
    double clamped = MACMenuBarClampCursorScale(scale);
    MACSetDefault(@(clamped), MACPreferencesCursorScaleKey);
    setCursorScale((float)MAX(1.0, clamped));
    reapplyVisibleTheme(YES);
    postDistributed(MACCursorPreferencesDidChangeNotification);
}

void MACMenuBarSetCursorShadow(BOOL enabled) {
    MACSetFlag(enabled, MACPreferencesCursorShadowKey);
    reapplyVisibleTheme(NO);
    postDistributed(MACCursorPreferencesDidChangeNotification);
}

void MACMenuBarSetFocusFollowsMouse(BOOL enabled) {
    NSDictionary *updated = MACMenuBarFFMConfigBySettingEnabled(MACFFMReadConfig(), enabled);
    if (![NSJSONSerialization isValidJSONObject:updated]) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:updated options:0 error:NULL];
    if (data == nil) return;

    MACSetDefault(data, MACPreferencesFocusFollowsMouseKey);
    postDistributed(MACFocusFollowsMouseDidChangeNotification);
}

void MACMenuBarOpenAccessibilitySettings(void) {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}

static void launchParentAppThenPost(NSString * _Nullable name) {
    NSBundle *parent = MACMenuBarParentAppBundle();
    if (parent == nil) return;

    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;

    [[NSWorkspace sharedWorkspace] openApplicationAtURL:parent.bundleURL
                                          configuration:configuration
                                      completionHandler:^(NSRunningApplication *app, NSError *error) {
        if (name == nil) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            postDistributed(name);
        });
    }];
}

void MACMenuBarRequestFocusFollowsMouseAccess(void) {
    if ([[NSRunningApplication runningApplicationsWithBundleIdentifier:MACAppBundleIdentifier] count] == 0) {
        MACSetDefault(@YES, MACPreferencesPendingFFMAccessWindowKey);
    } else {
        postDistributed(MACFocusFollowsMouseShowAccessWindowNotification);
    }
    launchParentAppThenPost(nil);
}

@interface MACMenuBarController : NSObject <NSPopoverDelegate>
@property (nonatomic, strong, nullable) NSStatusItem *statusItem;
@property (nonatomic, strong, nullable) NSPopover *popover;
@property (nonatomic, strong, nullable) id keyMonitor;
@property (nonatomic, strong, nullable) NSRunningApplication *previousApp;
@property (nonatomic) NSTimeInterval closedAt;
@end

@implementation MACMenuBarController

- (void)install {
    if (self.statusItem != nil) return;

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.behavior = NSStatusItemBehaviorRemovalAllowed;
    self.statusItem.autosaveName = @"MaCursorMenuBarItem";

    NSStatusBarButton *button = self.statusItem.button;
    button.image = MACMenuBarBrandImage();
    button.toolTip = @"MaCursor";
    [button setAccessibilityTitle:@"MaCursor"];
    [button setAccessibilityRole:NSAccessibilityButtonRole];
    button.target = self;
    button.action = @selector(statusItemClicked:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
}

- (void)uninstall {
    [self closePanel];
    self.popover = nil;
    if (self.statusItem == nil) return;
    [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
    self.statusItem = nil;
}

- (void)applyVisibility {
    BOOL wanted = MACFlag(MACPreferencesShowMenuBarIconKey);
    if (wanted) {
        [self install];
        self.statusItem.visible = YES;
    } else {
        [self uninstall];
    }
}

- (void)statusItemClicked:(id)sender {
    NSEvent *event = NSApp.currentEvent;
    if (MACMenuBarClickIsSecondary(event.type, event.modifierFlags)) {
        [self showContextMenu];
    } else {
        [self togglePanel];
    }
}

- (NSPopover *)panelPopover {
    if (self.popover != nil) return self.popover;

    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    popover.delegate = self;
    popover.contentViewController = [MACMenuBarPanelHost makeViewController];
    self.popover = popover;
    return popover;
}

- (void)togglePanel {
    if (self.popover.isShown) {
        [self closePanel];
        return;
    }
    if ([NSDate timeIntervalSinceReferenceDate] - self.closedAt < MACMenuBarReopenDebounce) return;
    [self showPanel];
}

- (void)showPanel {
    NSStatusBarButton *button = self.statusItem.button;
    if (button == nil) return;

    NSPopover *popover = [self panelPopover];
    NSAppearanceName appearanceName = MACMenuBarAppearanceNameForMode(MACDefault(@"MACAppearanceMode"));
    popover.appearance = appearanceName ? [NSAppearance appearanceNamed:appearanceName] : nil;

    [MACMenuBarPanelHost reload];
    [popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinY];
    applyPanelGlassAlpha(popover.contentViewController.view, MACMenuBarPanelGlassAlpha(panelBackgroundLevel()));
    NSRunningApplication *front = [NSWorkspace sharedWorkspace].frontmostApplication;
    self.previousApp = front.processIdentifier == NSProcessInfo.processInfo.processIdentifier ? nil : front;
    [NSApp activateIgnoringOtherApps:YES];
    [popover.contentViewController.view.window makeKeyWindow];

    __weak typeof(self) weakSelf = self;
    self.keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                            handler:^NSEvent * _Nullable(NSEvent *event) {
        if (event.keyCode == MACMenuBarEscapeKeyCode) {
            [weakSelf closePanel];
            return nil;
        }
        return event;
    }];
}

- (void)closePanel {
    if (self.popover.isShown) [self.popover performClose:nil];
}

- (void)popoverDidClose:(NSNotification *)notification {
    self.closedAt = [NSDate timeIntervalSinceReferenceDate];
    if (self.keyMonitor) {
        [NSEvent removeMonitor:self.keyMonitor];
        self.keyMonitor = nil;
    }
    if (NSApp.isActive && self.previousApp && !self.previousApp.terminated) {
        [self.previousApp activateWithOptions:0];
    }
    self.previousApp = nil;
}

- (void)showContextMenu {
    if (self.popover.isShown) {
        self.previousApp = nil;
        [self closePanel];
    }
    NSMenu *menu = [self contextMenu];
    self.statusItem.menu = menu;
    [self.statusItem.button performClick:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        weakSelf.statusItem.menu = nil;
    });
}

- (NSMenuItem *)itemWithTitle:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    return item;
}

- (NSMenu *)contextMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItem:[self itemWithTitle:MACMenuBarLocalized(@"Open MaCursor") action:@selector(openMainApp:)]];
    [menu addItem:[self itemWithTitle:MACMenuBarLocalized(@"Settings...") action:@selector(openSettings:)]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self itemWithTitle:MACMenuBarLocalized(@"Quit MaCursor") action:@selector(quit:)]];
    return menu;
}

- (void)openMainApp:(NSMenuItem *)sender {
    launchParentAppThenPost(nil);
}

- (void)openSettings:(NSMenuItem *)sender {
    MACSetDefault(@YES, MACPreferencesPendingOpenSettingsKey);
    launchParentAppThenPost(MACOpenSettingsRequestedNotification);
}

- (void)quit:(NSMenuItem *)sender {
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:MACAppBundleIdentifier]) {
        [app terminate];
    }
    [NSApp terminate:nil];
}

@end

static MACMenuBarController *sController = nil;

void MACMenuBarStart(void) {
    if (sController != nil) return;
    sController = [MACMenuBarController new];
    [sController applyVisibility];
}

void MACMenuBarApplyVisibilityPreference(void) {
    if (sController == nil) return;
    [sController applyVisibility];
}
