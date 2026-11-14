import AppKit
import SwiftUI

@MainActor
final class CursorBoardSideModel: ObservableObject {
    @Published var query = ""
    @Published var edge = CursorBoardEdge.right
    @Published var moves = false
    @Published var keepsOpen = false
    @Published var opens = 0
    @Published var scrolls = 0
    var search: @MainActor () -> Void = {}
    var close: @MainActor () -> Void = {}
    var keep: @MainActor (Bool) -> Void = { _ in }
    var move: @MainActor (Bool) -> Void = { _ in }
    var settings: @MainActor () -> Void = {}

    var row: Bool { edge.isRow && !moves }

    var chevron: String {
        if moves { return "chevron.down" }
        switch edge {
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        case .bottom: return "chevron.down"
        case .top: return "chevron.up"
        }
    }
}

struct CursorBoardSideView: View {
    static let viewport = -1
    static let start = "start"
    @ObservedObject var model: CursorBoardListModel
    @ObservedObject var side: CursorBoardSideModel
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                search
                if side.row { tools }
            }
            .padding([.horizontal, .top], 10)

            cards

            if !side.row {
                Divider()
                HStack(spacing: 2) { tools }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
        }
        .coordinateSpace(name: CursorBoardListView.space)
        .onPreferenceChange(CursorBoardCardFrames.self) { [model] frames in
            MainActor.assumeIsolated { model.frames = frames }
        }
        .onAppear { searching = true }
        .onChange(of: side.opens) { _ in searching = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MenuBarL("Cursor Board"))
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(MenuBarL("Search"), text: Binding(get: { side.query }, set: { side.query = $0; side.search() }))
                .textFieldStyle(.plain)
                .focused($searching)
                .accessibilityLabel(MenuBarL("Search Cursor Board"))
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    @ViewBuilder private var cards: some View {
        if model.items.isEmpty {
            Text(verbatim: MenuBarL(side.query.isEmpty ? "No copied items yet." : "No items match."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(side.row ? .horizontal : .vertical) {
                    if side.row {
                        LazyHStack(alignment: .top, spacing: 10) { rows }
                            .padding(10)
                            .id(Self.start)
                    } else {
                        LazyVStack(spacing: 10) { rows }
                            .padding(10)
                            .id(Self.start)
                    }
                }
                .overlayScrollers()
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CursorBoardCardFrames.self, value: [Self.viewport: proxy.frame(in: .named(CursorBoardListView.space))])
                })
                .onChange(of: side.scrolls) { _ in
                    if let id = model.selection?.id { proxy.scrollTo(id) }
                }
                .onChange(of: side.opens) { _ in
                    proxy.scrollTo(Self.start, anchor: side.row ? .leading : .top)
                }
            }
        }
    }

    private var rows: some View {
        ForEach(Array(model.items.enumerated()), id: \.element.id) { row, item in
            CursorBoardCard(model: model, item: item, row: row, wide: true)
                .frame(width: side.row ? 210 : nil)
                .id(item.id)
        }
    }

    @ViewBuilder private var tools: some View {
        tool(side.chevron, MenuBarL("Close Cursor Board"), on: false) { side.close() }
        tool(side.keepsOpen ? "pin.fill" : "pin", MenuBarL("Keep open"), on: side.keepsOpen) { side.keep(!side.keepsOpen) }
        tool("arrow.up.and.down.and.arrow.left.and.right", MenuBarL("Move: open near the pointer"), on: side.moves) { side.move(!side.moves) }
        if !side.row { Spacer(minLength: 0) }
        tool("gearshape", MenuBarL("Cursor Board Settings"), on: false) { side.settings() }
    }

    private func tool(_ symbol: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(on ? Color.white : Color.primary)
                .frame(width: 32, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Color.accentColor : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

class CursorBoardSidePanel: CursorBoardPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class CursorBoardSideHost: NSHostingView<CursorBoardSideView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CursorBoardSide {
    private static let slideKey = "slide"

    let model: CursorBoardListModel
    let side = CursorBoardSideModel()
    let panel: CursorBoardPanel
    let content = NSView()
    private let host: CursorBoardSideHost
    private var all: [CursorBoardItem] = []
    private var names: [String: String] = [:]
    private var offset = CGVector.zero
    private var place = (visible: CGRect.zero, gap: CGFloat(0))
    private(set) var isOpen = false {
        didSet { if isOpen != oldValue { model.runClock(isOpen) } }
    }
    var reduceMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var appName: @MainActor (String) -> String = { $0 }

    init(model: CursorBoardListModel, panel: CursorBoardPanel? = nil) {
        self.model = model
        let panel = panel ?? CursorBoardSidePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        host = CursorBoardSideHost(rootView: CursorBoardSideView(model: model, side: side))
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        let root = NSView()
        content.wantsLayer = true
        content.autoresizingMask = [.width, .height]
        let backing = NSVisualEffectView()
        backing.material = .popover
        backing.state = .active
        backing.blendingMode = .behindWindow
        backing.wantsLayer = true
        backing.layer?.cornerRadius = 14
        backing.layer?.cornerCurve = .continuous
        backing.layer?.masksToBounds = true
        backing.autoresizingMask = [.width, .height]
        host.autoresizingMask = [.width, .height]
        backing.addSubview(host)
        backing.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: backing))
        content.addSubview(backing)
        root.addSubview(content)
        panel.contentView = root
        panel.handle = { [weak self] in self?.handle($0) ?? false }
        panel.resigned = { [weak self] in self?.close(.clickOutside) }
        side.search = { [weak self] in self?.filter() }
    }

    func show(_ items: [CursorBoardItem], config: CursorBoardConfig, pointer: CGPoint, visible: CGRect, gap: CGFloat, locale: Locale, appearance: NSAppearance?) {
        all = items
        side.query = ""
        side.edge = config.position
        side.moves = config.moves
        side.keepsOpen = config.keepsOpen
        model.now = Date()
        model.locale = locale
        filter()
        place = (visible, gap)
        panel.appearance = appearance
        frame(pointer: pointer)
        isOpen = true
        side.opens += 1
        let slides = !side.moves && !reduceMotion()
        panel.hasShadow = !slides
        panel.alphaValue = side.moves && !reduceMotion() ? 0 : 1
        hold(slides ? CursorBoard.slideOffset(side.edge, size: panel.frame.size) : .zero)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.contentView?.displayIfNeeded()
        CATransaction.flush()
        if slides {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.slideIn() }
            }
        } else if panel.alphaValue == 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = CursorBoard.fade
                panel.animator().alphaValue = 1
            }
        }
    }

    func update(_ items: [CursorBoardItem], selecting id: UUID? = nil) {
        all = items
        guard isOpen else { return }
        model.now = Date()
        side.scrolls += 1
        let index = model.pager.selected
        let kept = id ?? model.selection?.id
        filter(selecting: kept)
        guard model.selection?.id != kept else { return }
        model.pager.selected = index
        model.pager.move(0)
    }

    func close(_ reason: CursorBoardClose) {
        guard isOpen else { return }
        guard reason.closes(keepsOpen: side.keepsOpen) else {
            if reason == .paste {
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
            return
        }
        guard [.escape, .chevron, .trigger, .clickOutside].contains(reason), !reduceMotion() else { return hide() }
        isOpen = false
        model.hovered = nil
        if side.moves {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = CursorBoard.fade
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated { if self?.isOpen == false { self?.panel.orderOut(nil) } }
            })
            return
        }
        panel.hasShadow = false
        slide(to: CursorBoard.slideOffset(side.edge, size: panel.frame.size), duration: CursorBoard.slideOut, timing: .easeIn) { [weak self] in
            if self?.isOpen == false { self?.panel.orderOut(nil) }
        }
    }

    func hide() {
        isOpen = false
        model.hovered = nil
        panel.orderOut(nil)
    }

    func moved(_ on: Bool, pointer: CGPoint) {
        side.moves = on
        guard isOpen else { return }
        content.layer?.removeAnimation(forKey: Self.slideKey)
        offset = .zero
        panel.alphaValue = 1
        panel.hasShadow = true
        frame(pointer: pointer)
        panel.invalidateShadow()
    }

    private func frame(pointer: CGPoint) {
        let frame = side.moves ? CursorBoard.movedFrame(pointer: pointer, visible: place.visible, gap: place.gap) : CursorBoard.panelFrame(side.edge, in: place.visible)
        panel.setFrame(frame, display: false)
        let bounds = CGRect(origin: .zero, size: frame.size)
        content.frame = bounds
        content.subviews.first?.frame = bounds
        host.frame = bounds
    }

    private func filter(selecting id: UUID? = nil) {
        let shown = all.filter { CursorBoard.matches($0, query: side.query, appName: $0.app.map(name)) }
        model.items = shown
        model.pager = CursorBoardPager(count: shown.count, size: CursorBoard.panelPageSize(shown.count))
        model.hovered = nil
        if let id, let index = shown.firstIndex(where: { $0.id == id }) { model.pager.selected = index }
    }

    private func name(_ app: String) -> String {
        if let known = names[app] { return known }
        let found = appName(app)
        names[app] = found
        return found
    }

    private func hold(_ target: CGVector) {
        offset = target
        content.layer?.add(slideAnimation(from: target, to: target), forKey: Self.slideKey)
    }

    private func slideIn() {
        guard isOpen else { return }
        slide(to: .zero, duration: CursorBoard.slideIn, timing: .easeOut) { [weak self] in
            guard self?.isOpen == true else { return }
            self?.panel.hasShadow = true
            self?.panel.invalidateShadow()
        }
    }

    private func slide(to target: CGVector, duration: TimeInterval, timing: CAMediaTimingFunctionName, done: @escaping @MainActor () -> Void) {
        guard let layer = content.layer else { return done() }
        let axis = side.edge.isRow ? "y" : "x"
        let running = layer.presentation()?.value(forKeyPath: "transform.translation.\(axis)") as? CGFloat
        let start = running.map { axis == "x" ? CGVector(dx: $0, dy: 0) : CGVector(dx: 0, dy: $0) } ?? offset
        offset = target
        let animation = slideAnimation(from: start, to: target)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { done() } }
        layer.add(animation, forKey: Self.slideKey)
        CATransaction.commit()
    }

    private func slideAnimation(from start: CGVector, to target: CGVector) -> CABasicAnimation {
        let axis = side.edge.isRow ? "y" : "x"
        let animation = CABasicAnimation(keyPath: "transform.translation.\(axis)")
        animation.fromValue = axis == "x" ? start.dx : start.dy
        animation.toValue = axis == "x" ? target.dx : target.dy
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        return animation
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
            guard let command = CursorBoard.panelCommand(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, flags: event.modifierFlags, row: side.row) else { return false }
            if !event.isARepeat || command == .up || command == .down { run(command) }
            return true
        case .scrollWheel where side.row && abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX):
            var view = panel.contentView?.hitTest(event.locationInWindow)
            while let current = view, !(current is NSScrollView) { view = current.superview }
            guard let scroll = view as? NSScrollView, let sideways = CursorBoard.sideways(event) else { return false }
            scroll.scrollWheel(with: sideways)
            return true
        case .mouseMoved:
            hover(at: event.locationInWindow)
        case .mouseExited:
            model.hovered = nil
        default:
            break
        }
        return false
    }

    private func hover(at point: CGPoint) {
        let local = host.convert(point, from: nil)
        let spot = host.isFlipped ? local : CGPoint(x: local.x, y: host.bounds.height - local.y)
        let inside = model.frames[CursorBoardSideView.viewport]?.contains(spot) ?? false
        let row = inside ? model.frames.first { $0.key >= 0 && $0.value.contains(spot) }?.key : nil
        guard row != model.hovered else { return }
        model.hovered = row
        if let row { model.pager.selected = row }
    }

    private func run(_ command: CursorBoardCommand) {
        switch command {
        case .up, .down:
            model.pager.move(command == .up ? -1 : 1)
            side.scrolls += 1
        case .paste(let plain): if let item = model.selection { model.paste(item, plain) }
        case .pick(let number, let plain): if let index = model.pager.index(number: number) { model.paste(model.items[index], plain) }
        case .pin: if let item = model.selection { model.pin(item) }
        case .delete: if let item = model.selection { model.delete(item) }
        case .close: close(.escape)
        case .older, .newer: break
        }
    }
}

@MainActor
final class CursorBoardEdgeWatch {
    private var monitors: [Any] = []
    private var state = CursorBoardHotEdge(edge: .right)
    var screens: [CGRect] = []
    var pushed: @MainActor () -> Void = {}

    func watch(_ edge: CursorBoardEdge?) {
        guard let edge else {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            return
        }
        if state.edge != edge { state = CursorBoardHotEdge(edge: edge) }
        screens = NSScreen.screens.map(\.frame)
        guard monitors.isEmpty else { return }
        let seen: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated {
                self?.moved(to: NSEvent.mouseLocation, by: CGVector(dx: event.deltaX, dy: event.deltaY), at: event.timestamp)
            }
        }
        monitors = [NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: seen),
                    NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { seen($0); return $0 }].compactMap { $0 }
    }

    func refresh() {
        screens = NSScreen.screens.map(\.frame)
    }

    func moved(to point: CGPoint, by delta: CGVector, at time: TimeInterval) {
        if state.moved(to: point, by: delta, at: time, screens: screens) { pushed() }
    }
}
