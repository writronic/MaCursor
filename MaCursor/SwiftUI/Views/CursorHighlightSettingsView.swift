import SwiftUI

extension CursorHighlightLook {
    var title: String {
        switch self {
        case .ripple: return String(localized: "Ripple")
        case .ring: return String(localized: "Ring")
        case .pulse: return String(localized: "Pulse")
        case .circle: return String(localized: "Circle (Click Ripple)")
        case .burst: return String(localized: "Burst")
        }
    }
}

extension CursorHighlightConfig {
    @MainActor
    static func tap() {
        let helperManager = HelperToolManager.shared
        var config = load()
        guard let enabled = CursorTrailsConfig.toggledValue(enabled: config.enabled, helperInstalled: helperManager.isInstalled,
                                                            running: helperManager.isRunning) else { return }
        config.enabled = enabled
        config.save()
    }
}

struct CursorHighlightSettingsView: View {
    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var highlight = CursorHighlightConfig.load()
    @State private var screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    @State private var trusted = FocusFollowsMouseConfig.accessibilityTrusted

    var body: some View {
        CursorHighlightPage(highlight: highlight, installed: helperManager.isInstalled, running: helperManager.isRunning,
                            screenRecording: screenRecording, trusted: trusted) { next in
            highlight = next
            next.save()
        }
        .onAppear {
            helperManager.refreshStatus()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorHighlightDidChange)) { _ in
            highlight = CursorHighlightConfig.load()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorTranslatorStatusDidChange)) { _ in
            screenRecording = CursorTranslatorConfig.screenRecordingAllowed
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACFocusFollowsMouseStatusDidChange)) { _ in
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenRecording = CursorTranslatorConfig.screenRecordingAllowed
            trusted = FocusFollowsMouseConfig.accessibilityTrusted
            if highlight.showsMagnifier, !screenRecording, helperManager.isInstalled { CursorHighlightConfig.notifyHelper() }
        }
    }
}

extension AccessWindowController {
    static let cursorMagnifier = AccessWindowController(title: String(localized: "Magnifier")) {
        NSHostingController(rootView: CursorMagnifierAccessView())
    }
}

private struct CursorMagnifierAccessView: View {
    @State private var screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    @State private var didRequest = false
    private let waitTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        AccessDialog(title: Text("Magnifier")) {
            Text("Screen Recording")
                .font(.headline)

            Group {
                if SystemSettingsPane.screenRecordingHasAudio() {
                    Text("MaCursor needs Screen Recording access to enlarge the screen around the pointer. Nothing is saved. Choose Allow Screen Recording, then turn on MaCursor in Privacy & Security → Screen & System Audio Recording.")
                } else {
                    Text("MaCursor needs Screen Recording access to enlarge the screen around the pointer. Nothing is saved. Choose Allow Screen Recording, then turn on MaCursor in Privacy & Security → Screen Recording.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if screenRecording {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.green)

                Button("Let’s Go!") {
                    CursorHighlightConfig.set(\.magnifier, true)
                    AccessWindowController.cursorMagnifier.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                if didRequest {
                    Text("Waiting for access. This window updates as soon as MaCursor is allowed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button("Not Now") {
                        CursorHighlightConfig.set(\.magnifier, false)
                        AccessWindowController.cursorMagnifier.dismiss()
                    }

                    Button("Allow Screen Recording") {
                        didRequest = true
                        CursorTranslatorConfig.requestScreenRecording()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACCursorTranslatorStatusDidChange)) { _ in read() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            guard AccessWindowController.cursorMagnifier.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(waitTicker) { _ in
            guard !screenRecording, AccessWindowController.cursorMagnifier.window?.isVisible == true else { return }
            refresh()
        }
        .onReceive(ModalWindowCoordinator.shared.activeModalDidChange) { _ in
            AccessWindowController.cursorMagnifier.reanchor()
        }
    }

    private func refresh() {
        CursorHighlightConfig.notifyHelper()
        read()
    }

    private func read() {
        screenRecording = CursorTranslatorConfig.screenRecordingAllowed
    }
}

struct CursorHighlightPage: View {
    let highlight: CursorHighlightConfig
    let installed: Bool
    let running: Bool
    var screenRecording = true
    var trusted = true
    let save: (CursorHighlightConfig) -> Void

    private var highlightOn: Bool {
        CursorTrailsConfig.isOn(enabled: highlight.enabled, running: running)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Group {
                FeatureOnOffBox(title: String(localized: "Cursor Highlight"),
                                subtitle: String(localized: "Dims the screen around the pointer and shows a ripple where you click."),
                                symbol: "cursorarrow.click.2", tint: .orange, isOn: Binding(
                                    get: { highlightOn },
                                    set: { _ in
                                        guard let enabled = CursorTrailsConfig.toggledValue(enabled: highlight.enabled, helperInstalled: installed,
                                                                                            running: running) else { return }
                                        change { $0.enabled = enabled }
                                    }
                                ))
            }
            .disabled(!installed)

            if !installed {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)

                    Text("Cursor Highlight requires the Helper Tool. You can install it from General → Helper Tool.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .featureNotice()
            }
        }
    }

    var body: some View {
        FeaturePageFrame(header: {
            header
        }, pane: {
            Form {
                if highlightOn {
                    if !highlight.clicks.isEmpty && !trusted {
                        FeatureSection {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)

                                Text("Accessibility access is missing. Allow MaCursorHelper in Privacy & Security → Accessibility.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 6)

                                Button("Open System Settings") {
                                    FocusFollowsMouseConfig.requestAccessibility()
                                }
                            }
                        }
                    }

                    FeatureSection {
                        Toggle("Spotlight (Cursor Highlight)", isOn: flag(\.spotlight))
                            .searchAnchor("hlSpot")
                        trigger(\.spotlightKey, \.spotlightClick)
                        if highlight.spotlight {
                            slider("Size", \.size, CursorHighlightConfig.sizes, step: 10)
                            slider("Dim", \.dim, CursorHighlightConfig.dims, step: 5)
                                .disabled(highlight.flashlight)
                                .searchAnchor("hlDim")
                            slider("Soft Edge", \.edge, CursorHighlightConfig.edges, step: 5)
                                .searchAnchor("hlEdge")
                            colour("Color", \.color)
                                .searchAnchor("hlColor")
                            Toggle("Flashlight Mode", isOn: flag(\.flashlight))
                                .searchAnchor("hlFlash")
                            trigger(\.flashlightKey, \.flashlightClick)
                        }
                    }

                    FeatureSection {
                        Toggle("Click Ripple", isOn: flag(\.ripple))
                            .searchAnchor("hlRipple")
                        if highlight.ripple {
                            Picker("Look", selection: Binding(get: { highlight.look }, set: { look in change { $0.look = look } })) {
                                ForEach(CursorHighlightLook.allCases, id: \.self) { look in
                                    Text(look.title).tag(look)
                                }
                            }
                            .pickerStyle(.menu)
                            .searchAnchor("hlLook")
                            slider("Size", \.rippleSize, CursorHighlightConfig.rippleSizes, step: 2)
                            Slider(value: Binding(get: { highlight.grow }, set: { grow in change { $0.grow = grow } }),
                                   in: CursorHighlightConfig.grows, step: 0.5) {
                                Text("Grow Size")
                            }
                            .searchAnchor("hlGrow")
                            if highlight.look.drawsLine {
                                slider("Line Width", \.lineWidth, CursorHighlightConfig.lineWidths, step: 1)
                                    .searchAnchor("hlLine")
                            }
                            slider("Opacity", \.opacity, CursorHighlightConfig.opacities, step: 5)
                                .searchAnchor("hlOpacity")
                            colour("Left Click", \.leftColor)
                                .searchAnchor("hlLeft")
                            colour("Right Click", \.rightColor)
                                .searchAnchor("hlRight")
                        }
                    }

                    FeatureSection {
                        Toggle("Magnifier", isOn: Binding(get: { highlight.magnifier }, set: { on in
                            change { next in
                                next.magnifier = on
                                next = CursorMagnifier.filled(next)
                            }
                        }))
                        .searchAnchor("hlMag")
                        trigger(\.magnifierKey, \.magnifierClick)
                        if highlight.magnifier {
                            if !screenRecording {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)

                                    Group {
                                        if SystemSettingsPane.screenRecordingHasAudio() {
                                            Text("Screen Recording access is missing. Allow MaCursor in Privacy & Security → Screen & System Audio Recording.")
                                        } else {
                                            Text("Screen Recording access is missing. Allow MaCursor in Privacy & Security → Screen Recording.")
                                        }
                                    }
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 6)

                                    Button("Open System Settings") {
                                        CursorTranslatorConfig.requestScreenRecording()
                                    }
                                }
                            }
                            Slider(value: Binding(get: { highlight.zoom }, set: { zoom in change { $0.zoom = zoom } }),
                                   in: CursorHighlightConfig.zooms, step: 0.5) {
                                Text("Zoom")
                            }
                            .searchAnchor("hlZoom")
                            slider("Size", \.lens, CursorHighlightConfig.lenses, step: 10)
                        }
                    }

                    FeatureSection {
                        LabeledContent("Shortcut") {
                            KeyRecorderView(shortcut: Binding(get: { highlight.shortcut }, set: { key in change { $0.shortcut = key } }),
                                            isTaken: { CursorScreenshot.refuses($0, held: Self.heldBefore + [CursorShakerConfig.load().shortcut].compactMap { $0 } + highlight.keys(besides: \.shortcut)) },
                                            isShadowed: highlight.shortcut.map { CursorScreenshot.refuses($0, held: Self.heldBefore) } ?? false)
                        }
                        .searchAnchor("hlKey")
                    }
                }
            }
            .formStyle(.grouped)
        })
    }

    private static var heldBefore: [KeyboardShortcutData] {
        MACFavoriteKeys(MACPreferences.value(forKey: MACPreferences.favoriteCursorsKey))
    }

    private func trigger(_ field: WritableKeyPath<CursorHighlightConfig, KeyboardShortcutData?>, _ click: WritableKeyPath<CursorHighlightConfig, CursorGestureTrigger>) -> some View {
        CursorTriggerRows(trigger: Binding(
            get: { CursorTrigger(key: highlight[keyPath: field], click: highlight[keyPath: click],
                                 shadowed: highlight[keyPath: field].map { highlight.heldElsewhere($0, besides: field) } ?? false) },
            set: { chosen in
                change {
                    $0[keyPath: field] = chosen.key
                    $0[keyPath: click] = chosen.click
                }
            }
        ), isTaken: { highlight.isTaken($0, key: field, click: click) }, window: ModalWindowCoordinator.shared.resolvedMainWindow)
    }

    private func change(_ edit: (inout CursorHighlightConfig) -> Void) {
        var next = highlight
        edit(&next)
        guard next != highlight else { return }
        save(next)
    }

    private func flag(_ key: WritableKeyPath<CursorHighlightConfig, Bool>) -> Binding<Bool> {
        Binding(get: { highlight[keyPath: key] }, set: { value in change { $0[keyPath: key] = value } })
    }

    private func slider(_ title: LocalizedStringKey, _ key: WritableKeyPath<CursorHighlightConfig, Int>, _ range: ClosedRange<Int>, step: Double) -> some View {
        Slider(value: Binding(get: { Double(highlight[keyPath: key]) }, set: { value in change { $0[keyPath: key] = Int(value.rounded()) } }),
               in: Double(range.lowerBound)...Double(range.upperBound), step: step) {
            Text(title)
        }
    }

    private func colour(_ title: LocalizedStringKey, _ key: WritableKeyPath<CursorHighlightConfig, UInt32>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { CursorTrailsPalette.color(at: 0, stops: [highlight[keyPath: key]], alpha: 1) },
            set: { color in change { $0[keyPath: key] = CursorGestures.hex(color) } }
        ), supportsOpacity: false)
    }
}

struct FollowReduceMotionSection: View {
    private let preferences: MACPreferences.Operations
    @State private var follows: Bool

    init(preferences: MACPreferences.Operations = .live) {
        self.preferences = preferences
        _follows = State(initialValue: MACPreferences.flag(MACPreferences.followReduceMotionKey, operations: preferences))
    }

    var body: some View {
        FeatureSection(footer: "When Reduce motion is on in System Settings, Cursor Highlight and Cursor Trails stay hidden.") {
            Toggle("Follow Reduce Motion", isOn: Binding(get: { follows }, set: { on in
                follows = on
                Self.set(on)
            }))
            .searchAnchor("setMotion")
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorSettingsDidReset)) { _ in
            follows = MACPreferences.flag(MACPreferences.followReduceMotionKey, operations: preferences)
        }
    }

    static func set(_ on: Bool) {
        MACPreferences.setFlag(on, forKey: MACPreferences.followReduceMotionKey)
        notifyHelper()
    }

    static func notifyHelper() {
        CursorTrailsConfig.notifyHelper()
        CursorHighlightConfig.notifyHelper()
    }
}
