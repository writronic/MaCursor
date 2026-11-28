import AppKit

@MainActor
final class CursorBoardController {
    private static var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }

    private let list = CursorBoardList()
    private let side: CursorBoardSide
    private let edge = CursorBoardEdgeWatch()
    private let queue = DispatchQueue(label: "com.writronic.macursor.board", qos: .utility)
    private var config = CursorBoardConfig()
    private var history = CursorBoardHistory()
    private var store: CursorBoardStore?
    private var timer: Timer?
    private var changeCount = 0
    private var pruned = Date.distantPast
    private var front: pid_t?
    var foreground: @MainActor () -> String? = { nil }
    var busy: @MainActor () -> Bool = { false }
    var trusted: @MainActor () -> Bool = { false }
    var wantsTrust: Bool { config.enabled }

    init() {
        side = CursorBoardSide(model: CursorBoardListModel())
        for model in [list.model, side.model] {
            model.paste = { [weak self] in self?.paste($0, plain: $1) }
            model.pin = { [weak self] in self?.pin($0) }
            model.delete = { [weak self] in self?.delete($0) }
        }
        side.appName = CursorGestures.appName
        side.side.close = { [weak self] in self?.side.close(.chevron) }
        side.side.keep = { [weak self] on in
            self?.side.side.keepsOpen = on
            self?.save { $0.keepsOpen = on }
        }
        side.side.move = { [weak self] on in
            self?.side.moved(on, pointer: NSEvent.mouseLocation)
            self?.save { $0.moves = on }
        }
        side.side.settings = { [weak self] in
            self?.side.hide()
            MenuBarService.openSettings(tab: "Cursor Board")
        }
        edge.pushed = { [weak self] in self?.edgePushed() }
    }

    func configChanged() {
        let latest = CursorBoardConfig.load()
        let previous = config
        config = latest
        guard latest.enabled else { return stop() }
        edge.watch(latest.opensAtEdge && latest.position != .top ? latest.position : nil)
        if let old = store {
            if previous.keepsHistory != latest.keepsHistory {
                let next = CursorBoardStore(latest, support: Self.support)
                let items = history.items
                queue.async { old.move(items, to: next) }
                store = next
            }
        } else {
            open(latest)
        }
        prune()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: CursorBoard.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        list.close()
        side.hide()
        edge.watch(nil)
        store = nil
        history = CursorBoardHistory()
        list.model.thumbnails = [:]
        side.model.thumbnails = [:]
    }

    func toggleList() {
        guard store != nil else { return }
        guard !list.isOpen else { return list.close() }
        side.hide()
        let place = prepare()
        list.show(history.ordered, size: config.listSize, pointer: place.pointer, visible: place.visible, gap: place.gap, locale: place.locale, appearance: place.appearance)
        loadThumbnails()
    }

    func togglePanel() {
        guard store != nil else { return }
        guard !side.isOpen else { return side.close(.trigger) }
        list.close()
        let place = prepare()
        side.show(history.ordered, config: config, pointer: place.pointer, visible: place.visible, gap: place.gap, locale: place.locale, appearance: place.appearance)
        loadThumbnails()
    }

    func close(_ reason: CursorBoardClose) {
        list.close()
        side.close(reason)
        if reason == .display { edge.refresh() }
    }

    private func edgePushed() {
        guard store != nil, !side.isOpen, !list.isOpen, !busy(), !CursorBoard.edgeClash(config.position) else { return }
        togglePanel()
    }

    private func prepare() -> (pointer: CGPoint, visible: CGRect, gap: CGFloat, locale: Locale, appearance: NSAppearance?) {
        prune()
        front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pointer = NSEvent.mouseLocation
        let visible = CursorTranslator.visible(at: pointer, on: NSScreen.screens.map { ($0.frame, $0.visibleFrame) }) ?? NSScreen.main?.visibleFrame ?? .zero
        let scale = (MACPreferences.value(forKey: MACPreferences.cursorScaleKey) as? NSNumber)?.doubleValue ?? 1
        let appearance = MACMenuBarAppearanceNameForMode(MACPreferences.value(forKey: MACPreferences.appearanceModeKey)).flatMap { NSAppearance(named: $0) }
        return (pointer, visible, CursorBoard.gap(scale: scale), MenuBarService.language().map(Locale.init(identifier:)) ?? .current, appearance)
    }

    private func save(_ edit: (inout CursorBoardConfig) -> Void) {
        var latest = CursorBoardConfig.load()
        edit(&latest)
        latest.save()
    }

    private func refresh(selecting id: UUID? = nil) {
        if side.isOpen {
            side.update(history.ordered, selecting: id)
        } else {
            list.update(history.ordered, selecting: id)
        }
    }

    func clearHistory() {
        guard let store else { return }
        forget(history.clear(), in: store)
    }

    func reloadHistory() {
        guard let store, store.root != nil else { return }
        let held = Set(history.items.map(\.id))
        queue.async { [weak self] in
            let items = store.load()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.store === store else { return }
                    self.history.reload(items, held: held)
                    self.prune()
                    self.refresh()
                    self.loadThumbnails()
                }
            }
        }
    }

    private func open(_ config: CursorBoardConfig) {
        let next = CursorBoardStore(config, support: Self.support)
        if next.root == nil { CursorBoardStore(root: Self.support.appendingPathComponent(CursorBoard.folder, isDirectory: true)).removeAll() }
        store = next
        history = CursorBoardHistory(items: next.load())
        changeCount = NSPasteboard.general.changeCount
    }

    private func tick() {
        if Date().timeIntervalSince(pruned) >= 3600 { prune() }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        guard trusted() else { return }
        guard let copy = CursorBoard.read(pasteboard, front: foreground(), ignored: config.ignored), pasteboard.changeCount == changeCount else { return }
        record(copy)
    }

    private func record(_ copy: CursorBoardCopy) {
        guard let store else { return }
        let kept = history.add(copy.item)
        let fresh = kept.id == copy.item.id
        prune()
        if side.isOpen { refresh() }
        let (picture, rich) = (copy.picture, copy.rich)
        queue.async { [weak self] in
            guard fresh else { return store.save(kept) }
            var files = [CursorBoardStore.rich: rich].compactMapValues { $0 }
            if let picture {
                let thumbnail = CursorScreenshotImageSource.image(from: CGImageSourceCreateWithData(picture as CFData, nil), side: CursorBoard.thumbnailSide).flatMap(MACCursorCapture.pngData(for:))
                guard let thumbnail else {
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.drop(kept) } }
                    return
                }
                files[CursorBoardStore.picture(kept)] = picture
                files[CursorBoardStore.thumbnail] = thumbnail
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.thumbnail(NSImage(data: thumbnail), for: kept.id) } }
            }
            store.save(kept, files: files)
        }
    }

    private func prune() {
        guard let store else { return }
        pruned = Date()
        forget(history.prune(keep: config.keep, limit: config.limit, now: pruned), in: store)
    }

    private func forget(_ gone: [CursorBoardItem], in store: CursorBoardStore) {
        guard !gone.isEmpty else { return }
        for item in gone { thumbnail(nil, for: item.id) }
        queue.async { for item in gone { store.remove(item.id) } }
        refresh()
    }

    private func drop(_ item: CursorBoardItem) {
        guard let store, let gone = history.remove(item.id) else { return }
        forget([gone], in: store)
    }

    private func loadThumbnails() {
        guard let store else { return }
        let wanted = history.items.filter { $0.picture != nil && list.model.thumbnails[$0.id] == nil }.map(\.id)
        guard !wanted.isEmpty else { return }
        queue.async { [weak self] in
            let found = wanted.compactMap { id in store.file(id, CursorBoardStore.thumbnail).map { (id, $0) } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for (id, data) in found { self?.thumbnail(NSImage(data: data), for: id) }
                }
            }
        }
    }

    private func thumbnail(_ image: NSImage?, for id: UUID) {
        list.model.thumbnails[id] = image
        side.model.thumbnails[id] = image
    }

    private func paste(_ item: CursorBoardItem, plain: Bool) {
        if side.isOpen { front = NSWorkspace.shared.frontmostApplication?.processIdentifier }
        list.close()
        side.close(.paste)
        guard let store else { return }
        var picked = item
        picked.date = Date()
        let kept = history.add(picked)
        if side.isOpen { refresh(selecting: kept.id) }
        let front = front
        queue.async { [weak self] in
            store.save(kept)
            let picture = item.picture == nil ? nil : store.file(item.id, CursorBoardStore.picture(item))
            let rich = item.rich && !plain ? store.file(item.id, CursorBoardStore.rich) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.deliver(item, picture: picture, rich: rich, plain: plain, front: front) }
            }
        }
    }

    private func deliver(_ item: CursorBoardItem, picture: Data?, rich: Data?, plain: Bool, front: pid_t?) {
        guard item.text != nil || picture != nil else { return NSSound.beep() }
        CursorBoard.write(item, picture: picture, rich: rich, plain: plain, to: .general)
        changeCount = NSPasteboard.general.changeCount
        guard HelperTrustProbe.isTrusted() else { return MenuBarService.requestCursorBoardAccess() }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == front else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + CursorBoard.pasteDelay) {
            MainActor.assumeIsolated { CursorGestureKeys.paste() }
        }
    }

    private func pin(_ item: CursorBoardItem) {
        guard let store, let pinned = history.togglePin(item.id) else { return }
        queue.async { store.save(pinned) }
        refresh(selecting: pinned.id)
    }

    private func delete(_ item: CursorBoardItem) {
        guard let store, let gone = history.remove(item.id) else { return }
        forget([gone], in: store)
    }
}
