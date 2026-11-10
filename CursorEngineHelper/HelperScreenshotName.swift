import AppKit

extension CursorScreenshotController {
    func nameContext(for naming: CursorScreenshotNaming, window: CursorScreenshotWindow? = nil) -> CursorScreenshotNameContext {
        let date = Date()
        guard naming.readsWindow else { return CursorScreenshotNameContext(date: date) }
        let shown = window ?? Self.topWindow()
        return CursorScreenshotNameContext(date: date, app: shown?.owner, title: shown?.title)
    }

    private static func topWindow() -> CursorScreenshotWindow? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let system = CursorScreenshotWindows.systemBundles.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }.map(\.processIdentifier)
        let skipped = system + [ProcessInfo.processInfo.processIdentifier]
        return CursorScreenshotWindows.top(list, skipping: Set(skipped))
    }
}

@MainActor
enum CursorScreenshotNamePrompt {
    static func ask(_ name: CursorScreenshotFileName, naming: CursorScreenshotNaming) async -> CursorScreenshotFileName {
        let own = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == own ? nil : $0 }
        let field = NSTextField(string: name.stem)
        field.frame = NSRect(origin: .zero, size: CursorScreenshotBackgroundLook.nameFieldSize)
        let alert = NSAlert()
        alert.messageText = MenuBarL("Name this screenshot")
        alert.accessoryView = field
        alert.addButton(withTitle: MenuBarL("OK"))
        alert.addButton(withTitle: MenuBarL("Use Default Name")).keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        let answer = alert.runModal()
        if let front, !front.isTerminated {
            front.activate(options: [])
            await CursorScreenshotController.waited { front.isActive }
        }
        guard answer == .alertFirstButtonReturn, let typed = naming.typed(field.stringValue) else { return name }
        return name.answered(typed)
    }
}
