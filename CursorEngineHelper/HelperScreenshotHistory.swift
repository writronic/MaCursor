import AppKit
import SwiftUI

@MainActor
enum CursorScreenshotHistory {
    static let thumbnailSide = 360
    static let store = CursorScreenshotHistoryStore(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(CursorScreenshot.historyFolder, isDirectory: true))
    private static var timer: Timer?

    static func record(_ picture: CGImage, scale: CGFloat, date: Date, name: CursorScreenshotFileName, file: URL?, config: CursorScreenshotConfig) {
        let keep = config.keepHistory
        guard keep != .disabled else { return }
        let entry = CursorScreenshotHistoryEntry(date: date, scale: scale, output: config.output, name: name, file: file)
        let store = store
        let side = thumbnailSide
        Task.detached(priority: .utility) {
            guard let data = MACCursorCapture.pngData(for: picture) else { return }
            let small = CursorScreenshotImageSource.image(from: CGImageSourceCreateWithData(data as CFData, nil), side: side)
            let thumbnail = small.flatMap { MACCursorCapture.pngData(for: $0) }
            await store.prune(keeping: keep, now: Date())
            await store.add(entry, picture: data, thumbnail: thumbnail)
        }
    }

    static func start() {
        clean()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { clean() }
        }
    }

    static func clean() {
        let keep = CursorScreenshotConfig.load().keepHistory
        let store = store
        Task.detached(priority: .utility) { await store.prune(keeping: keep, now: Date()) }
    }
}

@MainActor
final class CursorScreenshotHistoryWindow: NSObject, NSWindowDelegate {
    typealias Restore = @MainActor (CursorScreenshotHistoryEntry, CGImage, NSScreen) async -> Void

    private static var current: CursorScreenshotHistoryWindow?
    private static var previousApp: NSRunningApplication?

    private let window: NSWindow
    private let model: CursorScreenshotHistoryModel
    private let restore: Restore
    private var keyMonitor: Any?

    static func show(restore: @escaping Restore) {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        let shown = current ?? CursorScreenshotHistoryWindow(restore: restore)
        current = shown
        shown.model.reload()
        NSApp.activate(ignoringOtherApps: true)
        shown.window.makeKeyAndOrderFront(nil)
    }

    private init(restore: @escaping Restore) {
        self.restore = restore
        model = CursorScreenshotHistoryModel(store: CursorScreenshotHistory.store)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = MenuBarL("Capture History")
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: CursorScreenshotHistoryView(model: model))
        window.center()
        window.delegate = self
        model.acting = { [weak self] action, entry in self?.run(action, on: entry) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, window.attachedSheet == nil, event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad, .capsLock]).isEmpty else { return event }
        switch event.keyCode {
        case 36, 76:
            model.run(.restore, on: model.selected)
        case 51, 117:
            if let selected = model.selected { model.delete(selected.id) }
        case 53:
            window.close()
        default:
            return event
        }
        return nil
    }

    private func run(_ action: CursorScreenshotHistoryAction, on entry: CursorScreenshotHistoryEntry) {
        let screen = window.screen ?? NSScreen.main
        let url = model.store.pictureURL(entry)
        let restore = restore
        let back = Self.previousApp
        window.close()
        Task {
            if let back { await CursorScreenshotController.waited { back.isActive } }
            let picture = await Task.detached(priority: .userInitiated) {
                CursorScreenshotImageSource.image(from: CGImageSourceCreateWithURL(url as CFURL, nil), side: CursorScreenshotEditorLook.largestImageSide)
            }.value
            guard let picture, let screen else { return NSSound.beep() }
            switch action {
            case .restore: await restore(entry, picture, screen)
            case .edit: CursorScreenshotEditor.open(picture, scale: entry.scale, name: entry.name)
            case .pin:
                let output = entry.output
                let image = await Task.detached(priority: .userInitiated) { output.apply(picture, scale: entry.scale) }.value
                CursorScreenshotPin.show(image, scale: output.shownScale(entry.scale), on: screen)
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        Self.current = nil
        if NSApp.isActive, let previous = Self.previousApp, !previous.isTerminated { previous.activate(options: []) }
        Self.previousApp = nil
    }
}
