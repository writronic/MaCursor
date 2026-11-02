import Combine
import SwiftUI
import UniformTypeIdentifiers

enum CursorGesturesTab: CaseIterable {
    case general
    case gestures
    case shapes
    case actions

    @MainActor static var selected = CursorGesturesTab.general

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .gestures: return String(localized: "Gestures")
        case .shapes: return String(localized: "Shapes")
        case .actions: return String(localized: "Actions")
        }
    }

    var note: String {
        switch self {
        case .general: return String(localized: "Choose how the line looks, how closely a shape must match, and where gestures stay off.")
        case .gestures: return String(localized: "Click a gesture to edit it. Right-click it to duplicate or delete it.")
        case .shapes: return String(localized: "Shapes you can draw. Right-click a shape you drew to rename, redraw or delete it.")
        case .actions: return String(localized: "What a gesture can do. Right-click an action you made to edit or delete it.")
        }
    }
}

struct CursorGesturesSettingsView: View {
    @EnvironmentObject private var library: LibraryViewModel
    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var gestures = CursorGesturesConfig.load()
    @State private var trusted = FocusFollowsMouseConfig.accessibilityTrusted
    @State private var tab = CursorGesturesTab.selected
    @State private var search = ""
    @State private var filter = CursorGestureFilter.all
    @State private var editing: CursorGestureAction?
    @State private var deleting: String?
    @State private var restoring = false

    private var usable: Bool {
        trusted && helperManager.isRunning
    }

    var body: some View {
        let themes = library.cursorThemes.map { (id: $0.id, name: $0.name) }
        let shown = gestures.available(filter)
        let groups = gestures.groups(shown, search: search, themes: themes)
        GeometryReader { pane in
            let column = RightClickMenuLayout.tableWidth(contentWidth: pane.size.width - 2 * RightClickMenuLayout.pageMargin)
            ScrollView {
                VStack(alignment: .leading, spacing: RightClickMenuLayout.blockSpacing) {
                    Group {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Cursor Gestures")
                                Text("Draw a shape with the pointer to run an action.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Toggle("Cursor Gestures", isOn: Binding(
                                get: { FocusFollowsMouseConfig.isOn(enabled: gestures.enabled, trusted: usable) },
                                set: { _ in
                                    guard helperManager.isRunning else { return }
                                    switch FocusFollowsMouseConfig.toggleAction(enabled: gestures.enabled,
                                                                                helperInstalled: helperManager.isInstalled,
                                                                                trusted: usable) {
                                    case .enable: CursorGesturesConfig.setEnabled(true)
                                    case .requestAccess: AccessWindowController.cursorGestures.present()
                                    case .disable: CursorGesturesConfig.setEnabled(false)
                                    case .ignore: break
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                        .padding(RightClickMenuLayout.inset)
                        .frame(minHeight: RightClickMenuLayout.twoLineRowHeight)
                        .rightClickMenuCard()

                        if gestures.enabled && !trusted {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)

                                Text("Accessibility access is missing. Allow MaCursorHelper in Privacy & Security → Accessibility.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 6)

                                Button("Open System Settings") {
                                    FocusFollowsMouseConfig.requestAccessibility()
                                }
                            }
                            .padding(.horizontal, RightClickMenuLayout.inset)
                        }
                    }
                    .disabled(!helperManager.isInstalled)

                    if !helperManager.isInstalled {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)

                            Text("Cursor Gestures requires the Helper Tool. You can install it from General → Helper Tool.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, RightClickMenuLayout.inset)
                    }

                    if FocusFollowsMouseConfig.isOn(enabled: gestures.enabled, trusted: usable) {
                        Group {
                            TabBar(
                                titles: CursorGesturesTab.allCases.map(\.title),
                                label: String(localized: "Cursor Gestures"),
                                selection: Binding(
                                    get: { CursorGesturesTab.allCases.firstIndex(of: tab) ?? 0 },
                                    set: { tab = CursorGesturesTab.allCases[$0]; CursorGesturesTab.selected = tab }
                                )
                            )
                            .frame(maxWidth: .infinity)

                            VStack(alignment: .leading, spacing: RightClickMenuLayout.blockSpacing) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tab.title)
                                        .fontWeight(.semibold)
                                    Text(tab.note)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, RightClickMenuLayout.inset)

                                switch tab {
                                case .general:
                                    VStack(spacing: 0) {
                                        row(\.raiseWindow, resettable: false) {
                                            Toggle("Bring the Window Under the Pointer Forward First", isOn: $gestures.raiseWindow)
                                        }
                                        divider
                                        row(\.showLine, resettable: false) {
                                            Toggle("Show the Line While You Draw", isOn: $gestures.showLine)
                                        }
                                        divider
                                        row(\.colorByResult, resettable: false) {
                                            Toggle("Turn the Line Green When a Shape Matches", isOn: $gestures.colorByResult)
                                        }
                                        divider
                                        row(\.showShapeName, resettable: false) {
                                            Toggle("Show the Gesture Name and Match While You Draw", isOn: $gestures.showShapeName)
                                        }
                                        divider
                                        row(\.repeatMouse, resettable: false) {
                                            Toggle("Repeat with a Left Click on a Mouse", isOn: $gestures.repeatMouse)
                                        }
                                        .help("Keep holding the trigger after a gesture and left-click to run it again.")
                                        divider
                                        row(\.repeatTrackpad, resettable: false) {
                                            Toggle("Repeat with a Left Click on a Trackpad", isOn: $gestures.repeatTrackpad)
                                        }
                                        .help("Keep holding the trigger after a gesture and left-click to run it again.")
                                        divider
                                        row(\.switchWhileRepeating, resettable: false) {
                                            Toggle("A New Shape Changes What Repeats", isOn: $gestures.switchWhileRepeating)
                                        }
                                        divider
                                        row(\.lineColor) {
                                            Text("Line Color")
                                            Spacer(minLength: 8)
                                            ColorPicker("Line Color", selection: Binding(
                                                get: { CursorTrailsPalette.color(at: 0, stops: [gestures.lineColor], alpha: 1) },
                                                set: { gestures.lineColor = CursorGestures.hex($0) }
                                            ), supportsOpacity: false)
                                            .labelsHidden()
                                        }
                                        divider
                                        row(\.lineWidth) {
                                            Text("Line Width")
                                            Spacer(minLength: 8)
                                            Slider(value: $gestures.lineWidth, in: CursorGesturesConfig.widthRange, step: 1) {
                                                Text("Line Width")
                                            }
                                            .labelsHidden()
                                            .frame(width: Self.sliderWidth)
                                        }
                                        divider
                                        row(\.strictness) {
                                            Text("Strictness")
                                            Spacer(minLength: 8)
                                            Slider(value: $gestures.strictness, in: CursorGesturesConfig.strictnessRange, step: 0.05) {
                                                Text("Strictness")
                                            }
                                            .labelsHidden()
                                            .frame(width: Self.sliderWidth)
                                        }
                                        divider
                                        row(\.minimumSize) {
                                            Text("Minimum Size")
                                            Spacer(minLength: 8)
                                            Slider(value: $gestures.minimumSize, in: CursorGesturesConfig.sizeRange, step: 5) {
                                                Text("Minimum Size")
                                            }
                                            .labelsHidden()
                                            .frame(width: Self.sliderWidth)
                                        }
                                        divider
                                        row(\.ignorePostedClicks) {
                                            Toggle("Use Only Clicks from Your Mouse or Trackpad", isOn: $gestures.ignorePostedClicks)
                                        }
                                    }
                                    .rightClickMenuCard()

                                    VStack(spacing: 0) {
                                        HStack(spacing: 8) {
                                            Text("Ignored Apps")
                                            Spacer(minLength: 8)
                                            Button("Add App…") {
                                                if let app = chooseApp() { gestures.ignore(app, true) }
                                            }
                                        }
                                        .padding(.horizontal, RightClickMenuLayout.inset)
                                        .frame(minHeight: RightClickMenuLayout.rowHeight)
                                        .help("Cursor Gestures stay off in these apps for the triggers you pick.")

                                        ForEach(gestures.ignored, id: \.app) { entry in
                                            divider
                                            HStack(spacing: 8) {
                                                Image(nsImage: appIcon(entry.app))
                                                    .resizable()
                                                    .frame(width: 18, height: 18)

                                                Text(verbatim: CursorGestures.appName(entry.app))
                                                    .lineLimit(1)

                                                Spacer(minLength: 6)

                                                Picker("Triggers to Ignore", selection: ignored(entry.app, \.block)) {
                                                    Text("Every Trigger").tag(CursorGestureIgnoredApp.Block.all)
                                                    Text("Mouse Buttons").tag(CursorGestureIgnoredApp.Block.buttons)
                                                    Text("Held Keys").tag(CursorGestureIgnoredApp.Block.keys)
                                                }
                                                .labelsHidden()
                                                .fixedSize()

                                                Picker("Ignore When", selection: ignored(entry.app, \.frontOnly)) {
                                                    Text("In Front").tag(true)
                                                    Text("Under the Pointer").tag(false)
                                                }
                                                .labelsHidden()
                                                .fixedSize()

                                                Button {
                                                    gestures.ignore(entry.app, false)
                                                } label: {
                                                    Image(systemName: "minus.circle.fill")
                                                        .foregroundStyle(.secondary)
                                                }
                                                .buttonStyle(.borderless)
                                                .accessibilityLabel("Remove App")
                                            }
                                            .padding(.horizontal, RightClickMenuLayout.inset)
                                            .frame(minHeight: RightClickMenuLayout.rowHeight)
                                        }
                                    }
                                    .rightClickMenuCard()

                                    Button("Restore Ready-Made Gestures") {
                                        restoring = true
                                    }
                                    .alert("Restore Ready-Made Gestures", isPresented: $restoring) {
                                        Button("Restore") {
                                            change { $0.restoreReadyMade() }
                                        }

                                        Button("Cancel", role: .cancel) {}
                                    } message: {
                                        Text("Ready-made gestures you deleted come back, unless one of your gestures already uses the same shape and trigger.")
                                    }

                                    Text("Hold the trigger keys or button, draw a shape with the pointer and let go to run its action. Esc or any other key cancels the gesture, and so does a left click when repeat is off. With repeat on, left-click while you still hold the trigger to run the last gesture again.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.horizontal, RightClickMenuLayout.inset)
                                case .gestures:
                                    HStack(spacing: 8) {
                                        SearchFieldView(text: $search, prompt: String(localized: "Search"))
                                            .frame(maxWidth: .infinity)

                                        Button("New Gesture") {
                                            GestureEditorWindow.shared.edit(CursorGesture(apps: shown.apps), title: String(localized: "New Gesture"), themes: themes)
                                        }
                                    }

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 6) {
                                            GestureChip(title: String(localized: "All"), selected: shown == .all) {
                                                filter = .all
                                            }

                                            GestureChip(title: String(localized: "All Apps"), selected: shown == .allApps) {
                                                filter = .allApps
                                            }

                                            ForEach(gestures.scopedApps, id: \.self) { app in
                                                GestureChip(title: CursorGestures.appName(app), app: app, selected: shown == .app(app)) {
                                                    filter = .app(app)
                                                }
                                            }
                                        }
                                    }

                                    if gestures.gestures.isEmpty {
                                        Text("Add a gesture, then pick its shape and what it does.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if groups.isEmpty {
                                        Text("No Results for “\(search)”")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        VStack(alignment: .leading, spacing: 16) {
                                            ForEach(groups) { group in
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text(group.family?.title ?? String(localized: "Your Shapes"))
                                                        .font(.headline)

                                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                                                        ForEach(group.items) { gesture in
                                                            GestureCard(gesture: gesture, config: gestures, themes: themes) { on in
                                                                change { config in
                                                                    if let index = config.gestures.firstIndex(where: { $0.id == gesture.id }) {
                                                                        config.gestures[index].enabled = on
                                                                    }
                                                                }
                                                            } edit: {
                                                                GestureEditorWindow.shared.edit(gesture, title: String(localized: "Edit Gesture"), themes: themes)
                                                            } duplicate: {
                                                                var copy = gesture
                                                                copy.id = UUID()
                                                                copy.name = gestures.title(gesture, themes: themes)
                                                                GestureEditorWindow.shared.edit(copy, title: String(localized: "New Gesture"), themes: themes)
                                                            } delete: {
                                                                change { config in config.gestures.removeAll { $0.id == gesture.id } }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                case .shapes:
                                    GestureShapeGallery(config: gestures, scrolls: false, delete: confirmDelete) {
                                        gestures.put($0)
                                    }
                                case .actions:
                                    GestureActionList(actions: CursorGestures.catalogue(gestures, themes: themes), scrolls: false, own: gestures.actions,
                                                      edit: { editing = $0 }, delete: confirmDelete) {
                                        editing = CursorGestures.custom(.shortcut(CursorGestureShortcut(keyCode: 0, flags: 0)), name: "")
                                    }
                                }
                            }
                            .padding(.top, RightClickMenuLayout.headerSpacing - RightClickMenuLayout.blockSpacing)
                            .alert("Delete It?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                                Button("Delete", role: .destructive) {
                                    if let deleting { gestures.remove(deleting) }
                                }

                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Gestures that use “\(deleting.flatMap { gestures.shape($0)?.name ?? gestures.action($0)?.name } ?? "")” stop working until you pick something else for them.")
                            }
                            .sheet(item: $editing) { action in
                                GestureActionEditor(draft: action, isNew: !gestures.actions.contains { $0.id == action.id }) {
                                    gestures.put($0)
                                }
                            }
                        }
                        .disabled(!helperManager.isInstalled)
                    }
                }
                .frame(width: column)
                .padding(.leading, (pane.size.width - column) / 2)
                .padding(.vertical, RightClickMenuLayout.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            helperManager.refreshStatus()
            reload()
            if helperManager.isInstalled {
                CursorGesturesConfig.notifyHelper()
            }
        }
        .onChangeCompat(of: gestures) { edited in
            let latest = CursorGesturesConfig.load()
            var merged = edited
            merged.enabled = latest.enabled
            guard merged != latest else { return }
            merged.save()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorGesturesDidChange)) { _ in
            reload()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in
            reload()
        }
    }

    private func reload() {
        gestures = CursorGesturesConfig.load()
        trusted = FocusFollowsMouseConfig.accessibilityTrusted
    }

    private func change(_ edit: (inout CursorGesturesConfig) -> Void) {
        var latest = CursorGesturesConfig.load()
        edit(&latest)
        latest.save()
        gestures = latest
    }

    private func confirmDelete(_ id: String) {
        if gestures.uses(id) {
            deleting = id
        } else {
            gestures.remove(id)
        }
    }

    private static let sliderWidth: CGFloat = 240

    private var divider: some View {
        Divider()
            .padding(.horizontal, RightClickMenuLayout.inset)
    }

    private func row<Value: Equatable, Control: View>(_ setting: WritableKeyPath<CursorGesturesConfig, Value>,
                                                     resettable: Bool = true,
                                                     @ViewBuilder _ control: () -> Control) -> some View {
        HStack(spacing: 8) {
            control()

            if resettable {
                Button {
                    gestures.reset(setting)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to Default")
                .accessibilityLabel("Reset to Default")
                .opacity(gestures.isDefault(setting) ? 0 : 1)
                .disabled(gestures.isDefault(setting))
                .accessibilityHidden(gestures.isDefault(setting))
            } else {
                Image(systemName: "arrow.counterclockwise")
                    .hidden()
            }
        }
        .toggleStyle(GestureSwitchStyle())
        .padding(.horizontal, RightClickMenuLayout.inset)
        .frame(minHeight: RightClickMenuLayout.rowHeight)
    }

    private func ignored<Value>(_ app: String, _ setting: WritableKeyPath<CursorGestureIgnoredApp, Value>) -> Binding<Value> {
        Binding(get: { (gestures.ignored.first { $0.app == app } ?? CursorGestureIgnoredApp(app: app))[keyPath: setting] },
                set: { value in
                    if let index = gestures.ignored.firstIndex(where: { $0.app == app }) { gestures.ignored[index][keyPath: setting] = value }
                })
    }
}

struct GestureShapePicture: View {
    let points: [CGPoint]
    var clicks = false
    let color: UInt32

    var body: some View {
        Canvas { context, size in
            let line = CursorGestures.resample(points)
            guard line.count > 1 else { return }
            let box = line.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            let width = max(2, min(size.width, size.height) / 22)
            let scale = (min(size.width, size.height) - 4 * width) / max(box.width, box.height, .ulpOfOne)
            let placed = line.map { CGPoint(x: size.width / 2 + ($0.x - box.midX) * scale, y: size.height / 2 - ($0.y - box.midY) * scale) }
            for index in placed.indices.dropFirst() {
                var segment = Path()
                segment.move(to: placed[index - 1])
                segment.addLine(to: placed[index])
                let tint = CursorTrailsPalette.color(at: CGFloat(index) / CGFloat(placed.count - 1), stops: [color, 0xFFFFFF], alpha: 1)
                context.stroke(segment, with: .color(Color(cgColor: tint)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            let dot = width * 2.4
            for (point, tint) in [(placed[placed.count - 1], 0xFFFFFF), (placed[0], color)] {
                context.fill(Path(ellipseIn: CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)),
                             with: .color(Color(cgColor: CursorTrailsPalette.color(at: 0, stops: [tint], alpha: 1))))
            }
        }
        .overlay {
            if clicks {
                Image(systemName: "cursorarrow.click")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(Color(cgColor: CursorTrailsPalette.color(at: 0, stops: [color], alpha: 1)))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 1)
        .accessibilityHidden(true)
    }
}

@MainActor
private func appIcon(_ app: String) -> NSImage {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: app).map { NSWorkspace.shared.icon(forFile: $0.path) }
        ?? NSWorkspace.shared.icon(for: .applicationBundle)
}

private extension View {
    @ViewBuilder
    func scrolling(_ scrolls: Bool) -> some View {
        if scrolls {
            ScrollView { self }
        } else {
            self
        }
    }
}

private struct GestureSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }
}

private struct GestureChip: View {
    let title: String
    var app: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let app {
                    Image(nsImage: appIcon(app))
                        .resizable()
                        .frame(width: 14, height: 14)
                }

                Text(verbatim: title)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct GestureKeyCaps: View {
    let caps: [String]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(caps.indices, id: \.self) { index in
                Text(verbatim: caps[index])
                    .font(.system(size: 10, weight: .medium))
                    .frame(minWidth: 16, minHeight: 16)
                    .padding(.horizontal, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.secondary.opacity(0.5)))
            }
        }
        .fixedSize()
    }
}

private struct GestureTriggerChip: View {
    let trigger: CursorGestureTrigger

    var body: some View {
        let glyphs = CursorGestureKeys.glyphs(trigger.keys)
        HStack(spacing: 3) {
            if !glyphs.isEmpty {
                Text(verbatim: glyphs)
            }

            if trigger.button != nil {
                Image(systemName: "computermouse")
            }

            if trigger.twoFinger {
                Image(systemName: "hand.draw")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor.opacity(0.15)))
        .help(trigger.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trigger.label)
    }
}

private struct GestureCardFace: View {
    let gesture: CursorGesture
    let config: CursorGesturesConfig
    let themes: [(id: String, name: String)]
    var titleInset: CGFloat = 0
    @State private var layout = shortcutLayout()

    var body: some View {
        let actions = config.actions(gesture, themes: themes)
        HStack(alignment: .top, spacing: 10) {
            GestureShapePicture(points: config.shape(gesture.shape)?.points ?? [], clicks: gesture.shape == CursorGestures.clickShape.id, color: config.lineColor)
                .frame(width: 52, height: 52)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: config.title(gesture, themes: themes))
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.trailing, titleInset)

                HStack(spacing: 4) {
                    ForEach(gesture.triggers.indices, id: \.self) { index in
                        GestureTriggerChip(trigger: gesture.triggers[index])
                    }
                }

                HStack(spacing: 6) {
                    Text(verbatim: actions.map(\.name).joined(separator: ", "))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)

                    if actions.count == 1, let only = actions.first {
                        GestureKeyCaps(caps: only.caps(layout))
                    }
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .inputSourceChanged)) { _ in layout = shortcutLayout() }
    }
}

private struct GestureCard: View {
    let gesture: CursorGesture
    let config: CursorGesturesConfig
    let themes: [(id: String, name: String)]
    let toggle: (Bool) -> Void
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        let title = config.title(gesture, themes: themes)
        Button(action: edit) {
            GestureCardFace(gesture: gesture, config: config, themes: themes, titleInset: 40)
                .opacity(gesture.enabled ? 1 : 0.55)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.09 : 0.045)))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Toggle(isOn: Binding(get: { gesture.enabled }, set: toggle)) {
                Text(verbatim: title)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .padding(10)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu {
            Button("Edit", action: edit)
            Button("Duplicate", action: duplicate)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
        .help(config.summary(gesture, themes: themes))
    }
}

private struct GestureShapeGallery: View {
    let config: CursorGesturesConfig
    var scrolls = true
    var selected = ""
    var taken: Set<String> = []
    var pick: (String) -> Void = { _ in }
    var delete: ((String) -> Void)?
    let save: (CursorGestureShape) -> Void
    @State private var search = ""
    @State private var family: String?
    @State private var drawing: CursorGestureShape?

    var body: some View {
        let shown = config.shapeGroups().contains { title($0) == family } ? family : nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SearchFieldView(text: $search, prompt: String(localized: "Search"))
                    .frame(maxWidth: .infinity)

                Button("Draw New") {
                    drawing = CursorGestureShape()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    GestureChip(title: String(localized: "All"), selected: shown == nil) {
                        family = nil
                    }

                    ForEach(config.shapeGroups()) { group in
                        GestureChip(title: title(group), selected: shown == title(group)) {
                            family = title(group)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(config.shapeGroups(search: search).filter { shown == nil || title($0) == shown }) { group in
                    Text(title(group))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                        ForEach(group.items) { shape in
                            ThemeCard(name: shape.name, isApplied: shape.id == selected,
                                      help: taken.contains(shape.id) ? String(localized: "Another gesture uses this shape with the same trigger.") : nil) {
                                pick(shape.id)
                            } preview: {
                                GestureShapePicture(points: shape.points, clicks: shape.id == CursorGestures.clickShape.id, color: config.lineColor)
                                    .frame(height: 56)
                            }
                            .overlay(alignment: .topLeading) {
                                if taken.contains(shape.id) {
                                    Text("In use")
                                        .font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .contextMenu {
                                if let delete, shape.family == nil {
                                    Button("Rename or Redraw…") {
                                        drawing = shape
                                    }

                                    Button("Delete") {
                                        delete(shape.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .scrolling(scrolls)
        }
        .sheet(item: $drawing) { shape in
            GestureShapeRecorder(shape: shape, config: config, save: save)
        }
    }

    private func title(_ group: CursorGestureGroup<CursorGestureShape>) -> String {
        group.family?.title ?? String(localized: "Your Shapes")
    }
}

private struct GestureActionList: View {
    let actions: [CursorGestureAction]
    var scrolls = true
    var pick: (CursorGestureAction) -> Void = { _ in }
    var own: [CursorGestureAction] = []
    var edit: (CursorGestureAction) -> Void = { _ in }
    var delete: (String) -> Void = { _ in }
    var add: (() -> Void)?
    @State private var search = ""
    @State private var category: CursorGestureCategory?
    @State private var layout = shortcutLayout()

    var body: some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let current = CursorGestures.listed(category, in: actions)
        let shown = actions.filter { action in
            (current == nil || action.category == current) &&
                (query.isEmpty || action.name.localizedCaseInsensitiveContains(query) || action.caption(layout).localizedCaseInsensitiveContains(query))
        }
        let categories = CursorGestureCategory.allCases.filter { item in shown.contains { $0.category == item } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SearchFieldView(text: $search, prompt: String(localized: "Search"))
                    .frame(maxWidth: .infinity)

                if let add {
                    Button("New Custom Action", action: add)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    GestureChip(title: String(localized: "All"), selected: current == nil) {
                        category = nil
                    }

                    ForEach(CursorGestureCategory.allCases.filter { item in actions.contains { $0.category == item } }, id: \.self) { item in
                        GestureChip(title: item.title, selected: current == item) {
                            category = item
                        }
                    }
                }
            }

            if scrolls {
                List {
                    ForEach(categories, id: \.self) { item in
                        Section(item.title) {
                            ForEach(shown.filter { $0.category == item }) { action in
                                row(action)
                            }
                        }
                    }
                }
            } else {
                ForEach(categories, id: \.self) { item in
                    let items = shown.filter { $0.category == item }
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(items) { action in
                            if action.id != items.first?.id {
                                Divider()
                                    .padding(.horizontal, RightClickMenuLayout.inset)
                            }
                            row(action)
                                .padding(.horizontal, RightClickMenuLayout.inset)
                                .frame(minHeight: RightClickMenuLayout.rowHeight)
                        }
                    }
                    .rightClickMenuCard()
                }
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .inputSourceChanged)) { _ in layout = shortcutLayout() }
    }

    private func row(_ action: CursorGestureAction) -> some View {
        Button {
            pick(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: action.name)

                    Text(verbatim: action.caption(layout))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                GestureKeyCaps(caps: action.caps(layout))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if own.contains(where: { $0.id == action.id }) {
                Button("Edit") {
                    edit(action)
                }

                Button("Delete", role: .destructive) {
                    delete(action.id)
                }
            }
        }
    }
}

private struct GestureActionEditor: View {
    @State var draft: CursorGestureAction
    let isNew: Bool
    let save: (CursorGestureAction) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Custom Action" : "Edit Your Action")
                .font(.headline)

            Picker("What It Does", selection: Binding(
                get: {
                    switch draft.kind {
                    case .text: return 1
                    case .app: return 2
                    case .website: return 3
                    default: return 0
                    }
                },
                set: { value in
                    let kinds: [CursorGestureKind] = [.shortcut(CursorGestureShortcut(keyCode: 0, flags: 0)), .text(""), .app(""), .website("")]
                    remake(kinds[value])
                }
            )) {
                Text("Keyboard Shortcut").tag(0)
                Text("Typed Text").tag(1)
                Text("App").tag(2)
                Text("Website").tag(3)
            }
            .pickerStyle(.menu)
            .fixedSize()

            switch draft.kind {
            case .shortcut(let shortcut):
                GestureShortcutRecorder(shortcut: shortcut) { remake(.shortcut($0)) }
            case .text(let text):
                TextField("Typed Text", text: Binding(get: { text }, set: { remake(.text(String($0.prefix(CursorGestures.textLimit)))) }),
                          axis: .vertical)
                    .lineLimit(3...6)

                Text("Up to 500 characters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .app(let path):
                Button {
                    guard let url = NSOpenPanel.choose(applications: true) else { return }
                    if draft.name.isEmpty { draft.name = FileManager.default.displayName(atPath: url.path) }
                    remake(.app(url.path))
                } label: {
                    if path.isEmpty {
                        Text("Pick an App…")
                    } else {
                        Text(verbatim: draft.detail)
                    }
                }
            case .website(let address):
                TextField("Website Address", text: Binding(get: { address }, set: { remake(.website($0)) }))
            default:
                EmptyView()
            }

            TextField("Name", text: $draft.name)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func remake(_ kind: CursorGestureKind) {
        draft = CursorGestures.custom(kind, name: draft.name, id: draft.id)
    }
}

private struct GestureShortcutRecorder: View {
    let shortcut: CursorGestureShortcut
    let record: (CursorGestureShortcut) -> Void
    @State private var monitor: Any?
    @State private var layout = shortcutLayout()

    var body: some View {
        HStack {
            Button {
                monitor == nil ? start() : stop()
            } label: {
                if monitor != nil {
                    Text("Press shortcut…")
                } else if CursorGestureKeys.recordable(shortcut.keyCode, NSEvent.ModifierFlags(rawValue: shortcut.flags)) {
                    Text(verbatim: CursorGestureKeys.label(shortcut, layout: layout))
                } else {
                    Text("Record Shortcut")
                }
            }

            if monitor != nil {
                Text("Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in stop() }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .inputSourceChanged)) { _ in layout = shortcutLayout() }
    }

    private func start() {
        monitor = EditorTextShortcutCoordinator.addRecorder { event in
            switch CursorGestureKeys.recorded(event.keyCode, event.modifierFlags) {
            case .cancel:
                stop()
            case .refuse:
                NSSound.beep()
            case .shortcut(let shortcut):
                record(shortcut)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { EditorTextShortcutCoordinator.removeRecorder(monitor) }
        monitor = nil
    }
}

final class GestureEditorWindow: NSWindowController, NSWindowDelegate {
    static let shared = GestureEditorWindow()
    var draft = CursorGesture()
    private var original = CursorGesture()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 840),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 785, height: 560)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard draft != original else { return true }
        confirmDiscard { sender.close() }
        return false
    }

    private func confirmDiscard(then discard: @escaping () -> Void) {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Unsaved Changes")
        alert.informativeText = String(localized: "Your changes will be discarded if you don't save them.")
        alert.addButton(withTitle: String(localized: "Keep Editing"))
        alert.addButton(withTitle: String(localized: "Discard")).hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            guard response == .alertSecondButtonReturn else { return }
            self.draft = self.original
            discard()
        }
    }

    func edit(_ gesture: CursorGesture, title: String, themes: [(id: String, name: String)]) {
        guard let window else { return }
        if window.isVisible || window.isMiniaturized, draft != original {
            return confirmDiscard { self.edit(gesture, title: title, themes: themes) }
        }
        (original, draft) = (gesture, gesture)
        let frame = window.frame
        let content = NSHostingController(rootView: GestureEditor(draft: gesture, themes: themes))
        content.sizingOptions = [.minSize]
        window.contentViewController = content
        window.title = title
        if window.isVisible {
            window.setFrame(frame, display: true)
        } else {
            window.setContentSize(NSSize(width: 1200, height: 840))
            window.center()
        }
        ModalWindowCoordinator.shared.register(window, as: .modal)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct GestureEditor: View {
    @State private var draft: CursorGesture
    let themes: [(id: String, name: String)]
    @State private var config = CursorGesturesConfig.load()
    @State private var chooseApps: Bool
    @State private var warning: String?
    @State private var step = CursorGestureEditorStep.shape

    init(draft: CursorGesture, themes: [(id: String, name: String)]) {
        _draft = State(initialValue: draft)
        _chooseApps = State(initialValue: !draft.apps.isEmpty)
        self.themes = themes
    }

    private var catalogue: [CursorGestureAction] {
        CursorGestures.catalogue(config, themes: themes)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(CursorGestureEditorStep.allCases.enumerated()), id: \.element) { index, item in
                        Button {
                            step = item
                        } label: {
                            HStack(spacing: 12) {
                                Text(index + 1, format: .number)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(item == step ? Color.white : Color.primary)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(item == step ? Color.accentColor : Color.primary.opacity(0.1)))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.headline)
                                        .lineLimit(1)

                                    Text(verbatim: config.value(item, of: draft, themes: themes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(item == step ? Color(nsColor: .controlBackgroundColor) : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(item == step ? Color.primary.opacity(0.12) : Color.clear))
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(item == step ? .isSelected : [])
                    }

                    Spacer(minLength: 12)

                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GestureCardFace(gesture: draft, config: config, themes: themes)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 20)
                .frame(width: 268)
                .frame(maxHeight: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(.title2.weight(.semibold))

                        Text(step.note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    switch step {
                    case .shape:
                        GestureShapeGallery(config: config, selected: draft.shape, taken: config.taken(by: draft), pick: { draft.shape = $0 }) { shape in
                            config.put(shape)
                            draft.shape = shape.id
                            var latest = CursorGesturesConfig.load()
                            latest.put(shape)
                            latest.save()
                        }
                    case .trigger:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(draft.triggers.indices, id: \.self) { index in
                                    GestureTriggerEditor(trigger: trigger(index), remove: draft.triggers.count > 1 ? { draft.triggers.remove(at: index) } : nil)
                                }

                                Button("Add Trigger") {
                                    draft.triggers.append(CursorGestureTrigger())
                                }
                            }
                            .frame(width: 460, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    case .actions:
                        if !draft.steps.isEmpty {
                            List {
                                ForEach(draft.steps) { item in
                                    GestureStepRow(step: binding(for: item.id), action: catalogue.first { $0.id == item.action },
                                                   first: item.id == draft.steps.first?.id) {
                                        draft.steps.removeAll { $0.id == item.id }
                                    }
                                }
                                .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                            }
                            .frame(height: 160)
                        }

                        GestureActionList(actions: catalogue) { action in
                            draft.steps.append(CursorGestureStep(action: action.id))
                        }
                    case .details:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Name", text: $draft.name, prompt: Text(verbatim: config.title(draft, themes: themes)))

                                Picker("Works In", selection: $chooseApps) {
                                    Text("All Apps").tag(false)
                                    Text("Chosen Apps").tag(true)
                                }
                                .pickerStyle(.radioGroup)
                                .lineLimit(1)

                                if chooseApps {
                                    ForEach(draft.apps, id: \.self) { app in
                                        HStack(spacing: 8) {
                                            Image(nsImage: appIcon(app))
                                                .resizable()
                                                .frame(width: 18, height: 18)

                                            Text(verbatim: CursorGestures.appName(app))
                                                .lineLimit(1)

                                            Spacer(minLength: 6)

                                            Button {
                                                draft.apps.removeAll { $0 == app }
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.borderless)
                                            .accessibilityLabel("Remove App")
                                        }
                                    }

                                    Button("Add App…") {
                                        if let app = chooseApp(), !draft.apps.contains(app) {
                                            draft.apps.append(app)
                                        }
                                    }
                                }
                            }
                            .frame(width: 460, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()

            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(Array(config.summaryParts(draft, themes: themes).enumerated()), id: \.offset) { index, part in
                        if index > 0 {
                            Image(systemName: "arrow.forward")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Text(verbatim: part)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(index == 0 ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06)))
                    }
                }
                .font(.callout)
                .help(config.summary(draft, themes: themes))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(config.summary(draft, themes: themes))

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button("Cancel") {
                        GestureEditorWindow.shared.window?.performClose(nil)
                    }
                    .keyboardShortcut(.cancelAction)

                    if let next = step.next {
                        Button("Next: \(next.title)") {
                            step = next
                        }
                    }

                    Button("Save") {
                        save(replacing: false)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!config.canSave(draft) || chooseApps && draft.apps.isEmpty)
                }
                .fixedSize()
            }
            .padding(16)
        }
        .frame(minWidth: 785, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .alert(warning ?? "", isPresented: Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })) {
            Button("Replace", role: .destructive) {
                save(replacing: true)
            }

            Button("Cancel", role: .cancel) {}
        }
        .onChangeCompat(of: chooseApps) { chosen in
            if !chosen { draft.apps = [] }
        }
        .onChangeCompat(of: draft) { GestureEditorWindow.shared.draft = $0 }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorGesturesDidChange)) { _ in
            config = CursorGesturesConfig.load()
        }
    }

    private func trigger(_ index: Int) -> Binding<CursorGestureTrigger> {
        Binding(get: { draft.triggers.indices.contains(index) ? draft.triggers[index] : CursorGestureTrigger() },
                set: { if draft.triggers.indices.contains(index) { draft.triggers[index] = $0 } })
    }

    private func binding(for id: UUID) -> Binding<CursorGestureStep> {
        Binding(get: { draft.steps.first { $0.id == id } ?? CursorGestureStep(action: "") },
                set: { step in
                    if let index = draft.steps.firstIndex(where: { $0.id == id }) { draft.steps[index] = step }
                })
    }

    private func save(replacing: Bool) {
        var latest = CursorGesturesConfig.load()
        if !replacing, let clash = latest.conflictWarning(draft, themes: themes) {
            warning = clash
            return
        }
        latest.put(draft)
        latest.save()
        GestureEditorWindow.shared.close()
    }
}

private struct GestureTriggerEditor: View {
    @Binding var trigger: CursorGestureTrigger
    let remove: (() -> Void)?
    var buttonsOnly = false

    private static let keys: [(NSEvent.ModifierFlags, String)] = [(.function, "fn"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(Self.keys.indices, id: \.self) { index in
                        Toggle(isOn: Binding(
                            get: { NSEvent.ModifierFlags(rawValue: trigger.keys).contains(Self.keys[index].0) },
                            set: { on in
                                var keys = NSEvent.ModifierFlags(rawValue: trigger.keys)
                                if on { keys.insert(Self.keys[index].0) } else { keys.remove(Self.keys[index].0) }
                                trigger.keys = keys.rawValue
                            }
                        )) {
                            Text(verbatim: Self.keys[index].1)
                                .frame(minWidth: 18)
                        }
                        .toggleStyle(.button)
                    }

                    Spacer(minLength: 6)

                    if let remove {
                        Button(action: remove) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove Trigger")
                    }
                }

                Picker("Draw With", selection: Binding(
                    get: { trigger.twoFinger ? 4 : min(trigger.button ?? 0, 3) },
                    set: { value in
                        trigger.button = value == 3 ? max(trigger.button ?? 3, 3) : (1...2).contains(value) ? value : nil
                        trigger.twoFinger = value == 4
                        if value == 4 { trigger.device = .trackpad }
                    }
                )) {
                    if !buttonsOnly {
                        Text("Held Keys").tag(0)
                    }
                    Text("Right Button").tag(1)
                    Text("Middle Button").tag(2)
                    Text("Side Button").tag(3)
                    if !buttonsOnly {
                        Text("Two Fingers").tag(4)
                    }
                }
                .lineLimit(1)

                if let button = trigger.button, button >= 3 {
                    GestureButtonField(button: button) { trigger.button = $0 }
                }

                Picker("Device", selection: $trigger.device) {
                    Text("Mouse").tag(CursorGestureDevice.mouse)
                    Text("Trackpad").tag(CursorGestureDevice.trackpad)
                    Text("Both").tag(CursorGestureDevice.both)
                }
                .pickerStyle(.segmented)
                .lineLimit(1)
                .disabled(trigger.twoFinger)
            }
            .padding(4)
        }
    }
}

private struct GestureButtonField: View {
    let button: Int
    let name: (Int) -> Void
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(CursorGestureTrigger(button: button).label, systemImage: "computermouse")
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(monitor == nil ? Color.primary.opacity(0.05) : Color.accentColor.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(monitor == nil ? Color.clear : Color.accentColor))
                .contentShape(Rectangle())
                .onHover { $0 ? start() : stop() }
                .onDisappear(perform: stop)

            Text("Point here and click the side button you want.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard event.buttonNumber >= 3 else { return event }
            name(event.buttonNumber)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct GestureStepRow: View {
    @Binding var step: CursorGestureStep
    let action: CursorGestureAction?
    let first: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)

            Toggle(isOn: $step.enabled) {
                Text(verbatim: action?.name ?? "")
            }
            .labelsHidden()

            Image(systemName: action?.icon ?? "questionmark")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            Text(verbatim: action?.name ?? "")
                .lineLimit(1)

            Spacer(minLength: 6)

            if !first {
                Stepper(value: Binding(get: { step.wait ?? 0 }, set: { step.wait = $0 > 0 ? $0 : nil }), in: 0...5000, step: 50) {
                    Text("Wait \(Duration.milliseconds(step.wait ?? 0).formatted(.units(allowed: [.milliseconds], width: .abbreviated)))")
                        .font(.caption)
                }
            }

            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove Step")
        }
        .opacity(step.enabled ? 1 : 0.5)
    }
}

private struct GestureShapeRecorder: View {
    @State var shape: CursorGestureShape
    let config: CursorGesturesConfig
    let save: (CursorGestureShape) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas: [CGPoint] = []
    @State private var drawing = false
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.4))
                Path { $0.addLines(canvas) }
                    .stroke(Color(cgColor: CursorTrailsPalette.color(at: 0, stops: [config.lineColor], alpha: 1)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if canvas.isEmpty, testing {
                    Text("Draw the shape again to test it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if canvas.isEmpty, shape.points.isEmpty {
                    Text("Draw the shape here in one stroke.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if canvas.isEmpty {
                    GestureShapePicture(points: shape.points, color: config.lineColor)
                        .padding(40)
                }
            }
            .frame(height: 286)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !drawing {
                        canvas = []
                        drawing = true
                    }
                    canvas.append(value.location)
                }
                .onEnded { _ in
                    drawing = false
                    if testing { return }
                    if let points = CursorGestures.recorded(canvas) {
                        shape.points = points
                    } else {
                        canvas = []
                    }
                })

            if testing {
                if !drawing, !canvas.isEmpty {
                    if let score = config.score(canvas, as: shape) {
                        if score >= config.strictness {
                            Text("Matches · \(CursorGestures.percent(score))%")
                                .foregroundStyle(Color.green)
                        } else {
                            Text("Does Not Match · \(CursorGestures.percent(score))%")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Too small to match.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                TextField("Shape Name", text: $shape.name)

                if !shape.points.isEmpty, !shape.name.trimmingCharacters(in: .whitespaces).isEmpty, !config.canSave(shape) {
                    Text("Another shape has this name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Direction Counts", isOn: $shape.directional)
            }

            HStack {
                Spacer()

                if testing {
                    Button("Back") {
                        canvas = []
                        testing = false
                    }
                } else {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Next & Test") {
                        canvas = []
                        testing = true
                    }
                    .disabled(!config.canSave(shape))
                }

                Button("Save") {
                    save(shape)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!config.canSave(shape))
            }
        }
        .padding(16)
        .frame(width: 546)
    }
}

@MainActor
private func chooseApp() -> String? {
    NSOpenPanel.choose(applications: true).flatMap({ Bundle(url: $0)?.bundleIdentifier })
}

extension AccessWindowController {
    static let cursorGestures = AccessWindowController(title: String(localized: "Cursor Gestures")) {
        NSHostingController(rootView: CursorGesturesAccessView())
    }
}

private struct CursorGesturesAccessView: View {
    @State private var trusted = FocusFollowsMouseConfig.accessibilityTrusted
    @State private var didRequest = false
    private let waitTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        AccessDialog(title: Text("Allow Accessibility Access")) {
            Text("MaCursorHelper needs Accessibility access to see the keys you hold, to hold back the mouse buttons and two-finger scrolls that draw a gesture, and to run its action. Choose Allow for Accessibility, then turn on MaCursorHelper in Privacy & Security → Accessibility.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if trusted {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.green)

                Button("Let’s Go!") {
                    CursorGesturesConfig.setEnabled(true)
                    AccessWindowController.cursorGestures.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                if didRequest {
                    Text("Waiting for access. This window updates as soon as MaCursorHelper is allowed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button("Not Now") {
                        CursorGesturesConfig.setEnabled(false)
                        AccessWindowController.cursorGestures.dismiss()
                    }

                    Button("Allow for Accessibility") {
                        didRequest = true
                        FocusFollowsMouseConfig.requestAccessibility()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard AccessWindowController.cursorGestures.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(waitTicker) { _ in
            guard !trusted, AccessWindowController.cursorGestures.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(ModalWindowCoordinator.shared.activeModalDidChange) { _ in
            AccessWindowController.cursorGestures.reanchor()
        }
    }

    private func refresh() {
        CursorGesturesConfig.notifyHelper()
        trusted = FocusFollowsMouseConfig.accessibilityTrusted
    }
}

struct TranslatorTriggerEditor: View {
    @Binding var trigger: CursorGestureTrigger

    var body: some View {
        GestureTriggerEditor(trigger: $trigger, remove: nil, buttonsOnly: true)
    }
}
