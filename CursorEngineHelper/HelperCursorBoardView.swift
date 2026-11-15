import AppKit
import SwiftUI

@MainActor
final class CursorBoardListModel: ObservableObject {
    @Published var items: [CursorBoardItem] = []
    @Published var pager = CursorBoardPager(count: 0, size: 5)
    @Published var hovered: Int?
    @Published var thumbnails: [UUID: NSImage] = [:]
    var frames: [Int: CGRect] = [:]
    @Published var now = Date()
    var paste: @MainActor (CursorBoardItem, Bool) -> Void = { _, _ in }
    var pin: @MainActor (CursorBoardItem) -> Void = { _ in }
    var delete: @MainActor (CursorBoardItem) -> Void = { _ in }
    var turn: @MainActor (Int) -> Void = { _ in }
    private var clock: Timer?
    private var icons: [String: NSImage] = [:]
    private let ages: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter
    }()

    var locale: Locale {
        get { ages.locale }
        set { ages.locale = newValue }
    }

    var page: [CursorBoardItem] { Array(items[pager.range]) }

    var selection: CursorBoardItem? { page.indices.contains(pager.selected) ? page[pager.selected] : nil }

    func age(_ date: Date) -> String {
        ages.localizedString(for: min(date, now), relativeTo: now)
    }

    func runClock(_ on: Bool) {
        clock?.invalidate()
        clock = nil
        guard on else { return }
        let clock = Timer(timeInterval: CursorBoard.ageRefresh, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.now = Date() }
        }
        clock.tolerance = CursorBoard.ageTolerance
        RunLoop.main.add(clock, forMode: .common)
        self.clock = clock
    }

    func icon(_ app: String?) -> NSImage {
        let key = app ?? ""
        if let icon = icons[key] { return icon }
        let icon = app.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        icons[key] = icon
        return icon
    }
}

struct CursorBoardCardFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct CursorBoardListView: View {
    static let space = "CursorBoardList"
    @ObservedObject var model: CursorBoardListModel

    var body: some View {
        VStack(spacing: 6) {
            if model.items.isEmpty {
                Text(verbatim: MenuBarL("No copied items yet."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ForEach(Array(model.page.enumerated()), id: \.element.id) { row, item in
                    CursorBoardCard(model: model, item: item, row: row)
                }
                HStack {
                    turnButton("chevron.left", MenuBarL("Newer items"), step: -1, enabled: model.pager.hasNewer)
                    Spacer()
                    turnButton("chevron.right", MenuBarL("Older items"), step: 1, enabled: model.pager.hasOlder)
                }
            }
        }
        .padding(8)
        .frame(width: CursorBoardList.width)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(CursorBoardCardFrames.self) { [model] frames in
            MainActor.assumeIsolated { model.frames = frames }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MenuBarL("Cursor Board"))
    }

    private func turnButton(_ symbol: String, _ label: String, step: Int, enabled: Bool) -> some View {
        Button {
            model.turn(step)
        } label: {
            Image(systemName: symbol)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

struct CursorBoardCard: View {
    private static let fill = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.173, alpha: 1) : .white })
    private static let hover = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.212, alpha: 1) : NSColor(white: 0.953, alpha: 1) })

    @ObservedObject var model: CursorBoardListModel
    let item: CursorBoardItem
    let row: Int
    var wide = false

    private var selected: Bool { model.pager.selected == row }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: model.icon(item.app))
                .resizable()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let label = CursorBoardPager.label(row) {
                        Text(verbatim: label)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(MenuBarL("Pinned"))
                    }
                    Spacer(minLength: 4)
                    Text(verbatim: model.age(item.date))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))

                content
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: wide ? .infinity : nil, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(model.hovered == row ? Self.hover : Self.fill)
                .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .background(GeometryReader { proxy in
            Color.clear.preference(key: CursorBoardCardFrames.self, value: [row: proxy.frame(in: .named(CursorBoardListView.space))])
        })
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { model.paste(item, NSEvent.modifierFlags.contains(.option)) }
        .contextMenu {
            Button(MenuBarL("Paste")) { model.paste(item, false) }
            Button(MenuBarL("Paste as Plain Text")) { model.paste(item, true) }
            Button(MenuBarL(item.pinned ? "Unpin" : "Pin")) { model.pin(item) }
            Button(MenuBarL("Delete")) { model.delete(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.paste(item, false) }
    }

    @ViewBuilder private var content: some View {
        if item.picture != nil {
            Group {
                if let thumbnail = model.thumbnails[item.id] {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: wide ? nil : 72, height: wide ? 96 : 44)
            .frame(maxWidth: wide ? .infinity : nil)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(MenuBarL("Picture"))
            Text(verbatim: CursorBoardStore.fileType(item))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let colour = item.colour {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(cgColor: colour))
                        .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                        .frame(width: 12, height: 12)
                    Text(verbatim: text)
                }
            } else if let link = item.link {
                Text(verbatim: item.name ?? link.host ?? text)
                    .lineLimit(2)
                Text(verbatim: link.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(verbatim: text)
                    .lineLimit(wide ? 3 : 2)
            }
        }
    }
}

class CursorBoardPanel: NSPanel {
    var handle: @MainActor (NSEvent) -> Bool = { _ in false }
    var resigned: @MainActor () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        guard !handle(event) else { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        resigned()
    }
}

@MainActor
final class CursorBoardList {
    static let width: CGFloat = 300

    let model = CursorBoardListModel()
    let panel: CursorBoardPanel
    private let host: NSHostingView<CursorBoardListView>
    private var scroll = CursorBoardScroll()
    private var place = (pointer: CGPoint.zero, visible: CGRect.zero, gap: CGFloat(0))
    private(set) var isOpen = false {
        didSet { if isOpen != oldValue { model.runClock(isOpen) } }
    }

    init(panel: CursorBoardPanel? = nil) {
        let panel = panel ?? CursorBoardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        host = NSHostingView(rootView: CursorBoardListView(model: model))
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = false
        let backing = NSVisualEffectView()
        backing.material = .popover
        backing.state = .active
        backing.blendingMode = .behindWindow
        backing.wantsLayer = true
        backing.layer?.cornerRadius = 12
        backing.layer?.cornerCurve = .continuous
        backing.layer?.masksToBounds = true
        host.autoresizingMask = [.width, .height]
        backing.addSubview(host)
        backing.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: backing))
        panel.contentView = backing
        panel.handle = { [weak self] in self?.handle($0) ?? false }
        panel.resigned = { [weak self] in self?.close() }
        model.turn = { [weak self] in self?.turn($0) }
    }

    func show(_ items: [CursorBoardItem], size: Int, pointer: CGPoint, visible: CGRect, gap: CGFloat, locale: Locale, appearance: NSAppearance?) {
        model.items = items
        model.pager = CursorBoardPager(count: items.count, size: CursorBoard.listPageSize(size, height: visible.height))
        model.hovered = nil
        model.now = Date()
        model.locale = locale
        place = (pointer, visible, gap)
        scroll = CursorBoardScroll()
        panel.appearance = appearance
        isOpen = true
        refit()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func update(_ items: [CursorBoardItem], selecting id: UUID? = nil) {
        model.items = items
        model.pager.fit(count: items.count)
        if let id, let index = items.firstIndex(where: { $0.id == id }), model.pager.range.contains(index) {
            model.pager.selected = index - model.pager.range.lowerBound
        }
        guard isOpen else { return }
        model.now = Date()
        refit()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        model.hovered = nil
        panel.orderOut(nil)
    }

    private func refit() {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setFrame(CursorBoard.listFrame(size: size, pointer: place.pointer, visible: place.visible, gap: place.gap), display: true)
        panel.invalidateShadow()
    }

    private func turn(_ step: Int) {
        let page = model.pager
        model.pager.turn(step)
        guard model.pager != page else { return }
        model.hovered = nil
        refit()
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            guard let command = CursorBoard.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, flags: event.modifierFlags) else { return true }
            if !event.isARepeat || [.up, .down, .older, .newer].contains(command) { run(command) }
            return true
        case .scrollWheel:
            let step = scroll.step(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas, phase: event.phase, momentum: event.momentumPhase)
            if step != 0 { turn(step) }
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
        let row = model.frames.first { $0.value.contains(spot) }?.key
        guard row != model.hovered else { return }
        model.hovered = row
        if let row { model.pager.selected = row }
    }

    private func run(_ command: CursorBoardCommand) {
        switch command {
        case .up: model.pager.move(-1)
        case .down: model.pager.move(1)
        case .older: turn(1)
        case .newer: turn(-1)
        case .paste(let plain): if let item = model.selection { model.paste(item, plain) }
        case .pick(let number, let plain): if let index = model.pager.index(number: number) { model.paste(model.items[index], plain) }
        case .pin: if let item = model.selection { model.pin(item) }
        case .delete: if let item = model.selection { model.delete(item) }
        case .close: close()
        }
    }
}
