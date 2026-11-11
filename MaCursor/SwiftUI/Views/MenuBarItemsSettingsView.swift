import SwiftUI

private extension MACMenuBarItem {
    var title: String {
        switch self {
        case .themes: return String(localized: "Cursor Themes")
        case .activeApp: return String(localized: "Per-App Themes")
        case .quickControls: return String(localized: "Quick Controls")
        case .cursorScale: return String(localized: "Cursor Scale")
        case .cursorShadow: return String(localized: "Cursor Shadow")
        case .focusOnHover: return String(localized: "Focus on Hover")
        case .cursorGestures: return String(localized: "Cursor Gestures")
        case .cursorTranslator: return String(localized: "Cursor Translator")
        case .cursorShaker: return String(localized: "Cursor Shaker")
        case .cursorTrails: return String(localized: "Cursor Trails")
        }
    }
}

private extension MACMenuBarCaptureRow {
    var title: String {
        switch self {
        case .area: return String(localized: "Capture Area")
        case .previousArea: return String(localized: "Capture Previous Area")
        case .fullscreen: return String(localized: "Capture Fullscreen")
        case .selfTimer: return String(localized: "Self-Timer")
        case .text: return String(localized: "Capture Text (OCR)")
        case .open: return String(localized: "Open...")
        case .openClipboard: return String(localized: "Open from Clipboard")
        case .pin: return String(localized: "Pin to the Screen...")
        case .history: return String(localized: "Capture History...")
        }
    }
}

struct MenuBarItemsSettingsView: View {
    static let rowHeight: CGFloat = 37
    static var caption: Text {
        Text("Drag an item to change its place in the panel. Turning an item off hides it from the panel, and its feature keeps working.")
    }

    static func setShown(items: [MACMenuBarItem: Bool], captureRows: [MACMenuBarCaptureRow: Bool], preferences: MACPreferences.Operations = .live) {
        saveHidden(hiding(savedHidden(preferences), items), key: MACPreferences.menuBarHiddenItemsKey, preferences: preferences)
        saveHidden(hiding(savedCaptureHidden(preferences), captureRows), key: MACPreferences.menuBarHiddenCaptureRowsKey, preferences: preferences)
        NotificationCenter.default.post(name: .MACMenuBarHiddenRowsDidChange, object: nil)
    }

    private static func hiding<Item: Hashable>(_ hidden: Set<Item>, _ shown: [Item: Bool]) -> Set<Item> {
        hidden.subtracting(shown.filter(\.value).keys).union(shown.filter { !$0.value }.keys)
    }

    private static func saveHidden<Item: CaseIterable & Hashable & RawRepresentable>(_ hidden: Set<Item>, key: String, preferences: MACPreferences.Operations)
        where Item.RawValue == String {
        MACPreferences.set(Item.allCases.filter(hidden.contains).map(\.rawValue), forKey: key, operations: preferences)
    }

    private let preferences: MACPreferences.Operations
    @State private var order: [MACMenuBarItem]
    @State private var hidden: Set<MACMenuBarItem>
    @State private var captureOrder: [MACMenuBarCaptureRow]
    @State private var captureHidden: Set<MACMenuBarCaptureRow>

    init(preferences: MACPreferences.Operations = .live) {
        self.preferences = preferences
        _order = State(initialValue: Self.savedOrder(preferences))
        _hidden = State(initialValue: Self.savedHidden(preferences))
        _captureOrder = State(initialValue: Self.savedCaptureOrder(preferences))
        _captureHidden = State(initialValue: Self.savedCaptureHidden(preferences))
    }

    var body: some View {
        Text("Panel Items")
        itemList(order.filter(MACMenuBarItem.panelItems.contains), label: "Panel Items", title: \.title,
                 shown: { $0 == .quickControls ? nil : shownBinding($0, in: $hidden, key: MACPreferences.menuBarHiddenItemsKey, saved: Self.savedHidden) },
                 move: { move(in: MACMenuBarItem.panelItems, from: $0, to: $1) })
            .onReceive(NotificationCenter.default.publisher(for: .cursorSettingsDidReset)) { _ in
                order = Self.savedOrder(preferences)
                hidden = Self.savedHidden(preferences)
                captureOrder = Self.savedCaptureOrder(preferences)
                captureHidden = Self.savedCaptureHidden(preferences)
            }
            .onReceive(NotificationCenter.default.publisher(for: .MACMenuBarHiddenRowsDidChange)) { _ in
                hidden = Self.savedHidden(preferences)
                captureHidden = Self.savedCaptureHidden(preferences)
            }
        Text("Cursor Capture")
        itemList(captureOrder, label: "Cursor Capture", title: \.title,
                 shown: { shownBinding($0, in: $captureHidden, key: MACPreferences.menuBarHiddenCaptureRowsKey, saved: Self.savedCaptureHidden) },
                 move: moveCapture)
        Text("Quick Controls")
        itemList(order.filter(MACMenuBarItem.quickControlItems.contains), label: "Quick Controls", title: \.title,
                 shown: { shownBinding($0, in: $hidden, key: MACPreferences.menuBarHiddenItemsKey, saved: Self.savedHidden) },
                 move: { move(in: MACMenuBarItem.quickControlItems, from: $0, to: $1) })
    }

    private func itemList<Item: Hashable>(_ items: [Item], label: LocalizedStringKey, title: @escaping (Item) -> String,
                                          shown: @escaping (Item) -> Binding<Bool>?, move: @escaping (IndexSet, Int) -> Void) -> some View {
        List {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                row(title(item), shown: shown(item), at: index, count: items.count, move: move)
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: CGFloat(items.count) * Self.rowHeight)
        .accessibilityLabel(label)
    }

    private func row(_ title: String, shown: Binding<Bool>?, at index: Int, count: Int, move: @escaping (IndexSet, Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            if let shown {
                Text(title)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Toggle(title, isOn: shown)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityActions { moveActions(at: index, count: count, move: move) }
            } else {
                Text(title)
                    .lineLimit(1)
                    .accessibilityActions { moveActions(at: index, count: count, move: move) }
                Spacer(minLength: 8)
            }
        }
        .frame(height: Self.rowHeight)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Move Up") { move(IndexSet(integer: index), index - 1) }
                .disabled(index == 0)
            Button("Move Down") { move(IndexSet(integer: index), index + 2) }
                .disabled(index == count - 1)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 2.5, bottom: 0, trailing: 4))
    }

    @ViewBuilder
    private func moveActions(at index: Int, count: Int, move: @escaping (IndexSet, Int) -> Void) -> some View {
        if index > 0 {
            Button("Move Up") { move(IndexSet(integer: index), index - 1) }
        }
        if index < count - 1 {
            Button("Move Down") { move(IndexSet(integer: index), index + 2) }
        }
    }

    private func shownBinding<Item: CaseIterable & Hashable & RawRepresentable>(_ item: Item, in hidden: Binding<Set<Item>>, key: String,
                                                                              saved: @escaping (MACPreferences.Operations) -> Set<Item>) -> Binding<Bool>
        where Item.RawValue == String {
        Binding(
            get: { !hidden.wrappedValue.contains(item) },
            set: { shown in
                hidden.wrappedValue = saved(preferences)
                if shown { hidden.wrappedValue.remove(item) } else { hidden.wrappedValue.insert(item) }
                Self.saveHidden(hidden.wrappedValue, key: key, preferences: preferences)
            }
        )
    }

    private func move(in list: [MACMenuBarItem], from source: IndexSet, to destination: Int) {
        order = MACMenuBarItemOrder(order, movingIn: list, from: source, to: destination)
        MACPreferences.set(order.map(\.rawValue), forKey: MACPreferences.menuBarItemOrderKey, operations: preferences)
    }

    private func moveCapture(from source: IndexSet, to destination: Int) {
        captureOrder.move(fromOffsets: source, toOffset: destination)
        MACPreferences.set(captureOrder.map(\.rawValue), forKey: MACPreferences.menuBarCaptureOrderKey, operations: preferences)
    }

    private static func savedOrder(_ preferences: MACPreferences.Operations) -> [MACMenuBarItem] {
        MACMenuBarItemOrder(MACPreferences.value(forKey: MACPreferences.menuBarItemOrderKey, operations: preferences))
    }

    private static func savedHidden(_ preferences: MACPreferences.Operations) -> Set<MACMenuBarItem> {
        MACMenuBarHiddenItems(MACPreferences.value(forKey: MACPreferences.menuBarHiddenItemsKey, operations: preferences))
    }

    private static func savedCaptureOrder(_ preferences: MACPreferences.Operations) -> [MACMenuBarCaptureRow] {
        MACMenuBarCaptureRowOrder(MACPreferences.value(forKey: MACPreferences.menuBarCaptureOrderKey, operations: preferences))
    }

    private static func savedCaptureHidden(_ preferences: MACPreferences.Operations) -> Set<MACMenuBarCaptureRow> {
        MACMenuBarHiddenCaptureRows(MACPreferences.value(forKey: MACPreferences.menuBarHiddenCaptureRowsKey, operations: preferences))
    }
}
