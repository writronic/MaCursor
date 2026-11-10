import AppKit
import AudioToolbox
@preconcurrency import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CursorScreenshotController {
    private static let sound = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif")

    private var working = false
    private var pictures: CursorScreenshotPictures?
    private var imageHandOff: (@MainActor (CGImage?) -> Void)?
    private var overlay: CursorScreenshotOverlay? {
        didSet { opened() }
    }
    var opened: @MainActor () -> Void = {}
    var isOpen: Bool { overlay != nil }
    private var previousApp: NSRunningApplication?
    private var handingBack: Task<Void, Never>?
    private var handingBackTo: NSRunningApplication?
    private var countingKey: UInt32?
    private var readingText = false
    private var warmed = false
    private var backgroundCursor = MACBackgroundCursor()
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private let reader = CursorTranslatorReader()
    private lazy var cardModel = CursorScreenshotCardModel(dragFolder: Self.dragFolder, clipboardFolder: Self.clipboardFolder)
    private lazy var card = CursorScreenshotCard(model: cardModel)
    private lazy var countdown = CursorScreenshotCountdown()
    private lazy var notice = CursorScreenshotNotice()

    static let dragFolder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RightClickMenuSettings.appGroupIdentifier)?
        .appendingPathComponent(CursorScreenshot.dragFolder, isDirectory: true)
    static let clipboardFolder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: RightClickMenuSettings.appGroupIdentifier)?
        .appendingPathComponent(CursorScreenshot.clipboardFolder, isDirectory: true)

    init() {
        if let folder = Self.dragFolder { try? FileManager.default.removeItem(at: folder) }
        if let folders = CursorScreenshotEditor.dragFolders { try? FileManager.default.removeItem(at: folders) }
        let centers: [(NotificationCenter, [Notification.Name])] = [
            (NSWorkspace.shared.notificationCenter, CursorShaker.workspacePauses.filter { $0.value.starts }.map(\.key)),
            (DistributedNotificationCenter.default(), CursorShaker.distributedPauses.filter { $0.value.starts }.map(\.key)),
        ]
        for (center, names) in centers {
            for name in names {
                observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.closeOverlay() }
                }))
            }
        }
        CursorScreenshotHistory.start()
    }

    func takeWholeScreen(allowed: () -> Bool, clicked: Bool) {
        guard !working else { return }
        guard allowed() else { return MenuBarService.requestCursorScreenshotAccess() }
        let config = CursorScreenshotConfig.load()
        let pressed = clicked ? config.wholeScreenClick.keys : config.wholeScreenShortcut?.modifierFlagsRaw
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return NSSound.beep() }
        working = true
        let context = nameContext(for: config.naming)
        let display = Self.displayID(screen)
        Task {
            await handingBack?.value
            let picture = try? await Self.shot(of: screen, showsCursor: config.showsCursor, hidesDesktopIcons: config.hidesDesktopIcons)
            await deliver(picture, scale: Self.scale(of: picture, in: screen.frame), on: display, config: config, context: context, pressed: pressed)
        }
    }

    func takeSelfTimer(allowed: () -> Bool) {
        if cancelsCountdown(CursorScreenshot.selfTimerHotKeyID) { return }
        guard !working else { return }
        guard allowed() else { return MenuBarService.requestCursorScreenshotAccess() }
        var config = CursorScreenshotConfig.load()
        config.freezesScreen = false
        openOverlay(config: config, timed: true)
    }

    func takeArea(allowed: () -> Bool) {
        guard !working else { return }
        guard allowed() else { return MenuBarService.requestCursorScreenshotAccess() }
        openOverlay(config: CursorScreenshotConfig.load())
    }

    func takeImage(allowed: () -> Bool, done: @escaping @MainActor (CGImage?) -> Void) {
        guard !working else { return done(nil) }
        guard allowed() else {
            MenuBarService.requestCursorScreenshotAccess()
            return done(nil)
        }
        imageHandOff = done
        openOverlay(config: CursorScreenshotConfig.load())
    }

    func takeText(allowed: () -> Bool) {
        guard !working, !readingText else { return }
        guard allowed() else { return MenuBarService.requestCursorScreenshotAccess() }
        reader.prepare()
        var config = CursorScreenshotConfig.load()
        config.freezesScreen = true
        openOverlay(config: config, readsText: true)
    }

    func warmReader() {
        guard !warmed, CursorScreenshotConfig.load().enabled else { return }
        warmed = true
        CursorTranslatorReader.warm()
    }

    func repeatArea(allowed: () -> Bool, clicked: Bool) {
        guard !working else { return }
        guard allowed() else { return MenuBarService.requestCursorScreenshotAccess() }
        let config = CursorScreenshotConfig.load()
        let frames = Dictionary(NSScreen.screens.map { (Self.displayID($0), $0.frame) }, uniquingKeysWith: { first, _ in first })
        guard let area = config.lastArea, let box = CursorScreenshotBox.repeated(area, displays: frames),
              let screen = NSScreen.screens.first(where: { Self.displayID($0) == area.display }) else { return openOverlay(config: config) }
        working = true
        retake(box, on: screen, config: config, showsCursor: false, pressed: clicked ? config.repeatClick.keys : config.repeatShortcut?.modifierFlagsRaw)
    }

    private func retake(_ box: CGRect, on screen: NSScreen, config: CursorScreenshotConfig, showsCursor: Bool, pressed: UInt?) {
        let context = nameContext(for: config.naming)
        let display = Self.displayID(screen)
        Task {
            await handingBack?.value
            let picture = try? await Self.shot(of: screen, showsCursor: showsCursor, hidesDesktopIcons: config.hidesDesktopIcons)
            await deliver(Self.cropped(picture, to: box, in: screen.frame), scale: Self.scale(of: picture, in: screen.frame), on: display, config: config, context: context, pressed: pressed)
        }
    }

    private func retakeWindow(_ window: CursorScreenshotWindow, config: CursorScreenshotConfig) {
        let held = NSEvent.modifierFlags
        var chosen = config
        if CursorScreenshot.skipsDefaultPreset(held: held, pressed: nil) { chosen.background.defaultPreset = nil }
        let wallpaper = CursorScreenshot.wantsWallpaper(config.windowShot.background, held: held)
        let frames = Dictionary(NSScreen.screens.map { (Self.displayID($0), $0.frame) }, uniquingKeysWith: { first, _ in first })
        guard let display = CursorScreenshotWindows.display(holding: window.frame, among: frames),
              let screen = NSScreen.screens.first(where: { Self.displayID($0) == display }) else {
            working = false
            return NSSound.beep()
        }
        let context = nameContext(for: config.naming, window: window)
        Task {
            await handingBack?.value
            let taken = try? await Self.shot(of: window, on: screen, shadow: config.windowShot.shadow)
            let picture = wallpaper ? await Self.onWallpaper(taken, on: screen) : taken
            await deliver(picture, scale: screen.backingScaleFactor, on: display, config: chosen, context: context)
        }
    }

    private static func onWallpaper(_ picture: CGImage?, on screen: NSScreen) async -> CGImage? {
        guard let picture else { return nil }
        let scale = screen.backingScaleFactor
        let source = CursorScreenshotEditor.backdropSource(for: screen)
        return await Task.detached(priority: .userInitiated) { CursorScreenshotRender.exported(picture, style: CursorScreenshotWindows.wallpaperStyle, scale: scale, source: source) ?? picture }.value
    }

    private func counted(_ seconds: Int, by key: UInt32, then take: @escaping () -> Void) {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else { return take() }
        countingKey = key
        countdown.start(seconds: seconds, on: screen) { [self] in
            countingKey = nil
            guard CursorScreenshotConfig.load().enabled else {
                working = false
                return
            }
            take()
        }
    }

    private func cancelsCountdown(_ key: UInt32) -> Bool {
        guard CursorScreenshot.cancels(pressed: key, counting: countingKey) else { return false }
        stopCountdown()
        return true
    }

    private func stopCountdown() {
        countingKey = nil
        working = false
        countdown.stop()
    }

    func closeOverlay() {
        if countingKey != nil { stopCountdown() }
        guard let pictures else { return }
        pictures.end()
        self.pictures = nil
        working = false
        overlay?.close()
        backgroundCursor.turnOff()
        overlay = nil
        let handOff = imageHandOff
        imageHandOff = nil
        handOff?(nil)
        if let previous = previousApp {
            handingBackTo = previous
            handingBack = Task {
                defer { handingBackTo = nil }
                await Self.waited { NSApp.isActive }
                guard NSApp.isActive, !previous.isTerminated else { return }
                previous.activate(options: [])
                await Self.waited { previous.isActive }
            }
        }
        previousApp = nil
    }

    static func waited(until done: @MainActor () -> Bool) async {
        let end = Date().addingTimeInterval(0.5)
        while !done(), Date() < end {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func openOverlay(config: CursorScreenshotConfig, readsText: Bool = false, timed: Bool = false) {
        let point = NSEvent.mouseLocation
        let screens = NSScreen.screens.sorted { NSMouseInRect(point, $0.frame, false) && !NSMouseInRect(point, $1.frame, false) }
        guard !screens.isEmpty else {
            NSSound.beep()
            let handOff = imageHandOff
            imageHandOff = nil
            handOff?(nil)
            return
        }
        working = true
        let windows = self.windows()
        let remembers = config.remembersSelection && imageHandOff == nil && !readsText
        let stills = screens.map { screen in
            let size = CursorTranslator.pixels(screen.frame, scale: screen.backingScaleFactor)
            var still = CursorScreenshotStill(display: Self.displayID(screen), frame: screen.frame, width: size.width, height: size.height, windows: windows)
            if remembers { still.remembered = CursorScreenshotBox.repeated(config.lastArea, displays: [still.display: screen.frame]) }
            return still
        }
        let shown = CursorScreenshotOverlay(stills) { still, pick in
            if self.imageHandOff != nil {
                self.imageOverlayEnded(still, box: pick?.box)
            } else if readsText {
                self.textOverlayEnded(still, box: pick?.box)
            } else if timed {
                self.timerOverlayEnded(still, pick: pick, config: config)
            } else {
                self.overlayEnded(still, pick: pick, config: config)
            }
        }
        overlay = shown
        shown.crosshair = config.crosshair
        let front = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? handingBackTo : $0 }
        let takeFront = { [self] in
            previousApp = front
            NSApp.activate(ignoringOtherApps: true)
        }
        if !config.freezesScreen { backgroundCursor.turnOn() }
        shown.show()
        pictures = CursorScreenshotPictures(screens.map { screen in
            (Self.displayID(screen), { @MainActor [self] in
                await handingBack?.value
                return try? await Self.shot(of: screen, showsCursor: false, hidesDesktopIcons: config.hidesDesktopIcons)
            })
        }, freezes: config.freezesScreen, arrived: { shown.freeze($1, on: $0) }, settled: { [self] any in
            guard !any else { return takeFront() }
            closeOverlay()
            NSSound.beep()
        })
        guard !config.freezesScreen, config.crosshair.mode != .disabled, config.crosshair.showsMagnifier else { return }
        screens.forEach { screen in
            let display = Self.displayID(screen)
            Task { [weak shown] in
                guard let picture = try? await Self.shot(of: screen, showsCursor: false, hidesDesktopIcons: config.hidesDesktopIcons) else { return }
                shown?.magnify(picture, on: display)
            }
        }
    }

    private static func scale(of image: CGImage?, in frame: CGRect) -> CGFloat {
        image.map { CGFloat($0.width) / frame.width } ?? 1
    }

    private static func cropped(_ image: CGImage?, to box: CGRect, in frame: CGRect) -> CGImage? {
        image.flatMap { $0.cropping(to: CursorScreenshotBox.pixels(of: box, in: frame, width: $0.width, height: $0.height)) }
    }

    private func overlayEnded(_ still: CursorScreenshotStill, pick: CursorScreenshotPick?, config: CursorScreenshotConfig) {
        guard let pictures else { return }
        let picture = pick.flatMap { $0.window == nil ? pictures.keep(still.display) : nil }
        closeOverlay()
        guard let box = pick?.box else { return }
        CursorScreenshotConfig.remember(CursorScreenshotArea(display: still.display, box: box.offsetBy(dx: -still.frame.minX, dy: -still.frame.minY)))
        working = true
        if let window = pick?.window { return retakeWindow(window, config: config) }
        let context = nameContext(for: config.naming)
        Task {
            let image = await picture?.value
            await deliver(Self.cropped(image, to: box, in: still.frame), scale: Self.scale(of: image, in: still.frame), on: still.display, config: config, context: context)
        }
    }

    private func timerOverlayEnded(_ still: CursorScreenshotStill, pick: CursorScreenshotPick?, config: CursorScreenshotConfig) {
        guard pictures != nil else { return }
        closeOverlay()
        guard let box = pick?.box else { return }
        guard let screen = NSScreen.screens.first(where: { Self.displayID($0) == still.display }) else { return NSSound.beep() }
        CursorScreenshotConfig.remember(CursorScreenshotArea(display: still.display, box: box.offsetBy(dx: -still.frame.minX, dy: -still.frame.minY)))
        working = true
        counted(config.delay, by: CursorScreenshot.selfTimerHotKeyID) { [self] in
            if let window = pick?.window { return retakeWindow(window, config: config) }
            retake(box, on: screen, config: config, showsCursor: config.showsCursor, pressed: nil)
        }
    }

    private func imageOverlayEnded(_ still: CursorScreenshotStill, box: CGRect?) {
        guard let pictures else { return }
        let handOff = imageHandOff
        imageHandOff = nil
        let picture = box == nil ? nil : pictures.keep(still.display)
        closeOverlay()
        guard let box else {
            handOff?(nil)
            return
        }
        working = true
        Task {
            let image = await picture?.value
            working = false
            if image == nil { NSSound.beep() }
            handOff?(Self.cropped(image, to: box, in: still.frame))
        }
    }

    private func textOverlayEnded(_ still: CursorScreenshotStill, box: CGRect?) {
        guard let pictures else { return }
        let picture = box == nil ? nil : pictures.keep(still.display)
        closeOverlay()
        guard let box else { return }
        working = true
        Task {
            let image = await picture?.value
            working = false
            guard let image, let cropped = Self.cropped(image, to: box, in: still.frame) else { return NSSound.beep() }
            readText(cropped, pointScale: CGFloat(image.width) / still.frame.width, on: NSScreen.screens.first { Self.displayID($0) == still.display })
        }
    }

    private func readText(_ picture: CGImage, pointScale: CGFloat, on screen: NSScreen?) {
        guard !readingText, let screen = screen ?? NSScreen.main else { return }
        let clipboard = NSPasteboard.general.changeCount
        let recognition = CursorScreenshotConfig.load().textRecognition
        readingText = true
        cardModel.reading = true
        let waiting = reader.fresh ? MenuBarL("Preparing…") : MenuBarL("Reading…")
        let waited = Task { [weak self] in
            guard (try? await Task.sleep(nanoseconds: UInt64(CursorTranslatorChild.patience * 1_000_000_000))) != nil, !Task.isCancelled else { return }
            self?.showNotice(CursorScreenshotNoticeWords(name: waiting), on: screen)
        }
        Task {
            let larger = await Task.detached(priority: .userInitiated) { CursorScreenshot.forReading(picture, pointScale: pointScale) }.value
            let seen = await reader.read(larger, source: recognition.language)
            waited.cancel()
            readingText = false
            cardModel.reading = false
            guard let seen else {
                notice.stop()
                CursorTranslatorReader.warm()
                return NSSound.beep()
            }
            let whole = CGRect(x: 0, y: 0, width: picture.width, height: picture.height)
            let lines = seen.lines.map { CursorTranslatorLine(text: $0.text, rect: CursorTranslator.screenRect($0.box, in: whole)) }
            let text = CursorScreenshot.text(lines, keepsLineBreaks: recognition.keepsLineBreaks, keepsStyling: recognition.keepsStyling)
            guard let first = CursorScreenshot.firstLine(text) else {
                return showNotice(CursorScreenshotNoticeWords(name: MenuBarL("No Text Found"), mark: .nothing), on: screen)
            }
            guard CursorScreenshot.copyText(text, unlessChangedSince: clipboard) else { return notice.stop() }
            let link = recognition.detectsLinks ? CursorScreenshot.firstLink(in: CursorScreenshot.text(lines)) : nil
            showNotice(CursorScreenshotNoticeWords(name: MenuBarL("Text Copied"), line: first, mark: .copied, link: link), on: screen)
        }
    }

    private var shownCard: CGRect? {
        card.panel.isVisible ? card.panel.frame.insetBy(dx: CursorScreenshotCardLook.inset, dy: CursorScreenshotCardLook.inset) : nil
    }

    private func showNotice(_ words: CursorScreenshotNoticeWords, on screen: NSScreen) {
        notice.show(words, on: screen, corner: CursorScreenshotConfig.load().previewCorner, card: shownCard)
    }

    private static func dressed(_ picture: CGImage?, scale: CGFloat, config: CursorScreenshotConfig, on display: CGDirectDisplayID, pressed: UInt?) async -> CGImage? {
        guard let picture, !CursorScreenshot.skipsDefaultPreset(held: NSEvent.modifierFlags, pressed: pressed),
              let style = config.background.presets.first(where: { $0.id == config.background.defaultPreset })?.style else { return picture }
        let screen = NSScreen.screens.first(where: { displayID($0) == display }) ?? NSScreen.main
        let source = CursorScreenshotEditor.backdropSource(for: screen)
        return await Task.detached(priority: .userInitiated) { CursorScreenshotRender.exported(picture, style: style, scale: scale, source: source) ?? picture }.value
    }

    private func named(_ name: CursorScreenshotFileName, naming: CursorScreenshotNaming) async -> CursorScreenshotFileName {
        guard naming.asksForName else { return name }
        await handingBack?.value
        return await CursorScreenshotNamePrompt.ask(name, naming: naming)
    }

    private func deliver(_ picture: CGImage?, scale: CGFloat, on display: CGDirectDisplayID, config: CursorScreenshotConfig, context: CursorScreenshotNameContext, pressed: UInt? = nil) async {
        defer { working = false }
        let picture = await Self.dressed(picture, scale: scale, config: config, on: display, pressed: pressed)
        let folder = config.folderURL
        let output = config.output
        let screen = NSScreen.screens.first(where: { Self.displayID($0) == display }) ?? NSScreen.main
        let made = await Self.encoded(picture, scale: scale, output: output)
        cardModel.removeDragFile()
        guard let picture, let made else { return NSSound.beep() }
        let offered = CursorScreenshotConfig.load().naming.name(context, scale: scale, output: output)
        if config.copies, !CursorScreenshot.copy(made.data, as: output.format, mode: config.clipboard, in: Self.clipboardFolder, name: offered) { NSSound.beep() }
        CursorScreenshotConfig.spent(offered)
        let name = await named(offered, naming: config.naming)
        var file: URL?
        if config.saves {
            file = await Task.detached(priority: .userInitiated) { try? CursorScreenshot.save(made.data, as: output.format, in: folder, name: name) }.value
        }
        if config.saves && file == nil {
            NSSound.beep()
        } else if config.playsSound {
            Self.playSound()
        }
        CursorScreenshotHistory.record(picture, scale: scale, date: context.date, name: name, file: file, config: config)
        if config.pins { CursorScreenshotPin.show(made.image, scale: output.shownScale(scale), on: screen) }
        await handingBack?.value
        if config.annotates { CursorScreenshotEditor.open(picture, scale: scale, name: name) }
        guard config.showsPreview, let screen else { return }
        showCard(CursorScreenshotShot(image: picture, data: made.data, format: output.format, pointScale: screen.backingScaleFactor, date: context.date, name: name, file: file),
                 on: screen, config: config)
    }

    private func showCard(_ shot: CursorScreenshotShot, on screen: NSScreen, config: CursorScreenshotConfig) {
        let cardScreen = Self.cardScreen(follows: config.movesToActiveScreen) ?? screen
        cardModel.copyingText = { [weak self] in self?.readText($0.image, pointScale: $0.pointScale, on: cardScreen) }
        card.show(shot, on: cardScreen, corner: config.previewCorner, scale: CGFloat(config.previewScale))
        if notice.panel.isVisible, let shown = shownCard, notice.panel.frame.intersects(shown) {
            notice.place(in: cardScreen.visibleFrame, corner: config.previewCorner, card: shown)
        }
    }

    func restore(_ entry: CursorScreenshotHistoryEntry, picture: CGImage, on screen: NSScreen) async {
        let made = await Self.encoded(picture, scale: entry.scale, output: entry.output)
        cardModel.removeDragFile()
        guard let made else { return NSSound.beep() }
        let file = entry.file.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        showCard(CursorScreenshotShot(image: picture, data: made.data, format: entry.output.format, pointScale: entry.scale, date: entry.date, name: entry.name, file: file),
                 on: screen, config: CursorScreenshotConfig.load())
    }

    func showHistory() {
        CursorScreenshotHistoryWindow.show { [weak self] entry, picture, screen in
            await self?.restore(entry, picture: picture, on: screen)
        }
    }

    private static func cardScreen(follows: Bool) -> NSScreen? {
        let point = NSEvent.mouseLocation
        return CursorScreenshot.cardDisplay(pointer: NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }, main: NSScreen.screens.first, follows: follows)
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    private func windows() -> [CursorScreenshotWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let system = CursorScreenshotWindows.systemBundles.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }.map(\.processIdentifier)
        let found = CursorScreenshotWindows.windows(list, skipping: Set(system), primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        guard let shownCard else { return found }
        return CursorScreenshotWindows.trimmed(found, panel: card.panel.frame, to: shownCard)
    }

    private static func encoded(_ picture: CGImage?, scale: CGFloat, output: CursorScreenshotOutput) async -> (image: CGImage, data: Data)? {
        guard let picture else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let image = output.apply(picture, scale: scale)
            return output.format.data(of: image, scale: output.shownScale(scale)).map { (image, $0) }
        }.value
    }

    private static func playSound() {
        let url = sound
        DispatchQueue.global(qos: .userInitiated).async {
            var created: SystemSoundID = 0
            guard AudioServicesCreateSystemSoundID(url as CFURL, &created) == noErr else { return }
            let sound = created
            AudioServicesPlaySystemSoundWithCompletion(sound) { AudioServicesDisposeSystemSoundID(sound) }
        }
    }

    private static func shot(of screen: NSScreen, showsCursor: Bool, hidesDesktopIcons: Bool) async throws -> CGImage {
        let display = displayID(screen)
        let content = try await CursorTranslatorOnce.within(CursorScreenshot.limit) { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
        try Task.checkCancellation()
        guard let shown = content.displays.first(where: { $0.displayID == display }) else { throw CocoaError(.featureUnsupported) }
        let me = ProcessInfo.processInfo.processIdentifier
        let hidden = hidesDesktopIcons ? content.windows.filter { CursorScreenshotWindows.isDesktopIconOrWidget(bundle: $0.owningApplication?.bundleIdentifier, layer: $0.windowLayer) } : []
        let left = Set(hidden.compactMap { $0.owningApplication?.processID }).union([me])
        let own = content.applications.filter { left.contains($0.processID) }
        let kept = content.windows.filter { window in
            guard let owner = window.owningApplication?.processID, left.contains(owner) else { return false }
            return owner == me ? !CursorScreenshotWindows.isChrome(layer: window.windowLayer) : !hidden.contains { $0.windowID == window.windowID }
        }
        let filter = SCContentFilter(display: shown, excludingApplications: own, exceptingWindows: kept)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = showsCursor
        if #available(macOS 14, *) {
            let size = CursorTranslator.pixels(screen.frame, scale: CGFloat(filter.pointPixelScale))
            configuration.width = size.width
            configuration.height = size.height
            return try await CursorTranslatorOnce.within(CursorScreenshot.limit) { try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) }
        }
        let size = CursorTranslator.pixels(screen.frame, scale: screen.backingScaleFactor)
        configuration.width = size.width
        configuration.height = size.height
        return try await CursorTranslatorStreamShot.capture(filter, configuration, limit: CursorScreenshot.limit)
    }

    private static func shot(of window: CursorScreenshotWindow, on screen: NSScreen, shadow: Bool) async throws -> CGImage {
        let content = try await CursorTranslatorOnce.within(CursorScreenshot.limit) { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
        try Task.checkCancellation()
        guard let target = content.windows.first(where: { $0.windowID == window.id }) else { throw CocoaError(.featureUnsupported) }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.scalesToFit = false
        let shadowed: Bool
        if #available(macOS 14, *) {
            configuration.ignoreShadowsSingleWindow = !shadow
            shadowed = shadow
        } else {
            shadowed = false
        }
        let pad = shadowed ? CursorScreenshotWindows.shadowPadding : 0
        let size = CursorTranslator.pixels(CGRect(origin: .zero, size: target.frame.size).insetBy(dx: -pad, dy: -pad), scale: screen.backingScaleFactor)
        configuration.width = size.width
        configuration.height = size.height
        let image: CGImage
        if #available(macOS 14, *) {
            image = try await CursorTranslatorOnce.within(CursorScreenshot.limit) { try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) }
        } else {
            image = try await CursorTranslatorStreamShot.capture(filter, configuration, limit: CursorScreenshot.limit)
        }
        return await Task.detached(priority: .userInitiated) { CursorScreenshotWindowPicture.finished(image, window: window, shadowed: shadowed) }.value
    }
}

struct CursorScreenshotStill {
    let display: CGDirectDisplayID
    let frame: CGRect
    var width: Int
    var height: Int
    let windows: [CursorScreenshotWindow]
    var remembered: CGRect? = nil
}

final class CursorScreenshotPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class CursorScreenshotOverlayView: NSView {
    private static let dimColor = NSColor.black.withAlphaComponent(0.15)
    private static let edgeColor = NSColor.white
    private static let outerEdgeColor = NSColor.black.withAlphaComponent(0.35)
    private static let windowCorner: CGFloat = 8
    private static let ringWidth: CGFloat = 2
    private static let ringCorner: CGFloat = 10
    private static let labelColor = NSColor(white: 0.05, alpha: 1)
    private static let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    private static let guideColor = NSColor.white
    private static let guideShade = NSColor.black.withAlphaComponent(0.5)

    private var still: CursorScreenshotStill
    private let done: (CursorScreenshotPick?) -> Void
    private let dim = CAShapeLayer()
    private let guides = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let outerEdge = CAShapeLayer()
    private let number = CATextLayer()
    private let loupe = CALayer()
    private let lens = CALayer()
    private let cell = CAShapeLayer()
    private var anchor: CGPoint?
    private var pointer: CGPoint?
    private var box: CGRect?
    private var windowPick: CursorScreenshotPick?
    private var picksWindows = false
    private var moving: (from: CGPoint, box: CGRect)?

    var crosshair = CursorScreenshotCrosshair()
    var spacePressed: () -> Void = {}
    var returnPressed: () -> Void = {}
    var windowReleased: (CGPoint) -> Void = { _ in }
    var dragging: Bool { anchor != nil || moving != nil }
    var pending: CursorScreenshotPick? { dragging || picksWindows ? nil : box.map { CursorScreenshotPick(box: $0) } }
    var display: CGDirectDisplayID { still.display }

    init(still: CursorScreenshotStill, done: @escaping (CursorScreenshotPick?) -> Void) {
        self.still = still
        self.done = done
        super.init(frame: CGRect(origin: .zero, size: still.frame.size))
        let root = CALayer()
        root.frame = bounds
        root.contentsGravity = .resize
        dim.frame = bounds
        dim.fillRule = .evenOdd
        dim.fillColor = Self.dimColor.cgColor
        edge.frame = bounds
        edge.fillRule = .evenOdd
        outerEdge.frame = bounds
        outerEdge.fillRule = .evenOdd
        outerEdge.fillColor = Self.outerEdgeColor.cgColor
        number.font = Self.labelFont
        number.fontSize = Self.labelFont.pointSize
        number.foregroundColor = Self.labelColor.cgColor
        number.alignmentMode = .left
        number.shadowColor = NSColor.white.cgColor
        number.shadowOpacity = 1
        number.shadowRadius = 0.1
        number.shadowOffset = NSSize(width: 0.5, height: -0.5)
        guides.frame = bounds
        guides.strokeColor = Self.guideColor.cgColor
        guides.lineWidth = 1
        guides.shadowColor = Self.guideShade.cgColor
        guides.shadowOpacity = 1
        guides.shadowRadius = 1
        guides.shadowOffset = .zero
        guides.isHidden = true
        let side = CursorScreenshotBox.loupeSize
        let unit = side / CursorScreenshotBox.loupeSpan
        loupe.frame = CGRect(x: 0, y: 0, width: side, height: side)
        loupe.shadowColor = Self.guideShade.cgColor
        loupe.shadowOpacity = 1
        loupe.shadowRadius = 3
        loupe.shadowOffset = .zero
        loupe.shadowPath = CGPath(rect: loupe.bounds, transform: nil)
        loupe.isHidden = true
        lens.frame = loupe.bounds
        lens.backgroundColor = NSColor.black.cgColor
        lens.magnificationFilter = .nearest
        lens.masksToBounds = true
        lens.borderColor = Self.guideColor.cgColor
        lens.borderWidth = 1
        cell.frame = lens.bounds
        cell.path = CGPath(rect: CGRect(x: (side - unit) / 2, y: (side - unit) / 2, width: unit, height: unit), transform: nil)
        cell.fillColor = nil
        cell.strokeColor = Self.guideColor.cgColor
        cell.lineWidth = 1
        cell.shadowColor = Self.guideShade.cgColor
        cell.shadowOpacity = 1
        cell.shadowRadius = 1
        cell.shadowOffset = .zero
        lens.addSublayer(cell)
        loupe.addSublayer(lens)
        let scale = CGFloat(still.width) / still.frame.width
        [dim, guides, edge, outerEdge, number, cell].forEach { $0.contentsScale = scale }
        number.isHidden = true
        root.addSublayer(dim)
        root.addSublayer(guides)
        root.addSublayer(outerEdge)
        root.addSublayer(edge)
        root.addSublayer(number)
        root.addSublayer(loupe)
        layer = root
        wantsLayer = true
        box = still.remembered
        refreshCrosshair()
        redraw()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        setCrosshair()
    }

    override func mouseEntered(with event: NSEvent) {
        setCrosshair()
    }

    override func mouseMoved(with event: NSEvent) {
        hover(at: place(event))
        track(place(event), held: event.modifierFlags)
        setCrosshair()
    }

    override func flagsChanged(with event: NSEvent) {
        track(NSEvent.mouseLocation, held: event.modifierFlags)
    }

    override func mouseDown(with event: NSEvent) {
        if !picksWindows, let box, box.contains(place(event)) {
            if event.clickCount == 2 { return take() }
            moving = (place(event), box)
            return
        }
        anchor = place(event)
        pointer = anchor
        if !picksWindows { box = nil }
        redraw()
    }

    override func mouseDragged(with event: NSEvent) {
        track(place(event), held: event.modifierFlags)
        if let moving, !CursorScreenshotBox.movable(moving.box, in: still.frame) {
            guard CursorScreenshotBox.startsNewBox(from: moving.from, to: place(event), in: still.frame) else { return }
            anchor = moving.from
            self.moving = nil
        }
        if let moving {
            let point = place(event)
            box = CursorScreenshotBox.moved(moving.box, by: CGVector(dx: point.x - moving.from.x, dy: point.y - moving.from.y), in: still.frame)
            return redraw()
        }
        guard let anchor else { return }
        if picksWindows { return hover(at: place(event)) }
        pointer = place(event)
        box = CursorScreenshotBox.box(from: anchor, to: place(event), in: still.frame)
        redraw()
    }

    override func mouseUp(with event: NSEvent) {
        moving = nil
        guard let anchor else { return }
        self.anchor = nil
        if picksWindows {
            windowReleased(place(event))
            return
        }
        let last = CursorScreenshotBox.box(from: anchor, to: place(event), in: still.frame)
        done(CursorScreenshotBox.isTooSmall(last) ? nil : CursorScreenshotPick(box: last))
    }

    override func rightMouseDown(with event: NSEvent) {
        done(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { done(nil) }
        if event.keyCode == 49, !event.isARepeat, anchor == nil { spacePressed() }
        if event.keyCode == 36 || event.keyCode == 76, !event.isARepeat { returnPressed() }
    }

    func take() {
        if let pending { done(pending) }
    }

    override func cancelOperation(_ sender: Any?) {
        done(nil)
    }

    func freeze(_ picture: CGImage) {
        still.width = picture.width
        still.height = picture.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = picture
        lens.contents = picture
        CATransaction.commit()
        redraw()
    }

    func magnify(_ picture: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lens.contents = picture
        CATransaction.commit()
    }

    func track(_ point: CGPoint, held: NSEvent.ModifierFlags) {
        let lined = !picksWindows && crosshair.mode.draws(held: held) && NSMouseInRect(point, still.frame, false)
        let zoomed = lined && crosshair.showsMagnifier && lens.contents != nil
        guard lined || !guides.isHidden || !loupe.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guides.isHidden = !lined
        loupe.isHidden = !zoomed
        guard lined else { return }
        let local = CGPoint(x: point.x - still.frame.minX, y: point.y - still.frame.minY)
        let path = CursorScreenshotBox.guides(through: local, in: bounds)
        guides.path = path
        guides.shadowPath = path.copy(strokingWithWidth: 3, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        guard zoomed else { return }
        loupe.frame.origin = CursorScreenshotBox.loupeOrigin(pointer: local, in: bounds)
        lens.contentsRect = CursorScreenshotBox.loupeSource(pointer: local, in: bounds)
    }

    func pickWindows(_ on: Bool) {
        picksWindows = on
        box = nil
        moving = nil
        windowPick = nil
        redraw()
    }

    func hover(at pointer: CGPoint) {
        guard picksWindows else { return }
        let front = CursorScreenshotWindows.front(at: pointer, in: still.windows, on: still.frame)
        guard front != windowPick else { return }
        windowPick = front
        box = front?.box
        redraw()
    }

    func takeWindow(at point: CGPoint) {
        hover(at: point)
        if let windowPick { done(windowPick) }
    }

    func refreshCrosshair() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        window?.invalidateCursorRects(for: self)
        setCrosshair()
    }

    private func setCrosshair() {
        guard window?.isVisible == true else { return }
        NSCursor.crosshair.set()
    }

    private func place(_ event: NSEvent) -> CGPoint {
        let inside = convert(event.locationInWindow, from: nil)
        return CGPoint(x: inside.x + still.frame.minX, y: inside.y + still.frame.minY)
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let path = CGMutablePath()
        path.addRect(bounds)
        guard let box else {
            dim.path = path
            edge.path = nil
            outerEdge.path = nil
            number.isHidden = true
            return
        }
        if picksWindows {
            let inside = box.offsetBy(dx: -still.frame.minX, dy: -still.frame.minY)
            let hole = CGPath(roundedRect: inside, cornerWidth: Self.windowCorner, cornerHeight: Self.windowCorner, transform: nil)
            path.addPath(hole)
            dim.path = path
            let ring = CGMutablePath()
            ring.addRoundedRect(in: inside.insetBy(dx: -Self.ringWidth, dy: -Self.ringWidth), cornerWidth: Self.ringCorner, cornerHeight: Self.ringCorner)
            ring.addPath(hole)
            edge.fillColor = NSColor.controlAccentColor.cgColor
            edge.path = ring
            outerEdge.path = nil
            number.isHidden = true
            return
        }
        let inside = CursorScreenshotBox.shown(box, in: still.frame, width: still.width, height: still.height)
        path.addRect(inside)
        dim.path = path
        let pixel = still.frame.width / CGFloat(still.width)
        edge.fillColor = Self.edgeColor.cgColor
        edge.path = Self.frame(around: inside, from: 0, to: pixel)
        outerEdge.path = Self.frame(around: inside, from: pixel, to: pixel * 2)
        guard let pointer, still.frame.insetBy(dx: -1, dy: -1).contains(pointer) else {
            number.isHidden = true
            return
        }
        let text = CursorScreenshotBox.label(CursorScreenshotBox.pixels(of: box, in: still.frame, width: still.width, height: still.height))
        let size = (text as NSString).size(withAttributes: [.font: Self.labelFont])
        let room = NSSize(width: ceil(size.width), height: ceil(size.height))
        number.string = text
        number.isHidden = false
        number.frame = CGRect(origin: CursorScreenshotBox.labelOrigin(pointer: CGPoint(x: pointer.x - still.frame.minX, y: pointer.y - still.frame.minY), size: room, in: bounds), size: room)
    }

    private static func frame(around rect: CGRect, from inner: CGFloat, to outer: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRect(rect.insetBy(dx: -outer, dy: -outer))
        path.addRect(rect.insetBy(dx: -inner, dy: -inner))
        return path
    }
}

@MainActor
final class CursorScreenshotOverlay {
    private var panels: [(panel: CursorScreenshotPanel, view: CursorScreenshotOverlayView)] = []
    private var timer: DispatchSourceTimer?
    private var picksWindows = false

    var crosshair = CursorScreenshotCrosshair() {
        didSet { panels.forEach { $0.view.crosshair = crosshair } }
    }

    init(_ stills: [CursorScreenshotStill], done: @escaping (CursorScreenshotStill, CursorScreenshotPick?) -> Void) {
        for still in stills {
            let panel = CursorScreenshotPanel(contentRect: still.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = false
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
            panel.canHide = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.acceptsMouseMovedEvents = true
            panel.animationBehavior = .none
            panel.isMovable = false
            let view = CursorScreenshotOverlayView(still: still) { done(still, $0) }
            view.spacePressed = { [weak self] in self?.switchMode() }
            view.returnPressed = { [weak self] in
                guard let self, !self.panels.contains(where: { $0.view.dragging }) else { return }
                self.panels.first { $0.view.pending != nil }?.view.take()
            }
            view.windowReleased = { [weak self] point in
                self?.panels.first { NSMouseInRect(point, $0.panel.frame, false) }?.view.takeWindow(at: point)
            }
            panel.contentView = view
            panel.makeFirstResponder(view)
            panels.append((panel, view))
        }
    }

    func show() {
        panels.forEach { $0.panel.orderFrontRegardless() }
        follow()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.follow() }
        }
        self.timer = timer
        timer.resume()
    }

    func close() {
        if let timer {
            timer.cancel()
            self.timer = nil
            NSCursor.arrow.set()
        }
        let closing = panels
        panels = []
        closing.forEach { $0.panel.close() }
        DispatchQueue.main.async { withExtendedLifetime(closing) {} }
    }

    func freeze(_ picture: CGImage, on display: CGDirectDisplayID) {
        panels.first { $0.view.display == display }?.view.freeze(picture)
    }

    func magnify(_ picture: CGImage, on display: CGDirectDisplayID) {
        panels.first { $0.view.display == display }?.view.magnify(picture)
    }

    private func switchMode() {
        picksWindows.toggle()
        panels.forEach { $0.view.pickWindows(picksWindows) }
        follow()
    }

    private func follow() {
        let point = NSEvent.mouseLocation
        panels.forEach { $0.view.hover(at: point) }
        let target = panels.first { $0.view.dragging } ?? panels.first { NSMouseInRect(point, $0.panel.frame, false) } ?? panels.first
        if let target, !target.panel.isKeyWindow {
            target.panel.makeKey()
            target.view.refreshCrosshair()
        }
        panels.forEach { $0.view.track(point, held: NSEvent.modifierFlags) }
        NSCursor.crosshair.set()
    }
}

private func cursorScreenshotTone(dark: NSColor, light: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
}

enum CursorScreenshotCountdownLook {
    static let width: CGFloat = 96
    static let height: CGFloat = 64
    static let corner: CGFloat = 26
    static let digit: CGFloat = 28
    static let edge = Color(nsColor: .separatorColor)
    static let wash = cursorScreenshotTone(dark: NSColor(white: 30 / 255, alpha: 0.3), light: NSColor(white: 1, alpha: 0.3))
    static let solid = cursorScreenshotTone(dark: NSColor(white: 30 / 255, alpha: 1), light: .white)
    static let fade: TimeInterval = 0.25
    static let change: TimeInterval = 0.25
    static let topShare: CGFloat = 5
}

@MainActor
final class CursorScreenshotCountdownModel: ObservableObject {
    @Published var left = 0
}

struct CursorScreenshotCountdownMaterial: NSViewRepresentable {
    var size = NSSize(width: CursorScreenshotCountdownLook.width, height: CursorScreenshotCountdownLook.height)

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        let look = CursorScreenshotCountdownLook.self
        view.maskImage = NSImage(size: size, flipped: false) { rect in
            let path = RoundedRectangle(cornerRadius: look.corner, style: .continuous).path(in: rect).cgPath
            guard let drawing = NSGraphicsContext.current?.cgContext else { return false }
            drawing.addPath(path)
            drawing.fillPath()
            return true
        }
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct CursorScreenshotCountdownView: View {
    @ObservedObject var model: CursorScreenshotCountdownModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var scale

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CursorScreenshotCountdownLook.corner, style: .continuous)
    }

    @ViewBuilder private var plate: some View {
        if reduceTransparency {
            shape.fill(CursorScreenshotCountdownLook.solid)
        } else {
            CursorScreenshotCountdownMaterial().overlay(shape.fill(CursorScreenshotCountdownLook.wash))
        }
    }

    var body: some View {
        Text(verbatim: "\(model.left)")
            .font(.system(size: CursorScreenshotCountdownLook.digit, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .contentTransition(.numericText(countsDown: true))
            .animation(reduceMotion ? nil : .easeInOut(duration: CursorScreenshotCountdownLook.change), value: model.left)
            .frame(width: CursorScreenshotCountdownLook.width, height: CursorScreenshotCountdownLook.height)
            .background(plate)
            .overlay(shape.strokeBorder(CursorScreenshotCountdownLook.edge, lineWidth: 1 / scale))
    }
}

@MainActor
final class CursorScreenshotCountdown {
    let model = CursorScreenshotCountdownModel()
    let host: NSHostingView<CursorScreenshotCountdownView>
    let panel: NSPanel
    private var timer: Timer?
    private var fades = 0
    private var finished: () -> Void = {}

    init() {
        host = NSHostingView(rootView: CursorScreenshotCountdownView(model: model))
        host.sizingOptions = []
        host.wantsLayer = true
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: CursorScreenshotCountdownLook.width, height: CursorScreenshotCountdownLook.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.contentView = host
    }

    func start(seconds: Int, on screen: NSScreen, done: @escaping () -> Void) {
        prepare(seconds: seconds, in: screen.visibleFrame, done: done)
        panel.display()
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        fade(to: 1)
    }

    func prepare(seconds: Int, in visible: CGRect, done: @escaping () -> Void) {
        panel.setFrameOrigin(NSPoint(x: (visible.midX - panel.frame.width / 2).rounded(),
                                     y: (visible.maxY - visible.height / CursorScreenshotCountdownLook.topShare - panel.frame.height).rounded()))
        if !panel.isVisible { panel.alphaValue = 0 }
        model.left = seconds
        finished = done
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        finished = {}
        fade(to: 0)
    }

    func fade(to alpha: CGFloat) {
        fades += 1
        let fade = fades
        NSAnimationContext.runAnimationGroup { context in
            context.duration = CursorScreenshotCountdownLook.fade
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, alpha == 0, self.fades == fade else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func tick() {
        guard model.left <= 1 else {
            model.left -= 1
            return
        }
        let done = finished
        stop()
        done()
    }
}

enum CursorScreenshotNoticeLook {
    static let width: CGFloat = 480
    static let height: CGFloat = 56
    static let screenEdge: CGFloat = 20
    static let cardGap: CGFloat = 8
    static let sideInset: CGFloat = 16
    static let gap: CGFloat = 10
    static let icon: CGFloat = 22
    static let nameSize: CGFloat = 13
    static let nameHeight: CGFloat = 16
    static let lineSize: CGFloat = 12
    static let lineHeight: CGFloat = 15
    static let shown: TimeInterval = 4
    static let linkHeight: CGFloat = 128
    static let linkGap: CGFloat = 6
    static let linkShown: TimeInterval = 10
    static let green = Color(nsColor: NSColor(srgbRed: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1))
    static let tick = cursorScreenshotTone(dark: NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1), light: .white)
    static let warning = cursorScreenshotTone(dark: NSColor(srgbRed: 0xE6 / 255, green: 0x9F / 255, blue: 0, alpha: 1), light: NSColor(srgbRed: 0xD5 / 255, green: 0x5E / 255, blue: 0, alpha: 1))
    static let secondary = cursorScreenshotTone(dark: NSColor(white: 1, alpha: 0.55), light: NSColor(white: 0, alpha: 0.62))
}

struct CursorScreenshotNoticeWords {
    enum Mark { case copied, nothing }

    var name: String
    var line: String?
    var mark: Mark?
    var link: URL?

    var height: CGFloat { link == nil ? CursorScreenshotNoticeLook.height : CursorScreenshotNoticeLook.linkHeight }
}

@MainActor
final class CursorScreenshotNoticeModel: ObservableObject {
    @Published var words = CursorScreenshotNoticeWords(name: "")
    var opening: (URL) -> Void = { _ in }
    var neverOpening: () -> Void = {}
}

struct CursorScreenshotNoticeView: View {
    @ObservedObject var model: CursorScreenshotNoticeModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var scale

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CursorScreenshotCountdownLook.corner, style: .continuous)
    }

    @ViewBuilder private var plate: some View {
        if reduceTransparency {
            shape.fill(CursorScreenshotCountdownLook.solid)
        } else {
            CursorScreenshotCountdownMaterial(size: NSSize(width: CursorScreenshotNoticeLook.width, height: model.words.height))
                .id(model.words.link != nil)
                .overlay(shape.fill(CursorScreenshotCountdownLook.wash))
        }
    }

    @ViewBuilder private var mark: some View {
        switch model.words.mark {
        case .copied:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .symbolRenderingMode(.palette)
                .foregroundStyle(CursorScreenshotNoticeLook.tick, CursorScreenshotNoticeLook.green)
                .frame(width: CursorScreenshotNoticeLook.icon, height: CursorScreenshotNoticeLook.icon)
        case .nothing:
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(CursorScreenshotNoticeLook.warning)
                .frame(width: CursorScreenshotNoticeLook.icon, height: CursorScreenshotNoticeLook.icon)
        case nil:
            EmptyView()
        }
    }

    var body: some View {
        let look = CursorScreenshotNoticeLook.self
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: look.gap) {
                mark.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.words.name)
                        .font(.system(size: look.nameSize, weight: .semibold))
                        .lineLimit(1)
                        .frame(height: look.nameHeight)
                    if let line = model.words.line {
                        Text(verbatim: line)
                            .font(.system(size: look.lineSize))
                            .foregroundStyle(look.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(height: look.lineHeight)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: look.height)
            if let link = model.words.link {
                Divider()
                VStack(alignment: .leading, spacing: look.linkGap) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(MenuBarL("Do you want to open this link?"))
                            .font(.system(size: look.lineSize, weight: .semibold))
                            .lineLimit(1)
                            .frame(height: look.lineHeight)
                        Text(verbatim: link.absoluteString)
                            .font(.system(size: look.lineSize))
                            .foregroundStyle(look.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(height: look.lineHeight)
                    }
                    HStack(spacing: look.gap) {
                        Spacer(minLength: 0)
                        Button(MenuBarL("Never open links")) { model.neverOpening() }
                        Button(MenuBarL("Open Link in Browser")) { model.opening(link) }
                    }
                    .controlSize(.small)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, look.sideInset)
        .frame(width: look.width, height: model.words.height)
        .foregroundStyle(.primary)
        .background(plate)
        .overlay(shape.strokeBorder(CursorScreenshotCountdownLook.edge, lineWidth: 1 / scale))
    }
}

final class CursorScreenshotNoticeHost: NSHostingView<CursorScreenshotNoticeView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CursorScreenshotNotice {
    let model = CursorScreenshotNoticeModel()
    let host: CursorScreenshotNoticeHost
    let panel: NSPanel
    private var timer: Timer?
    private var fades = 0

    init() {
        host = CursorScreenshotNoticeHost(rootView: CursorScreenshotNoticeView(model: model))
        host.sizingOptions = []
        host.wantsLayer = true
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: CursorScreenshotNoticeLook.width, height: CursorScreenshotNoticeLook.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.contentView = host
        model.opening = { [weak self] link in
            NSWorkspace.shared.open(link)
            self?.stop()
        }
        model.neverOpening = { [weak self] in
            var config = CursorScreenshotConfig.load()
            config.textRecognition.detectsLinks = false
            config.save()
            self?.stop()
        }
    }

    func show(_ words: CursorScreenshotNoticeWords, on screen: NSScreen, corner: CursorScreenshotCorner, card: CGRect?) {
        prepare(words, in: screen.visibleFrame, corner: corner, card: card)
        panel.display()
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        fade(to: 1)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: words.name, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func prepare(_ words: CursorScreenshotNoticeWords, in visible: CGRect, corner: CursorScreenshotCorner, card: CGRect?) {
        let look = CursorScreenshotNoticeLook.self
        panel.setContentSize(NSSize(width: look.width, height: words.height))
        place(in: visible, corner: corner, card: card)
        panel.ignoresMouseEvents = words.link == nil
        if !panel.isVisible { panel.alphaValue = 0 }
        model.words = words
        timer?.invalidate()
        timer = nil
        guard words.mark != nil else { return }
        let timer = Timer(timeInterval: words.link == nil ? look.shown : look.linkShown, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fade(to: 0) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func place(in visible: CGRect, corner: CursorScreenshotCorner, card: CGRect?) {
        let look = CursorScreenshotNoticeLook.self
        panel.setFrameOrigin(corner.noticeOrigin(size: panel.frame.size, margin: look.screenEdge, gap: look.cardGap, in: visible, card: card))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        fade(to: 0)
    }

    func fade(to alpha: CGFloat) {
        fades += 1
        let fade = fades
        NSAnimationContext.runAnimationGroup { context in
            context.duration = CursorScreenshotCountdownLook.fade
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, alpha == 0, self.fades == fade else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

struct CursorScreenshotShot {
    let image: CGImage
    let data: Data
    let format: CursorScreenshotFormat
    let pointScale: CGFloat
    let date: Date
    let name: CursorScreenshotFileName
    var file: URL?
}

enum CursorScreenshotCardLook {
    static let width: CGFloat = 354
    static let height: CGFloat = 157
    static let inset: CGFloat = 28
    static let screenEdge: CGFloat = 20
    static let corner: CGFloat = 12
    static let padding: CGFloat = 8
    static let pictureWidth: CGFloat = 200
    static let pictureHeight: CGFloat = 140
    static let pictureCorner: CGFloat = 8
    static let rowHeight: CGFloat = 28
    static let rowCorner: CGFloat = 6
    static let rowFont: CGFloat = 13
    static let rowGlyph: CGFloat = 16
    static let rowGap: CGFloat = 8
    static let rowOff: CGFloat = 0.4
    static let shadowBlur: CGFloat = 12
    static let shadowDrop: CGFloat = 4
    static let ground = cursorScreenshotTone(dark: NSColor(srgbRed: 0x17 / 255, green: 0x1C / 255, blue: 0x21 / 255, alpha: 1), light: .white)
    static let label = cursorScreenshotTone(dark: NSColor(srgbRed: 0xEB / 255, green: 0xEF / 255, blue: 0xF2 / 255, alpha: 1), light: NSColor(srgbRed: 0x19 / 255, green: 0x1E / 255, blue: 0x22 / 255, alpha: 1))
    static let hairline = cursorScreenshotTone(dark: NSColor(white: 1, alpha: 0.08), light: NSColor(srgbRed: 0x19 / 255, green: 0x1E / 255, blue: 0x22 / 255, alpha: 0.1))
    static let edge = cursorScreenshotTone(dark: NSColor(white: 1, alpha: 0.12), light: NSColor(white: 0, alpha: 0.12))
    static let shadow = cursorScreenshotTone(dark: NSColor(white: 0, alpha: 0.3), light: NSColor(white: 0, alpha: 0.1))
    static let rowHover = cursorScreenshotTone(dark: NSColor(srgbRed: 0xEB / 255, green: 0xEF / 255, blue: 0xF2 / 255, alpha: 0.06), light: NSColor(srgbRed: 0x19 / 255, green: 0x1E / 255, blue: 0x22 / 255, alpha: 0.05))
    static let rowPress = cursorScreenshotTone(dark: NSColor(srgbRed: 0xEB / 255, green: 0xEF / 255, blue: 0xF2 / 255, alpha: 0.1), light: NSColor(srgbRed: 0x19 / 255, green: 0x1E / 255, blue: 0x22 / 255, alpha: 0.08))
    static let fade: TimeInterval = 0.25
    static let slideKey = "slide"
}

@MainActor
final class CursorScreenshotCardModel: ObservableObject {
    @Published private(set) var shot: CursorScreenshotShot?
    @Published private(set) var hovering = false
    @Published private(set) var hoveredRow: String?
    @Published var reading = false
    @Published private(set) var scale: CGFloat = 1

    var closing: () -> Void = {}
    var copyingText: (CursorScreenshotShot) -> Void = { _ in }
    private var dragging = false
    private var asking = false
    private var saving: Set<Date> = []
    private var clock = CursorScreenshotCardClock()
    private var timer: Timer?
    private let dragFolder: URL?
    private let clipboardFolder: URL?
    private let pasteboard: NSPasteboard
    private let saveFolder: () -> URL
    private let seconds: () -> Int?
    private let clipboardMode: () -> CursorScreenshotClipboardMode
    private let settings: () -> CursorScreenshotConfig

    init(dragFolder: URL?, clipboardFolder: URL?, pasteboard: NSPasteboard = .general, saveFolder: @escaping () -> URL = { CursorScreenshotConfig.load().folderURL },
         seconds: @escaping () -> Int? = { CursorScreenshotConfig.load().cardSeconds },
         clipboardMode: @escaping () -> CursorScreenshotClipboardMode = { CursorScreenshotConfig.load().clipboard },
         settings: @escaping () -> CursorScreenshotConfig = { CursorScreenshotConfig.load() }) {
        self.dragFolder = dragFolder
        self.clipboardFolder = clipboardFolder
        self.pasteboard = pasteboard
        self.saveFolder = saveFolder
        self.seconds = seconds
        self.clipboardMode = clipboardMode
        self.settings = settings
    }

    func removeDragFile() {
        if !dragging, let dragFolder { try? FileManager.default.removeItem(at: dragFolder) }
    }

    func present(_ shot: CursorScreenshotShot, scale: CGFloat, hovering inside: Bool) {
        self.shot = shot
        self.scale = scale
        hovering = inside
        hoveredRow = nil
        countDown()
    }

    func setHovering(_ inside: Bool) {
        hovering = inside
        if shot != nil { countDown() }
    }

    func setRow(_ row: String, hovered inside: Bool) {
        if inside {
            hoveredRow = row
        } else if hoveredRow == row {
            hoveredRow = nil
        }
    }

    func edit() {
        guard let shot else { return }
        CursorScreenshotEditor.open(shot.image, scale: shot.pointScale, name: shot.name)
    }

    func startDrag() -> URL? {
        guard let shot, let dragFolder, let file = try? CursorScreenshot.dragFile(shot.data, as: shot.format, name: shot.name, in: dragFolder) else {
            NSSound.beep()
            return nil
        }
        dragging = true
        countDown()
        return file
    }

    func dragEnded(hovering inside: Bool, dropped: Bool, optionHeld: Bool) {
        dragging = false
        hovering = inside
        guard shot != nil else { return }
        if CursorScreenshot.closesAfterDrag(settings().closesAfterDrag, dropped: dropped, optionHeld: optionHeld) { return close() }
        countDown()
    }

    func copy() {
        guard let shot else { return }
        if !CursorScreenshot.copy(shot.data, as: shot.format, mode: clipboardMode(), in: clipboardFolder, name: shot.name, to: pasteboard) { NSSound.beep() }
    }

    func copyText() {
        guard let shot, !reading else { return }
        copyingText(shot)
    }

    func saveOrShow() {
        guard let shot else { return }
        if let file = shot.file {
            if FileManager.default.fileExists(atPath: file.path) { return NSWorkspace.shared.activateFileViewerSelecting([file]) }
            self.shot?.file = nil
            return NSSound.beep()
        }
        guard saving.insert(shot.date).inserted else { return }
        if settings().saveButton.asks(optionHeld: NSEvent.modifierFlags.contains(.option)) { return ask(shot) }
        save(shot)
    }

    private func timeUp() {
        guard let shot, settings().closeAction.savesFirst(saved: shot.file != nil), saving.insert(shot.date).inserted else { return close() }
        save(shot) { [weak self] in self?.close() }
    }

    private func save(_ shot: CursorScreenshotShot, then done: @escaping () -> Void = {}) {
        let data = shot.data
        let format = shot.format
        let date = shot.date
        let name = shot.name
        let folder = saveFolder()
        Task {
            let file = await Task.detached(priority: .userInitiated) { try? CursorScreenshot.save(data, as: format, in: folder, name: name) }.value
            saving.remove(date)
            guard let file else { return NSSound.beep() }
            guard self.shot?.date == date else { return }
            self.shot?.file = file
            done()
        }
    }

    private func ask(_ shot: CursorScreenshotShot) {
        let date = shot.date
        let data = shot.data
        let folder = saveFolder()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(shot.format.rawValue) ?? .png]
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.nameFieldStringValue = shot.name.freeFile(as: shot.format, in: folder)
        let front = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : $0 }
        asking = true
        countDown()
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [self] answer in
            asking = false
            if self.shot != nil { countDown() }
            front?.activate(options: [])
            guard answer == .OK, let url = panel.url else {
                saving.remove(date)
                return
            }
            Task {
                let written = await Task.detached(priority: .userInitiated) { (try? data.write(to: url, options: .atomic)) != nil }.value
                saving.remove(date)
                guard written else { return NSSound.beep() }
                if self.shot?.date == date { self.shot?.file = url }
            }
        }
    }

    func close() {
        stopTimer()
        closing()
    }

    func clear() {
        stopTimer()
        shot = nil
        hovering = false
        hoveredRow = nil
    }

    private func countDown() {
        clock.restart(held: hovering || dragging || asking, at: Date(), seconds: seconds())
        stopTimer()
        guard let deadline = clock.deadline else { return }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timeUp() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

final class CursorScreenshotCardImageView: NSView, NSDraggingSource {
    private let model: CursorScreenshotCardModel
    private var press = CursorScreenshotCardPress()

    init(model: CursorScreenshotCardModel) {
        self.model = model
        super.init(frame: .zero)
        let root = CALayer()
        root.contentsGravity = .resizeAspectFill
        root.minificationFilter = .trilinear
        root.backgroundColor = NSColor.black.cgColor
        root.cornerRadius = CursorScreenshotCardLook.pictureCorner
        root.cornerCurve = .continuous
        layer = root
        wantsLayer = true
        root.masksToBounds = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(MenuBarL("Cursor Capture"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func show(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        press.down(at: event.locationInWindow, count: event.clickCount)
    }

    override func mouseUp(with event: NSEvent) {
        if press.opensEditor() { model.edit() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard press.startsDrag(at: event.locationInWindow), let shot = model.shot, let file = model.startDrag() else { return }
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let image = shot.image
        let frame = CursorScreenshotRender.dragFrame(NSSize(width: image.width, height: image.height), in: bounds.size, backing: shot.pointScale, around: convert(event.locationInWindow, from: nil))
        item.setDraggingFrame(frame, contents: NSImage(cgImage: image, size: frame.size))
        _ = beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let card = window?.frame.insetBy(dx: CursorScreenshotCardLook.inset, dy: CursorScreenshotCardLook.inset) ?? .zero
        model.dragEnded(hovering: NSMouseInRect(screenPoint, card, false), dropped: !operation.isEmpty, optionHeld: NSEvent.modifierFlags.contains(.option))
    }
}

final class CursorScreenshotCardTracker: NSView {
    var changed: (Bool) -> Void = { _ in }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) {
        changed(true)
    }

    override func mouseExited(with event: NSEvent) {
        changed(false)
    }
}

struct CursorScreenshotCardHover: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> CursorScreenshotCardTracker {
        CursorScreenshotCardTracker()
    }

    func updateNSView(_ view: CursorScreenshotCardTracker, context: Context) {
        view.changed = changed
    }
}

struct CursorScreenshotCardRowStyle: ButtonStyle {
    let hovered: Bool
    let corner: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let look = CursorScreenshotCardLook.self
        configuration.label
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(configuration.isPressed ? look.rowPress : hovered ? look.rowHover : Color.clear))
    }
}

struct CursorScreenshotCardImage: NSViewRepresentable {
    let model: CursorScreenshotCardModel
    let image: CGImage?
    let corner: CGFloat

    func makeNSView(context: Context) -> CursorScreenshotCardImageView {
        CursorScreenshotCardImageView(model: model)
    }

    func updateNSView(_ view: CursorScreenshotCardImageView, context: Context) {
        view.show(image)
        view.layer?.cornerRadius = corner
    }
}

struct CursorScreenshotCardView: View {
    @ObservedObject var model: CursorScreenshotCardModel
    @Environment(\.displayScale) private var scale

    private var zoom: CGFloat { model.scale }

    var body: some View {
        let look = CursorScreenshotCardLook.self
        HStack(spacing: look.padding * zoom) {
            CursorScreenshotCardImage(model: model, image: model.shot?.image, corner: look.pictureCorner * zoom)
                .frame(width: look.pictureWidth * zoom, height: look.pictureHeight * zoom)
                .overlay(RoundedRectangle(cornerRadius: look.pictureCorner * zoom, style: .continuous).stroke(look.hairline, lineWidth: 1 / scale).allowsHitTesting(false))
            VStack(spacing: 0) {
                row("copy", glyph: "doc.on.doc", title: MenuBarL("Copy"), action: model.copy)
                row("save", glyph: model.shot?.file == nil ? "square.and.arrow.down" : "folder", title: model.shot?.file == nil ? MenuBarL("Save") : MenuBarL("Show in Finder"), action: model.saveOrShow)
                row("edit", glyph: "pencil", title: MenuBarL("Edit"), action: model.edit)
                row("copyText", glyph: "text.viewfinder", title: MenuBarL("Copy Text"), enabled: !model.reading, action: model.copyText)
                Rectangle().fill(look.hairline).frame(height: 1)
                row("close", glyph: "xmark", title: MenuBarL("Close"), action: model.close)
            }
        }
        .padding(look.padding * zoom)
        .frame(width: look.width * zoom, height: look.height * zoom)
        .foregroundStyle(look.label)
        .background(CursorScreenshotCardHover { model.setHovering($0) })
        .background(RoundedRectangle(cornerRadius: look.corner * zoom, style: .continuous).fill(look.ground).shadow(color: look.shadow, radius: look.shadowBlur * zoom, y: look.shadowDrop * zoom))
        .overlay(RoundedRectangle(cornerRadius: look.corner * zoom + 1, style: .continuous).strokeBorder(look.edge, lineWidth: 1).padding(-1).allowsHitTesting(false))
        .padding(look.inset)
    }

    private func row(_ id: String, glyph: String, title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        let look = CursorScreenshotCardLook.self
        return Button(action: action) {
            HStack(spacing: look.rowGap * zoom) {
                Image(systemName: glyph)
                    .font(.system(size: look.rowFont * zoom))
                    .frame(width: look.rowGlyph * zoom, height: look.rowGlyph * zoom)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: look.rowFont * zoom))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, look.rowGap * zoom)
            .frame(height: look.rowHeight * zoom)
            .contentShape(Rectangle())
        }
        .buttonStyle(CursorScreenshotCardRowStyle(hovered: enabled && model.hoveredRow == id, corner: look.rowCorner * zoom))
        .disabled(!enabled)
        .opacity(enabled ? 1 : look.rowOff)
        .background(CursorScreenshotCardHover { model.setRow(id, hovered: $0) })
    }
}

final class CursorScreenshotCardHost: NSHostingView<CursorScreenshotCardView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CursorScreenshotCard {
    let model: CursorScreenshotCardModel
    let host: CursorScreenshotCardHost
    let panel: NSPanel
    private var fades = 0
    private var away: CGFloat = 0
    private var offset: CGFloat = 0

    init(model: CursorScreenshotCardModel) {
        self.model = model
        host = CursorScreenshotCardHost(rootView: CursorScreenshotCardView(model: model))
        host.sizingOptions = []
        host.wantsLayer = true
        let outer = CursorScreenshotCardLook.inset * 2
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: CursorScreenshotCardLook.width + outer, height: CursorScreenshotCardLook.height + outer),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.contentView = host
        model.closing = { [weak self] in self?.fade(to: 0) }
    }

    func show(_ shot: CursorScreenshotShot, on screen: NSScreen, corner: CursorScreenshotCorner, scale: CGFloat) {
        prepare(shot, in: screen.visibleFrame, corner: corner, scale: scale)
        panel.orderFrontRegardless()
        fade(to: 1)
    }

    func prepare(_ shot: CursorScreenshotShot, in visible: CGRect, corner: CursorScreenshotCorner, scale: CGFloat) {
        let look = CursorScreenshotCardLook.self
        let size = NSSize(width: look.width * scale, height: look.height * scale)
        panel.setContentSize(NSSize(width: size.width + look.inset * 2, height: size.height + look.inset * 2))
        let origin = corner.cardOrigin(size: size, margin: look.screenEdge, in: visible)
        panel.setFrameOrigin(NSPoint(x: origin.x - look.inset, y: origin.y - look.inset))
        away = corner.slide(size.width + look.inset)
        if !panel.isVisible {
            host.alphaValue = 0
            offset = away
        }
        let card = panel.frame.insetBy(dx: look.inset, dy: look.inset)
        model.present(shot, scale: scale, hovering: NSMouseInRect(NSEvent.mouseLocation, card, false))
    }

    func fade(to alpha: CGFloat) {
        fades += 1
        let fade = fades
        slide(to: alpha == 0 ? away : 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = CursorScreenshotCardLook.fade
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            host.animator().alphaValue = alpha
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, alpha == 0, self.fades == fade else { return }
                self.panel.orderOut(nil)
                self.host.layer?.removeAnimation(forKey: CursorScreenshotCardLook.slideKey)
                self.model.clear()
            }
        }
    }

    private func slide(to target: CGFloat) {
        guard let layer = host.layer else { return }
        let path = "transform.translation.x"
        let running = layer.animation(forKey: CursorScreenshotCardLook.slideKey) == nil ? nil : layer.presentation()?.value(forKeyPath: path) as? CGFloat
        let start = running ?? offset
        offset = target
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            layer.removeAnimation(forKey: CursorScreenshotCardLook.slideKey)
            return
        }
        let animation = CABasicAnimation(keyPath: path)
        animation.fromValue = start
        animation.toValue = target
        animation.duration = CursorScreenshotCardLook.fade
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: CursorScreenshotCardLook.slideKey)
    }
}
