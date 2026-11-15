import AppKit
import CryptoKit
import UniformTypeIdentifiers

extension Notification.Name {
    nonisolated static let MACCursorBoardDidChange = Notification.Name("MACCursorBoardDidChange")
    nonisolated static let MACCursorBoardClearHistory = Notification.Name("MACCursorBoardClearHistory")
    nonisolated static let MACCursorBoardShowAccessWindow = Notification.Name("MACCursorBoardShowAccessWindow")
}

enum CursorBoardKeep: String, CaseIterable, Codable, Sendable {
    case day, week, month, threeMonths, sixMonths, year, forever

    var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 91
        case .sixMonths: return 182
        case .year: return 365
        case .forever: return nil
        }
    }
}

enum CursorBoardEdge: String, CaseIterable, Codable, Sendable {
    case left, bottom, top, right

    var isRow: Bool { self == .bottom || self == .top }
}

enum CursorBoardClose {
    case escape, chevron, trigger, clickOutside, paste, space, display

    func closes(keepsOpen: Bool) -> Bool {
        !keepsOpen || (self != .clickOutside && self != .paste)
    }
}

struct CursorBoardConfig: Codable, Equatable {
    static let limits = [50, 100, 200, 500]
    static let listSizes = 5...10

    var enabled = false
    var keepsHistory = true
    var keep = CursorBoardKeep.week
    var limit = 200
    var listSize = 5
    var listShortcut: KeyboardShortcutData?
    var listClick = CursorGestureTrigger(keys: NSEvent.ModifierFlags.command.rawValue, button: 2)
    var panelShortcut: KeyboardShortcutData?
    var panelClick = CursorGestureTrigger(keys: NSEvent.ModifierFlags([.option, .command]).rawValue, button: 0)
    var position = CursorBoardEdge.right
    var opensAtEdge = true
    var keepsOpen = false
    var moves = false
    var ignored: [String] = []

    private enum CodingKeys: String, CodingKey {
        case enabled, keepsHistory, keep, limit, listSize, listShortcut, listClick, panelShortcut, panelClick, position, opensAtEdge, keepsOpen, moves, ignored
    }

    var clicks: [(id: UInt32, trigger: CursorGestureTrigger)] {
        let rows: [(id: UInt32, trigger: CursorGestureTrigger)] = [(CursorBoard.listHotKeyID, listClick), (CursorBoard.panelHotKeyID, panelClick)]
        return enabled ? rows.filter { CursorTranslator.usable($0.trigger) } : []
    }

    var triggers: [CursorGestureTrigger] { [listClick, panelClick] }

    func triggers(besides click: WritableKeyPath<CursorBoardConfig, CursorGestureTrigger>) -> [CursorGestureTrigger] {
        [\CursorBoardConfig.listClick, \.panelClick].filter { $0 != click }.map { self[keyPath: $0] }
    }

    func keys(besides field: WritableKeyPath<CursorBoardConfig, KeyboardShortcutData?>?) -> [KeyboardShortcutData] {
        [\CursorBoardConfig.listShortcut, \.panelShortcut].filter { $0 != field }.compactMap { self[keyPath: $0] }
    }

    static func load() -> CursorBoardConfig {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard let data = MACPreferences.value(forKey: MACPreferences.cursorBoardKey) as? Data,
              let config = try? JSONDecoder().decode(CursorBoardConfig.self, from: data) else { return CursorBoardConfig() }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        MACPreferences.set(data, forKey: MACPreferences.cursorBoardKey)
        Self.post(.MACCursorBoardDidChange)
    }

    static func setEnabled(_ enabled: Bool) {
        var config = load()
        guard config.enabled != enabled else { return }
        config.enabled = enabled
        config.save()
    }

    static func tap(enabled: Bool, usable: Bool) {
        guard usable else { return }
        setEnabled(!enabled)
    }

    static func notifyHelper() {
        post(.MACCursorBoardDidChange)
    }

    static func clearHistory() {
        post(.MACCursorBoardClearHistory)
    }

    private static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

extension CursorBoardConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
        keepsHistory = (try? container.decode(Bool.self, forKey: .keepsHistory)) ?? true
        keep = (try? container.decode(CursorBoardKeep.self, forKey: .keep)) ?? .week
        if let limit = try? container.decode(Int.self, forKey: .limit), Self.limits.contains(limit) {
            self.limit = limit
        }
        if let size = try? container.decode(Int.self, forKey: .listSize), Self.listSizes.contains(size) {
            listSize = size
        }
        listShortcut = try? container.decode(KeyboardShortcutData.self, forKey: .listShortcut)
        listClick = (try? container.decode(CursorGestureTrigger.self, forKey: .listClick)) ?? listClick
        panelShortcut = try? container.decode(KeyboardShortcutData.self, forKey: .panelShortcut)
        panelClick = (try? container.decode(CursorGestureTrigger.self, forKey: .panelClick)) ?? panelClick
        position = (try? container.decode(CursorBoardEdge.self, forKey: .position)) ?? .right
        opensAtEdge = (try? container.decode(Bool.self, forKey: .opensAtEdge)) ?? true
        keepsOpen = (try? container.decode(Bool.self, forKey: .keepsOpen)) ?? false
        moves = (try? container.decode(Bool.self, forKey: .moves)) ?? false
        ignored = (try? container.decode([String].self, forKey: .ignored)) ?? []
    }
}

struct CursorBoardItem: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var date: Date
    var app: String?
    var text: String?
    var name: String?
    var picture: String?
    var bytes: Int?
    var type: String?
    var rich = false
    var pinned = false

    var link: URL? { text.flatMap(CursorBoard.link(in:)) }

    var colour: CGColor? { text.flatMap(CursorBoard.colour(in:)) }

    func same(as other: CursorBoardItem) -> Bool {
        text == other.text && picture == other.picture
    }
}

struct CursorBoardCopy: Sendable {
    var item: CursorBoardItem
    var picture: Data?
    var rich: Data?
}

struct CursorBoardHistory: Equatable {
    var items: [CursorBoardItem] = []

    var ordered: [CursorBoardItem] { items.filter(\.pinned) + items.filter { !$0.pinned } }

    mutating func add(_ item: CursorBoardItem) -> CursorBoardItem {
        guard let index = items.firstIndex(where: { $0.same(as: item) }) else {
            items.insert(item, at: 0)
            return item
        }
        var kept = items.remove(at: index)
        kept.date = item.date
        items.insert(kept, at: 0)
        return kept
    }

    mutating func prune(keep: CursorBoardKeep, limit: Int, now: Date) -> [CursorBoardItem] {
        let oldest = keep.days.map { now.addingTimeInterval(-TimeInterval($0) * 86_400) }
        var counted = 0
        var bytes = 0
        var full = false
        var gone: [CursorBoardItem] = []
        items = items.filter { item in
            guard !item.pinned else { return true }
            counted += 1
            let size = item.bytes ?? 0
            full = full || bytes + size > CursorBoard.largestTotal
            let stays = counted <= limit && (size == 0 || !full) && oldest.map { item.date >= $0 } != false
            if stays { bytes += size } else { gone.append(item) }
            return stays
        }
        return gone
    }

    mutating func remove(_ id: UUID) -> CursorBoardItem? {
        items.firstIndex { $0.id == id }.map { items.remove(at: $0) }
    }

    mutating func togglePin(_ id: UUID) -> CursorBoardItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        items[index].pinned.toggle()
        return items[index]
    }

    mutating func clear() -> [CursorBoardItem] {
        let gone = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        return gone
    }
}

struct CursorBoardPager: Equatable {
    var count: Int
    var size: Int
    var page = 0
    var selected = 0

    var pages: Int { max(1, (count + size - 1) / size) }

    var range: Range<Int> { min(count, page * size)..<min(count, page * size + size) }

    var hasNewer: Bool { page > 0 }

    var hasOlder: Bool { page + 1 < pages }

    mutating func turn(_ step: Int) {
        let next = min(max(page + step, 0), pages - 1)
        guard next != page else { return }
        page = next
        selected = 0
    }

    mutating func move(_ step: Int) {
        selected = min(max(selected + step, 0), max(range.count - 1, 0))
    }

    mutating func fit(count: Int) {
        self.count = count
        page = min(page, pages - 1)
        move(0)
    }

    func index(number: Int) -> Int? {
        (1...9).contains(number) && number <= range.count ? range.lowerBound + number - 1 : nil
    }

    static func label(_ row: Int) -> String? {
        row < 9 ? "⌘\(row + 1)" : nil
    }
}

enum CursorBoardCommand: Equatable {
    case up, down, older, newer, paste(plain: Bool), pick(Int, plain: Bool), pin, delete, close
}

struct CursorBoardScroll {
    private var total: CGFloat = 0
    private var turned = false

    mutating func step(deltaY: CGFloat, precise: Bool, phase: NSEvent.Phase, momentum: NSEvent.Phase) -> Int {
        guard momentum.isEmpty else { return 0 }
        guard precise else { return deltaY < 0 ? 1 : deltaY > 0 ? -1 : 0 }
        if phase.contains(.began) || phase.contains(.mayBegin) { (total, turned) = (0, false) }
        total += deltaY
        guard !turned, abs(total) >= 20 else { return 0 }
        turned = true
        return total < 0 ? 1 : -1
    }
}

struct CursorBoardHotEdge: Equatable {
    static let reach: CGFloat = 2
    static let corner: CGFloat = 24
    static let push: CGFloat = 40
    static let hold: TimeInterval = 0.15
    static let rearm: CGFloat = 20
    static let rest: TimeInterval = 0.1

    var edge: CursorBoardEdge
    private var entered: TimeInterval?
    private var last: TimeInterval = 0
    private var pushed: CGFloat = 0
    private var armed = true

    init(edge: CursorBoardEdge) {
        self.edge = edge
    }

    mutating func moved(to point: CGPoint, by delta: CGVector, at time: TimeInterval, screens: [CGRect]) -> Bool {
        guard let screen = screens.first(where: { $0.minX <= point.x && point.x <= $0.maxX && $0.minY <= point.y && point.y <= $0.maxY }) else {
            entered = nil
            return false
        }
        let away: CGFloat
        let along: CGFloat
        let span: (CGFloat, CGFloat)
        let beyond: CGPoint
        let outward: CGFloat
        switch edge {
        case .left: (away, along, span, beyond, outward) = (point.x - screen.minX, point.y, (screen.minY, screen.maxY), CGPoint(x: screen.minX - 1, y: point.y), -delta.dx)
        case .right: (away, along, span, beyond, outward) = (screen.maxX - point.x, point.y, (screen.minY, screen.maxY), CGPoint(x: screen.maxX + 1, y: point.y), delta.dx)
        case .bottom: (away, along, span, beyond, outward) = (point.y - screen.minY, point.x, (screen.minX, screen.maxX), CGPoint(x: point.x, y: screen.minY - 1), delta.dy)
        case .top: (away, along, span, beyond, outward) = (screen.maxY - point.y, point.x, (screen.minX, screen.maxX), CGPoint(x: point.x, y: screen.maxY + 1), -delta.dy)
        }
        if away > Self.rearm { armed = true }
        guard armed, away <= Self.reach, along >= span.0 + Self.corner, along <= span.1 - Self.corner, !screens.contains(where: { $0.contains(beyond) }) else {
            entered = nil
            return false
        }
        defer { last = time }
        guard let start = entered, outward > 0, time - last <= Self.rest else {
            entered = time
            pushed = 0
            return false
        }
        pushed += outward
        guard pushed >= Self.push, time - start >= Self.hold else { return false }
        armed = false
        entered = nil
        return true
    }
}

final class CursorBoardStore: @unchecked Sendable {
    static let entry = "entry.json"
    static let thumbnail = "thumbnail.png"
    static let rich = "rich.rtf"

    let root: URL?
    private var memory: [String: Data] = [:]

    init(root: URL?) {
        self.root = root
    }

    static func picture(_ item: CursorBoardItem) -> String {
        "picture." + (item.type.flatMap { UTType($0)?.preferredFilenameExtension } ?? "png")
    }

    static func fileType(_ item: CursorBoardItem) -> String {
        (picture(item) as NSString).pathExtension.uppercased()
    }

    convenience init(_ config: CursorBoardConfig, support: URL) {
        self.init(root: config.keepsHistory ? support.appendingPathComponent(CursorBoard.folder, isDirectory: true) : nil)
    }

    func save(_ item: CursorBoardItem, files: [String: Data] = [:]) {
        guard let root else {
            for (name, data) in files { memory["\(item.id)/\(name)"] = data }
            return
        }
        let manager = FileManager.default
        let folder = root.appendingPathComponent(item.id.uuidString, isDirectory: true)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var marked = root
            try marked.setResourceValues(values)
            for (name, data) in files { try data.write(to: folder.appendingPathComponent(name)) }
            try JSONEncoder().encode(item).write(to: folder.appendingPathComponent(Self.entry), options: .atomic)
        } catch {
            if !files.isEmpty { try? manager.removeItem(at: folder) }
        }
    }

    func file(_ id: UUID, _ name: String) -> Data? {
        guard let root else { return memory["\(id)/\(name)"] }
        return try? Data(contentsOf: root.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent(name))
    }

    func remove(_ id: UUID) {
        guard let root else {
            memory = memory.filter { !$0.key.hasPrefix("\(id)/") }
            return
        }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    func removeAll() {
        memory = [:]
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func load() -> [CursorBoardItem] {
        guard let root else { return [] }
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { folder -> CursorBoardItem? in
            let data = try? Data(contentsOf: folder.appendingPathComponent(Self.entry))
            guard let item = data.flatMap({ try? JSONDecoder().decode(CursorBoardItem.self, from: $0) }) else {
                try? FileManager.default.removeItem(at: folder)
                return nil
            }
            return item
        }.sorted { $0.date > $1.date }
    }

    func move(_ items: [CursorBoardItem], to other: CursorBoardStore) {
        for item in items {
            other.save(item, files: [Self.picture(item), Self.thumbnail, Self.rich].reduce(into: [:]) { $0[$1] = file(item.id, $1) })
        }
        removeAll()
    }
}

enum CursorBoard {
    static let listHotKeyID = CursorShaker.hotKeyID - 6
    static let panelHotKeyID = CursorShaker.hotKeyID - 7
    static let listCard: CGFloat = 100
    static let listChrome: CGFloat = 38
    static let panelInset: CGFloat = 8
    static let panelSide: CGFloat = 340
    static let panelStrip: CGFloat = 270
    static let movedSize = CGSize(width: 340, height: 520)
    static let slideIn: TimeInterval = 0.22
    static let slideOut: TimeInterval = 0.18
    static let fade: TimeInterval = 0.15
    static let folder = "MaCursor/CursorBoard"
    static let marker = NSPasteboard.PasteboardType("com.writronic.macursor.board")
    static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    static let urlNameType = NSPasteboard.PasteboardType("public.url-name")
    static let secretTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
                                           "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping",
                                           "net.antelle.keeweb", "Pasteboard generator type"]
    static let largestPicture = 32 * 1024 * 1024
    static let largestTotal = 512 * 1024 * 1024
    static let thumbnailSide = 360
    static let tick: TimeInterval = 0.5
    static let ageRefresh: TimeInterval = 60
    static let ageTolerance: TimeInterval = 10
    static let pasteDelay: TimeInterval = 0.08
    static let pasteKey = CursorGestureShortcut(keyCode: 9, flags: NSEvent.ModifierFlags.command.rawValue, character: "v")
    static let pasteFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
    private static let fileImageTypes = ["public.png", "public.jpeg", "public.heic", "org.webmproject.webp"].map { NSPasteboard.PasteboardType($0) }
    private static let imageTypes = fileImageTypes + [.tiff]
    private static let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    private static let keypadKeys: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]

    static func skips(_ types: [String], source: String?, front: String?, ignored: [String]) -> Bool {
        types.contains { $0 == marker.rawValue || secretTypes.contains($0) } || [source, front].contains { $0.map(ignored.contains) == true }
    }

    static func read(_ pasteboard: NSPasteboard, front: String?, ignored: [String], now: Date = Date()) -> CursorBoardCopy? {
        let types = pasteboard.types ?? []
        guard !skips(types.map(\.rawValue), source: nil, front: front, ignored: ignored) else { return nil }
        let source = types.contains(sourceType) ? pasteboard.string(forType: sourceType) : nil
        guard !skips([], source: source, front: nil, ignored: ignored) else { return nil }
        let app = source ?? front
        let file = types.contains(.fileURL)
        if !file, let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let rich = types.contains(.rtf) ? pasteboard.data(forType: .rtf).flatMap { $0.count <= largestPicture ? $0 : nil } : nil
            let name = link(in: text) == nil ? nil : pasteboard.string(forType: urlNameType)
            return CursorBoardCopy(item: CursorBoardItem(date: now, app: app, text: text, name: name, rich: rich != nil), rich: rich)
        }
        guard let type = pasteboard.availableType(from: file ? fileImageTypes : imageTypes),
              let data = pasteboard.data(forType: type), data.count <= largestPicture else { return nil }
        return CursorBoardCopy(item: CursorBoardItem(date: now, app: app, picture: digest(data), bytes: data.count, type: type.rawValue), picture: data)
    }

    static func write(_ item: CursorBoardItem, picture: Data?, rich: Data?, plain: Bool, to pasteboard: NSPasteboard) {
        if let text = item.text {
            let rich = plain ? nil : rich
            pasteboard.declareTypes([marker, .string] + (rich == nil ? [] : [.rtf]), owner: nil)
            pasteboard.setString(text, forType: .string)
            if let rich { pasteboard.setData(rich, forType: .rtf) }
        } else if let picture {
            let type = NSPasteboard.PasteboardType(item.type ?? "public.png")
            pasteboard.declareTypes([marker, type], owner: nil)
            pasteboard.setData(picture, forType: type)
        }
        pasteboard.setData(Data(), forType: marker)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func link(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return nil }
        return url
    }

    static func colour(in text: String) -> CGColor? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "#", [4, 7].contains(trimmed.count), trimmed.dropFirst().allSatisfy(\.isHexDigit),
              let value = UInt32(trimmed.dropFirst(), radix: 16) else { return nil }
        let wide = trimmed.count == 7
        let channel = { (shift: UInt32) -> CGFloat in
            wide ? CGFloat(value >> shift & 0xFF) / 255 : CGFloat(value >> (shift / 2) & 0xF) / 15
        }
        return CGColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1)
    }

    static func gap(scale: Double) -> CGFloat {
        CGFloat(22 * scale + 4)
    }

    static func listFrame(size: CGSize, pointer: CGPoint, visible: CGRect, gap: CGFloat) -> CGRect {
        var x = pointer.x + gap
        if x + size.width > visible.maxX { x = pointer.x - gap - size.width }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        let y = max(min(pointer.y, visible.maxY) - size.height, visible.minY)
        return CGRect(x: x, y: min(y, visible.maxY - size.height), width: size.width, height: size.height)
    }

    static func panelFrame(_ edge: CursorBoardEdge, in visible: CGRect) -> CGRect {
        let width = max(0, edge.isRow ? visible.width - 2 * panelInset : min(panelSide, visible.width - 2 * panelInset))
        let height = max(0, edge.isRow ? min(panelStrip, visible.height - 2 * panelInset) : visible.height - 2 * panelInset)
        let x = edge == .right ? visible.maxX - panelInset - width : visible.minX + panelInset
        let y = edge == .top ? visible.maxY - panelInset - height : visible.minY + panelInset
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func movedFrame(pointer: CGPoint, visible: CGRect, gap: CGFloat) -> CGRect {
        listFrame(size: movedSize, pointer: pointer, visible: visible, gap: gap)
    }

    static func slideOffset(_ edge: CursorBoardEdge, size: CGSize) -> CGVector {
        switch edge {
        case .left: return CGVector(dx: -size.width, dy: 0)
        case .right: return CGVector(dx: size.width, dy: 0)
        case .bottom: return CGVector(dx: 0, dy: -size.height)
        case .top: return CGVector(dx: 0, dy: size.height)
        }
    }

    static func sideways(_ event: NSEvent) -> NSEvent? {
        guard let copy = event.cgEvent?.copy() else { return nil }
        let fields: [(along: CGEventField, across: CGEventField)] = [(.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
                                                                     (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
                                                                     (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2)]
        let values = fields.map { copy.getDoubleValueField($0.along) }
        for field in fields { copy.setDoubleValueField(field.along, value: 0) }
        for (field, value) in zip(fields, values) { copy.setDoubleValueField(field.across, value: value) }
        return NSEvent(cgEvent: copy)
    }

    static func listPageSize(_ limit: Int, height: CGFloat) -> Int {
        max(1, min(limit, Int((height - listChrome) / listCard)))
    }

    static func panelPageSize(_ count: Int) -> Int {
        max(count, 1)
    }

    static func edgeClash(_ edge: CursorBoardEdge, dock: String?, stageManager: Bool) -> Bool {
        let docked = CursorBoardEdge(rawValue: dock ?? "") ?? .bottom
        return edge == .top || edge == docked || (stageManager && edge == (docked == .left ? .right : .left))
    }

    static func edgeClash(_ edge: CursorBoardEdge) -> Bool {
        let dock = "com.apple.dock" as CFString
        let windows = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(dock)
        CFPreferencesAppSynchronize(windows)
        return edgeClash(edge, dock: CFPreferencesCopyAppValue("orientation" as CFString, dock) as? String,
                         stageManager: CFPreferencesCopyAppValue("GloballyEnabled" as CFString, windows) as? Bool ?? false)
    }

    static func matches(_ item: CursorBoardItem, query: String, appName: String?) -> Bool {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty || [item.text, item.name, appName].contains { $0?.localizedStandardContains(words) == true }
    }

    static func panelCommand(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags, row: Bool) -> CursorBoardCommand? {
        let held = flags.contains(.command)
        let plain = flags.contains(.option)
        switch keyCode {
        case 126 where !row, 123 where row: return .up
        case 125 where !row, 124 where row: return .down
        case 36, 76: return .paste(plain: plain)
        case 53: return .close
        case 51 where held, 117 where held: return .delete
        default: break
        }
        guard held else { return nil }
        if let index = digitKeys.firstIndex(of: keyCode) ?? keypadKeys.firstIndex(of: keyCode) { return .pick(index + 1, plain: plain) }
        return characters?.lowercased() == "p" ? .pin : nil
    }

    static func command(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> CursorBoardCommand? {
        let plain = flags.contains(.option)
        switch keyCode {
        case 126: return .up
        case 125: return .down
        case 124: return .older
        case 123: return .newer
        case 36, 76: return .paste(plain: plain)
        case 51, 117: return .delete
        case 53: return .close
        default: break
        }
        if let index = digitKeys.firstIndex(of: keyCode) ?? keypadKeys.firstIndex(of: keyCode) { return .pick(index + 1, plain: plain) }
        return characters?.lowercased() == "p" ? .pin : nil
    }
}
