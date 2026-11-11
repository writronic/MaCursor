import AppKit
import IOKit.hidsystem

extension Notification.Name {
    nonisolated static let MACCursorGesturesDidChange = Notification.Name("MACCursorGesturesDidChange")
}

enum CursorGestureDevice: String, Codable, CaseIterable {
    case mouse, trackpad, both

    init(subtype: Int64) {
        self = subtype == Int64(NSEvent.EventSubtype.touch.rawValue) ? .trackpad : .mouse
    }

    var name: String {
        switch self {
        case .mouse: String(localized: "Mouse")
        case .trackpad: String(localized: "Trackpad")
        case .both: String(localized: "Mouse or Trackpad")
        }
    }
}

struct CursorGestureTrigger: Codable, Hashable {
    var keys: UInt = 0
    var button: Int?
    var twoFinger = false
    var device = CursorGestureDevice.both

    func overlaps(_ other: CursorGestureTrigger) -> Bool {
        keys == other.keys && button == other.button && twoFinger == other.twoFinger &&
            (device == .both || other.device == .both || device == other.device)
    }

    var complete: Bool { keys != 0 || button != nil }

    var clicks: Bool { (button ?? 0) >= 2 && !twoFinger }

    var label: String {
        let name: String? = switch button {
        case nil: nil
        case 1?: String(localized: "Right Button")
        case 2?: String(localized: "Middle Button")
        case 3?: String(localized: "Back Button")
        case 4?: String(localized: "Forward Button")
        default: String(localized: "Side Button")
        }
        return [CursorGestureKeys.glyphs(keys), name ?? "", twoFinger ? String(localized: "Two Fingers") : ""]
            .filter { !$0.isEmpty }.joined(separator: " + ")
    }
}

enum CursorGestureFilter: Hashable {
    case all, allApps, app(String)

    var apps: [String] {
        if case .app(let app) = self { [app] } else { [] }
    }
}

struct CursorGestureGroup<Item>: Identifiable {
    let family: CursorGestureFamily?
    let items: [Item]

    var id: CursorGestureFamily? { family }
}

struct CursorGestureStep: Codable, Equatable, Identifiable {
    var id = UUID()
    var action: String
    var wait: Int?
    var enabled = true
}

struct CursorGesture: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = ""
    var enabled = true
    var shape = ""
    var triggers = [CursorGestureTrigger(keys: NSEvent.ModifierFlags.option.rawValue)]
    var apps: [String] = []
    var steps: [CursorGestureStep] = []
}

enum CursorGestureFamily: String, Codable, CaseIterable {
    case lines, diagonals, corners, returns, curves, letters, clicks

    var title: String {
        switch self {
        case .lines: return String(localized: "Lines")
        case .diagonals: return String(localized: "Diagonals")
        case .corners: return String(localized: "Corners")
        case .returns: return String(localized: "Returns")
        case .curves: return String(localized: "Curves")
        case .letters: return String(localized: "Letters")
        case .clicks: return String(localized: "Clicks")
        }
    }
}

enum CursorGestureEditorStep: CaseIterable {
    case shape, trigger, actions, details

    var title: String {
        switch self {
        case .shape: return String(localized: "Shape")
        case .trigger: return String(localized: "Trigger")
        case .actions: return String(localized: "Actions")
        case .details: return String(localized: "Details")
        }
    }

    var note: String {
        switch self {
        case .shape: return String(localized: "Draw it with the pointer while you hold the trigger.")
        case .trigger: return String(localized: "Hold these keys or this button while you draw. Add another trigger for a second way to start it.")
        case .actions: return String(localized: "Click an action to add it. Add more to run them in order.")
        case .details: return String(localized: "Name the gesture and choose the apps it works in.")
        }
    }

    var next: CursorGestureEditorStep? {
        Self.allCases.drop { $0 != self }.dropFirst().first
    }
}

struct CursorGestureShape: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name = ""
    var points: [CGPoint] = []
    var directional = true
    var family: CursorGestureFamily?
}

enum CursorGestureCategory: String, Codable, CaseIterable {
    case general, browser, clipboard, windows, system, apps, macursor, custom

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .browser: return String(localized: "Browser and Tabs")
        case .clipboard: return String(localized: "Clipboard")
        case .windows: return String(localized: "Windows")
        case .system: return String(localized: "System")
        case .apps: return String(localized: "Apps")
        case .macursor: return String(localized: "MaCursor")
        case .custom: return String(localized: "Custom")
        }
    }
}

enum CursorGestureOperation: String, Codable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf, topLeftQuarter, topRightQuarter, bottomLeftQuarter, bottomRightQuarter,
         leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds, maximize, center, nextDisplay, restoreSize,
         minimize, closeWindow, hideApp, volumeUp, volumeDown, mute, brightnessUp, brightnessDown, sleep, screenSaver,
         nextFavoriteTheme, systemCursors, screenshotArea,
         capturePreviousArea, captureFullscreen, captureSelfTimer, captureText, captureOpen, captureOpenClipboard, capturePin, captureHistory,
         cursorShadow, focusOnHover, cursorTranslator, cursorShaker, cursorTrails, switchByApp

    var capture: MACMenuBarCaptureItem? {
        switch self {
        case .screenshotArea: return .area
        case .capturePreviousArea: return .previousArea
        case .captureFullscreen: return .fullscreen
        case .captureSelfTimer: return .selfTimer
        case .captureText: return .text
        default: return nil
        }
    }

    var needsCursorCapture: Bool {
        capture != nil || [.captureOpen, .captureOpenClipboard, .capturePin, .captureHistory].contains(self)
    }
}

struct CursorGestureShortcut: Codable, Equatable {
    var keyCode: UInt16
    var flags: UInt
    var character: String?
}

enum CursorGestureKind: Codable, Equatable {
    case shortcut(CursorGestureShortcut)
    case text(String)
    case app(String)
    case website(String)
    case theme(String)
    case operation(CursorGestureOperation)
}

struct CursorGestureAction: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var detail = ""
    var icon: String
    var category = CursorGestureCategory.custom
    var kind: CursorGestureKind
    var key: String?

    var changesScreen: Bool {
        if case .operation(let operation) = kind, operation.capture != nil { return true }
        guard case .shortcut = kind else { return false }
        return category == .system
    }

    var typesIntoWindow: Bool {
        switch kind {
        case .shortcut: return category != .system
        case .text: return true
        default: return false
        }
    }

    func caps(_ layout: Data? = shortcutLayout()) -> [String] {
        guard case .shortcut(let shortcut) = kind else { return [] }
        return CursorGestureKeys.caps(shortcut, layout: layout)
    }

    func caption(_ layout: Data? = shortcutLayout()) -> String {
        guard category == .custom, case .shortcut(let shortcut) = kind else { return detail }
        return CursorGestureKeys.label(shortcut, layout: layout)
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .shortcut(let shortcut): return CursorGestureKeys.recordable(shortcut.keyCode, NSEvent.ModifierFlags(rawValue: shortcut.flags))
        case .text(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= CursorGestures.textLimit
        case .app(let path): return !path.isEmpty
        case .website(let address): return CursorGestures.website(address) != nil
        case .theme, .operation: return false
        }
    }
}

struct CursorGestureIgnoredApp: Codable, Equatable {
    enum Block: String, Codable, CaseIterable {
        case all, buttons, keys
    }

    var app: String
    var block = Block.all
    var frontOnly = true
}

struct CursorGesturesConfig: Codable, Equatable {
    static let strictnessRange: ClosedRange<CGFloat> = 0.5...1
    static let sizeRange: ClosedRange<CGFloat> = 5...100
    static let widthRange: ClosedRange<CGFloat> = 2...12

    var enabled = false
    var readyMadeAdded = false
    var gestures: [CursorGesture] = []
    var shapes: [CursorGestureShape] = []
    var actions: [CursorGestureAction] = []
    var ignored: [CursorGestureIgnoredApp] = []
    var strictness = CursorGestures.threshold
    var minimumSize = CursorGestures.minimumSize
    var raiseWindow = true
    var showLine = true
    var colorByResult = true
    var showShapeName = true
    var repeatMouse = true
    var repeatTrackpad = true
    var switchWhileRepeating = true
    var lineColor: UInt32 = 0x008ECB
    var lineWidth: CGFloat = 4
    var ignorePostedClicks = true

    static func load() -> CursorGesturesConfig {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard let data = MACPreferences.value(forKey: MACPreferences.cursorGesturesKey) as? Data,
              let config = try? JSONDecoder().decode(CursorGesturesConfig.self, from: data) else { return CursorGesturesConfig() }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        MACPreferences.set(data, forKey: MACPreferences.cursorGesturesKey)
        CursorGesturesConfig.notifyHelper()
    }

    static func notifyHelper() {
        DistributedNotificationCenter.default().postNotificationName(.MACCursorGesturesDidChange, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    static func setEnabled(_ enabled: Bool) {
        var config = load()
        guard config.enabled != enabled else { return }
        config.turn(enabled)
        config.save()
    }

    mutating func turn(_ on: Bool) {
        enabled = on
        guard on, !readyMadeAdded else { return }
        readyMadeAdded = true
        restoreReadyMade()
    }

    mutating func restoreReadyMade() {
        gestures += CursorGestures.readyMade.filter { made in !gestures.contains { $0.id == made.id } && conflict(made) == nil }
    }

    func isDefault<Value: Equatable>(_ setting: KeyPath<CursorGesturesConfig, Value>) -> Bool {
        self[keyPath: setting] == CursorGesturesConfig()[keyPath: setting]
    }

    mutating func reset<Value>(_ setting: WritableKeyPath<CursorGesturesConfig, Value>) {
        self[keyPath: setting] = CursorGesturesConfig()[keyPath: setting]
    }

    func canSave(_ shape: CursorGestureShape) -> Bool {
        let name = shape.name.trimmingCharacters(in: .whitespaces)
        return shape.family == nil && !shape.points.isEmpty && !name.isEmpty &&
            !allShapes.contains { $0.id != shape.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    mutating func put(_ shape: CursorGestureShape) {
        guard canSave(shape) else { return }
        var shape = shape
        shape.name = shape.name.trimmingCharacters(in: .whitespaces)
        if let index = shapes.firstIndex(where: { $0.id == shape.id }) {
            shapes[index] = shape
        } else {
            shapes.append(shape)
        }
    }

    mutating func put(_ action: CursorGestureAction) {
        guard action.isValid else { return }
        var action = action
        action.name = action.name.trimmingCharacters(in: .whitespaces)
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
        } else {
            actions.append(action)
        }
    }

    func uses(_ id: String) -> Bool {
        gestures.contains { $0.shape == id || $0.steps.contains { $0.action == id } }
    }

    mutating func remove(_ id: String) {
        shapes.removeAll { $0.id == id }
        actions.removeAll { $0.id == id }
    }

    var keyTriggers: [NSEvent.ModifierFlags] { held(twoFinger: false) }

    var padTriggers: [NSEvent.ModifierFlags] { held(twoFinger: true) }

    func tapMask(clicksLeft: Bool) -> CGEventMask {
        let left: [CGEventType] = enabled || clicksLeft ? [.leftMouseDown, .leftMouseUp, .leftMouseDragged] : []
        let buttons = left + [.rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        return (padTriggers.isEmpty ? buttons : buttons + [.scrollWheel]).reduce(0) { $0 | 1 << $1.rawValue }
    }

    func holds(_ trigger: CursorGestureTrigger, front: String?, pointer: @autoclosure () -> String? = nil) -> Bool {
        !wanting(trigger, front: front).isEmpty && !blocks(button: true, front: front, pointer: pointer())
    }

    func wanting(_ trigger: CursorGestureTrigger, front: String?) -> [CursorGesture] {
        gestures.filter { $0.enabled && $0.triggers.contains(where: trigger.overlaps) && ($0.apps.isEmpty || $0.apps.contains(front ?? "")) }
    }

    func clicked(_ trigger: CursorGestureTrigger, front: String?) -> CursorGesture? {
        guard trigger.clicks, front != MACAppBundleIdentifier else { return nil }
        let found = wanting(trigger, front: front).filter { $0.shape == CursorGestures.clickShape.id }
        return found.first { !$0.apps.isEmpty } ?? found.first
    }

    func accepts(source stateID: Int64) -> Bool {
        !ignorePostedClicks || stateID == Int64(CGEventSourceStateID.hidSystemState.rawValue)
    }

    func repeats(on device: CursorGestureDevice) -> Bool {
        device == .trackpad ? repeatTrackpad : repeatMouse
    }

    private func held(twoFinger: Bool) -> [NSEvent.ModifierFlags] {
        Set(gestures.filter(\.enabled).flatMap(\.triggers).filter { $0.button == nil && $0.twoFinger == twoFinger && $0.keys != 0 }.map(\.keys))
            .sorted().map { NSEvent.ModifierFlags(rawValue: $0) }
    }

    func shape(_ id: String) -> CursorGestureShape? {
        allShapes.first { $0.id == id }
    }

    private var allShapes: [CursorGestureShape] { CursorGestures.shapes + [CursorGestures.clickShape] + shapes }

    func action(_ id: String) -> CursorGestureAction? {
        CursorGestures.actions.first { $0.id == id } ?? actions.first { $0.id == id } ??
            (id.hasPrefix(CursorGestures.themePrefix) ? CursorGestures.theme(String(id.dropFirst(CursorGestures.themePrefix.count))) : nil)
    }

    func scopeApp(front: String?, pointer: String?) -> String? {
        raiseWindow ? pointer ?? front : front
    }

    func match(for stroke: [CGPoint], trigger: CursorGestureTrigger, front: String?) -> (gesture: CursorGesture, score: CGFloat)? {
        guard let ink = self.ink(stroke) else { return nil }
        let candidates = wanting(trigger, front: front)
        func best(_ group: [CursorGesture]) -> (gesture: CursorGesture, score: CGFloat)? {
            var winner: (gesture: CursorGesture, distance: CGFloat)?
            for gesture in group {
                guard let template = template(gesture.shape), let distance = ink.distance(to: template),
                      distance < winner?.distance ?? .infinity else { continue }
                winner = (gesture, distance)
            }
            guard let winner, 1 - winner.distance / .pi >= strictness else { return nil }
            return (winner.gesture, 1 - winner.distance / .pi)
        }
        let scoped = best(candidates.filter { !$0.apps.isEmpty }), global = best(candidates.filter(\.apps.isEmpty))
        guard let scoped else { return global }
        guard let global, global.score > scoped.score + CursorGestures.appMargin else { return scoped }
        return global
    }

    func score(_ canvas: [CGPoint], as shape: CursorGestureShape) -> CGFloat? {
        guard let ink = self.ink(canvas.map { CGPoint(x: $0.x, y: -$0.y) }) else { return nil }
        return 1 - (CursorGestureTemplate(shape.points, directional: shape.directional).flatMap(ink.distance(to:)) ?? .infinity) / .pi
    }

    private func ink(_ stroke: [CGPoint]) -> CursorGestureTemplate? {
        stroke.count > 2 && CursorGestures.extent(stroke) >= minimumSize ? CursorGestureTemplate(stroke) : nil
    }

    func conflict(_ gesture: CursorGesture) -> CursorGesture? {
        gestures.first { other in
            other.id != gesture.id && other.shape == gesture.shape &&
                (other.apps.isEmpty && gesture.apps.isEmpty || !Set(other.apps).isDisjoint(with: gesture.apps)) &&
                other.triggers.contains { trigger in gesture.triggers.contains(where: trigger.overlaps) }
        }
    }

    func conflictWarning(_ gesture: CursorGesture, themes: [(id: String, name: String)] = []) -> String? {
        conflict(gesture).map { String(localized: "“\(title($0, themes: themes))” already uses this shape and trigger.") }
    }

    mutating func put(_ gesture: CursorGesture) {
        var gesture = gesture
        gesture.name = gesture.name.trimmingCharacters(in: .whitespaces)
        while let other = conflict(gesture), let index = gestures.firstIndex(where: { $0.id == other.id }) {
            let kept = other.apps.filter { !gesture.apps.contains($0) }
            var shared = other
            shared.triggers.removeAll { trigger in gesture.triggers.contains(where: trigger.overlaps) }
            if kept.isEmpty {
                gestures[index].triggers = shared.triggers
                if shared.triggers.isEmpty { gestures.remove(at: index) }
            } else {
                gestures[index].apps = kept
                if !shared.triggers.isEmpty {
                    shared.id = UUID()
                    shared.apps = other.apps.filter(gesture.apps.contains)
                    gestures.insert(shared, at: index + 1)
                }
            }
        }
        if let index = gestures.firstIndex(where: { $0.id == gesture.id }) {
            gestures[index] = gesture
        } else {
            gestures.append(gesture)
        }
    }

    func taken(by gesture: CursorGesture) -> Set<String> {
        Set(allShapes.map(\.id).filter { id in
            var probe = gesture
            probe.shape = id
            return conflict(probe) != nil
        })
    }

    func canSave(_ gesture: CursorGesture) -> Bool {
        shape(gesture.shape) != nil && !gesture.steps.isEmpty && !gesture.triggers.isEmpty && gesture.triggers.allSatisfy(\.complete) &&
            (gesture.shape != CursorGestures.clickShape.id || gesture.triggers.allSatisfy(\.clicks))
    }

    func actions(_ gesture: CursorGesture, themes: [(id: String, name: String)] = []) -> [CursorGestureAction] {
        let catalogue = CursorGestures.catalogue(self, themes: themes)
        return gesture.steps.filter(\.enabled).compactMap { step in catalogue.first { $0.id == step.action } }
    }

    func title(_ gesture: CursorGesture, themes: [(id: String, name: String)] = [], localized: (String) -> String? = { _ in nil }) -> String {
        guard gesture.name.isEmpty, let action = actions(gesture, themes: themes).first else { return gesture.name }
        return action.key.flatMap(localized) ?? action.name
    }

    func label(_ match: (gesture: CursorGesture, score: CGFloat), themes: [(id: String, name: String)] = [], localized: (String) -> String) -> String? {
        let title = title(match.gesture, themes: themes, localized: { localized($0) })
        return title.isEmpty ? nil : String(format: localized("%1$@ · %2$lld%%"), title, CursorGestures.percent(match.score))
    }

    func summaryParts(_ gesture: CursorGesture, themes: [(id: String, name: String)] = [],
                      appName: (String) -> String = CursorGestures.appName) -> [String] {
        [gesture.triggers.map(\.label).filter { !$0.isEmpty }.joined(separator: ", "),
         shape(gesture.shape)?.name ?? "",
         gesture.apps.isEmpty ? String(localized: "All Apps") : gesture.apps.map(appName).joined(separator: ", "),
         actions(gesture, themes: themes).map(\.name).joined(separator: ", ")]
            .map { $0.isEmpty ? "—" : $0 }
    }

    func summary(_ gesture: CursorGesture, themes: [(id: String, name: String)] = [],
                 appName: (String) -> String = CursorGestures.appName) -> String {
        summaryParts(gesture, themes: themes, appName: appName).joined(separator: " → ")
    }

    func value(_ step: CursorGestureEditorStep, of gesture: CursorGesture, themes: [(id: String, name: String)] = [],
               appName: (String) -> String = CursorGestures.appName) -> String {
        let parts = summaryParts(gesture, themes: themes, appName: appName)
        switch step {
        case .shape: return parts[1]
        case .trigger:
            let triggers = gesture.triggers.filter { !$0.label.isEmpty }.map { $0.label + " · " + $0.device.name }
            return triggers.isEmpty ? "—" : triggers.joined(separator: ", ")
        case .actions: return parts[3]
        case .details:
            let name = title(gesture, themes: themes)
            return (name.isEmpty ? "—" : name) + " · " + parts[2]
        }
    }

    var scopedApps: [String] {
        gestures.flatMap(\.apps).reduce(into: []) { apps, app in
            if !apps.contains(app) { apps.append(app) }
        }
    }

    func available(_ filter: CursorGestureFilter) -> CursorGestureFilter {
        switch filter {
        case .allApps where !gestures.contains(where: { $0.apps.isEmpty }): .all
        case .app(let app) where !scopedApps.contains(app): .all
        default: filter
        }
    }

    func groups(_ filter: CursorGestureFilter, search: String = "",
                themes: [(id: String, name: String)] = []) -> [CursorGestureGroup<CursorGesture>] {
        let search = search.trimmingCharacters(in: .whitespaces)
        let shown = gestures.filter { gesture in
            let scoped = switch filter {
            case .all: true
            case .allApps: gesture.apps.isEmpty
            case .app(let app): gesture.apps.contains(app)
            }
            let names = [title(gesture, themes: themes), shape(gesture.shape)?.name ?? ""] + actions(gesture, themes: themes).map(\.name)
            return scoped && (search.isEmpty || names.contains { $0.localizedCaseInsensitiveContains(search) })
        }
        return CursorGestures.grouped(shown) { shape($0.shape)?.family }
    }

    func shapeGroups(search: String = "") -> [CursorGestureGroup<CursorGestureShape>] {
        let search = search.trimmingCharacters(in: .whitespaces)
        return CursorGestures.grouped(allShapes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) },
                                      by: \.family)
    }

    mutating func ignore(_ app: String, _ on: Bool) {
        if !on {
            ignored.removeAll { $0.app == app }
        } else if !ignored.contains(where: { $0.app == app }) {
            ignored.append(CursorGestureIgnoredApp(app: app))
        }
    }

    func blocks(button: Bool, front: String?, pointer: @autoclosure () -> String? = nil) -> Bool {
        var under: String??
        return ignored.contains { entry in
            guard entry.block == .all || (entry.block == .buttons) == button else { return false }
            guard !entry.frontOnly else { return entry.app == front }
            under = under ?? pointer()
            return entry.app == under
        }
    }

    private func template(_ shape: String) -> CursorGestureTemplate? {
        CursorGestures.templates[shape] ?? shapes.first { $0.id == shape }.flatMap { CursorGestureTemplate($0.points, directional: $0.directional) }
    }
}

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decode(T.self, forKey: key)) ?? fallback
    }
}

extension CursorGestureTrigger {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        keys = c.value(.keys, keys)
        button = c.value(.button, button)
        twoFinger = c.value(.twoFinger, twoFinger)
        device = c.value(.device, device)
    }
}

extension CursorGestureStep {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(action: try c.decode(String.self, forKey: .action))
        id = c.value(.id, id)
        wait = c.value(.wait, wait)
        enabled = c.value(.enabled, enabled)
    }
}

extension CursorGesture {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        id = c.value(.id, id)
        name = c.value(.name, name)
        enabled = c.value(.enabled, enabled)
        shape = c.value(.shape, shape)
        triggers = c.value(.triggers, triggers)
        apps = c.value(.apps, apps)
        steps = c.value(.steps, steps)
    }
}

extension CursorGestureShape {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        id = c.value(.id, id)
        name = c.value(.name, name)
        points = c.value(.points, points)
        directional = c.value(.directional, directional)
        family = c.value(.family, family)
    }
}

extension CursorGestureAction {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), icon: try c.decode(String.self, forKey: .icon),
                  kind: try c.decode(CursorGestureKind.self, forKey: .kind))
        id = c.value(.id, id)
        detail = c.value(.detail, detail)
        category = c.value(.category, category)
    }
}

extension CursorGestureIgnoredApp {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(app: try c.decode(String.self, forKey: .app))
        block = c.value(.block, block)
        frontOnly = c.value(.frontOnly, frontOnly)
    }
}

extension CursorGesturesConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        enabled = c.value(.enabled, enabled)
        readyMadeAdded = c.value(.readyMadeAdded, readyMadeAdded)
        gestures = c.value(.gestures, gestures)
        shapes = c.value(.shapes, shapes)
        actions = c.value(.actions, actions)
        ignored = c.value(.ignored, ignored)
        strictness = c.value(.strictness, strictness)
        minimumSize = c.value(.minimumSize, minimumSize)
        raiseWindow = c.value(.raiseWindow, raiseWindow)
        showLine = c.value(.showLine, showLine)
        colorByResult = c.value(.colorByResult, colorByResult)
        showShapeName = c.value(.showShapeName, showShapeName)
        repeatMouse = c.value(.repeatMouse, repeatMouse)
        repeatTrackpad = c.value(.repeatTrackpad, repeatTrackpad)
        switchWhileRepeating = c.value(.switchWhileRepeating, switchWhileRepeating)
        lineColor = c.value(.lineColor, lineColor)
        lineWidth = c.value(.lineWidth, lineWidth)
        ignorePostedClicks = c.value(.ignorePostedClicks, ignorePostedClicks)
    }
}

struct CursorGestureTemplate {
    let plain: [CGFloat]
    let turned: [CGFloat]
    let reversed: [CGFloat]
    let linear: Bool
    let corner: Bool
    let closure: CGFloat
    let directional: Bool

    init?(_ raw: [CGPoint], directional: Bool = true) {
        let points = CursorGestures.resample(raw)
        guard points.count == CursorGestures.count else { return nil }
        closure = CursorGestures.closure(points)
        linear = CursorGestures.linear(points, closure: closure)
        corner = CursorGestures.corner(points)
        self.directional = directional
        let uniform = linear && !corner
        plain = CursorGestures.vector(points, turn: false, uniform: uniform)
        turned = CursorGestures.vector(points, turn: true, uniform: uniform)
        reversed = CursorGestures.vector(points.reversed(), turn: true, uniform: uniform)
    }

    func distance(to template: CursorGestureTemplate) -> CGFloat? {
        guard linear == template.linear || linear && corner else { return nil }
        var distance = template.directional ? acos(min(max(Self.dot(plain, template.plain), -1), 1))
            : min(Self.rotated(turned, template.turned), Self.rotated(reversed, template.turned))
        if !linear && corner != template.corner { distance += 0.47 }
        return distance + 1.2 * abs(closure - template.closure)
    }

    private static func dot(_ a: [CGFloat], _ b: [CGFloat]) -> CGFloat {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func rotated(_ a: [CGFloat], _ b: [CGFloat]) -> CGFloat {
        var same: CGFloat = 0, cross: CGFloat = 0
        for index in stride(from: 0, to: min(a.count, b.count) - 1, by: 2) {
            same += a[index] * b[index] + a[index + 1] * b[index + 1]
            cross += a[index] * b[index + 1] - a[index + 1] * b[index]
        }
        return acos(min(hypot(same, cross), 1))
    }
}

enum CursorGestures {
    static let count = 64
    static let threshold: CGFloat = 0.75
    static let minimumSize: CGFloat = 10
    static let appMargin: CGFloat = 0.2
    static let themePrefix = "theme:"
    static let textLimit = 500

    static let shapes: [CursorGestureShape] = {
        let u = [CGPoint(x: -1, y: 1)] + arc(0, 0, 1, 180, 360) + [CGPoint(x: 1, y: 1)]
        let arch = [CGPoint(x: -1, y: -1)] + arc(0, 0, 1, 180, 0) + [CGPoint(x: 1, y: -1)]
        let v = walk([(0.5, -1), (0.5, 1)])
        return [
            shape("lineUp", "Line Up", .lines, walk([(0, 1)])),
            shape("lineDown", "Line Down", .lines, walk([(0, -1)])),
            shape("lineLeft", "Line Left", .lines, walk([(-1, 0)])),
            shape("lineRight", "Line Right", .lines, walk([(1, 0)])),
            shape("slantUpRight", "Slant Up Right", .diagonals, walk([(1, 1)])),
            shape("slantUpLeft", "Slant Up Left", .diagonals, walk([(-1, 1)])),
            shape("slantDownRight", "Slant Down Right", .diagonals, walk([(1, -1)])),
            shape("slantDownLeft", "Slant Down Left", .diagonals, walk([(-1, -1)])),
            shape("rightThenDown", "Right, Then Down", .corners, walk([(1, 0), (0, -1)])),
            shape("rightThenUp", "Right, Then Up", .corners, walk([(1, 0), (0, 1)])),
            shape("leftThenDown", "Left, Then Down", .corners, walk([(-1, 0), (0, -1)])),
            shape("leftThenUp", "Left, Then Up", .corners, walk([(-1, 0), (0, 1)])),
            shape("downThenRight", "Down, Then Right", .corners, walk([(0, -1), (1, 0)])),
            shape("downThenLeft", "Down, Then Left", .corners, walk([(0, -1), (-1, 0)])),
            shape("upThenRight", "Up, Then Right", .corners, walk([(0, 1), (1, 0)])),
            shape("upThenLeft", "Up, Then Left", .corners, walk([(0, 1), (-1, 0)])),
            shape("upAndBack", "Up and Back", .returns, walk([(0, 1), (0, -1)])),
            shape("downAndBack", "Down and Back", .returns, walk([(0, -1), (0, 1)])),
            shape("leftAndBack", "Left and Back", .returns, walk([(-1, 0), (1, 0)])),
            shape("rightAndBack", "Right and Back", .returns, walk([(1, 0), (-1, 0)])),
            shape("upRightAndBack", "Up Right and Back", .returns, walk([(1, 1), (-1, -1)])),
            shape("upLeftAndBack", "Up Left and Back", .returns, walk([(-1, 1), (1, -1)])),
            shape("downRightAndBack", "Down Right and Back", .returns, walk([(1, -1), (-1, 1)])),
            shape("downLeftAndBack", "Down Left and Back", .returns, walk([(-1, -1), (1, 1)])),
            letter("c", .curves, arc(0, 0, 1, 45, 315)),
            shape("backwardC", "Backward C", .curves, arc(0, 0, 1, 135, -135)),
            letter("u", .curves, u),
            shape("uRightToLeft", "U, Right to Left", .curves, u.reversed()),
            shape("arch", "Arch", .curves, arch),
            shape("archRightToLeft", "Arch, Right to Left", .curves, arch.reversed()),
            shape("circle", "Circle", .curves, arc(0, 0, 1, 0, 360), directional: false),
            letter("v", .letters, v),
            shape("vRightToLeft", "V, Right to Left", .letters, v.reversed()),
            shape("peak", "Peak", .letters, walk([(0.5, 1), (0.5, -1)])),
            letter("z", .letters, walk([(1, 0), (-1, -1), (1, 0)])),
            letter("s", .letters, arc(0, 0.5, 0.5, 30, 270) + arc(0, -0.5, 0.5, 90, -150)),
            letter("n", .letters, walk([(0, 1), (1, -1), (0, 1)])),
            letter("m", .letters, walk([(0, 1), (0.5, -0.6), (0.5, 0.6), (0, -1)])),
            letter("w", .letters, walk([(0.25, -1), (0.25, 0.6), (0.25, -0.6), (0.25, 1)])),
        ]
    }()

    static let clickShape = shape("click", "Short Click", .clicks, [])

    static func isAppWindow(_ info: [String: Any]) -> Bool {
        (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 && ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0) > 0
    }

    static func owner(at point: CGPoint, in windows: [[String: Any]]) -> pid_t? {
        let window = windows.first { info in
            isAppWindow(info) && ((info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?.contains(point) ?? false)
        }
        return window?[kCGWindowOwnerPID as String] as? pid_t
    }

    static func app(at point: CGPoint) -> String? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let owner = owner(at: point, in: windows) else { return nil }
        return NSRunningApplication(processIdentifier: owner)?.bundleIdentifier
    }

    static let templates: [String: CursorGestureTemplate] = Dictionary(uniqueKeysWithValues: shapes.compactMap { shape in
        CursorGestureTemplate(shape.points, directional: shape.directional).map { (shape.id, $0) }
    })

    static let actions: [CursorGestureAction] = [
        action("undo", "Undo", String(localized: "Take back your last change"), "arrow.uturn.backward", .general, key(6, "z", .command)),
        action("redo", "Redo", String(localized: "Bring back what you took back"), "arrow.uturn.forward", .general, key(6, "z", [.shift, .command])),
        action("switchApp", "Switch to Last App", String(localized: "Go to the app you used before this one"), "arrow.left.arrow.right", .general, key(48, nil, .command)),
        action("back", "Back", String(localized: "Go to the page you saw before"), "chevron.backward", .browser, key(33, "[", .command)),
        action("forward", "Forward", String(localized: "Go to the page you saw after this one"), "chevron.forward", .browser, key(30, "]", .command)),
        action("pageTop", "Top of Page", String(localized: "Jump to the start of the page"), "arrow.up.to.line", .browser, key(126, nil, .command)),
        action("pageBottom", "Bottom of Page", String(localized: "Jump to the end of the page"), "arrow.down.to.line", .browser, key(125, nil, .command)),
        action("newTab", "New Tab", String(localized: "Open an empty tab"), "plus.square.on.square", .browser, key(17, "t", .command)),
        action("closeTab", "Close Tab", String(localized: "Close the tab you are on"), "xmark.square", .browser, key(13, "w", .command)),
        action("reload", "Reload Page", String(localized: "Load the page again"), "arrow.clockwise", .browser, key(15, "r", .command)),
        action("reopenTab", "Reopen Last Closed Tab", String(localized: "Bring back the tab you closed"), "arrow.counterclockwise", .browser, key(17, "t", [.shift, .command])),
        action("nextTab", "Show Next Tab", String(localized: "Move one tab to the right"), "arrow.right.square", .browser, key(124, nil, [.option, .command])),
        action("previousTab", "Show Previous Tab", String(localized: "Move one tab to the left"), "arrow.left.square", .browser, key(123, nil, [.option, .command])),
        action("copy", "Copy", String(localized: "Put the selection on the clipboard"), "doc.on.doc", .clipboard, key(8, "c", .command)),
        action("cut", "Cut", String(localized: "Move the selection to the clipboard"), "scissors", .clipboard, key(7, "x", .command)),
        action("paste", "Paste", String(localized: "Insert what is on the clipboard"), "doc.on.clipboard", .clipboard, key(9, "v", .command)),
        snap(.leftHalf, "Left Half", "rectangle.lefthalf.filled"),
        snap(.rightHalf, "Right Half", "rectangle.righthalf.filled"),
        snap(.topHalf, "Top Half", "rectangle.tophalf.filled"),
        snap(.bottomHalf, "Bottom Half", "rectangle.bottomhalf.filled"),
        snap(.topLeftQuarter, "Top Left Quarter", "rectangle.split.2x2"),
        snap(.topRightQuarter, "Top Right Quarter", "rectangle.split.2x2"),
        snap(.bottomLeftQuarter, "Bottom Left Quarter", "rectangle.split.2x2"),
        snap(.bottomRightQuarter, "Bottom Right Quarter", "rectangle.split.2x2"),
        snap(.leftThird, "Left Third", "rectangle.split.3x1"),
        snap(.centerThird, "Center Third", "rectangle.split.3x1"),
        snap(.rightThird, "Right Third", "rectangle.split.3x1"),
        snap(.leftTwoThirds, "Left Two Thirds", "rectangle.split.3x1"),
        snap(.rightTwoThirds, "Right Two Thirds", "rectangle.split.3x1"),
        snap(.maximize, "Maximize", "arrow.up.left.and.arrow.down.right"),
        snap(.center, "Center", "rectangle.center.inset.filled"),
        operation(.nextDisplay, "Next Display", String(localized: "Move the window to the next display"), "display.2", .windows),
        operation(.restoreSize, "Restore Size", String(localized: "Put the window back where it was"), "arrow.uturn.backward.circle", .windows),
        operation(.minimize, "Minimize", String(localized: "Send the window to the Dock"), "minus.rectangle", .windows),
        operation(.closeWindow, "Close Window", String(localized: "Close the window under the pointer"), "xmark.rectangle", .windows),
        action("fullScreen", "Full Screen", String(localized: "Fill the screen with the window, or go back"), "arrow.up.backward.and.arrow.down.forward", .windows, key(3, "f", [.control, .command])),
        operation(.hideApp, "Hide App", String(localized: "Hide every window of the app"), "eye.slash", .windows),
        action("missionControl", "Mission Control", String(localized: "See all open windows at once"), "rectangle.3.group", .system, key(126, nil, .control)),
        action("appExpose", "App Exposé", String(localized: "See the windows of the app in front"), "square.stack.3d.up", .system, key(125, nil, .control)),
        action("spaceLeft", "Move Left a Space", String(localized: "Go to the Space on the left"), "chevron.left.2", .system, key(123, nil, .control)),
        action("spaceRight", "Move Right a Space", String(localized: "Go to the Space on the right"), "chevron.right.2", .system, key(124, nil, .control)),
        action("showDesktop", "Show Desktop", String(localized: "Move every window aside"), "menubar.dock.rectangle", .system, key(103, nil, [])),
        action("spotlight", "Spotlight", String(localized: "Search your Mac"), "magnifyingglass", .system, key(49, nil, .command)),
        action("lockScreen", "Lock Screen", String(localized: "Lock the Mac right away"), "lock", .system, key(12, "q", [.control, .command])),
        action("forceQuit", "Force Quit Window", String(localized: "Choose an app that is not responding"), "exclamationmark.octagon", .system, key(53, nil, [.option, .command])),
        action("screenshot", "Screenshot of the Screen", String(localized: "Save a picture of the whole screen"), "camera", .system, key(20, nil, [.shift, .command])),
        operation(.screenshotArea, "Screenshot of an Area", String(localized: "Save a picture of the part you choose"), "camera.viewfinder", .system),
        action("screenshotOptions", "Screenshot Options", String(localized: "Open the screenshot tools"), "camera.aperture", .system, key(23, nil, [.shift, .command])),
        operation(.capturePreviousArea, "Capture Previous Area", String(localized: "Take a picture of the same area again"), "repeat", .system),
        operation(.captureFullscreen, "Capture Fullscreen", String(localized: "Take a picture of the screen under the pointer"), "display", .system),
        operation(.captureSelfTimer, "Self-Timer", String(localized: "Choose a part, and the picture is taken after a wait"), "timer", .system),
        operation(.captureText, "Capture Text (OCR)", String(localized: "Copy the text in the part you choose"), "text.viewfinder", .system),
        operation(.captureOpen, "Open...", String(localized: "Open a picture file in the editor"), "folder", .system),
        operation(.captureOpenClipboard, "Open from Clipboard", String(localized: "Open the picture on the clipboard in the editor"), "doc.on.clipboard", .system),
        operation(.capturePin, "Pin to the Screen...", String(localized: "Keep a picture on top of your windows"), "pin", .system),
        operation(.captureHistory, "Capture History...", String(localized: "See the pictures you took before"), "clock.arrow.circlepath", .system),
        operation(.volumeUp, "Volume Up", String(localized: "Make the sound louder"), "speaker.wave.3", .system),
        operation(.volumeDown, "Volume Down", String(localized: "Make the sound quieter"), "speaker.wave.1", .system),
        operation(.mute, "Mute", String(localized: "Turn the sound off or on"), "speaker.slash", .system),
        operation(.brightnessUp, "Brightness Up", String(localized: "Make the display brighter"), "sun.max", .system),
        operation(.brightnessDown, "Brightness Down", String(localized: "Make the display darker"), "sun.min", .system),
        operation(.sleep, "Sleep", String(localized: "Put the Mac to sleep"), "moon", .system),
        operation(.screenSaver, "Start Screen Saver", String(localized: "Show the screen saver now"), "sparkles.tv", .system),
        operation(.nextFavoriteTheme, "Next Favorite Theme", String(localized: "Apply the next theme in your favorites"), "star", .macursor),
        operation(.systemCursors, "Use System Cursors", String(localized: "Go back to the standard macOS cursors"), "cursorarrow", .macursor),
        operation(.cursorShadow, "Cursor Shadow", String(localized: "Turn it on, or off when it is on"), "shadow", .macursor),
        operation(.focusOnHover, "Focus on Hover", String(localized: "Turn it on, or off when it is on"), "macwindow.on.rectangle", .macursor),
        operation(.cursorTranslator, "Cursor Translator", String(localized: "Turn it on, or off when it is on"), "text.bubble", .macursor),
        operation(.cursorShaker, "Cursor Shaker", String(localized: "Turn it on, or off when it is on"), "arrow.left.and.right", .macursor),
        operation(.cursorTrails, "Cursor Trails", String(localized: "Turn it on, or off when it is on"), "cursorarrow.motionlines", .macursor),
        operation(.switchByApp, "Per-App Themes", String(localized: "Turn it on, or off when it is on"), "app.badge", .macursor),
    ]

    static let readyMade: [CursorGesture] = {
        let option = CursorGestureTrigger(keys: NSEvent.ModifierFlags.option.rawValue)
        let right = CursorGestureTrigger(button: 1, device: .mouse)
        let rows: [(Int, String, [CursorGestureTrigger], String)] = [
            (1, "lineLeft", [option], "back"),
            (2, "lineRight", [option], "forward"),
            (3, "lineUp", [option], "pageTop"),
            (4, "lineDown", [option], "pageBottom"),
            (19, "c", [option, right], "copy"),
        ]
        return rows.map { number, shape, triggers, action in
            CursorGesture(id: UUID(uuidString: String(format: "4D614375-7273-6F72-4765-%012X", number)) ?? UUID(),
                          shape: shape, triggers: triggers, steps: [CursorGestureStep(action: action)])
        }
    }()

    static func theme(_ identifier: String, name: String = "") -> CursorGestureAction {
        CursorGestureAction(id: themePrefix + identifier, name: name, detail: String(localized: "Apply this theme"), icon: "cursorarrow.rays",
                            category: .macursor, kind: .theme(identifier))
    }

    static func catalogue(_ config: CursorGesturesConfig, themes: [(id: String, name: String)]) -> [CursorGestureAction] {
        actions + themes.map { theme($0.id, name: $0.name) } + config.actions
    }

    static func listed(_ category: CursorGestureCategory?, in actions: [CursorGestureAction]) -> CursorGestureCategory? {
        actions.contains { $0.category == category } ? category : nil
    }

    static func custom(_ kind: CursorGestureKind, name: String, id: String = UUID().uuidString) -> CursorGestureAction {
        let (icon, category, detail): (String, CursorGestureCategory, String) = switch kind {
        case .shortcut: ("command", .custom, "")
        case .text(let text): ("text.cursor", .custom, text)
        case .app(let path): ("app", .apps, path.isEmpty ? "" : FileManager.default.displayName(atPath: path))
        case .website(let address): ("globe", .apps, address)
        case .theme, .operation: ("questionmark", .custom, "")
        }
        return CursorGestureAction(id: id, name: name, detail: detail, icon: icon, category: category, kind: kind)
    }

    static func hex(_ color: CGColor) -> UInt32 {
        let rgb = CGColorSpace(name: CGColorSpace.sRGB).flatMap { color.converted(to: $0, intent: .defaultIntent, options: nil) }?.components ?? []
        return rgb.prefix(3).reduce(0) { $0 << 8 | UInt32((min(max($1, 0), 1) * 255).rounded()) }
    }

    @MainActor static func play(_ steps: ArraySlice<CursorGestureStep>, wait: @escaping @MainActor (Int, @escaping @MainActor () -> Void) -> Void,
                                live: @escaping @MainActor () -> Bool, run: @escaping @MainActor (String) -> Bool,
                                done: @escaping @MainActor () -> Void) {
        guard let step = steps.first else { return done() }
        guard step.enabled else { return play(steps.dropFirst(), wait: wait, live: live, run: run, done: done) }
        wait(steps.startIndex == 0 ? 0 : max(step.wait ?? 0, 0)) {
            guard live() else { return }
            guard run(step.action) else { return done() }
            play(steps.dropFirst(), wait: wait, live: live, run: run, done: done)
        }
    }

    static func resample(_ points: [CGPoint]) -> [CGPoint] {
        let lengths = zip(points, points.dropFirst()).reduce(into: [CGFloat(0)]) { lengths, pair in
            lengths.append(lengths[lengths.count - 1] + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y))
        }
        guard let total = lengths.last, total > 0 else { return [] }
        var segment = 1
        return (0..<count).map { index in
            let distance = total * CGFloat(index) / CGFloat(count - 1)
            while segment < points.count - 1, lengths[segment] < distance { segment += 1 }
            let start = points[segment - 1], end = points[segment]
            let span = lengths[segment] - lengths[segment - 1]
            let t = span > 0 ? (distance - lengths[segment - 1]) / span : 0
            return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
        }
    }

    static func percent(_ score: CGFloat) -> Int {
        Int((min(max(score, 0), 1) * 100).rounded())
    }

    static func target(_ gesture: CursorGesture, _ window: MACFFMWindow?, front: String?) -> MACFFMWindow? {
        gesture.shape != clickShape.id || front != nil && window?.owner.bundleIdentifier == front ? window : nil
    }

    static func extent(_ points: [CGPoint]) -> CGFloat {
        let box = bounds(points)
        return hypot(box.width, box.height)
    }

    static func closure(_ points: [CGPoint]) -> CGFloat {
        let box = bounds(points), diagonal = hypot(box.width, box.height)
        guard let first = points.first, let last = points.last, diagonal > 0 else { return 0 }
        return min(hypot(last.x - first.x, last.y - first.y) / diagonal, 1)
    }

    static func linear(_ points: [CGPoint], closure: CGFloat) -> Bool {
        guard closure >= 0.15, let first = points.first, let last = points.last else { return false }
        let chord = hypot(last.x - first.x, last.y - first.y)
        let spread = points.reduce(0) { $0 + abs(($1.x - first.x) * (last.y - first.y) - ($1.y - first.y) * (last.x - first.x)) / chord }
        return spread / CGFloat(points.count) / chord < 0.15
    }

    static func corner(_ points: [CGPoint]) -> Bool {
        let arc = zip(points, points.dropFirst()).reduce(into: [CGFloat(0)]) { $0.append($0[$0.count - 1] + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) }
        let reach = arc[arc.count - 1] * 0.1
        return points.indices.contains { index in
            guard let back = points.indices[..<index].last(where: { arc[index] - arc[$0] >= reach }),
                  let ahead = points.indices[(index + 1)...].first(where: { arc[$0] - arc[index] >= reach }) else { return false }
            let turn = abs(atan2(points[ahead].y - points[index].y, points[ahead].x - points[index].x) -
                atan2(points[index].y - points[back].y, points[index].x - points[back].x))
            return min(turn, 2 * .pi - turn) >= 65 * .pi / 180
        }
    }

    static func vector(_ points: [CGPoint], turn: Bool, uniform: Bool) -> [CGFloat] {
        var points = points
        let middle = centroid(points)
        if turn, let first = points.first {
            let angle = -atan2(middle.y - first.y, middle.x - first.x)
            points = points.map { point in
                CGPoint(x: middle.x + (point.x - middle.x) * cos(angle) - (point.y - middle.y) * sin(angle),
                        y: middle.y + (point.x - middle.x) * sin(angle) + (point.y - middle.y) * cos(angle))
            }
        }
        let box = bounds(points)
        let width = max(box.width, .ulpOfOne), height = max(box.height, .ulpOfOne)
        let uniform = uniform || thin(points) ? max(width, height) : nil
        let scaled = points.map { CGPoint(x: $0.x / (uniform ?? width), y: $0.y / (uniform ?? height)) }
        let centre = centroid(scaled)
        let flat = scaled.flatMap { [$0.x - centre.x, $0.y - centre.y] }
        let length = flat.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? flat.map { $0 / length } : flat
    }

    static func recorded(_ canvas: [CGPoint]) -> [CGPoint]? {
        let points = resample(canvas.map { CGPoint(x: $0.x, y: -$0.y) })
        let box = bounds(points)
        let size = max(box.width, box.height)
        guard canvas.count >= 5, size >= minimumSize else { return nil }
        return points.map { CGPoint(x: ($0.x - box.midX) / size, y: ($0.y - box.midY) / size) }
    }

    static func nextFavorite(after current: String?, in favorites: [String]) -> String? {
        guard let first = favorites.first else { return nil }
        guard let current, let index = favorites.firstIndex(of: current) else { return first }
        return favorites[(index + 1) % favorites.count]
    }

    static func appName(_ app: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app).map { FileManager.default.displayName(atPath: $0.path) } ?? app
    }

    static func grouped<Item>(_ items: [Item], by family: (Item) -> CursorGestureFamily?) -> [CursorGestureGroup<Item>] {
        ([nil] + CursorGestureFamily.allCases.map(Optional.some)).compactMap { wanted in
            let members = items.filter { family($0) == wanted }
            return members.isEmpty ? nil : CursorGestureGroup(family: wanted, items: members)
        }
    }

    static func website(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: text.contains("://") ? text : "https://" + text),
              ["http", "https"].contains(url.scheme?.lowercased()), url.host != nil else { return nil }
        return url
    }

    private static func thin(_ points: [CGPoint]) -> Bool {
        let middle = centroid(points)
        let spread = points.reduce((xx: CGFloat(0), yy: CGFloat(0), xy: CGFloat(0))) { sum, point in
            let x = point.x - middle.x, y = point.y - middle.y
            return (sum.xx + x * x, sum.yy + y * y, sum.xy + x * y)
        }
        let angle = atan2(2 * spread.xy, spread.xx - spread.yy) / 2
        let along = points.map { ($0.x - middle.x) * cos(angle) + ($0.y - middle.y) * sin(angle) }
        let across = points.map { ($0.y - middle.y) * cos(angle) - ($0.x - middle.x) * sin(angle) }
        let long = (along.max() ?? 0) - (along.min() ?? 0), short = (across.max() ?? 0) - (across.min() ?? 0)
        return min(long, short) < 0.15 * max(long, short)
    }

    private static func bounds(_ points: [CGPoint]) -> CGRect {
        points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    private static func centroid(_ points: [CGPoint]) -> CGPoint {
        let count = CGFloat(max(points.count, 1))
        return CGPoint(x: points.reduce(0) { $0 + $1.x } / count, y: points.reduce(0) { $0 + $1.y } / count)
    }

    private static func walk(_ steps: [(CGFloat, CGFloat)]) -> [CGPoint] {
        steps.reduce(into: [CGPoint.zero]) { points, step in
            points.append(CGPoint(x: points[points.count - 1].x + step.0, y: points[points.count - 1].y + step.1))
        }
    }

    private static func arc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ from: CGFloat, _ to: CGFloat) -> [CGPoint] {
        (0...48).map { index in
            let angle = (from + (to - from) * CGFloat(index) / 48) * .pi / 180
            return CGPoint(x: x + radius * cos(angle), y: y + radius * sin(angle))
        }
    }

    private static func shape(_ id: String, _ name: String.LocalizationValue, _ family: CursorGestureFamily, _ points: [CGPoint],
                              directional: Bool = true) -> CursorGestureShape {
        CursorGestureShape(id: id, name: String(localized: name), points: points, directional: directional, family: family)
    }

    private static func letter(_ id: String, _ family: CursorGestureFamily, _ points: [CGPoint]) -> CursorGestureShape {
        CursorGestureShape(id: id, name: id.uppercased(), points: points, family: family)
    }

    private static func key(_ keyCode: UInt16, _ character: String?, _ flags: NSEvent.ModifierFlags) -> CursorGestureKind {
        .shortcut(CursorGestureShortcut(keyCode: keyCode, flags: flags.rawValue, character: character))
    }

    private static func action(_ id: String, _ name: String.LocalizationValue, _ detail: String, _ icon: String, _ category: CursorGestureCategory,
                               _ kind: CursorGestureKind) -> CursorGestureAction {
        CursorGestureAction(id: id, name: String(localized: name), detail: detail, icon: icon, category: category, kind: kind,
                            key: LocalizedStringResource(name).key)
    }

    private static func operation(_ operation: CursorGestureOperation, _ name: String.LocalizationValue, _ detail: String, _ icon: String,
                                  _ category: CursorGestureCategory) -> CursorGestureAction {
        action(operation.rawValue, name, detail, icon, category, .operation(operation))
    }

    private static func snap(_ operation: CursorGestureOperation, _ name: String.LocalizationValue, _ icon: String) -> CursorGestureAction {
        self.operation(operation, name, String(localized: "Fit the window under the pointer to this place"), icon, .windows)
    }
}

enum CursorGestureWindow {
    private static let third: CGFloat = 1 / 3
    private static let units: [CursorGestureOperation: CGRect] = [
        .leftHalf: CGRect(x: 0, y: 0, width: 0.5, height: 1), .rightHalf: CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
        .topHalf: CGRect(x: 0, y: 0.5, width: 1, height: 0.5), .bottomHalf: CGRect(x: 0, y: 0, width: 1, height: 0.5),
        .topLeftQuarter: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), .topRightQuarter: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        .bottomLeftQuarter: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), .bottomRightQuarter: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
        .leftThird: CGRect(x: 0, y: 0, width: third, height: 1), .centerThird: CGRect(x: third, y: 0, width: third, height: 1),
        .rightThird: CGRect(x: 2 * third, y: 0, width: third, height: 1),
        .leftTwoThirds: CGRect(x: 0, y: 0, width: 2 * third, height: 1), .rightTwoThirds: CGRect(x: third, y: 0, width: 2 * third, height: 1),
        .maximize: CGRect(x: 0, y: 0, width: 1, height: 1),
    ]

    static func flip(_ rect: CGRect, _ primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(origin: MACFFMConvertToAXPoint(CGPoint(x: rect.minX, y: rect.maxY), primaryScreenHeight), size: rect.size)
    }

    static func frame(_ action: CursorGestureOperation, window: CGRect, screens: [(frame: CGRect, visible: CGRect)], pointer: CGPoint,
                      saved: inout [CFHashCode: CGRect], key: CFHashCode) -> CGRect? {
        if action == .restoreSize { return saved.removeValue(forKey: key) }
        let screens = screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        let overlaps = screens.map { $0.frame.intersection(window) }.map { $0.isNull ? 0 : $0.width * $0.height }
        guard let index = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }).flatMap({ overlaps[$0] > 0 ? $0 : nil })
                ?? screens.firstIndex(where: { $0.frame.contains(pointer) }) else { return nil }
        let visible = screens[index].visible
        let target: CGRect
        if let unit = units[action] {
            target = place(unit, in: visible)
        } else if action == .center {
            target = fit(CGRect(x: visible.midX - window.width / 2, y: visible.midY - window.height / 2, width: window.width, height: window.height), in: visible)
        } else if action == .nextDisplay, screens.count > 1 {
            let next = screens[(index + 1) % screens.count].visible
            target = fit(place(CGRect(x: (window.minX - visible.minX) / visible.width, y: (window.minY - visible.minY) / visible.height,
                                      width: window.width / visible.width, height: window.height / visible.height), in: next), in: next)
        } else {
            return nil
        }
        if saved[key] == nil { saved[key] = window }
        return target
    }

    private static func place(_ unit: CGRect, in visible: CGRect) -> CGRect {
        CGRect(x: visible.minX + unit.minX * visible.width, y: visible.minY + unit.minY * visible.height,
               width: unit.width * visible.width, height: unit.height * visible.height)
    }

    private static func fit(_ rect: CGRect, in visible: CGRect) -> CGRect {
        let width = min(rect.width, visible.width), height = min(rect.height, visible.height)
        return CGRect(x: min(max(rect.minX, visible.minX), visible.maxX - width), y: min(max(rect.minY, visible.minY), visible.maxY - height),
                      width: width, height: height)
    }
}

struct CursorGestureStroke {
    enum Phase { case idle, drawing, blocked }

    static let keys: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]

    let triggers: Set<UInt>
    private let all: NSEvent.ModifierFlags
    private(set) var phase = Phase.idle
    private(set) var points: [CGPoint] = []
    private(set) var trigger: NSEvent.ModifierFlags = []

    init(triggers: [NSEvent.ModifierFlags]) {
        let held = triggers.map { $0.intersection(Self.keys) }.filter { !$0.isEmpty }
        self.triggers = Set(held.map(\.rawValue))
        all = held.reduce([]) { $0.union($1) }
    }

    mutating func moved(to point: CGPoint, flags: NSEvent.ModifierFlags, buttons: Int) -> [CGPoint]? {
        if let finished = flagsChanged(flags) { return finished }
        let held = flags.intersection(Self.keys)
        guard phase == .drawing || phase == .idle && triggers.contains(held.rawValue) else { return nil }
        guard buttons == 0 else {
            cancel(flags)
            return nil
        }
        if phase == .idle { trigger = held }
        phase = .drawing
        points.append(point)
        return nil
    }

    mutating func flagsChanged(_ flags: NSEvent.ModifierFlags) -> [CGPoint]? {
        let held = flags.intersection(Self.keys)
        if phase == .blocked, held.isDisjoint(with: all) { phase = .idle }
        guard phase == .drawing, held != trigger else { return nil }
        let finished = held.isStrictSubset(of: trigger) ? points : nil
        cancel(flags)
        return finished
    }

    mutating func cancel(_ flags: NSEvent.ModifierFlags) {
        points = []
        phase = flags.isDisjoint(with: all) ? .idle : .blocked
    }

    mutating func clear() {
        points = []
    }
}

struct CursorGesturePress: Equatable {
    static let reach: CGFloat = 12

    let button: Int
    let start: CGPoint
    let trigger: CursorGestureTrigger
    private(set) var drawing = false
    private(set) var points: [CGPoint] = []

    init(button: Int, start: CGPoint, trigger: CursorGestureTrigger) {
        self.button = button
        self.start = start
        self.trigger = trigger
    }

    var click: CGPoint? { drawing ? nil : start }

    mutating func dragged(to point: CGPoint) {
        if !drawing, hypot(point.x - start.x, point.y - start.y) >= Self.reach {
            drawing = true
            points = [start]
        }
        if drawing { points.append(point) }
    }

    mutating func clear() {
        points = []
    }
}

struct CursorGestureRepeat: Equatable {
    static let settle: TimeInterval = 0.15
    static let gap: TimeInterval = 0.1
    static let limit: TimeInterval = 30
    static let switchPoints = 5
    static let switchSize: CGFloat = 30

    let trigger: CursorGestureTrigger
    let began: TimeInterval
    private(set) var gesture: CursorGesture
    private(set) var last: TimeInterval

    init?(_ drawn: [CGPoint], trigger: CursorGestureTrigger, started: TimeInterval, at now: TimeInterval,
          config: CursorGesturesConfig, front: String?) {
        guard now - started >= Self.settle, let gesture = config.match(for: drawn, trigger: trigger, front: front)?.gesture else { return nil }
        self.trigger = trigger
        self.gesture = gesture
        began = now
        last = now
    }

    static func holds(_ repeating: CursorGestureRepeat?, drawn: [CGPoint], trigger: CursorGestureTrigger, held: UInt, at now: TimeInterval,
                      config: CursorGesturesConfig, front: String?, pointer: @autoclosure () -> String? = nil) -> Bool {
        guard config.repeats(on: trigger.device), trigger.button != nil || held == trigger.keys else { return false }
        let ready = repeating.map { now - $0.began <= limit }
            ?? (CursorGestures.extent(drawn) >= CursorGesturePress.reach && config.match(for: drawn, trigger: trigger, front: front) != nil)
        return ready && !config.blocks(button: true, front: front, pointer: pointer())
    }

    mutating func click(_ drawn: [CGPoint], at now: TimeInterval, config: CursorGesturesConfig, front: String?) -> CursorGesture? {
        guard now - last > Self.gap else { return nil }
        last = now
        gesture = switched(drawn, config: config, front: front) ?? gesture
        return gesture
    }

    func switched(_ drawn: [CGPoint], config: CursorGesturesConfig, front: String?) -> CursorGesture? {
        guard config.switchWhileRepeating, drawn.count >= Self.switchPoints, CursorGestures.extent(drawn) >= Self.switchSize,
              let found = config.match(for: drawn, trigger: trigger, front: front)?.gesture, found.id != gesture.id else { return nil }
        return found
    }
}

struct CursorGestureScroll {
    static let smoothing: CGFloat = 0.35
    static let gain: CGFloat = 2

    private(set) var position: CGPoint
    private var speed = CGVector.zero

    static var natural: Bool {
        UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }

    init(at position: CGPoint) {
        self.position = position
    }

    mutating func scrolled(x: CGFloat, y: CGFloat, inverted: Bool) -> CGPoint {
        let finger = inverted ? CGVector(dx: x, dy: -y) : CGVector(dx: -x, dy: y)
        speed = CGVector(dx: speed.dx + Self.smoothing * (finger.dx - speed.dx), dy: speed.dy + Self.smoothing * (finger.dy - speed.dy))
        position = CGPoint(x: position.x + Self.gain * speed.dx, y: position.y + Self.gain * speed.dy)
        return position
    }
}

struct CursorGestureSnapshot {
    var config = CursorGesturesConfig()
    var front: String?
    var height: CGFloat = 0
    var natural = true
    var appAt: @Sendable (CGPoint) -> String? = CursorGestures.app(at:)
    var translator: CursorGestureTrigger?
    var captures: [(id: UInt32, trigger: CursorGestureTrigger)] = []
}

final class CursorGestureShared: @unchecked Sendable {
    private let lock = NSLock()
    private var current = CursorGestureSnapshot()

    var snapshot: CursorGestureSnapshot {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

enum CursorGestureNote {
    case update([CGPoint], CursorGestureTrigger, finished: Bool)
    case play(CursorGesture?)
    case frame(CursorTranslatorNote)
    case capture(UInt32)
}

struct CursorGestureInput {
    static let echo: TimeInterval = 0.25

    private(set) var stroke: CursorGestureStroke
    private(set) var pad: CursorGestureStroke
    private(set) var press: CursorGesturePress?
    private(set) var framing: CursorTranslatorPress?
    private(set) var repeating: CursorGestureRepeat?
    private(set) var leftHeld = false
    private var leftSince: TimeInterval = 0
    private var glide = CursorGestureScroll(at: .zero)
    private var device = CursorGestureDevice.mouse
    private var began: TimeInterval = 0
    private var shown = false
    private var unanswered: TimeInterval?
    private var failedOpen = false
    private var ownsScroll = false
    private var swallowing: Set<Int> = []
    var notes: [CursorGestureNote] = []
    var clicks: [(button: Int, at: CGPoint, keys: UInt)] = []

    init(_ config: CursorGesturesConfig) {
        stroke = CursorGestureStroke(triggers: config.keyTriggers)
        pad = CursorGestureStroke(triggers: config.padTriggers)
    }

    var isDrawing: Bool { press != nil || framing != nil || stroke.phase == .drawing || pad.phase == .drawing }

    mutating func cancel(_ flags: NSEvent.ModifierFlags, at time: TimeInterval) {
        stroke.cancel(flags)
        if began <= time {
            pad.cancel(flags)
            if let dropped = press { swallowing.insert(dropped.button) }
            press = nil
            if repeating?.trigger.button != nil { repeating = nil }
        }
        if let repeating, repeating.began <= time { self.repeating = nil }
        if leftHeld, leftSince <= time {
            leftHeld = false
            swallowing.insert(0)
        }
        update()
    }

    mutating func spaceChanged(_ flags: NSEvent.ModifierFlags, at time: TimeInterval) {
        stroke.cancel(flags)
        if began <= time { pad.cancel(flags) }
        update()
    }

    mutating func handle(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags, at time: TimeInterval, _ snapshot: CursorGestureSnapshot) {
        guard type == .flagsChanged else { return cancel(flags, at: time) }
        let padded = pad.flagsChanged(flags), keyed = stroke.flagsChanged(flags)
        if let padded { return finish(padded, padTrigger, snapshot) }
        if let keyed { return finish(keyed, keyTrigger, snapshot) }
        if let repeating, repeating.trigger.button == nil, flags.intersection(CursorGestureStroke.keys).rawValue != repeating.trigger.keys {
            return release([], snapshot)
        }
        update()
    }

    mutating func moved(to point: CGPoint, flags: NSEvent.ModifierFlags, buttons: Int, device: CursorGestureDevice, at now: TimeInterval,
                        _ snapshot: CursorGestureSnapshot) {
        let starting = stroke.phase != .drawing
        let finished = stroke.moved(to: point, flags: flags, buttons: buttons)
        if starting, stroke.phase == .drawing { (self.device, began) = (device, now) }
        if stroke.points.count == 1,
           snapshot.config.blocks(button: false, front: snapshot.front, pointer: snapshot.appAt(flip(point, snapshot))) {
            stroke.cancel(flags)
        }
        finish(finished, keyTrigger, snapshot)
    }

    mutating func tapped(_ type: CGEventType, _ event: CGEvent, _ snapshot: CursorGestureSnapshot, at now: TimeInterval) -> Bool {
        guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput else {
            for dropped in [press?.button, framing?.button, leftHeld ? 0 : nil] { if let dropped { swallowing.insert(dropped) } }
            if let ended = framing, ended.drawing { notes.append(.frame(ended.released)) }
            press = nil
            framing = nil
            if repeating?.trigger.button != nil { repeating = nil }
            leftHeld = false
            unanswered = nil
            update()
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == CursorGestureKeys.marker { unanswered = nil }
        guard event.getIntegerValueField(.eventSourceUserData) != CursorGestureKeys.marker,
              event.getIntegerValueField(.eventSourceUserData) != CursorShaker.marker,
              snapshot.config.accepts(source: event.getIntegerValueField(.eventSourceStateID)) else { return false }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
            let pressed = CursorGestureTrigger(keys: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(CursorGestureStroke.keys).rawValue,
                                               button: Int(event.getIntegerValueField(.mouseEventButtonNumber)),
                                               device: CursorGestureDevice(subtype: event.getIntegerValueField(.mouseEventSubtype)))
            if let capture = snapshot.captures.first(where: { $0.trigger.overlaps(pressed) }) {
                swallowing.insert(pressed.button ?? 0)
                notes.append(.capture(capture.id))
                return true
            }
        }
        if let unanswered, now - unanswered > Self.echo { failedOpen = true }
        guard !failedOpen else {
            for dropped in [press?.button, framing?.button, leftHeld ? 0 : nil] { if let dropped { swallowing.insert(dropped) } }
            if let ended = framing, ended.drawing { notes.append(.frame(ended.released)) }
            press = nil
            framing = nil
            leftHeld = false
            update()
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            switch type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                swallowing.remove(button)
                return false
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                return swallowing.contains(button)
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                return swallowing.remove(button) != nil
            default:
                return false
            }
        }
        if type == .scrollWheel { return scrolled(event, snapshot, at: now) }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let keys = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(CursorGestureStroke.keys)
        let (config, front) = (snapshot.config, snapshot.front)
        switch type {
        case .leftMouseDown:
            swallowing.remove(0)
            let live = current
            leftHeld = CursorGestureRepeat.holds(repeating, drawn: live.points, trigger: live.trigger, held: keys.rawValue,
                                                 at: now, config: config, front: front, pointer: snapshot.appAt(event.location))
            leftSince = now
            return leftHeld
        case .leftMouseDragged:
            return leftHeld || swallowing.contains(0)
        case .leftMouseUp:
            guard leftHeld else { return swallowing.remove(0) != nil }
            leftHeld = false
            repeatClick(snapshot, at: now)
            return true
        case .rightMouseDown, .otherMouseDown:
            swallowing.remove(button)
            let trigger = CursorGestureTrigger(keys: keys.rawValue, button: button,
                                               device: CursorGestureDevice(subtype: event.getIntegerValueField(.mouseEventSubtype)))
            if framing == nil, press == nil, snapshot.translator?.overlaps(trigger) == true {
                framing = CursorTranslatorPress(button: button, start: flip(event.location, snapshot))
                return true
            }
            guard press == nil, config.holds(trigger, front: front, pointer: snapshot.appAt(event.location)) else { return false }
            stroke.cancel(keys)
            pad.cancel(keys)
            press = CursorGesturePress(button: button, start: flip(event.location, snapshot), trigger: trigger)
            began = now
            return true
        case .rightMouseDragged, .otherMouseDragged:
            guard !swallowing.contains(button) else { return true }
            if var moving = framing, moving.button == button {
                moving.dragged(to: flip(event.location, snapshot))
                framing = moving
                if moving.drawing { notes.append(.frame(.drawing(moving.start, moving.end))) }
                return true
            }
            guard press?.button == button else { return false }
            let point = flip(event.location, snapshot)
            press?.dragged(to: point)
            update()
            return true
        default:
            if swallowing.remove(button) != nil { return true }
            if let ended = framing, ended.button == button {
                framing = nil
                notes.append(.frame(ended.released))
                return true
            }
            guard let ended = press, ended.button == button else { return false }
            press = nil
            released(ended, snapshot, at: now)
            return true
        }
    }

    private mutating func scrolled(_ event: CGEvent, _ snapshot: CursorGestureSnapshot, at now: TimeInterval) -> Bool {
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0, press == nil else { return false }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let fresh = phase == Int64(CGScrollPhase.began.rawValue) || phase == Int64(CGScrollPhase.mayBegin.rawValue)
        let drawing = pad.phase == .drawing
        if fresh, !drawing { ownsScroll = false }
        if ownsScroll, !drawing { return true }
        guard drawing || fresh && pad.phase == .idle && pad.triggers.contains(flags.intersection(CursorGestureStroke.keys).rawValue) else { return false }
        guard event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else { return drawing }
        if !drawing {
            let trigger = CursorGestureTrigger(keys: flags.intersection(CursorGestureStroke.keys).rawValue, twoFinger: true, device: .trackpad)
            guard !snapshot.config.blocks(button: false, front: snapshot.front, pointer: snapshot.appAt(event.location)),
                  !snapshot.config.wanting(trigger, front: snapshot.front).isEmpty else { return false }
            stroke.cancel(flags)
            glide = CursorGestureScroll(at: flip(event.location, snapshot))
            began = now
            ownsScroll = true
        }
        let point = glide.scrolled(x: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                                   y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), inverted: snapshot.natural)
        finish(pad.moved(to: point, flags: flags, buttons: 0), padTrigger, snapshot)
        return true
    }

    private mutating func released(_ ended: CursorGesturePress, _ snapshot: CursorGestureSnapshot, at now: TimeInterval) {
        guard let point = ended.click else { return finish(ended.points, ended.trigger, snapshot) }
        if let gesture = snapshot.config.clicked(ended.trigger, front: snapshot.front) { return play(gesture) }
        clicks.append((ended.button, flip(point, snapshot), ended.trigger.keys))
        unanswered = unanswered ?? now
        update()
    }

    private mutating func repeatClick(_ snapshot: CursorGestureSnapshot, at now: TimeInterval) {
        let live = current
        if var ongoing = repeating {
            guard let next = ongoing.click(live.points, at: now, config: snapshot.config, front: snapshot.front) else { return }
            repeating = ongoing
            clearCurrent()
            play(next)
        } else if let entered = CursorGestureRepeat(live.points, trigger: live.trigger, started: began, at: now, config: snapshot.config, front: snapshot.front) {
            repeating = entered
            update(live)
            clearCurrent()
        }
    }

    private mutating func finish(_ points: [CGPoint]?, _ trigger: CursorGestureTrigger, _ snapshot: CursorGestureSnapshot) {
        guard let points else { return update() }
        guard let repeating, repeating.trigger == trigger else { return update((points, trigger)) }
        release(points, snapshot)
    }

    private mutating func release(_ drawn: [CGPoint], _ snapshot: CursorGestureSnapshot) {
        guard let ending = repeating else { return }
        repeating = nil
        play(ending.switched(drawn, config: snapshot.config, front: snapshot.front))
    }

    private var keyTrigger: CursorGestureTrigger { CursorGestureTrigger(keys: stroke.trigger.rawValue, device: device) }

    private var padTrigger: CursorGestureTrigger { CursorGestureTrigger(keys: pad.trigger.rawValue, twoFinger: true, device: .trackpad) }

    private var current: (points: [CGPoint], trigger: CursorGestureTrigger) {
        if let press { return (press.points, press.trigger) }
        return pad.phase == .drawing ? (pad.points, padTrigger) : (stroke.points, keyTrigger)
    }

    private mutating func clearCurrent() {
        if press != nil {
            press?.clear()
        } else if pad.phase == .drawing {
            pad.clear()
        } else {
            stroke.clear()
        }
    }

    private func flip(_ point: CGPoint, _ snapshot: CursorGestureSnapshot) -> CGPoint {
        MACFFMConvertToAXPoint(point, snapshot.height)
    }

    private mutating func play(_ gesture: CursorGesture?) {
        shown = false
        notes.append(.play(gesture))
    }

    private mutating func update(_ finished: (points: [CGPoint], trigger: CursorGestureTrigger)? = nil) {
        let (points, trigger) = finished ?? current
        guard finished != nil || !points.isEmpty || shown else { return }
        shown = finished == nil && !points.isEmpty
        notes.append(.update(points, trigger, finished: finished != nil))
    }
}

enum CursorGestureKeys {
    static let marker: Int64 = 0x4D_6143_6745
    static let limit = 20
    static let names: [UInt16: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 117: "⌦",
        36: "↩", 76: "⌤", 48: "⇥", 53: "⎋", 49: "␣", 51: "⌫",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
    private static let modifiers: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
    private static let functionKeys = Set(names.keys).subtracting([36, 76, 48, 53, 49, 51])

    static let systemHotKeyIDs = ["missionControl": 32, "appExpose": 33, "spaceLeft": 79, "spaceRight": 81, "showDesktop": 36]

    static func systemHotKeys() -> [String: Any]? {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
    }

    static func system(_ id: String, _ shortcut: CursorGestureShortcut,
                       in hotKeys: @autoclosure () -> [String: Any]? = systemHotKeys()) -> CursorGestureShortcut? {
        guard let number = systemHotKeyIDs[id], let entry = hotKeys()?[String(number)] as? [String: Any] else { return shortcut }
        guard (entry["enabled"] as? NSNumber)?.boolValue != false else { return nil }
        guard let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int], parameters.count == 3,
              let keyCode = UInt16(exactly: parameters[1]), let flags = UInt(exactly: parameters[2]) else { return shortcut }
        guard keyCode != 0xFFFF else { return nil }
        return CursorGestureShortcut(keyCode: keyCode, flags: NSEvent.ModifierFlags(rawValue: flags).intersection([.command, .option, .control, .shift]).rawValue)
    }

    static func recordable(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
        names[keyCode] != nil || !flags.isDisjoint(with: [.command, .option, .control])
    }

    enum Recorded: Equatable {
        case cancel, refuse, shortcut(CursorGestureShortcut)
    }

    static func recorded(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> Recorded {
        let flags = flags.intersection([.command, .option, .control, .shift])
        if keyCode == 53 && flags.isEmpty { return .cancel }
        return recordable(keyCode, flags) ? .shortcut(CursorGestureShortcut(keyCode: keyCode, flags: flags.rawValue)) : .refuse
    }

    static func label(_ shortcut: CursorGestureShortcut, layout: Data? = shortcutLayout()) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: shortcut.flags)
        let keyCode = keyCode(for: shortcut, in: shortcut.character == nil ? [:] : layout.map(keyCodes) ?? [:])
        let key = names[keyCode] ?? layout.flatMap { shortcutKey(keyCode, flags, $0) }.flatMap { $0.isEmpty ? nil : $0.uppercased() }
            ?? shortcut.character?.uppercased() ?? "?"
        return modifiers.filter { flags.contains($0.0) }.map(\.1).joined() + key
    }

    static func caps(_ shortcut: CursorGestureShortcut, layout: Data? = shortcutLayout()) -> [String] {
        let held = modifiers.filter { NSEvent.ModifierFlags(rawValue: shortcut.flags).contains($0.0) }.map(\.1)
        return held + [String(label(shortcut, layout: layout).dropFirst(held.count))]
    }

    static func glyphs(_ keys: UInt) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: keys)
        return (flags.contains(.function) ? "fn" : "") + modifiers.filter { flags.contains($0.0) }.map(\.1).joined()
    }

    static func keyCodes(_ layout: Data) -> [String: UInt16] {
        (UInt16(0)..<128).reversed().reduce(into: [:]) { table, keyCode in
            guard let key = shortcutKey(keyCode, .command, layout), !key.isEmpty else { return }
            table[key.lowercased()] = keyCode
        }
    }

    static func chunks(_ text: String) -> [[UniChar]] {
        text.reduce(into: []) { chunks, character in
            let units = Array(String(character).utf16)
            if let last = chunks.last, last.count + units.count <= limit {
                chunks[chunks.count - 1] += units
            } else {
                chunks.append(units)
            }
        }
    }

    static func posted(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData) == marker || CursorShaker.posted(event)
    }

    @MainActor private static var table = shortcutLayout().map(keyCodes) ?? [:]

    @MainActor static func rebuildLayout() {
        table = shortcutLayout().map(keyCodes) ?? [:]
    }

    static func keyCode(for shortcut: CursorGestureShortcut, in table: [String: UInt16]) -> UInt16 {
        shortcut.character.flatMap { table[$0] } ?? shortcut.keyCode
    }

    @MainActor static func keyCode(for shortcut: CursorGestureShortcut) -> UInt16 {
        keyCode(for: shortcut, in: table)
    }

    @MainActor static func press(_ shortcut: CursorGestureShortcut) {
        let keyCode = keyCode(for: shortcut)
        var flags = CGEventFlags(rawValue: UInt64(NSEvent.ModifierFlags(rawValue: shortcut.flags).intersection([.command, .option, .control, .shift]).rawValue))
        if functionKeys.contains(keyCode) { flags.insert(.maskSecondaryFn) }
        if (123...126).contains(keyCode) { flags.insert(.maskNumericPad) }
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            post(CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down), flags)
        }
    }

    static func click(_ button: Int, at point: CGPoint, keys: UInt) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in button == 1 ? [CGEventType.rightMouseDown, .rightMouseUp] : [.otherMouseDown, .otherMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button == 1 ? .right : .center)
            event?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            post(event, CGEventFlags(rawValue: UInt64(keys)))
        }
    }

    static func mediaKey(for operation: CursorGestureOperation) -> Int32? {
        [.volumeUp: NX_KEYTYPE_SOUND_UP, .volumeDown: NX_KEYTYPE_SOUND_DOWN, .mute: NX_KEYTYPE_MUTE,
         .brightnessUp: NX_KEYTYPE_BRIGHTNESS_UP, .brightnessDown: NX_KEYTYPE_BRIGHTNESS_DOWN][operation]
    }

    static func mediaData(_ key: Int32, down: Bool) -> Int {
        Int(key) << 16 | Int(down ? NX_KEYDOWN : NX_KEYUP) << 8
    }

    @MainActor static func pressMedia(_ key: Int32) {
        for down in [true, false] {
            let data = mediaData(key, down: down)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(data & 0xff00)),
                               timestamp: 0, windowNumber: 0, context: nil, subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                               data1: data, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    @MainActor static func type(_ text: String) {
        let source = CGEventSource(stateID: .privateState)
        for chunk in chunks(text) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                post(event, [])
            }
        }
    }

    private static func post(_ event: CGEvent?, _ flags: CGEventFlags) {
        guard let event else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }
}
