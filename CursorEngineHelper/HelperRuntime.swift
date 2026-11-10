import AppKit
import Carbon
import Metal
import SystemConfiguration

private func helperHotKeyCallback(
    _ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context else { return OSStatus(eventNotHandledErr) }
    var hotKey = EventHotKeyID(signature: 0, id: 0)
    let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
    guard result == noErr else { return result }
    let runtime = Unmanaged<HelperRuntime>.fromOpaque(context).takeUnretainedValue()
    return MainActor.assumeIsolated {
        runtime.hotKeyPressed(signature: hotKey.signature, id: hotKey.id)
    }
}

private func helperConsoleUserCallback(
    _ store: SCDynamicStore, _ changedKeys: CFArray, _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let user = SCDynamicStoreCopyConsoleUser(store, nil, nil) as String?
    let runtime = Unmanaged<HelperRuntime>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { runtime.consoleUserChanged(user) }
}

private func helperNotificationCallback(
    _ center: CFNotificationCenter?, _ context: UnsafeMutableRawPointer?, _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?, _ userInfo: CFDictionary?
) {
    guard let context, let name else { return }
    let notification = name.rawValue as String
    let runtime = Unmanaged<HelperRuntime>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { runtime.notificationReceived(notification) }
}

private func helperDisplayCallback(
    _ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let runtime = Unmanaged<HelperRuntime>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { runtime.displayChanged() }
}

private func helperGestureTapCallback(
    _ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ context: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<CursorGestureTap>.fromOpaque(context).takeUnretainedValue()
    return tap.tapped(type, event) ? nil : Unmanaged.passUnretained(event)
}

final class CursorGestureTap: @unchecked Sendable {
    let shared = CursorGestureShared()
    private weak var owner: CursorGesturesController?
    private var input: CursorGestureInput
    private var drawing = false
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?

    init(owner: CursorGesturesController, config: CursorGesturesConfig) {
        self.owner = owner
        input = CursorGestureInput(config)
    }

    func start(_ port: CFMachPort) {
        guard let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            CGEvent.tapEnable(tap: port, enable: false)
            return CFMachPortInvalidate(port)
        }
        (self.port, self.source) = (port, source)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in serve(ready) }
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func stop() {
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(CFRunLoopGetCurrent()) }
        CFRunLoopWakeUp(loop)
    }

    func run(_ step: @escaping @Sendable (inout CursorGestureInput, CursorGestureSnapshot) -> Void) {
        let work = { [self] in
            step(&input, shared.snapshot)
            send()
        }
        guard let loop else { return work() }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(loop)
    }

    fileprivate func tapped(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let swallow = input.tapped(type, event, shared.snapshot, at: ProcessInfo.processInfo.systemUptime)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let port { CGEvent.tapEnable(tap: port, enable: true) }
        send()
        return swallow
    }

    private func serve(_ ready: DispatchSemaphore) {
        guard let port, let source else {
            ready.signal()
            return
        }
        let loop = CFRunLoopGetCurrent()
        self.loop = loop
        CFRunLoopAddSource(loop, source, .commonModes)
        ready.signal()
        CFRunLoopRun()
        CGEvent.tapEnable(tap: port, enable: false)
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFMachPortInvalidate(port)
    }

    private func send() {
        for click in input.clicks { CursorGestureKeys.click(click.button, at: click.at, keys: click.keys) }
        let notes = input.notes, drawing = input.isDrawing
        input.clicks = []
        input.notes = []
        guard !notes.isEmpty || drawing != self.drawing else { return }
        self.drawing = drawing
        DispatchQueue.main.async { self.owner?.received(notes, drawing: drawing, from: self) }
    }
}

private let inputSourceChanged = kTISNotifySelectedKeyboardInputSourceChanged as String

private let finderScript = """
    on frontfolder()
        with timeout of 10 seconds
            tell application "Finder" to return URL of (target of front Finder window)
        end timeout
    end frontfolder

    on makefile(fileName)
        with timeout of 10 seconds
            tell application "Finder"
                set destination to target of front Finder window
                if exists item fileName of destination then return false
                select (make new file at destination with properties {name:fileName})
            end tell
        end timeout
        return true
    end makefile
    """

private func askFinder(_ handler: String, _ arguments: String...) throws -> NSAppleEventDescriptor {
    let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
    let status = withExtendedLifetime(finder) { AEDeterminePermissionToAutomateTarget(finder.aeDesc, typeWildCard, typeWildCard, true) }
    guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
                                                  targetDescriptor: .currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID),
                                                  transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(keyASSubroutineName))
    let parameters = NSAppleEventDescriptor.list()
    for argument in arguments { parameters.insert(NSAppleEventDescriptor(string: argument), at: parameters.numberOfItems + 1) }
    event.setParam(parameters, forKeyword: keyDirectObject)
    var error: NSDictionary?
    guard let result = NSAppleScript(source: finderScript)?.executeAppleEvent(event, error: &error) else {
        throw NSError(domain: NSOSStatusErrorDomain, code: error?[NSAppleScript.errorNumber] as? Int ?? Int(errOSAScriptError))
    }
    return result
}

@MainActor
final class HelperRuntime {
    private static let hotKeySignature: OSType = 0x4D414352
    private var registeredThemes: [UInt32: String] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var shortcutRecording = false
    private var eventHandler: EventHandlerRef?
    private var store: SCDynamicStore?
    private var consoleSource: CFRunLoopSource?
    private var appearanceObservation: NSKeyValueObservation?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var terminationObserver: NSObjectProtocol?
    private var displayRegistered = false
    private var running = false
    private var displayDebounce = HelperEventPolicy.DisplayDebounce()
    private var displayTimer: DispatchSourceTimer?
    private var activationTimer: DispatchSourceTimer?
    private var menuBarController: MenuBarController?
    private let focusController = MACFocusFollowsMouseController(trustCheck: HelperTrustProbe.isTrusted)
    private let cursorTrails = CursorTrailsController()
    private lazy var cursorGestures = CursorGesturesController(overlay: cursorTrails)
    private let cursorShaker = CursorShakerController()
    private let cursorTranslator = CursorTranslatorController()
    private let cursorScreenshot = CursorScreenshotController()
    private var captureClicks = CursorScreenshotConfig.load().clicks
    private let autoSwitchSchedule = MACAutoSwitchScheduleTimer()

    func run() {
        MACPreferences.set(MACHelperBuildIdentityAtPath(Bundle.main.executablePath),
                           forKey: MACPreferences.helperBuildKey)
        defer { stop() }
        let context = Unmanaged.passUnretained(self).toOpaque()
        var storeContext = SCDynamicStoreContext(version: 0, info: context,
                                               retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "com.apple.dts.ConsoleUser" as CFString,
                                              helperConsoleUserCallback, &storeContext) else {
            print("Failed to create SCDynamicStore")
            return
        }
        self.store = store
        let key = SCDynamicStoreKeyCreateConsoleUser(nil)
        guard SCDynamicStoreSetNotificationKeys(store, [key] as CFArray, nil),
              let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else {
            print("Failed to create console-user notifications")
            return
        }
        consoleSource = source
        running = true

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        applyAppearance()
        appearanceObservation = application.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.systemAppearanceChanged() }
        }
        observeDistributed("AppleInterfaceThemeChangedNotification")
        let displayResult = CGDisplayRegisterReconfigurationCallback(helperDisplayCallback, context)
        displayRegistered = displayResult == .success
        if !displayRegistered { print("Failed to register display callback: \(displayResult.rawValue)") }

        MACCursorCapture.shared.capture(to: MACCursorCapture.systemDefaultPath)
        MACAutoSwitchEffects.shared.recoverBaseThemeIfNeeded()
        applyStoredTheme(for: NSUserName())
        MACCursorActions.shared.assertPreferredCursorScale()

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                       object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.appActivated(bundleID) }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                       object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { if bundleID == MACAppBundleIdentifier { self?.shortcutRecordingStopped() } }
        })
        registerHotKeys()
        observeDistributed("MACShortcutsDidChange")
        observeDistributed(Notification.Name.MACShortcutRecordingDidStart.rawValue)
        observeDistributed(Notification.Name.MACShortcutRecordingDidStop.rawValue)
        observeDistributed(Notification.Name.MACAutoSwitchDidChange.rawValue)
        observeDistributed(Notification.Name.MACMenuBarDidChange.rawValue)
        observeDistributed(Notification.Name.MACFocusFollowsMouseDidChange.rawValue)
        observeDistributed(Notification.Name.MACCursorTrailsDidChange.rawValue)
        observeDistributed(Notification.Name.MACAutoSwitchAppliedThemeDidChange.rawValue)
        observeDistributed(Notification.Name.MACCursorGesturesDidChange.rawValue)
        observeDistributed(Notification.Name.MACCursorShakerDidChange.rawValue)
        observeDistributed(Notification.Name.MACCursorTranslatorDidChange.rawValue)
        observeDistributed(Notification.Name.MACCursorScreenshotDidChange.rawValue)
        observeDistributed(Notification.Name.MACAppearanceDidChange.rawValue)
        observeDistributed(inputSourceChanged)
        for name in RightClickMenuHandoff.requests.keys {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), context, helperNotificationCallback, name as CFString, nil, .deliverImmediately)
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.running == true else { return }
                self?.focusController.noteSpaceChange()
                self?.cursorGestures.cancel()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wokeFromSleep() }
        })
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: application, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }

        MACAutoSwitchEffects.shared.applyIfNeeded()
        MACMenuBarState.shared.noteForegroundBundleID(foregroundBundleID())
        MACAutoSwitchEffects.shared.handleFrontmostApp(foregroundBundleID())
        autoSwitchSchedule.start()
        focusController.strokesEnabled = { [weak self] in
            (self?.cursorGestures.wantsTrust ?? false) || (self?.cursorShaker.wantsTrust ?? false) || (self?.cursorTranslator.wantsTrust ?? false)
                || !(self?.captureClicks.isEmpty ?? true)
        }
        focusController.strokeInProgress = { [weak self] in self?.cursorGestures.isDrawing ?? false }
        focusController.trustWillCheck = { [weak self] in self?.cursorTranslator.probeAhead() }
        focusController.trustSynced = { [weak self] in
            self?.cursorTranslator.sync(trusted: $0)
            self?.cursorGestures.sync(trusted: $0)
            self?.cursorShaker.sync(trusted: $0)
        }
        cursorGestures.translator = { [weak self] in self?.cursorTranslator.trigger }
        cursorGestures.framed = { [weak self] in self?.cursorTranslator.received($0) }
        cursorGestures.captures = { [weak self] in self?.captureClicks ?? [] }
        cursorGestures.capturing = { [weak self] in self?.cursorScreenshot.isOpen ?? false }
        cursorGestures.captured = { [weak self] in _ = self?.hotKeyPressed(signature: Self.hotKeySignature, id: $0, clicked: true) }
        cursorScreenshot.opened = { [weak self] in self?.cursorGestures.publish() }
        cursorGestures.raiseWindow = { [weak self] in self?.focusController.raise($0) ?? false }
        cursorGestures.windowUnderPointer = { [weak self] in self?.focusController.windowUnderPointer() }
        cursorGestures.windowFrame = { [weak self] in self?.focusController.copyWindowFrame($0) }
        focusController.start()
        focusController.syncTrust()
        cursorTrails.start()
        cursorScreenshot.warmReader()
        CursorScreenshotEditor.imageSource = { [weak self] done in
            guard let self else { return done(nil) }
            self.cursorScreenshot.takeImage(allowed: {
                self.cursorTranslator.probe()
                return self.cursorTranslator.screenRecording
            }, done: done)
        }
        menuBarController = MenuBarController()
        menuBarController?.captureHandler = { [weak self] item in
            _ = self?.hotKeyPressed(signature: Self.hotKeySignature, id: item.hotKeyID)
        }
        menuBarController?.historyHandler = { [weak self] in self?.cursorScreenshot.showHistory() }
        menuBarController?.applyVisibility()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        application.run()
    }

    private func stop() {
        let wasRunning = running
        running = false
        cursorScreenshot.closeOverlay()
        displayTimer?.cancel()
        activationTimer?.cancel()
        displayTimer = nil
        activationTimer = nil
        autoSwitchSchedule.stop()
        displayDebounce = HelperEventPolicy.DisplayDebounce()
        unregisterHotKeys()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        let context = Unmanaged.passUnretained(self).toOpaque()
        if displayRegistered { CGDisplayRemoveReconfigurationCallback(helperDisplayCallback, context) }
        displayRegistered = false
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDistributedCenter(), context)
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), context)
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
        if let consoleSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), consoleSource, .defaultMode)
            CFRunLoopSourceInvalidate(consoleSource)
        }
        consoleSource = nil
        store = nil
        if wasRunning {
            focusController.stop()
            cursorGestures.stop()
            cursorTrails.stop()
            cursorShaker.stop()
            cursorTranslator.stop()
        }
    }

    private func observeDistributed(_ name: String) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(),
                                        Unmanaged.passUnretained(self).toOpaque(), helperNotificationCallback,
                                        name as CFString, nil, .deliverImmediately)
    }

    fileprivate func notificationReceived(_ name: String) {
        guard running else { return }
        switch name {
        case "AppleInterfaceThemeChangedNotification":
            DispatchQueue.main.async { [weak self] in self?.systemAppearanceChanged() }
        case Notification.Name.MACAppearanceDidChange.rawValue:
            applyAppearance()
        case "MACShortcutsDidChange":
            CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            unregisterHotKeys()
            registerHotKeys()
        case Notification.Name.MACShortcutRecordingDidStart.rawValue:
            shortcutRecording = true
            unregisterHotKeys()
        case Notification.Name.MACShortcutRecordingDidStop.rawValue:
            shortcutRecordingStopped()
        case Notification.Name.MACAutoSwitchDidChange.rawValue:
            applyAutoSwitchAndRefresh()
            MACAutoSwitchEffects.shared.handleFrontmostApp(foregroundBundleID())
            autoSwitchSchedule.reschedule()
        case Notification.Name.MACMenuBarDidChange.rawValue:
            menuBarController?.applyVisibility()
        case Notification.Name.MACFocusFollowsMouseDidChange.rawValue:
            focusController.configDidChange()
        case Notification.Name.MACCursorGesturesDidChange.rawValue:
            cursorGestures.reloadThemes()
            if focusController.lastTrusted, CursorGesturesConfig.load().enabled == cursorGestures.wantsTrust {
                cursorGestures.sync(trusted: true)
            } else {
                focusController.syncTrust()
            }
        case inputSourceChanged:
            CursorGestureKeys.rebuildLayout()
        case Notification.Name.MACCursorShakerDidChange.rawValue:
            if focusController.lastTrusted, CursorShakerConfig.load().enabled == cursorShaker.wantsTrust {
                cursorShaker.sync(trusted: true)
            } else {
                focusController.syncTrust()
            }
            menuBarController?.refreshShaker()
            unregisterHotKeys()
            registerHotKeys()
        case Notification.Name.MACCursorTranslatorDidChange.rawValue:
            guard !cursorTranslator.configChanged() else { break }
            if focusController.lastTrusted, CursorTranslatorConfig.load().enabled == cursorTranslator.wantsTrust {
                focusController.trustSynced(true)
            } else {
                focusController.syncTrust()
            }
        case Notification.Name.MACCursorScreenshotDidChange.rawValue:
            cursorTranslator.probe()
            cursorScreenshot.warmReader()
            CursorScreenshotHistory.clean()
            unregisterHotKeys()
            registerHotKeys()
            captureClicks = CursorScreenshotConfig.load().clicks
            if focusController.lastTrusted {
                cursorGestures.sync(trusted: true)
            } else {
                focusController.syncTrust()
            }
        case Notification.Name.MACCursorTrailsDidChange.rawValue:
            cursorTrails.start()
            menuBarController?.refreshTrails()
        case Notification.Name.MACAutoSwitchAppliedThemeDidChange.rawValue:
            cursorTrails.themeChanged()
        default:
            guard let request = RightClickMenuHandoff.requests[name] else { break }
            HelperFinderHandoff.receive(request, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, settings: RightClickMenuSettings.load(),
                                        folder: { try askFinder("frontfolder").stringValue ?? "" }, makeFile: { try askFinder("makefile", $0).booleanValue },
                                        copy: { RightClickMenuActions.copyPaths([$0]) },
                                        open: { RightClickMenuActions.openSelection([$0], application: RightClickMenuApplication.resolve($1),
                                                                                    reportFailure: { _ in NSSound.beep() }) },
                                        fail: { _ in NSSound.beep() })
        }
    }

    private func applyAppearance() {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        MACApplyAppearanceMode(MACPreferences.value(forKey: MACPreferences.appearanceModeKey), to: NSApplication.shared)
    }

    private func systemAppearanceChanged() {
        guard running, MACAutoSwitchMatchesSystemAppearance(MACAutoSwitchEffects.shared.readConfig()) else { return }
        applyAutoSwitchAndRefresh()
    }

    private func foregroundBundleID() -> String? {
        HelperEventPolicy.foregroundBundleID(cached: MACMenuBarState.shared.lastForegroundBundleID,
                                            live: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    private func applyStoredTheme(for user: String) {
        guard let home = NSHomeDirectoryForUser(user),
              let identifier = MACPreferences.value(forKey: MACPreferences.appliedCursorKey,
                                                   user: user as CFString,
                                                   host: kCFPreferencesCurrentHost) as? String else { return }
        let directory = (home as NSString).appendingPathComponent("Library/Application Support/MaCursor/cursors")
        let path = ((directory as NSString).appendingPathComponent(identifier) as NSString).appendingPathExtension("cursor")
        if let path, !MACCursorActions.shared.applyTheme(atPath: path) { print("Failed to apply stored Cape for \(user)") }
    }

    fileprivate func consoleUserChanged(_ user: String?) {
        guard running, let user else { return }
        if user == "loginwindow" {
            focusController.stop()
            cursorTranslator.stop()
            cursorGestures.stop()
            cursorTrails.stop()
            cursorShaker.stop()
            return
        }
        MACAutoSwitchEffects.shared.clearAppOverride()
        applyStoredTheme(for: user)
        MACAutoSwitchEffects.shared.applyIfNeeded()
        MACAutoSwitchEffects.shared.handleFrontmostApp(foregroundBundleID())
        MACCursorActions.shared.assertPreferredCursorScale()
        focusController.stop()
        focusController.start()
        cursorGestures.stop()
        cursorTrails.stop()
        cursorShaker.stop()
        focusController.syncTrust()
        cursorTrails.start()
    }

    private func appActivated(_ bundleID: String?) {
        guard running else { return }
        if bundleID != MACAppBundleIdentifier { shortcutRecordingStopped() }
        HelperEventPolicy.handleActivation(
            bundleID: bundleID, consumeRecentRaise: focusController.consumeRecentRaise,
            noteForeground: MACMenuBarState.shared.noteForegroundBundleID, cancelDwell: focusController.cancelPendingRaise,
            scheduleReassert: { bundleID, delay in
                activationTimer?.cancel()
                let timer = DispatchSource.makeTimerSource(queue: .main)
                timer.schedule(deadline: .now() + delay)
                timer.setEventHandler { [weak self, weak timer] in
                    MainActor.assumeIsolated {
                        guard let self, let timer, self.running, self.activationTimer === timer else { return }
                        self.activationTimer = nil
                        timer.cancel()
                        MACAutoSwitchEffects.shared.handleFrontmostApp(bundleID)
                        MACCursorActions.shared.finalizeApply(scaleBump: MACCursorDefinitions.refreshScaleBumpSmall)
                    }
                }
                activationTimer = timer
                timer.resume()
            }
        )
        cursorGestures.publish()
    }

    fileprivate func displayChanged() {
        guard running else { return }
        cursorScreenshot.closeOverlay()
        displayTimer?.cancel()
        let deadline = displayDebounce.replaceDeadline(at: .now())
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: deadline)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running, self.displayDebounce.consume(deadline) else { return }
                self.displayTimer?.cancel()
                self.displayTimer = nil
                MACAutoSwitchEffects.shared.clearAppOverride()
                self.applyStoredTheme(for: NSUserName())
                MACAutoSwitchEffects.shared.applyIfNeeded()
                MACAutoSwitchEffects.shared.handleFrontmostApp(self.foregroundBundleID())
                MACCursorActions.shared.assertPreferredCursorScale()
                self.cursorTrails.stop()
                self.cursorTrails.start()
                self.cursorGestures.publish()
                self.cursorTranslator.displaysChanged()
            }
        }
        displayTimer = timer
        timer.resume()
    }

    private func applyAutoSwitchAndRefresh() {
        if MACAutoSwitchEffects.shared.applyIfNeeded() { MACAutoSwitchEffects.shared.forceVisualRefresh() }
    }

    private func wokeFromSleep() {
        guard running else { return }
        applyAutoSwitchAndRefresh()
        MACAutoSwitchEffects.shared.handleFrontmostApp(foregroundBundleID())
        MACCursorActions.shared.assertPreferredCursorScale()
        autoSwitchSchedule.reschedule()
        focusController.stop()
        focusController.start()
        cursorGestures.stop()
        cursorTrails.stop()
        focusController.syncTrust()
        cursorTrails.start()
    }

    private func shortcutRecordingStopped() {
        guard shortcutRecording else { return }
        shortcutRecording = false
        unregisterHotKeys()
        registerHotKeys()
    }

    private func registerHotKeys() {
        guard !shortcutRecording else { return }
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let result = InstallEventHandler(GetApplicationEventTarget(), helperHotKeyCallback, 1, &eventType,
                                             Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            if result != noErr { print("Failed to install Carbon event handler: \(result)") }
        }
        for shortcut in HelperEventPolicy.shortcuts(from: MACPreferences.value(forKey: MACPreferences.favoriteCursorsKey)) {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.hotKeySignature, id: shortcut.id)
            let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                            GetApplicationEventTarget(), 0, &reference)
            guard result == noErr, let reference else {
                print("Failed to register hotkey \(shortcut.id): \(result)")
                continue
            }
            registeredThemes[shortcut.id] = shortcut.themeIdentifier
            hotKeyRefs.append(reference)
        }
        if let shortcut = CursorShakerConfig.load().shortcut, MACShortcutIsAllowed(shortcut.modifierFlagsRaw, shortcut.keyCode) {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.hotKeySignature, id: CursorShaker.hotKeyID)
            if RegisterEventHotKey(UInt32(shortcut.keyCode), HelperEventPolicy.carbonModifiers(shortcut.modifierFlagsRaw), id,
                                   GetApplicationEventTarget(), 0, &reference) == noErr, let reference {
                hotKeyRefs.append(reference)
            }
        }
        let screenshot = CursorScreenshotConfig.load()
        let screenshotKeys = [(CursorScreenshot.wholeScreenHotKeyID, screenshot.wholeScreenShortcut),
                              (CursorScreenshot.areaHotKeyID, screenshot.areaShortcut),
                              (CursorScreenshot.repeatHotKeyID, screenshot.repeatShortcut),
                              (CursorScreenshot.textHotKeyID, screenshot.textShortcut),
                              (CursorScreenshot.selfTimerHotKeyID, screenshot.selfTimerShortcut)]
        for (keyID, key) in screenshotKeys where screenshot.enabled {
            guard let shortcut = key, MACShortcutIsAllowed(shortcut.modifierFlagsRaw, shortcut.keyCode) else { continue }
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.hotKeySignature, id: keyID)
            if RegisterEventHotKey(UInt32(shortcut.keyCode), HelperEventPolicy.carbonModifiers(shortcut.modifierFlagsRaw), id,
                                   GetApplicationEventTarget(), 0, &reference) == noErr, let reference {
                hotKeyRefs.append(reference)
            }
        }
    }

    private func unregisterHotKeys() {
        for reference in hotKeyRefs {
            let result = UnregisterEventHotKey(reference)
            if result != noErr { print("Failed to unregister hotkey: \(result)") }
        }
        hotKeyRefs.removeAll()
        registeredThemes.removeAll()
    }

    fileprivate func hotKeyPressed(signature: OSType, id: UInt32, clicked: Bool = false) -> OSStatus {
        if running, signature == Self.hotKeySignature, id == CursorShaker.hotKeyID {
            if HelperTrustProbe.isTrusted() {
                MenuBarService.setCursorShakerEnabled(!CursorShakerConfig.load().enabled)
            } else {
                MenuBarService.requestCursorShakerAccess()
            }
            return noErr
        }
        if running, signature == Self.hotKeySignature,
           [CursorScreenshot.wholeScreenHotKeyID, CursorScreenshot.areaHotKeyID, CursorScreenshot.repeatHotKeyID, CursorScreenshot.textHotKeyID, CursorScreenshot.selfTimerHotKeyID].contains(id) {
            let allowed: () -> Bool = { [self] in
                cursorTranslator.probe()
                return cursorTranslator.screenRecording
            }
            switch id {
            case CursorScreenshot.areaHotKeyID: cursorScreenshot.takeArea(allowed: allowed)
            case CursorScreenshot.repeatHotKeyID: cursorScreenshot.repeatArea(allowed: allowed, clicked: clicked)
            case CursorScreenshot.textHotKeyID: cursorScreenshot.takeText(allowed: allowed)
            case CursorScreenshot.selfTimerHotKeyID: cursorScreenshot.takeSelfTimer(allowed: allowed)
            default: cursorScreenshot.takeWholeScreen(allowed: allowed, clicked: clicked)
            }
            return noErr
        }
        guard running, signature == Self.hotKeySignature, let identifier = registeredThemes[id] else {
            return OSStatus(eventNotHandledErr)
        }
        if MenuBarService.applyTheme(identifier) {
            MACAutoSwitchEffects.shared.forceVisualRefresh()
        } else {
            print("Failed to apply Cape for hotkey \(id)")
        }
        return noErr
    }
}

@MainActor
final class CursorGesturesController {
    private static let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    private static let matched = CGColor(srgbRed: 0.18, green: 0.78, blue: 0.56, alpha: 0.9)
    private static let fade: CABasicAnimation = {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.4
        return fade
    }()
    private unowned let overlay: CursorTrailsController
    private var config = CursorGesturesConfig()
    private var themes: [(id: String, name: String)] = []
    private var current: (points: [CGPoint], trigger: CursorGestureTrigger) = ([], CursorGestureTrigger())
    private var pending = false
    private var strokeKeys: Set<UInt> = []
    private var lastHeld: UInt?
    private var monitors: [Any] = []
    private var tap: CursorGestureTap?
    private var drawn = false
    private var fades = 0
    private(set) var onScreen = false
    private var savedFrames: [CFHashCode: CGRect] = [:]
    private var generation = 0
    private var playing = false
    private var queued: [(gesture: CursorGesture, target: MACFFMWindow?)] = []
    private(set) var isDrawing = false
    var raiseWindow: @MainActor (MACFFMWindow) -> Bool = { _ in false }
    var windowUnderPointer: @MainActor () -> MACFFMWindow? = { nil }
    var windowFrame: @MainActor (AXUIElement) -> CGRect? = { _ in nil }
    var translator: @MainActor () -> CursorGestureTrigger? = { nil }
    var framed: @MainActor (CursorTranslatorNote) -> Void = { _ in }
    var captures: @MainActor () -> [(id: UInt32, trigger: CursorGestureTrigger)] = { [] }
    var capturing: @MainActor () -> Bool = { false }
    var captured: @MainActor (UInt32) -> Void = { _ in }
    private var clicksLeft = false

    init(overlay: CursorTrailsController) {
        self.overlay = overlay
        overlay.strokes = self
    }

    var wantsTrust: Bool { config.enabled }
    var isRunning: Bool { !monitors.isEmpty }

    func reloadThemes() {
        themes = MACMenuBarState.shared.catalog().map { ($0.id, $0.name) }
    }

    func sync(trusted: Bool) {
        let stored = CursorGesturesConfig.load()
        let latest = stored.enabled ? stored : CursorGesturesConfig()
        let clicks = captures()
        let left = clicks.contains { $0.trigger.button == 0 }
        let wanted = (latest.enabled || translator() != nil || !clicks.isEmpty) && trusted
        let restart = wanted != (tap != nil) || wanted && (latest.enabled != config.enabled || latest.keyTriggers != config.keyTriggers || latest.padTriggers != config.padTriggers
            || left != clicksLeft)
        config = latest
        clicksLeft = left
        strokeKeys = CursorGestureStroke(triggers: latest.keyTriggers).triggers
        guard restart else { return publish() }
        reloadThemes()
        stop()
        if wanted {
            let session = CursorGestureTap(owner: self, config: config)
            tap = session
            publish()
            if config.enabled {
                monitors = [NSEvent.addGlobalMonitorForEvents(matching: Self.events) { [weak self] event in
                                guard !CursorGestureKeys.posted(event) else { return }
                                let (type, flags, time) = (event.type, event.modifierFlags, event.timestamp)
                                MainActor.assumeIsolated { self?.handle(type, flags, at: time) }
                            },
                            NSEvent.addLocalMonitorForEvents(matching: Self.events) { [weak self] event in
                                guard !CursorGestureKeys.posted(event) else { return event }
                                let (type, flags, time) = (event.type, event.modifierFlags, event.timestamp)
                                MainActor.assumeIsolated { self?.handle(type, flags, at: time) }
                                return event
                            }].compactMap { $0 }
            }
            if let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: config.tapMask(clicksLeft: left),
                                            callback: helperGestureTapCallback, userInfo: Unmanaged.passUnretained(session).toOpaque()) {
                session.start(port)
            }
        }
        overlay.start()
    }

    func publish() {
        tap?.shared.snapshot = CursorGestureSnapshot(config: config, front: MACMenuBarState.shared.lastForegroundBundleID,
                                                     height: NSScreen.screens.first?.frame.height ?? 0, natural: CursorGestureScroll.natural,
                                                     translator: translator(), captures: capturing() ? [] : captures())
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        tap?.stop()
        tap = nil
        savedFrames = [:]
        isDrawing = false
        generation += 1
        queued = []
        playing = false
        current = ([], CursorGestureTrigger())
        lastHeld = nil
        update()
    }

    func cancel() {
        let (flags, time) = (NSEvent.modifierFlags, ProcessInfo.processInfo.systemUptime)
        tap?.run { input, _ in input.spaceChanged(flags, at: time) }
    }

    func moved(_ device: CursorGestureDevice, buttons: Int, flags: NSEvent.ModifierFlags) {
        let held = flags.intersection(CursorGestureStroke.keys).rawValue
        guard isRunning, strokeKeys.contains(held) || held != lastHeld else { return }
        lastHeld = held
        let (point, now) = (NSEvent.mouseLocation, ProcessInfo.processInfo.systemUptime)
        tap?.run { input, snapshot in input.moved(to: point, flags: flags, buttons: buttons, device: device, at: now, snapshot) }
    }

    private func handle(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags, at time: TimeInterval) {
        tap?.run { input, snapshot in input.handle(type, flags, at: time, snapshot) }
    }

    fileprivate func received(_ notes: [CursorGestureNote], drawing: Bool, from session: CursorGestureTap) {
        guard session === tap else { return }
        isDrawing = drawing
        for note in notes {
            switch note {
            case .update(let points, let trigger, let finished):
                if finished {
                    current = ([], trigger)
                    update((points, trigger))
                } else {
                    current = (points, trigger)
                    guard !pending else { continue }
                    pending = true
                    let fps = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1 / Double(fps > 0 ? fps : 60)) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.pending = false
                            self.update()
                        }
                    }
                }
            case .play(let gesture):
                current = ([], CursorGestureTrigger())
                show([], matched: nil, fading: false)
                if let gesture { perform(gesture, later: false, target: CursorGestures.target(gesture, windowUnderPointer(), front: MACMenuBarState.shared.lastForegroundBundleID)) }
            case .frame(let note):
                framed(note)
            case .capture(let id):
                captured(id)
            }
        }
    }

    private func update(_ finished: (points: [CGPoint], trigger: CursorGestureTrigger)? = nil) {
        let (points, trigger) = finished ?? current
        let target = finished == nil ? nil : windowUnderPointer()
        let match = points.isEmpty ? nil : config.match(for: points, trigger: trigger,
                                                        front: config.scopeApp(front: MACMenuBarState.shared.lastForegroundBundleID, pointer: target?.owner.bundleIdentifier))
        let gesture = match?.gesture
        let actions = gesture?.steps.filter(\.enabled).compactMap { config.action($0.action) } ?? []
        let hide = finished != nil && actions.first?.changesScreen == true
        show(hide ? [] : points, matched: match, fading: finished != nil && !hide)
        if finished != nil, let gesture { perform(gesture, later: hide || actions.contains(where: \.typesIntoWindow) && config.raiseWindow && target.map { raiseWindow($0) } ?? false, target: target) }
    }

    private func show(_ points: [CGPoint], matched: (gesture: CursorGesture, score: CGFloat)?, fading: Bool) {
        let name = fading || !config.showShapeName ? nil : matched.flatMap { config.label($0, themes: themes, localized: MenuBarL) }
        let tip = name == nil ? nil : points.last
        let points = config.showLine ? points : []
        guard drawn || !points.isEmpty || tip != nil else { return }
        drawn = (!points.isEmpty || tip != nil) && !fading
        onScreen = drawn || fading
        fades += 1
        if fading {
            let token = fades
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fade.duration) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.fades == token else { return }
                    self.onScreen = false
                    self.overlay.order()
                }
            }
        }
        if onScreen { overlay.order() }
        defer { overlay.order() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for window in overlay.windows {
            guard let root = window.contentView?.layer else { continue }
            let line = root.sublayers?.lazy.compactMap { $0 as? CAShapeLayer }.first ?? Self.line(in: root, scale: window.backingScaleFactor)
            let path = CGMutablePath()
            path.addLines(between: points.map { CGPoint(x: $0.x - window.frame.minX, y: $0.y - window.frame.minY) })
            line.removeAllAnimations()
            line.path = path
            line.lineWidth = config.lineWidth
            line.strokeColor = matched != nil && config.colorByResult ? Self.matched
                : CursorTrailsPalette.color(at: 0, stops: [config.lineColor], alpha: 0.9)
            line.opacity = fading ? 0 : 1
            if fading { line.add(Self.fade, forKey: nil) }
            let label = root.sublayers?.lazy.compactMap { $0 as? CATextLayer }.first ?? Self.label(in: root, scale: window.backingScaleFactor)
            label.string = name.map { " \($0) " }
            label.isHidden = tip == nil
            if let tip {
                label.frame = CGRect(origin: CGPoint(x: tip.x - window.frame.minX + 16, y: tip.y - window.frame.minY + 16), size: label.preferredFrameSize())
            }
        }
        CATransaction.commit()
    }

    private static func line(in root: CALayer, scale: CGFloat) -> CAShapeLayer {
        let line = CAShapeLayer()
        line.frame = root.bounds
        line.contentsScale = scale
        line.fillColor = nil
        line.lineCap = .round
        line.lineJoin = .round
        root.addSublayer(line)
        return line
    }

    private static func label(in root: CALayer, scale: CGFloat) -> CATextLayer {
        let label = CATextLayer()
        label.contentsScale = scale
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.fontSize = 13
        label.foregroundColor = .white
        label.backgroundColor = CGColor(gray: 0, alpha: 0.6)
        label.cornerRadius = 6
        root.addSublayer(label)
        return label
    }

    private func perform(_ gesture: CursorGesture, later: Bool, target: MACFFMWindow?) {
        guard !playing else { return queued.append((gesture, target)) }
        playing = true
        let token = generation
        let play: @MainActor () -> Void = { [weak self] in
            CursorGestures.play(gesture.steps[...], wait: { milliseconds, next in
                guard milliseconds > 0 else { return next() }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { MainActor.assumeIsolated(next) }
            }, live: { self?.generation == token }, run: { self?.run($0, target: target) ?? false }, done: { self?.next() })
        }
        guard later else { return play() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated(play) }
    }

    private func next() {
        playing = false
        guard !queued.isEmpty else { return }
        let (gesture, target) = queued.removeFirst()
        perform(gesture, later: false, target: target)
    }

    private func run(_ id: String, target: MACFFMWindow?) -> Bool {
        guard let action = config.action(id) else { return false }
        switch action.kind {
        case .shortcut(let shortcut):
            guard let shortcut = CursorGestureKeys.system(id, shortcut) else { return false }
            CursorGestureKeys.press(shortcut)
        case .text(let text):
            CursorGestureKeys.type(text)
        case .app(let path):
            guard FileManager.default.fileExists(atPath: path) else { return false }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        case .website(let text):
            guard let url = CursorGestures.website(text) else { return false }
            return NSWorkspace.shared.open(url)
        case .theme(let identifier):
            return apply(identifier)
        case .operation(let operation):
            return operate(operation, target: target)
        }
        return true
    }

    private func operate(_ operation: CursorGestureOperation, target: MACFFMWindow?) -> Bool {
        switch operation {
        case .nextFavoriteTheme:
            CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            let favorites = MACMenuBarFavoriteCatalog(MACMenuBarState.shared.catalog(), MACPreferences.value(forKey: MACPreferences.favoriteThemesKey))
            let current = MACMenuBarVisibleThemeIdentifier(MACPreferences.value(forKey: MACPreferences.appliedCursorKey) as? String,
                                                           MACPreferences.value(forKey: MACPreferences.appOverrideKey) as? String)
            return CursorGestures.nextFavorite(after: current, in: favorites.map(\.id)).map(apply) ?? false
        case .systemCursors:
            MenuBarService.resetCursorsOnly()
        case .sleep:
            return (try? Process.run(URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["sleepnow"], terminationHandler: nil)) != nil
        case .screenSaver:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        default:
            guard let key = CursorGestureKeys.mediaKey(for: operation) else { return arrange(operation, target: target) }
            CursorGestureKeys.pressMedia(key)
        }
        return true
    }

    private func arrange(_ operation: CursorGestureOperation, target: MACFFMWindow?) -> Bool {
        guard let target, let height = NSScreen.screens.first?.frame.height else { return false }
        switch operation {
        case .minimize:
            return AXUIElementSetAttributeValue(target.window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
        case .closeWindow:
            var button: CFTypeRef?
            guard AXUIElementCopyAttributeValue(target.window, kAXCloseButtonAttribute as CFString, &button) == .success,
                  let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return false }
            return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
        case .hideApp:
            return !target.owner.isTerminated && target.owner.hide()
        default:
            guard let frame = windowFrame(target.window),
                  let moved = CursorGestureWindow.frame(operation, window: CursorGestureWindow.flip(frame, height),
                                                        screens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) },
                                                        pointer: NSEvent.mouseLocation, saved: &savedFrames, key: CFHash(target.window)) else { return false }
            let placed = CursorGestureWindow.flip(moved, height)
            var origin = placed.origin, size = placed.size
            guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
            for (attribute, value) in [(kAXSizeAttribute, dimensions), (kAXPositionAttribute, position), (kAXSizeAttribute, dimensions)] {
                AXUIElementSetAttributeValue(target.window, attribute as CFString, value)
            }
            return true
        }
    }

    private func apply(_ identifier: String) -> Bool {
        guard MenuBarService.applyTheme(identifier) else { return false }
        MACAutoSwitchEffects.shared.forceVisualRefresh()
        return true
    }
}

@MainActor
final class CursorTrailsController {
    private static let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    private var config = CursorTrailsConfig()
    private var monitors: [Any] = []
    private(set) var windows: [NSWindow] = []
    weak var strokes: CursorGesturesController?
    private var metal: CursorTrailsMetal?
    private var clock: DispatchSourceTimer?
    private var pauseTimer: DispatchSourceTimer?
    private var emitting = false
    private var drawn = false
    private var shown = false
    private var glows: [CALayer] = []
    private var samples: [CursorTrailsSample] = []
    private var dots: [CursorTrailsDot] = []
    private var restTip: CGPoint?
    private var stops: [UInt32] = []
    private var theme: String?

    func start() {
        let previous = config
        config = CursorTrailsConfig.load()
        guard config.enabled || strokes?.isRunning == true else { return stop() }
        refreshStops()
        let renderer = config.enabled && config.useGPU && config.style == .line ? CursorTrailsMetal.shared : nil
        if config.style != previous.style || config.useGPU != previous.useGPU || config.enabled != previous.enabled { stop() }
        if !config.enabled { clock?.cancel(); clock = nil; samples = []; dots = []; show([]) }
        guard monitors.isEmpty else { return settle() }
        metal = renderer
        windows = NSScreen.screens.map { Self.overlay($0, layer: renderer?.layer() ?? (config.emits ? CAEmitterLayer() : CALayer())) }
        metal?.draw([], on: windows)
        monitors = [NSEvent.addGlobalMonitorForEvents(matching: Self.events) { [weak self] event in
                        guard !CursorShaker.posted(event) else { return }
                        let device = CursorGestureDevice(subtype: Int64(event.subtype.rawValue))
                        let (buttons, flags) = (event.type == .mouseMoved ? 0 : 1, event.modifierFlags)
                        MainActor.assumeIsolated {
                            self?.strokes?.moved(device, buttons: buttons, flags: flags)
                            self?.moved()
                        }
                    },
                    NSEvent.addLocalMonitorForEvents(matching: Self.events) { [weak self] event in
                        guard !CursorShaker.posted(event) else { return event }
                        let device = CursorGestureDevice(subtype: Int64(event.subtype.rawValue))
                        let (buttons, flags) = (event.type == .mouseMoved ? 0 : 1, event.modifierFlags)
                        MainActor.assumeIsolated {
                            self?.strokes?.moved(device, buttons: buttons, flags: flags)
                            self?.moved()
                        }
                        return event
                    }].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        clock?.cancel()
        clock = nil
        settle()
        samples = []
        dots = []
        drawn = false
        shown = false
        metal?.draw([], on: windows)
        windows.forEach { $0.close() }
        windows = []
    }

    func order() {
        let needed = drawn || pauseTimer != nil || !glows.isEmpty || strokes?.onScreen == true
        guard needed != shown else { return }
        shown = needed
        for window in windows {
            if needed { window.orderFrontRegardless() } else { window.orderOut(nil) }
        }
    }

    func themeChanged() {
        guard config.enabled, config.palette == .match, !windows.isEmpty else { return }
        let previous = stops
        refreshStops()
        guard stops != previous else { return }
        if pauseTimer != nil {
            emitters { emitter, _ in
                emitter.emitterCells = config.particles(stops: stops)
                emitter.beginTime = CACurrentMediaTime()
            }
        }
        if !glows.isEmpty { glow(at: NSEvent.mouseLocation) }
    }

    private func moved() {
        guard clock == nil else { return }
        guard config.enabled else { return }
        let tip = NSEvent.mouseLocation
        guard restTip.map({ MACFFMMovementExceedsThreshold($0, tip, 0.5) }) ?? true else { return }
        restTip = tip
        glow(at: nil)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if config.emits { return emit() }
        refreshStops()
        let fps = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: CursorTrailsSample.interval(framesPerSecond: fps), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        clock = timer
        timer.resume()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let tip = NSEvent.mouseLocation
        if config.style == .softDots {
            (samples, dots) = CursorTrailsDot.step(samples, dots, to: tip, at: now, lifetime: config.lifetime, width: config.width, stops: stops)
            show(dots, at: now)
        } else {
            samples = CursorTrailsSample.advance(samples, to: tip, at: now, length: config.lifetime)
            show(CursorTrailsPiece.line(samples, tip: tip, at: now, length: config.lifetime, width: CGFloat(config.width), fade: config.fade, stops: stops))
        }
        guard samples.isEmpty, dots.isEmpty else { return }
        clock?.cancel()
        clock = nil
        restTip = tip
        glow(at: tip)
    }

    private func show(_ pieces: [CursorTrailsPiece]) {
        guard drawn || !pieces.isEmpty else { return }
        drawn = !pieces.isEmpty
        if drawn { order() }
        defer { order() }
        if let metal { return metal.draw(CursorTrailsPiece.strip(pieces), on: windows) }
        paint { CursorTrailsPiece.picture(pieces, in: $0.frame, scale: $0.backingScaleFactor) }
    }

    private func show(_ dots: [CursorTrailsDot], at now: TimeInterval) {
        guard drawn || !dots.isEmpty else { return }
        drawn = !dots.isEmpty
        if drawn { order() }
        defer { order() }
        paint { CursorTrailsDot.picture(dots, at: now, lifetime: config.lifetime, fade: config.fade, in: $0.frame, scale: $0.backingScaleFactor) }
    }

    private func paint(_ picture: (NSWindow) -> (frame: CGRect, image: CGImage)?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for window in windows {
            guard let layer = window.contentView?.layer?.sublayers?.first else { continue }
            let shown = picture(window)
            layer.frame = shown?.frame ?? .zero
            layer.contents = shown?.image
        }
        CATransaction.commit()
    }

    private func emit() {
        let fresh = pauseTimer == nil
        if fresh {
            refreshStops()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.rest() } }
            timer.resume()
            pauseTimer = timer
            order()
        }
        emitting = true
        pauseTimer?.schedule(deadline: .now() + CursorTrailsStyle.pause)
        let tip = NSEvent.mouseLocation
        emitters { emitter, origin in
            if fresh {
                emitter.emitterCells = config.particles(stops: stops)
                emitter.beginTime = CACurrentMediaTime()
            }
            emitter.emitterPosition = CGPoint(x: tip.x - origin.x, y: tip.y - origin.y)
            emitter.birthRate = 1
        }
    }

    private func rest() {
        guard emitting else {
            settle()
            return glow(at: NSEvent.mouseLocation)
        }
        emitting = false
        pauseTimer?.schedule(deadline: .now() + config.lifetime)
        emitters { emitter, _ in emitter.birthRate = 0 }
    }

    private func settle() {
        pauseTimer?.cancel()
        pauseTimer = nil
        emitting = false
        emitters { emitter, _ in
            emitter.birthRate = 0
            emitter.emitterCells = nil
        }
        glow(at: nil)
    }

    private func glow(at tip: CGPoint?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glows.forEach { $0.removeFromSuperlayer() }
        glows = []
        if let tip, config.glow {
            for window in windows {
                let glow = config.glowLayer(at: tip, in: window.frame, stops: stops)
                glow.contentsScale = window.backingScaleFactor
                window.contentView?.layer?.addSublayer(glow)
                glows.append(glow)
            }
        }
        CATransaction.commit()
        order()
    }

    private func emitters(_ change: (CAEmitterLayer, CGPoint) -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for window in windows {
            if let emitter = window.contentView?.layer?.sublayers?.first as? CAEmitterLayer { change(emitter, window.frame.origin) }
        }
        CATransaction.commit()
    }

    private func refreshStops() {
        guard config.palette == .match else {
            stops = config.palette.stops
            theme = nil
            return
        }
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        let path = MACMenuBarVisibleThemeIdentifier(MACPreferences.value(forKey: MACPreferences.appliedCursorKey) as? String,
                                                    MACPreferences.value(forKey: MACPreferences.appOverrideKey) as? String)
            .map(MACAutoSwitchThemePathForIdentifier)
        let modified = path.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }
        let key = "\(path ?? "")|\(modified?.timeIntervalSinceReferenceDate ?? 0)"
        guard key != theme else { return }
        theme = key
        stops = CursorTrailsPalette.matchStops(themeAt: path)
    }

    private static func overlay(_ screen: NSScreen, layer: CALayer) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.layer = CALayer()
        view.wantsLayer = true
        layer.frame = view.bounds
        layer.contentsScale = screen.backingScaleFactor
        view.layer?.addSublayer(layer)
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        return window
    }
}

final class CursorTrailsMetal: @unchecked Sendable {
    static let shared = CursorTrailsMetal()
    private static let shaders = """
        #include <metal_stdlib>
        using namespace metal;
        struct TrailVertex { float4 position; float4 color; };
        struct TrailFragment { float4 position [[position]]; float4 color; };
        vertex TrailFragment trailVertex(uint id [[vertex_id]], const device TrailVertex *strip [[buffer(0)]],
                                         constant float4 &screen [[buffer(1)]]) {
            TrailFragment out;
            out.position = float4((strip[id].position.xy - screen.xy) / screen.zw * 2.0f - 1.0f, strip[id].position.z, 1.0f);
            out.color = strip[id].color;
            return out;
        }
        fragment float4 trailFragment(TrailFragment in [[stage_in]]) {
            return in.color;
        }
        """
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let samples: Int
    private let work = DispatchQueue(label: "com.writronic.macursor.trails", qos: .userInteractive)
    private var targets: [SIMD2<Int>: (color: MTLTexture?, depth: MTLTexture)] = [:]
    private var buffer: MTLBuffer?
    private var last: MTLCommandBuffer?
    @MainActor private var queued = 0

    private init?() {
        guard let device = MTLCopyAllDevices().first(where: { $0.isLowPower }) ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaders, options: nil) else { return nil }
        let samples = device.supportsFamily(.apple7) ? 4 : 1
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "trailVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "trailFragment")
        descriptor.rasterSampleCount = samples
        descriptor.depthAttachmentPixelFormat = .depth32Float
        let color: MTLRenderPipelineColorAttachmentDescriptor = descriptor.colorAttachments[0]
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let depthTest = MTLDepthStencilDescriptor()
        depthTest.depthCompareFunction = .less
        depthTest.isDepthWriteEnabled = true
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let depth = device.makeDepthStencilState(descriptor: depthTest) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.depth = depth
        self.samples = samples
    }

    func layer() -> CAMetalLayer {
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = true
        layer.presentsWithTransaction = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        return layer
    }

    @MainActor func draw(_ strip: [CursorTrailsVertex], on windows: [NSWindow]) {
        guard strip.isEmpty || queued == 0 else { return }
        queued += 1
        nonisolated(unsafe) let windows = windows.compactMap { window in
            (window.contentView?.layer?.sublayers?.first as? CAMetalLayer).map { (layer: $0, frame: window.frame, scale: window.backingScaleFactor) }
        }
        work.async {
            self.render(strip, on: windows)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.queued -= 1 } }
        }
    }

    private func render(_ strip: [CursorTrailsVertex], on windows: [(layer: CAMetalLayer, frame: CGRect, scale: CGFloat)]) {
        guard let commands = queue.makeCommandBuffer() else { return }
        let length = strip.count * MemoryLayout<CursorTrailsVertex>.stride
        last?.waitUntilCompleted()
        if (buffer?.length ?? 0) < length { buffer = device.makeBuffer(length: 2 * length, options: []) }
        let vertices = strip.isEmpty ? nil : buffer
        if let vertices { strip.withUnsafeBytes { vertices.contents().copyMemory(from: $0.baseAddress!, byteCount: length) } }
        var drawables: [CAMetalDrawable] = []
        var kept: [SIMD2<Int>: (color: MTLTexture?, depth: MTLTexture)] = [:]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for window in windows {
            let layer = window.layer, scale = window.scale
            guard let vertices, let frame = CursorTrailsPiece.frame(strip, in: window.frame, scale: scale, atLeast: layer.frame.size) else {
                layer.frame = .zero
                continue
            }
            layer.drawableSize = CGSize(width: frame.width * scale, height: frame.height * scale)
            guard let drawable = layer.nextDrawable(),
                  let target = self.target(width: drawable.texture.width, height: drawable.texture.height) else {
                layer.frame = .zero
                continue
            }
            kept[SIMD2(drawable.texture.width, drawable.texture.height)] = target
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target.color ?? drawable.texture
            pass.colorAttachments[0].resolveTexture = target.color == nil ? nil : drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = target.color == nil ? .store : .multisampleResolve
            pass.depthAttachment.texture = target.depth
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.clearDepth = 1
            pass.depthAttachment.storeAction = .dontCare
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { continue }
            var box = SIMD4<Float>(Float(window.frame.minX + frame.minX), Float(window.frame.minY + frame.minY), Float(frame.width), Float(frame.height))
            encoder.setRenderPipelineState(pipeline)
            encoder.setDepthStencilState(depth)
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&box, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: strip.count)
            encoder.endEncoding()
            layer.frame = frame
            drawables.append(drawable)
        }
        targets = kept
        commands.commit()
        last = commands
        if !drawables.isEmpty { commands.waitUntilScheduled() }
        drawables.forEach { $0.present() }
        CATransaction.commit()
    }

    private func target(width: Int, height: Int) -> (color: MTLTexture?, depth: MTLTexture)? {
        let size = SIMD2(width, height)
        if let target = targets[size] { return target }
        func texture(_ format: MTLPixelFormat) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            descriptor.usage = .renderTarget
            descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
            descriptor.sampleCount = samples
            descriptor.storageMode = samples > 1 ? .memoryless : .private
            return device.makeTexture(descriptor: descriptor)
        }
        let color = samples > 1 ? texture(.bgra8Unorm) : nil
        guard let depth = texture(.depth32Float), samples == 1 || color != nil else { return nil }
        let target = (color: color, depth: depth)
        targets[size] = target
        return target
    }
}
