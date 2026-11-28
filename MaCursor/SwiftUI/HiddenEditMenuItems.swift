import AppKit

@MainActor
final class HiddenEditMenuItems {
    static let shared = HiddenEditMenuItems()

    static let entries: [(title: String, action: Selector, key: String)] = [
        ("Cut", #selector(NSText.cut(_:)), "x"),
        ("Copy", #selector(NSText.copy(_:)), "c"),
        ("Paste", #selector(NSText.paste(_:)), "v"),
        ("Select All", #selector(NSText.selectAll(_:)), "a")
    ]

    private var mainMenuObservation: NSKeyValueObservation?
    private var menuObservers: [NSObjectProtocol] = []
    private var isInstallQueued = false

    var isRunning: Bool { mainMenuObservation != nil }

    static func install(into mainMenu: NSMenu?) {
        let undo = Selector(("undo:"))
        guard let editMenu = mainMenu?.items.compactMap(\.submenu).first(where: { menu in
            menu.items.contains { $0.action == undo }
        }) else { return }
        for entry in entries where !editMenu.items.contains(where: { $0.action == entry.action }) {
            let item = NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: entry.key)
            item.keyEquivalentModifierMask = .command
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            editMenu.addItem(item)
        }
    }

    func start() {
        guard mainMenuObservation == nil else { return }
        mainMenuObservation = NSApp.observe(\.mainMenu, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.queueInstall() }
        }
        menuObservers = [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.queueInstall() }
            }
        }
    }

    func stop() {
        mainMenuObservation?.invalidate()
        mainMenuObservation = nil
        menuObservers.forEach(NotificationCenter.default.removeObserver)
        menuObservers = []
    }

    private func queueInstall() {
        guard !isInstallQueued else { return }
        isInstallQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isInstallQueued = false
                if self.isRunning { Self.install(into: NSApp.mainMenu) }
            }
        }
    }
}
