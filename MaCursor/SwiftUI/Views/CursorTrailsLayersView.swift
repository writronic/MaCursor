import SwiftUI

extension CursorTrailsPicture {
    var title: String {
        switch self {
        case .softDot: return String(localized: "Soft Dot")
        case .star: return String(localized: "Star")
        case .bubble: return String(localized: "Bubble")
        case .snowflake: return String(localized: "Snowflake")
        case .heart: return String(localized: "Heart")
        case .bolt: return String(localized: "Bolt")
        case .twinkle: return String(localized: "Twinkle")
        case .symbol: return String(localized: "SF Symbol")
        case .image: return String(localized: "Image")
        }
    }

    static func imageData(at url: URL) -> Data? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 4 * imageSide] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return imageData(from: picture)
    }
}

extension CursorTrailsSizeCurve {
    var title: String {
        switch self {
        case .steady: return String(localized: "Steady")
        case .grow: return String(localized: "Grow")
        case .shrink: return String(localized: "Shrink")
        case .smallBigSmall: return String(localized: "Small-Big-Small")
        case .bigSmallBig: return String(localized: "Big-Small-Big")
        }
    }
}

extension CursorTrailsCopy {
    static func preview(themeAt path: String?) -> CursorTrailsCopy? {
        func plist(_ path: String) -> [AnyHashable: Any]? {
            (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [AnyHashable: Any] }
        }
        return CursorTrailsCopy(theme: path.flatMap(plist), baseline: plist(MACCursorCapture.systemDefaultPath), scale: 1, leftHanded: false)
    }
}

extension CursorTrailsConfig {
    func showing(_ style: CursorTrailsStyle) -> CursorTrailsConfig {
        var config = self
        config.style = style
        return config
    }

    func showing(_ style: CursorTrailsCustomStyle) -> CursorTrailsConfig {
        var config = self
        config.style = .customParticles
        config.customStyles = [style]
        config.customStyle = style.id
        return config
    }

    func saving(_ style: CursorTrailsCustomStyle) -> CursorTrailsConfig {
        var config = self
        let isNew = !customStyles.contains { $0.id == style.id }
        config.put(style)
        if isNew, config.customStyles.contains(where: { $0.id == style.id }) {
            config.style = .customParticles
            config.customStyle = style.id
        }
        return config
    }
}

enum CursorTrailsEditorStep: Int, CaseIterable {
    case layers, birth, direction, motion, look, details

    static let anchors: [CursorTrailsEditorStep: [String]] = [
        .layers: ["tpName", "tpEnabled", "tpOffsetX", "tpOffsetY"], .birth: ["tpRate", "tpLife", "tpLifeRange"],
        .direction: ["tpAngle", "tpAngleRange", "tpLat", "tpLatRange"], .motion: ["tpSpeed", "tpSpeedRange", "tpAccX", "tpAccY"],
        .look: ["tpPicture", "tpSymbol", "tpImage", "tpCard", "tpColor", "tpSize", "tpSizeRange", "tpCurve", "tpSpin", "tpSpinRange", "tpFade"],
    ]

    static func holding(_ anchor: String?) -> CursorTrailsEditorStep? {
        guard let anchor else { return nil }
        return anchors.first { $0.value.contains(anchor) }?.key
    }

    var title: String {
        switch self {
        case .layers: return String(localized: "Layers")
        case .birth: return String(localized: "Birth")
        case .direction: return String(localized: "Direction")
        case .motion: return String(localized: "Motion")
        case .look: return String(localized: "Look")
        case .details: return String(localized: "Details")
        }
    }

    var note: String {
        switch self {
        case .layers: return String(localized: "A style is made of layers. Each layer is its own kind of particle.")
        case .birth: return String(localized: "How many particles appear, and how long each one lives.")
        case .direction: return String(localized: "Which way the particles fly when they are born.")
        case .motion: return String(localized: "How fast they move, and what pushes them on the way.")
        case .look: return String(localized: "What each particle looks like: picture, color, size, spin and fade.")
        case .details: return String(localized: "Name the style. The name shows on its card.")
        }
    }

    var next: CursorTrailsEditorStep? {
        CursorTrailsEditorStep(rawValue: rawValue + 1)
    }
}

final class CursorTrailsPreview {
    static let size = CGSize(width: 216, height: 100)
    static let stillTime: TimeInterval = 1.6
    private static let travel: TimeInterval = 2.4
    private static let loop: TimeInterval = 3.2

    let size = CursorTrailsPreview.size
    private(set) var time: TimeInterval = 0
    private var start: TimeInterval?
    private var samples: [CursorTrailsSample] = []
    private var dots: [CursorTrailsDot] = []
    private var still: (config: CursorTrailsConfig, stops: [UInt32], scale: CGFloat, echo: CGImage?, image: CGImage?)?
    private var painted: (config: CursorTrailsConfig, stops: [UInt32], echo: CGImage?, copy: CursorTrailsCopy?)?

    func tip(at time: TimeInterval) -> CGPoint {
        let along = min(time.truncatingRemainder(dividingBy: Self.loop) / Self.travel, 1)
        return CGPoint(x: 14 + along * (size.width - 40), y: size.height * (0.3 + 0.45 * along) + size.height * 0.12 * sin(along * 3 * .pi))
    }

    func curve() -> [CGPoint] {
        (0...48).map { tip(at: Double($0) / 48 * Self.travel) }
    }

    func picture(_ config: CursorTrailsConfig, stops: [UInt32], at now: TimeInterval, scale: CGFloat, echo: CursorTrailsCopy? = nil) -> CGImage? {
        advance(config, stops: stops, at: now)
        return draw(config, stops: stops, scale: scale, echo: echo)
    }

    private func advance(_ config: CursorTrailsConfig, stops: [UInt32], at now: TimeInterval) {
        if start == nil { start = now }
        let previous = time
        time = now - (start ?? now)
        if time.truncatingRemainder(dividingBy: Self.loop) < previous.truncatingRemainder(dividingBy: Self.loop) || time - previous >= Self.loop { samples = [] }
        let tip = tip(at: time)
        if let recipes = config.recipes {
            (samples, dots) = CursorTrailsDot.step(samples, dots, to: tip, at: time, lifetime: config.lifetime, width: config.width, stops: stops, recipes: recipes)
        } else if config.drawsCopies {
            samples = CursorTrailsCopy.advance(samples, to: tip, at: time, count: config.length)
        } else {
            samples = CursorTrailsSample.advance(samples, to: tip, at: time, length: config.lifetime)
        }
    }

    private func copy(_ config: CursorTrailsConfig, stops: [UInt32], echo: CursorTrailsCopy?) -> CursorTrailsCopy? {
        if let painted, painted.config == config, painted.stops == stops, painted.echo === echo?.image { return painted.copy }
        let copy = echo.map { config.painted($0, stops: stops) }
        painted = (config, stops, echo?.image, copy)
        return copy
    }

    private func draw(_ config: CursorTrailsConfig, stops: [UInt32], scale: CGFloat, echo: CursorTrailsCopy?) -> CGImage? {
        guard let context = MACCursorShadow.makeContext(width: Int(size.width * scale), height: Int(size.height * scale)) else { return nil }
        let screen = CGRect(origin: .zero, size: size)
        let tip = tip(at: time)
        let trail = config.recipes != nil ? CursorTrailsDot.picture(dots, at: time, lifetime: config.lifetime, fade: config.fade, in: screen, scale: scale)
            : config.drawsCopies ? copy(config, stops: stops, echo: echo)?.picture(samples, tip: tip, fade: config.fade, in: screen, scale: scale)
            : CursorTrailsPiece.picture(CursorTrailsPiece.line(samples, tip: tip, at: time, length: config.lifetime, width: CGFloat(config.width),
                                                               fade: config.fade, stops: stops), in: screen, scale: scale)
        if let drawn = trail {
            context.draw(drawn.image, in: CGRect(x: drawn.frame.minX * scale, y: drawn.frame.minY * scale, width: drawn.frame.width * scale, height: drawn.frame.height * scale))
        }
        return context.makeImage()
    }

    func still(_ config: CursorTrailsConfig, stops: [UInt32], scale: CGFloat, echo: CursorTrailsCopy? = nil) -> CGImage? {
        if let still, still.config == config, still.stops == stops, still.scale == scale, still.echo === echo?.image { return still.image }
        let fresh = CursorTrailsPreview()
        (0...Int(Self.stillTime * 30)).forEach { fresh.advance(config, stops: stops, at: Double($0) / 30) }
        let image = fresh.draw(config, stops: stops, scale: scale, echo: echo)
        still = (config, stops, scale, echo?.image, image)
        return image
    }
}

struct CursorTrailsPreviewView: View {
    let config: CursorTrailsConfig
    let stops: [UInt32]
    var moving = true
    var echo: CursorTrailsCopy?
    private let size = CursorTrailsPreview.size
    @State private var preview = CursorTrailsPreview()
    @Environment(\.displayScale) private var scale

    var body: some View {
        Group {
            if moving {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let image = preview.picture(config, stops: stops, at: context.date.timeIntervalSinceReferenceDate, scale: scale, echo: echo)
                    face(image, tip: preview.tip(at: preview.time))
                }
            } else {
                face(preview.still(config, stops: stops, scale: scale, echo: echo), tip: preview.tip(at: CursorTrailsPreview.stillTime))
            }
        }
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private func face(_ image: CGImage?, tip: CGPoint) -> some View {
        let arrow = NSCursor.arrow
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.addLines(preview.curve().map { CGPoint(x: $0.x, y: size.height - $0.y) })
            }
            .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let image {
                Image(decorative: image, scale: scale)
            }
            Image(nsImage: arrow.image)
                .offset(x: tip.x - arrow.hotSpot.x, y: size.height - tip.y - arrow.hotSpot.y)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

struct CursorTrailsLayersView: View {
    enum Unit {
        case points, seconds, degrees, speed, push, turn

        func text(_ value: Double, locale: Locale = CursorTrailsLayersView.locale) -> String {
            let whole = Int64(value.rounded())
            switch self {
            case .points: return String(localized: "\(whole) pt")
            case .seconds: return String(localized: "\(CursorTrailsLayersView.number(value, locale: locale)) s")
            case .degrees: return String(localized: "\(whole)°")
            case .speed: return String(localized: "\(whole) pt/s")
            case .push: return String(localized: "\(whole) pt/s²")
            case .turn: return String(localized: "\(whole)°/s")
            }
        }
    }

    nonisolated static let rowHeight: CGFloat = 26

    @Binding var trails: CursorTrailsConfig
    var save: (CursorTrailsConfig) -> Void = { $0.save() }
    var themePath: () -> String? = CursorTrailsLayersView.liveThemePath
    @EnvironmentObject private var router: MainWindowRouter
    @State private var themeStops: [UInt32] = []
    @State private var echo: CursorTrailsCopy?

    nonisolated static func liveThemePath() -> String? {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return MACMenuBarVisibleThemeIdentifier(MACPreferences.value(forKey: MACPreferences.appliedCursorKey) as? String,
                                                MACPreferences.value(forKey: MACPreferences.appOverrideKey) as? String)
            .map(MACAutoSwitchThemePathForIdentifier)
    }

    nonisolated static var locale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    nonisolated static func number(_ value: Double, locale: Locale = locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    nonisolated static func summary(_ layer: CursorTrailsLayer, locale: Locale = locale) -> String {
        String(localized: "\(Int64(layer.birthRate.rounded()))/s · life \(number(layer.lifetime, locale: locale)) s")
    }

    nonisolated static func title(_ layer: CursorTrailsLayer, at place: Int) -> String {
        layer.name.isEmpty ? String(localized: "Layer \(Int64(place + 1))") : layer.name
    }

    nonisolated static func title(_ style: CursorTrailsCustomStyle, at place: Int) -> String {
        style.name.isEmpty ? String(localized: "Custom Style \(Int64(place + 1))") : style.name
    }

    nonisolated static func pictures(_ style: CursorTrailsCustomStyle) -> String {
        style.layers.map(\.picture).reduce(into: [CursorTrailsPicture]()) { if !$0.contains($1) { $0.append($1) } }.map(\.title).joined(separator: ", ")
    }

    private var stops: [UInt32] {
        trails.palette == .match ? themeStops : trails.palette.stops
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(CursorTrailsStyle.allCases.filter { $0 != .customParticles }, id: \.self) { style in
                    ThemeCard(name: style.title, isApplied: trails.style == style) {
                        edit { $0.style = style }
                    } preview: {
                        CursorTrailsCardPreview(config: trails.showing(style), stops: stops, echo: echo)
                    }
                }
                ForEach(Array(trails.customStyles.enumerated()), id: \.element.id) { place, style in
                    customCard(style, at: place)
                }
                Button {
                    router.editTrailStyle(CursorTrailsCustomStyle(), title: String(localized: "New Style"))
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                        Text("New Style")
                            .font(.system(size: 10.5))
                    }
                    .frame(maxWidth: .infinity, minHeight: CursorTrailsCardPreview.height + 37, maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(trails.customStyles.count >= CursorTrailsCustomStyle.styleCap)
                .searchAnchor("tNew")
            }
            .searchAnchor("tStyle")
        }
        .padding(.vertical, 4)
        .onAppear(perform: readTheme)
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACAutoSwitchAppliedThemeDidChange)) { _ in readTheme() }
    }

    private func readTheme() {
        let path = themePath()
        themeStops = CursorTrailsPalette.matchStops(themeAt: path)
        echo = CursorTrailsCopy.preview(themeAt: path)
    }

    private func customCard(_ style: CursorTrailsCustomStyle, at place: Int) -> some View {
        let title = Self.title(style, at: place)
        let open = { router.editTrailStyle(style, title: String(localized: "Edit Style")) }
        return ThemeCard(name: title, isApplied: trails.style == .customParticles && trails.customStyle == style.id) {
            edit {
                $0.style = .customParticles
                $0.customStyle = style.id
            }
        } preview: {
            CursorTrailsCardPreview(config: trails.showing(style), stops: stops)
        }
        .overlay(alignment: .topLeading) {
            Button(action: open) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit"))
            .accessibilityValue(Text(verbatim: title))
            .help(Text("Edit"))
            .padding(4)
        }
        .contextMenu {
            Button("Edit", action: open)
            Button("Duplicate") {
                var copy = style
                copy.id = UUID()
                copy.name = title
                router.editTrailStyle(copy, title: String(localized: "New Style"))
            }
            .disabled(trails.customStyles.count >= CursorTrailsCustomStyle.styleCap)
            Divider()
            Button("Delete", role: .destructive) {
                edit { $0.deleteStyle(style.id) }
            }
            .disabled(trails.customStyles.count <= 1)
        }
    }

    private func edit(_ update: (inout CursorTrailsConfig) -> Void) {
        update(&trails)
        save(trails)
    }
}

private struct CursorTrailsCardPreview: View {
    static let scale: CGFloat = 0.68
    static let height = CursorTrailsPreview.size.height * scale

    let config: CursorTrailsConfig
    let stops: [UInt32]
    var echo: CursorTrailsCopy?
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        CursorTrailsPreviewView(config: config, stops: stops, moving: shown && !reduceMotion && isEnabled, echo: echo)
            .scaleEffect(Self.scale, anchor: .topLeading)
            .frame(width: CursorTrailsPreview.size.width * Self.scale, height: Self.height, alignment: .topLeading)
            .onAppear { shown = true }
            .onDisappear { shown = false }
    }
}

struct CursorTrailsStylePage: View {
    typealias Unit = CursorTrailsLayersView.Unit

    @EnvironmentObject private var router: MainWindowRouter
    @State private var draft: CursorTrailsConfig
    @State private var step: CursorTrailsEditorStep
    @State private var selected = 0
    @State private var themeStops: [UInt32] = []
    @State private var window: NSWindow?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    private let original: CursorTrailsCustomStyle
    private let place: Int
    private let save: (CursorTrailsCustomStyle) -> Void
    private let themePath: () -> String?
    private let pageTitle: String

    init(style: CursorTrailsCustomStyle, config: CursorTrailsConfig, pageTitle: String, step: CursorTrailsEditorStep = .layers,
         save: @escaping (CursorTrailsCustomStyle) -> Void = { CursorTrailsConfig.load().saving($0).save() },
         themePath: @escaping () -> String? = CursorTrailsLayersView.liveThemePath) {
        _draft = State(initialValue: config.showing(style))
        _step = State(initialValue: step)
        self.pageTitle = pageTitle
        original = style
        place = config.customStyles.firstIndex { $0.id == style.id } ?? config.customStyles.count
        self.save = save
        self.themePath = themePath
    }

    private var style: CursorTrailsCustomStyle {
        draft.styleInUse
    }

    private var index: Int {
        min(max(selected, 0), draft.layers.count - 1)
    }

    private var layer: CursorTrailsLayer {
        draft.layers[index]
    }

    private var stops: [UInt32] {
        draft.palette == .match ? themeStops : draft.palette.stops
    }

    private var title: String {
        CursorTrailsLayersView.title(style, at: place)
    }

    private func value(_ item: CursorTrailsEditorStep) -> String {
        switch item {
        case .layers: return draft.layers.enumerated().map { CursorTrailsLayersView.title($1, at: $0) }.joined(separator: " · ")
        case .birth: return CursorTrailsLayersView.summary(layer)
        case .direction: return [Unit.degrees.text(layer.angle), Unit.degrees.text(layer.angleRange)].joined(separator: " · ")
        case .motion: return [Unit.speed.text(layer.velocity), Unit.speed.text(layer.velocityRange)].joined(separator: " · ")
        case .look: return [layer.picture.title, Unit.points.text(layer.size)].joined(separator: " · ")
        case .details: return title
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                ViewThatFits(in: .vertical) {
                    column(fills: true)
                    ScrollView {
                        column(fills: false)
                    }
                }
                .frame(width: 268)
                .frame(maxHeight: .infinity, alignment: .top)
                .frame(minHeight: 0)
                .background(Color.pageFill)
                .toolbarTitleItem("MaCursor")
                .toolbar {
                    ToolbarItem {
                        Button { router.back() } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                        .help("Back")
                    }
                }
                .sidebarToggleRemoved()
                .navigationSplitViewColumnWidth(268)
            } detail: {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(.title2.weight(.semibold))

                        Text(step.note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            rows
                        }
                        .frame(width: 560, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .controlBackgroundColor))
                .frame(minHeight: 0)
                .toolbarTitleItem(Text(pageTitle))
            }
            .onChangeCompat(of: columnVisibility) { newValue in
                if newValue != .all {
                    columnVisibility = .all
                }
            }

            Divider()

            HStack(spacing: 0) {
                let on = draft.layers.enumerated().filter(\.element.enabled).map { CursorTrailsLayersView.title($1, at: $0) }
                HStack(spacing: 6) {
                    ForEach(Array(on.enumerated()), id: \.offset) { index, name in
                        if index > 0 {
                            Image(systemName: "arrow.forward")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Text(verbatim: name)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(index == 0 ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06)))
                    }
                }
                .font(.callout)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button("Cancel") {
                        router.back()
                    }
                    .keyboardShortcut(.cancelAction)

                    if let next = step.next {
                        Button("Next: \(next.title)") {
                            step = next
                        }
                    }

                    Button("Save") {
                        save(style)
                        router.closeEditor()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .fixedSize()
            }
            .padding(16)
        }
        .frame(minWidth: 785, maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            router.leaveEditor = requestLeave
            themeStops = CursorTrailsPalette.matchStops(themeAt: themePath())
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .MACAutoSwitchAppliedThemeDidChange)) { _ in
            themeStops = CursorTrailsPalette.matchStops(themeAt: themePath())
        }
        .background(WindowAccessor(window: $window, onCloseAttempt: { router.back(); return false }))
    }

    private func column(fills: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(CursorTrailsEditorStep.allCases.enumerated()), id: \.element) { number, item in
                Button {
                    step = item
                } label: {
                    HStack(spacing: 12) {
                        Text(number + 1, format: .number)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(item == step ? Color.white : Color.primary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(item == step ? Color.accentColor : Color.primary.opacity(0.1)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.headline)
                                .lineLimit(1)

                            Text(verbatim: value(item))
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

            if fills {
                Spacer(minLength: 12)
            }

            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
                .padding(.top, fills ? 0 : 12)

            VStack(alignment: .leading, spacing: 6) {
                CursorTrailsPreviewView(config: draft, stops: stops)

                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(1)

                Text(verbatim: CursorTrailsLayersView.pictures(style))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(maxHeight: fills ? .infinity : nil, alignment: .top)
    }

    @ViewBuilder
    private var rows: some View {
        switch step {
        case .layers:
            VStack(spacing: 2) {
                ForEach(Array(draft.layers.enumerated()), id: \.offset) { index, layer in
                    row(layer, at: index)
                }
            }
            HStack {
                Button("Add") {
                    edit { selected = $0.addLayer() }
                }
                .disabled(draft.layers.count >= CursorTrailsLayer.layerCap)
                Button("Duplicate") {
                    edit { selected = $0.duplicateLayer(at: index) }
                }
                .disabled(draft.layers.count >= CursorTrailsLayer.layerCap)
                Button("Delete") {
                    edit { selected = $0.deleteLayer(at: index) }
                }
                .disabled(draft.layers.count <= 1)
            }
            .padding(.vertical, 10)
            Divider()
            line("Name") { _ in
                LimitedLengthTextField(text: Binding(
                    get: { layer.name },
                    set: { value in change { $0.name = value } }
                ), placeholder: CursorTrailsLayersView.title(CursorTrailsLayer(), at: index), characterLimit: CursorTrailsLayer.nameLimit)
                .frame(width: 220)
            }
            .searchAnchor("tpName")
            toggle("Enabled", \.enabled)
                .searchAnchor("tpEnabled")
            slider("Layer Offset X", \.offsetX, step: 1, unit: .points)
                .searchAnchor("tpOffsetX")
            slider("Layer Offset Y", \.offsetY, step: 1, unit: .points)
                .searchAnchor("tpOffsetY")
        case .birth:
            layerMenu
            slider("Birth Rate", \.birthRate, step: 1, unit: nil)
                .searchAnchor("tpRate")
            slider("Lifetime", \.lifetime, step: 0.05, unit: .seconds)
                .searchAnchor("tpLife")
            slider("Lifetime Range", \.lifetimeRange, step: 0.05, unit: .seconds, top: 2 * layer.lifetime)
                .searchAnchor("tpLifeRange")
        case .direction:
            layerMenu
            slider("Angle", \.angle, step: 1, unit: .degrees)
                .searchAnchor("tpAngle")
            slider("Angle Range", \.angleRange, step: 1, unit: .degrees)
                .searchAnchor("tpAngleRange")
            slider("Latitude", \.latitude, step: 1, unit: .degrees)
                .searchAnchor("tpLat")
            slider("Latitude Range", \.latitudeRange, step: 1, unit: .degrees)
                .searchAnchor("tpLatRange")
        case .motion:
            layerMenu
            slider("Velocity", \.velocity, step: 1, unit: .speed)
                .searchAnchor("tpSpeed")
            slider("Velocity Range", \.velocityRange, step: 1, unit: .speed)
                .searchAnchor("tpSpeedRange")
            slider("X Acceleration", \.xAcceleration, step: 1, unit: .push)
                .searchAnchor("tpAccX")
            slider("Y Acceleration", \.yAcceleration, step: 1, unit: .push)
                .searchAnchor("tpAccY")
        case .look:
            layerMenu
            line("Picture") { label in
                Picker(label, selection: Binding(
                    get: { layer.picture },
                    set: { value in change { $0.picture = value } }
                )) {
                    ForEach(CursorTrailsPicture.allCases, id: \.self) { picture in
                        Text(picture.title).tag(picture)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 190, alignment: .trailing)
            }
            .searchAnchor("tpPicture")
            if layer.picture == .symbol {
                VStack(alignment: .leading, spacing: 0) {
                    line("Symbol Name") { _ in
                        LimitedLengthTextField(text: Binding(
                            get: { layer.symbol },
                            set: { value in change { $0.symbol = value } }
                        ), placeholder: "star.fill", characterLimit: CursorTrailsLayer.symbolLimit)
                        .frame(width: 220)
                    }
                    if CursorTrailsPicture.symbolArt(layer.symbol) == nil {
                        Text("This Mac has no SF Symbol with this name.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                    }
                }
                .searchAnchor("tpSymbol")
            }
            if layer.picture == .image {
                VStack(alignment: .leading, spacing: 0) {
                    line("Image") { _ in
                        HStack(spacing: 8) {
                            if let art = CursorTrailsPicture.imageArt(layer.image) {
                                Image(decorative: art, scale: 2)
                            }
                            Button("Choose…") {
                                guard let url = NSOpenPanel.choose([.image]) else { return }
                                change { $0.image = CursorTrailsPicture.imageData(at: url) }
                            }
                        }
                    }
                    Group {
                        if CursorTrailsPicture.imageArt(layer.image) == nil {
                            Text("Choose an image for this layer.")
                        } else {
                            Text("The image keeps its own colors.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                }
                .searchAnchor("tpImage")
            }
            toggle("Use Colors Card", \.usesCard)
                .disabled(layer.picture == .image)
                .searchAnchor("tpCard")
            line("Color") { label in
                ColorPicker(label, selection: Binding(
                    get: { CursorTrailsPalette.color(at: 0, stops: [layer.color], alpha: 1) },
                    set: { value in change { $0.color = CursorGestures.hex(value) } }
                ), supportsOpacity: false)
                .labelsHidden()
            }
            .disabled(layer.usesCard || layer.picture == .image)
            .searchAnchor("tpColor")
            slider("Size", \.size, step: 1, unit: .points)
                .searchAnchor("tpSize")
            slider("Size Range", \.sizeRange, step: 1, unit: .points, top: 2 * layer.size)
                .searchAnchor("tpSizeRange")
            VStack(alignment: .leading, spacing: 0) {
                line("Size Over Life") { label in
                    Picker(label, selection: Binding(
                        get: { layer.sizeCurve },
                        set: { value in change { $0.sizeCurve = value } }
                    )) {
                        ForEach(CursorTrailsSizeCurve.allCases, id: \.self) { curve in
                            Text(curve.title).tag(curve)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 190, alignment: .trailing)
                }
                if layer.enabled && layer.sizeCurve.curved {
                    Text("The processor draws this curve, so this style does not use the graphics hardware.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }
            .searchAnchor("tpCurve")
            slider("Spin", \.spin, step: 1, unit: .turn)
                .searchAnchor("tpSpin")
            slider("Spin Range", \.spinRange, step: 1, unit: .turn)
                .searchAnchor("tpSpinRange")
            toggle("Fade", \.fade)
                .searchAnchor("tpFade")
        case .details:
            line("Name") { _ in
                LimitedLengthTextField(text: Binding(
                    get: { style.name },
                    set: { value in edit { $0.customStyles[0].name = String(value.prefix(CursorTrailsLayer.nameLimit)) } }
                ), placeholder: CursorTrailsLayersView.title(CursorTrailsCustomStyle(), at: place), characterLimit: CursorTrailsLayer.nameLimit)
                .frame(width: 220)
            }
        }
    }

    private var layerMenu: some View {
        line("Layer") { label in
            Picker(label, selection: Binding(get: { index }, set: { selected = $0 })) {
                ForEach(Array(draft.layers.enumerated()), id: \.offset) { place, layer in
                    Text(verbatim: CursorTrailsLayersView.title(layer, at: place)).tag(place)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 190, alignment: .trailing)
        }
    }

    private func line<Content: View>(_ label: LocalizedStringKey, @ViewBuilder _ content: (LocalizedStringKey) -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label)
                    .lineLimit(1)
                Spacer(minLength: 12)
                content(label)
            }
            .frame(minHeight: 28)
            .padding(.vertical, 8)
            Divider()
        }
    }

    private func toggle(_ label: LocalizedStringKey, _ key: WritableKeyPath<CursorTrailsLayer, Bool>) -> some View {
        line(label) { label in
            Toggle(label, isOn: Binding(
                get: { layer[keyPath: key] },
                set: { value in change { $0[keyPath: key] = value } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }

    private func row(_ layer: CursorTrailsLayer, at index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                selected = index
            } label: {
                HStack(spacing: 8) {
                    if layer.picture == .image, let art = CursorTrailsPicture.imageArt(layer.image) {
                        Image(decorative: art, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 10, height: 10)
                    } else {
                        Circle()
                            .fill(Color(cgColor: CursorTrailsPalette.color(at: 0, stops: !layer.usesCard ? [layer.color] : stops, alpha: 1)))
                            .frame(width: 10, height: 10)
                    }
                    Text(CursorTrailsLayersView.title(layer, at: index))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(CursorTrailsLayersView.summary(layer))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: CursorTrailsLayersView.rowHeight, maxHeight: CursorTrailsLayersView.rowHeight, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(index == self.index ? Color.accentColor.opacity(0.2) : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle(CursorTrailsLayersView.title(layer, at: index), isOn: Binding(
                get: { layer.enabled },
                set: { value in change(at: index) { $0.enabled = value } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
        }
    }

    private func slider(_ label: LocalizedStringKey, _ key: WritableKeyPath<CursorTrailsLayer, Double>, step: Double, unit: Unit?, top: Double? = nil) -> some View {
        let limit = CursorTrailsLayer.limit(key)
        let value = layer[keyPath: key]
        return line(label) { _ in
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { layer[keyPath: key] },
                    set: { value in change { $0[keyPath: key] = (value / step).rounded() * step } }
                ), in: limit.lowerBound...max(min(top ?? limit.upperBound, limit.upperBound), limit.lowerBound + step))
                .labelsHidden()
                .frame(width: 316)
                Text(unit?.text(value) ?? String(localized: "\(Int64(value.rounded()))/s"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72, alignment: .trailing)
            }
        }
    }

    private func change(at index: Int? = nil, _ update: (inout CursorTrailsLayer) -> Void) {
        let index = index ?? self.index
        guard draft.layers.indices.contains(index) else { return }
        var layer = draft.layers[index]
        update(&layer)
        layer = layer.clamped()
        guard layer != draft.layers[index] else { return }
        draft.layers[index] = layer
    }

    private func edit(_ update: (inout CursorTrailsConfig) -> Void) {
        update(&draft)
    }

    private func requestLeave(then next: @escaping () -> Void) {
        guard style != original else { return next() }
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Unsaved Changes")
        alert.informativeText = String(localized: "Your changes will be discarded if you don't save them.")
        alert.addButton(withTitle: String(localized: "Keep Editing"))
        alert.addButton(withTitle: String(localized: "Discard")).hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            guard response == .alertSecondButtonReturn else { return }
            next()
        }
    }
}
