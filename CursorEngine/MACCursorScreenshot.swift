import AppKit

extension Notification.Name {
    nonisolated static let MACCursorScreenshotDidChange = Notification.Name("MACCursorScreenshotDidChange")
    nonisolated static let MACCursorScreenshotShowAccessWindow = Notification.Name("MACCursorScreenshotShowAccessWindow")
}

struct CursorScreenshotConfig: Codable, Equatable {
    var enabled = false
    var showsCursor = true
    var freezesScreen = true
    var wholeScreenShortcut: KeyboardShortcutData?
    var areaShortcut: KeyboardShortcutData?
    var repeatShortcut: KeyboardShortcutData?
    var textShortcut: KeyboardShortcutData?
    var selfTimerShortcut: KeyboardShortcutData?
    var wholeScreenClick = CursorGestureTrigger(keys: NSEvent.ModifierFlags([.command, .option]).rawValue, button: 1)
    var areaClick = CursorGestureTrigger(keys: NSEvent.ModifierFlags.command.rawValue, button: 1)
    var repeatClick = CursorGestureTrigger()
    var textClick = CursorGestureTrigger()
    var selfTimerClick = CursorGestureTrigger()
    var copies = true
    var saves = false
    var folder = ""
    var lastArea: CursorScreenshotArea?
    var showsPreview = false
    var annotates = true
    var pins = false
    var delay = 2
    var playsSound = false
    var closesAfter = true
    var previewSeconds = 5
    var previewCorner = CursorScreenshotCorner.bottomLeft
    var warnsBeforeFlatten = true
    var background = CursorScreenshotBackgroundLibrary()
    var output = CursorScreenshotOutput()
    var windowShot = CursorScreenshotWindowShot()
    var crosshair = CursorScreenshotCrosshair()
    var naming = CursorScreenshotNaming()
    var clipboard = CursorScreenshotClipboardMode.fileAndImage
    var textRecognition = CursorScreenshotTextRecognition()
    var remembersSelection = false
    var keepHistory = CursorScreenshotHistoryKeep.week
    var movesToActiveScreen = true
    var previewScale = 1.0
    var closeAction = CursorScreenshotCloseAction.saveAndClose
    var closesAfterDrag = true
    var saveButton = CursorScreenshotSaveButton.exportLocation
    var hidesDesktopIcons = true

    private enum CodingKeys: String, CodingKey {
        case enabled, showsCursor, freezesScreen, wholeScreenShortcut, areaShortcut, repeatShortcut, textShortcut, selfTimerShortcut,
             wholeScreenClick, areaClick, repeatClick, textClick, selfTimerClick, copies, saves, folder, lastArea,
             showsPreview, annotates, pins, delay, playsSound, closesAfter, previewSeconds, previewCorner, warnsBeforeFlatten, background, output, windowShot, crosshair, naming,
             clipboard, textRecognition, remembersSelection, keepHistory,
             movesToActiveScreen, previewScale, closeAction, closesAfterDrag, saveButton, hidesDesktopIcons
    }

    var cardSeconds: Int? {
        closesAfter ? previewSeconds : nil
    }

    var folderURL: URL {
        folder.isEmpty ? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] : URL(fileURLWithPath: folder, isDirectory: true)
    }

    func keys(besides field: WritableKeyPath<CursorScreenshotConfig, KeyboardShortcutData?>) -> [KeyboardShortcutData] {
        let rows: [WritableKeyPath<CursorScreenshotConfig, KeyboardShortcutData?>] = [\.wholeScreenShortcut, \.areaShortcut, \.repeatShortcut, \.textShortcut, \.selfTimerShortcut]
        return rows.filter { $0 != field }.compactMap { self[keyPath: $0] }
    }

    private static var clickRows: [(id: UInt32, field: WritableKeyPath<CursorScreenshotConfig, CursorGestureTrigger>)] {
        [(CursorScreenshot.wholeScreenHotKeyID, \.wholeScreenClick), (CursorScreenshot.areaHotKeyID, \.areaClick), (CursorScreenshot.repeatHotKeyID, \.repeatClick),
         (CursorScreenshot.textHotKeyID, \.textClick), (CursorScreenshot.selfTimerHotKeyID, \.selfTimerClick)]
    }

    func clicks(besides field: WritableKeyPath<CursorScreenshotConfig, CursorGestureTrigger>) -> [CursorGestureTrigger] {
        Self.clickRows.filter { $0.field != field }.map { self[keyPath: $0.field] }.filter { $0.button != nil }
    }

    var clicks: [(id: UInt32, trigger: CursorGestureTrigger)] {
        guard enabled else { return [] }
        return Self.clickRows.map { ($0.id, self[keyPath: $0.field]) }.filter { CursorTranslator.usable($0.trigger) }
    }

    static func load() -> CursorScreenshotConfig {
        CFPreferencesSynchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        guard let data = MACPreferences.value(forKey: MACPreferences.cursorScreenshotKey) as? Data,
              let config = try? JSONDecoder().decode(CursorScreenshotConfig.self, from: data) else { return CursorScreenshotConfig() }
        return config
    }

    func save() {
        write()
        CursorScreenshotConfig.notifyHelper()
    }

    private func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        MACPreferences.set(data, forKey: MACPreferences.cursorScreenshotKey)
    }

    static func remember(_ area: CursorScreenshotArea) {
        var config = load()
        config.lastArea = area
        config.write()
    }

    static func spent(_ name: CursorScreenshotFileName) {
        var config = load()
        guard config.naming.spend(name) else { return }
        config.write()
    }

    static func stopWarningBeforeFlatten() {
        var config = load()
        config.warnsBeforeFlatten = false
        config.write()
    }

    static func changeBackground(_ change: (inout CursorScreenshotBackgroundLibrary) -> Void) {
        var config = load()
        change(&config.background)
        config.write()
    }

    static func notifyHelper() {
        DistributedNotificationCenter.default().postNotificationName(.MACCursorScreenshotDidChange, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    static func setEnabled(_ enabled: Bool) {
        var config = load()
        guard config.enabled != enabled else { return }
        config.enabled = enabled
        config.save()
    }

    static func isOn(enabled: Bool, usable: Bool) -> Bool {
        enabled && usable
    }
}

extension CursorScreenshotConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
        showsCursor = (try? container.decode(Bool.self, forKey: .showsCursor)) ?? true
        freezesScreen = (try? container.decode(Bool.self, forKey: .freezesScreen)) ?? true
        wholeScreenShortcut = try? container.decode(KeyboardShortcutData.self, forKey: .wholeScreenShortcut)
        areaShortcut = try? container.decode(KeyboardShortcutData.self, forKey: .areaShortcut)
        repeatShortcut = try? container.decode(KeyboardShortcutData.self, forKey: .repeatShortcut)
        textShortcut = try? container.decode(KeyboardShortcutData.self, forKey: .textShortcut)
        selfTimerShortcut = try? container.decode(KeyboardShortcutData.self, forKey: .selfTimerShortcut)
        wholeScreenClick = (try? container.decode(CursorGestureTrigger.self, forKey: .wholeScreenClick)) ?? wholeScreenClick
        areaClick = (try? container.decode(CursorGestureTrigger.self, forKey: .areaClick)) ?? areaClick
        repeatClick = (try? container.decode(CursorGestureTrigger.self, forKey: .repeatClick)) ?? repeatClick
        textClick = (try? container.decode(CursorGestureTrigger.self, forKey: .textClick)) ?? textClick
        selfTimerClick = (try? container.decode(CursorGestureTrigger.self, forKey: .selfTimerClick)) ?? selfTimerClick
        lastArea = try? container.decode(CursorScreenshotArea.self, forKey: .lastArea)
        copies = (try? container.decode(Bool.self, forKey: .copies)) ?? true
        saves = (try? container.decode(Bool.self, forKey: .saves)) ?? false
        showsPreview = (try? container.decode(Bool.self, forKey: .showsPreview)) ?? false
        annotates = (try? container.decode(Bool.self, forKey: .annotates)) ?? true
        pins = (try? container.decode(Bool.self, forKey: .pins)) ?? false
        if let delay = try? container.decode(Int.self, forKey: .delay), CursorScreenshot.delays.contains(delay) {
            self.delay = delay
        }
        playsSound = (try? container.decode(Bool.self, forKey: .playsSound)) ?? false
        closesAfter = (try? container.decode(Bool.self, forKey: .closesAfter)) ?? true
        if let seconds = try? container.decode(Int.self, forKey: .previewSeconds), CursorScreenshot.cardTimes.contains(seconds) {
            previewSeconds = seconds
        }
        if let corner = try? container.decode(CursorScreenshotCorner.self, forKey: .previewCorner) {
            previewCorner = corner
        }
        warnsBeforeFlatten = (try? container.decode(Bool.self, forKey: .warnsBeforeFlatten)) ?? true
        background = (try? container.decode(CursorScreenshotBackgroundLibrary.self, forKey: .background)) ?? CursorScreenshotBackgroundLibrary()
        output = (try? container.decode(CursorScreenshotOutput.self, forKey: .output)) ?? CursorScreenshotOutput()
        windowShot = (try? container.decode(CursorScreenshotWindowShot.self, forKey: .windowShot)) ?? CursorScreenshotWindowShot()
        crosshair = (try? container.decode(CursorScreenshotCrosshair.self, forKey: .crosshair)) ?? CursorScreenshotCrosshair()
        naming = (try? container.decode(CursorScreenshotNaming.self, forKey: .naming)) ?? CursorScreenshotNaming()
        clipboard = (try? container.decode(CursorScreenshotClipboardMode.self, forKey: .clipboard)) ?? .fileAndImage
        textRecognition = (try? container.decode(CursorScreenshotTextRecognition.self, forKey: .textRecognition)) ?? CursorScreenshotTextRecognition()
        if let folder = try? container.decode(String.self, forKey: .folder), folder.hasPrefix("/") {
            self.folder = folder
        }
        remembersSelection = (try? container.decode(Bool.self, forKey: .remembersSelection)) ?? false
        keepHistory = (try? container.decode(CursorScreenshotHistoryKeep.self, forKey: .keepHistory)) ?? .week
        movesToActiveScreen = (try? container.decode(Bool.self, forKey: .movesToActiveScreen)) ?? true
        if let scale = try? container.decode(Double.self, forKey: .previewScale), CursorScreenshot.cardScales.contains(scale) {
            previewScale = scale
        }
        closeAction = (try? container.decode(CursorScreenshotCloseAction.self, forKey: .closeAction)) ?? .saveAndClose
        closesAfterDrag = (try? container.decode(Bool.self, forKey: .closesAfterDrag)) ?? true
        saveButton = (try? container.decode(CursorScreenshotSaveButton.self, forKey: .saveButton)) ?? .exportLocation
        hidesDesktopIcons = (try? container.decode(Bool.self, forKey: .hidesDesktopIcons)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(showsCursor, forKey: .showsCursor)
        try container.encode(freezesScreen, forKey: .freezesScreen)
        try container.encode(wholeScreenShortcut, forKey: .wholeScreenShortcut)
        try container.encode(areaShortcut, forKey: .areaShortcut)
        try container.encode(repeatShortcut, forKey: .repeatShortcut)
        try container.encode(textShortcut, forKey: .textShortcut)
        try container.encode(selfTimerShortcut, forKey: .selfTimerShortcut)
        try container.encode(wholeScreenClick, forKey: .wholeScreenClick)
        try container.encode(areaClick, forKey: .areaClick)
        try container.encode(repeatClick, forKey: .repeatClick)
        try container.encode(textClick, forKey: .textClick)
        try container.encode(selfTimerClick, forKey: .selfTimerClick)
        try container.encode(copies, forKey: .copies)
        try container.encode(saves, forKey: .saves)
        try container.encode(folder, forKey: .folder)
        try container.encode(lastArea, forKey: .lastArea)
        try container.encode(showsPreview, forKey: .showsPreview)
        try container.encode(annotates, forKey: .annotates)
        try container.encode(pins, forKey: .pins)
        try container.encode(delay, forKey: .delay)
        try container.encode(playsSound, forKey: .playsSound)
        try container.encode(closesAfter, forKey: .closesAfter)
        try container.encode(previewSeconds, forKey: .previewSeconds)
        try container.encode(previewCorner, forKey: .previewCorner)
        try container.encode(warnsBeforeFlatten, forKey: .warnsBeforeFlatten)
        try container.encode(background, forKey: .background)
        try container.encode(output, forKey: .output)
        try container.encode(windowShot, forKey: .windowShot)
        try container.encode(crosshair, forKey: .crosshair)
        try container.encode(naming, forKey: .naming)
        try container.encode(clipboard, forKey: .clipboard)
        try container.encode(textRecognition, forKey: .textRecognition)
        try container.encode(remembersSelection, forKey: .remembersSelection)
        try container.encode(keepHistory, forKey: .keepHistory)
        try container.encode(movesToActiveScreen, forKey: .movesToActiveScreen)
        try container.encode(previewScale, forKey: .previewScale)
        try container.encode(closeAction, forKey: .closeAction)
        try container.encode(closesAfterDrag, forKey: .closesAfterDrag)
        try container.encode(saveButton, forKey: .saveButton)
        try container.encode(hidesDesktopIcons, forKey: .hidesDesktopIcons)
    }
}

enum CursorScreenshotClipboardMode: String, CaseIterable, Codable, Sendable {
    case fileAndImage, imageOnly, fileOnly
}

enum CursorScreenshotFormat: String, CaseIterable, Codable, Sendable {
    case jpeg = "public.jpeg", png = "public.png", heic = "public.heic", webp = "org.webmproject.webp"

    static let outputChoices: [CursorScreenshotFormat] = [.png, .jpeg, .webp]

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .webp: return "webp"
        }
    }

    var label: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .webp: return "WEBP"
        }
    }
}

struct CursorScreenshotOutput: Codable, Equatable, Sendable {
    var format = CursorScreenshotFormat.png
    var convertsToSRGB = false
    var scalesTo1x = false
    var addsBorder = false

    func shownScale(_ scale: CGFloat) -> CGFloat {
        scalesTo1x ? 1 : scale
    }
}

extension CursorScreenshotOutput {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let format = try? container.decode(CursorScreenshotFormat.self, forKey: .format), CursorScreenshotFormat.outputChoices.contains(format) {
            self.format = format
        }
        convertsToSRGB = (try? container.decode(Bool.self, forKey: .convertsToSRGB)) ?? false
        scalesTo1x = (try? container.decode(Bool.self, forKey: .scalesTo1x)) ?? false
        addsBorder = (try? container.decode(Bool.self, forKey: .addsBorder)) ?? false
    }
}

enum CursorScreenshotWindowBackground: String, Codable, Sendable {
    case transparent, wallpaper
}

struct CursorScreenshotWindowShot: Codable, Equatable, Sendable {
    var background = CursorScreenshotWindowBackground.transparent
    var shadow = false
}

extension CursorScreenshotWindowShot {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        background = (try? container.decode(CursorScreenshotWindowBackground.self, forKey: .background)) ?? .transparent
        shadow = (try? container.decode(Bool.self, forKey: .shadow)) ?? false
    }
}

enum CursorScreenshotCrosshairMode: String, CaseIterable, Codable, Sendable {
    case always, command, disabled

    func draws(held: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .always: return true
        case .command: return held.contains(.command)
        case .disabled: return false
        }
    }
}

struct CursorScreenshotCrosshair: Codable, Equatable, Sendable {
    var mode = CursorScreenshotCrosshairMode.disabled
    var showsMagnifier = true
}

extension CursorScreenshotCrosshair {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? container.decode(CursorScreenshotCrosshairMode.self, forKey: .mode)) ?? .disabled
        showsMagnifier = (try? container.decode(Bool.self, forKey: .showsMagnifier)) ?? true
    }
}

struct CursorScreenshotTextRecognition: Codable, Equatable, Sendable {
    var language: String?
    var keepsLineBreaks = true
    var detectsLinks = false
    var keepsStyling = false
}

extension CursorScreenshotTextRecognition {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = (try? container.decode(String.self, forKey: .language)).flatMap { CursorScreenshot.recognitionLanguages.contains($0) ? $0 : nil }
        keepsLineBreaks = (try? container.decode(Bool.self, forKey: .keepsLineBreaks)) ?? true
        detectsLinks = (try? container.decode(Bool.self, forKey: .detectsLinks)) ?? false
        keepsStyling = (try? container.decode(Bool.self, forKey: .keepsStyling)) ?? false
    }
}

enum CursorScreenshot {
    static let wholeScreenHotKeyID = CursorShaker.hotKeyID - 1
    static let areaHotKeyID = CursorShaker.hotKeyID - 2
    static let repeatHotKeyID = CursorShaker.hotKeyID - 3
    static let textHotKeyID = CursorShaker.hotKeyID - 4
    static let selfTimerHotKeyID = CursorShaker.hotKeyID - 5
    static let wallpaperFolder = "MaCursor/CursorScreenshotWallpapers"
    static let dragFolder = "Cursor Capture Drag"
    static let editorDragFolder = "Cursor Capture Editor Drag"
    static let clipboardFolder = "Cursor Capture Clipboard"
    static let historyFolder = "MaCursor/CursorScreenshotHistory"
    static let limit: TimeInterval = 5
    static let delays = [2, 5, 10, 15]

    static func removeCopiedFiles(support: URL?, group: URL?) {
        let folders = [support?.appendingPathComponent(wallpaperFolder, isDirectory: true),
                       group?.appendingPathComponent(dragFolder, isDirectory: true),
                       group?.appendingPathComponent(editorDragFolder, isDirectory: true),
                       group?.appendingPathComponent(clipboardFolder, isDirectory: true),
                       support?.appendingPathComponent(historyFolder, isDirectory: true)]
        for folder in folders.compactMap({ $0 }) { try? FileManager.default.removeItem(at: folder) }
    }

    static let cardTimes = [5, 10, 15, 30, 60, 120, 300, 600]
    static let cardScales = [0.75, 1, 1.25, 1.5]

    static func closesAfterDrag(_ setting: Bool, dropped: Bool, optionHeld: Bool) -> Bool {
        dropped && setting != optionHeld
    }

    static func cardDisplay<Display>(pointer: Display?, main: Display?, follows: Bool) -> Display? {
        follows ? pointer ?? main : main
    }

    static func cancels(pressed: UInt32, counting: UInt32?) -> Bool {
        pressed == counting
    }

    static func refuses(_ candidate: KeyboardShortcutData, held: [KeyboardShortcutData]) -> Bool {
        let macOSKeys = [20, 21].map { KeyboardShortcutData(keyCode: $0, modifierFlagsRaw: NSEvent.ModifierFlags([.control, .shift, .command]).rawValue, keyCharacter: nil) }
        return (macOSKeys + held).contains { MACShortcutsCollide($0.keyCode, $0.modifierFlagsRaw, candidate.keyCode, candidate.modifierFlagsRaw) }
    }

    static func refuses(_ candidate: CursorGestureTrigger, held: [CursorGestureTrigger]) -> Bool {
        candidate.button != nil && held.contains(where: candidate.overlaps)
    }

    static func skipsDefaultPreset(held: NSEvent.ModifierFlags, pressed: UInt?) -> Bool {
        guard held.contains(.shift) else { return false }
        guard let pressed else { return true }
        return !NSEvent.ModifierFlags(rawValue: pressed).contains(.shift)
    }

    static func wantsWallpaper(_ setting: CursorScreenshotWindowBackground, held: NSEvent.ModifierFlags) -> Bool {
        setting == .wallpaper || held.contains(.shift)
    }

    @discardableResult
    static func save(_ data: Data, as format: CursorScreenshotFormat, in folder: URL, name: CursorScreenshotFileName) throws -> URL {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent(".\(UUID().uuidString).\(format.fileExtension)")
        defer { try? files.removeItem(at: partial) }
        try data.write(to: partial)
        var number = 1
        while true {
            let file = folder.appendingPathComponent(name.file(as: format, copy: number))
            do {
                try files.moveItem(at: partial, to: file)
                return file
            } catch CocoaError.fileWriteFileExists {
                number += 1
            }
        }
    }

    static func dragFile(_ data: Data, as format: CursorScreenshotFormat, name: CursorScreenshotFileName, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name.file(as: format))
        try data.write(to: file, options: .atomic)
        return file
    }

    @discardableResult
    static func copy(_ data: Data, as format: CursorScreenshotFormat, mode: CursorScreenshotClipboardMode, in folder: URL?, name: CursorScreenshotFileName,
                     to pasteboard: NSPasteboard = .general) -> Bool {
        if let folder { try? FileManager.default.removeItem(at: folder) }
        if mode != .imageOnly {
            guard let folder, let file = try? dragFile(data, as: format, name: name, in: folder) else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects([file as NSURL])
            if mode == .fileOnly { return true }
        }
        let type = NSPasteboard.PasteboardType(format.rawValue)
        let tiff = format == .png ? nil : NSBitmapImageRep(data: data)?.tiffRepresentation
        let types: [NSPasteboard.PasteboardType] = tiff == nil ? [type] : [type, .tiff]
        if mode == .imageOnly {
            pasteboard.declareTypes(types, owner: nil)
        } else {
            pasteboard.addTypes(types, owner: nil)
        }
        pasteboard.setData(data, forType: type)
        if let tiff { pasteboard.setData(tiff, forType: .tiff) }
        return true
    }

    @discardableResult
    static func copyText(_ text: String, unlessChangedSince count: Int, to pasteboard: NSPasteboard = .general) -> Bool {
        guard pasteboard.changeCount == count else { return false }
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
        return true
    }

    static func forReading(_ image: CGImage, pointScale: CGFloat) -> CGImage {
        guard pointScale < 1.5, max(image.width, image.height) <= 1920 else { return image }
        let width = image.width * 3 / 2
        let height = image.height * 3 / 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    static func text(_ lines: [CursorTranslatorLine]) -> String {
        let rows = Self.rows(lines)
        guard rows.contains(where: { $0.count > 1 }), !textColumns(rows) else { return lines.map(\.text).joined(separator: "\n") }
        return rows.map { across($0).map(\.text).joined(separator: "\t") }.joined(separator: "\n")
    }

    private static func rows(_ lines: [CursorTranslatorLine]) -> [[CursorTranslatorLine]] {
        var rows: [[CursorTranslatorLine]] = []
        for line in lines.sorted(by: { $0.rect.midY > $1.rect.midY }) {
            if let first = rows.last?.first, abs(first.rect.midY - line.rect.midY) < min(first.rect.height, line.rect.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
    }

    private static func textColumns(_ rows: [[CursorTranslatorLine]]) -> Bool {
        let shared = rows.filter { $0.count > 1 }
        let columns = shared.filter { row in
            let across = row.sorted { $0.rect.minX < $1.rect.minX }
            let long = row.filter { $0.rect.width >= 10 * $0.rect.height }.count
            let gap = zip(across, across.dropFirst()).map { $1.rect.minX - $0.rect.maxX }.max() ?? 0
            return long > 1 || (long == 1 && gap > 3 * across[0].rect.height)
        }
        return !shared.isEmpty && columns.count * 2 > shared.count
    }

    private static func across(_ row: [CursorTranslatorLine]) -> [CursorTranslatorLine] {
        let rtl = row.contains { $0.text.unicodeScalars.contains { (0x590...0x8FF).contains($0.value) } }
        return row.sorted { rtl ? $0.rect.maxX > $1.rect.maxX : $0.rect.minX < $1.rect.minX }
    }

    private static func seam(_ text: String, _ next: String) -> String {
        guard let last = text.last, let first = next.first else { return text + next }
        let hyphen = last == "-" && text.dropLast().last?.isWhitespace == false
        return hyphen || CursorTranslator.ideographic(last) || CursorTranslator.ideographic(first) ? text + next : text + " " + next
    }

    static let recognitionLanguages = ["ar", "ars", "zh-Hans", "zh-Hant", "cs", "da", "nl", "en", "fr", "de", "id", "it", "ja", "ko", "ms",
                                       "no", "nb", "nn", "pl", "pt", "ro", "ru", "es", "sv", "th", "tr", "uk", "vi"]

    static func text(_ lines: [CursorTranslatorLine], keepsLineBreaks: Bool) -> String {
        let kept = text(lines)
        guard !keepsLineBreaks else { return kept }
        return kept.components(separatedBy: CharacterSet(charactersIn: "\n\t")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .reduce("", seam)
    }

    static func text(_ lines: [CursorTranslatorLine], keepsLineBreaks: Bool, keepsStyling: Bool) -> String {
        let rows = Self.rows(lines)
        guard keepsStyling, !textColumns(rows) else { return text(lines, keepsLineBreaks: keepsLineBreaks) }
        let units: [(text: String, rect: CGRect)] = rows.compactMap { row in
            let pieces = across(row).map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !pieces.isEmpty else { return nil }
            return (keepsLineBreaks ? pieces.joined(separator: "\t") : pieces.reduce("", seam), row.reduce(CGRect.null) { $0.union($1.rect) })
        }
        guard let first = units.first else { return "" }
        let average = units.map(\.rect.height).reduce(0, +) / CGFloat(units.count)
        return zip(units, units.dropFirst()).reduce(first.text) { text, pair in
            let (above, unit) = pair
            if above.rect.minY - unit.rect.maxY > max(0.75 * average, 0.68 * max(above.rect.height, unit.rect.height)) { return text + "\n\n" + unit.text }
            return keepsLineBreaks || CursorTranslator.listed(unit.text) ? text + "\n" + unit.text : seam(text, unit.text)
        }
    }

    static func firstLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        func webLink(_ text: String) -> NSTextCheckingResult? {
            detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).first { match in
                match.url.map { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host?.isEmpty == false } ?? false
            }
        }
        var lines = text.components(separatedBy: "\n")[...]
        while let line = lines.popFirst() {
            guard var found = webLink(line) else { continue }
            var joined = line
            while NSMaxRange(found.range) == (joined as NSString).length, let last = joined.last, "/-_=&?#%~+".contains(last),
                  let next = lines.first, case let piece = next.prefix(while: { !$0.isWhitespace }), !piece.isEmpty,
                  let longer = webLink(joined + piece), longer.range.location == found.range.location, NSMaxRange(longer.range) > NSMaxRange(found.range) {
                joined += piece
                found = longer
                guard piece.count == next.count else { break }
                lines.removeFirst()
            }
            return found.url
        }
        return nil
    }

    static func firstLine(_ text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}

@MainActor
final class CursorScreenshotPictures {
    private var taking: [UInt32: Task<CGImage?, Never>] = [:]
    private var waiting: [UInt32: @MainActor () async -> CGImage?] = [:]
    private var arrived: ((UInt32, CGImage) -> Void)?
    private var settled: ((Bool) -> Void)?
    private var left: Int
    private var any = false

    init(_ takes: [(display: UInt32, take: @MainActor () async -> CGImage?)], freezes: Bool,
         arrived: @escaping (UInt32, CGImage) -> Void, settled: @escaping (Bool) -> Void) {
        self.arrived = arrived
        self.settled = settled
        left = takes.count
        for (display, take) in takes {
            guard freezes else {
                waiting[display] = take
                continue
            }
            taking[display] = Task { [weak self] in
                let image = await take()
                self?.finished(display, image)
                return image
            }
        }
    }

    func keep(_ display: UInt32) -> Task<CGImage?, Never>? {
        guard let take = waiting.removeValue(forKey: display) else { return taking.removeValue(forKey: display) }
        return Task { await take() }
    }

    func end() {
        arrived = nil
        settled = nil
        waiting = [:]
        taking.values.forEach { $0.cancel() }
        taking = [:]
    }

    private func finished(_ display: UInt32, _ image: CGImage?) {
        guard let arrived, let settled else { return }
        left -= 1
        if let image {
            any = true
            arrived(display, image)
        }
        if left == 0 { settled(any) }
    }
}

enum CursorScreenshotCorner: String, Codable, CaseIterable {
    case bottomLeft, bottomRight

    private var onLeft: Bool { self == .bottomLeft }

    func cardOrigin(size: NSSize, margin: CGFloat, in visible: CGRect) -> CGPoint {
        CGPoint(x: onLeft ? visible.minX + margin : visible.maxX - margin - size.width, y: visible.minY + margin)
    }

    func noticeOrigin(size: NSSize, margin: CGFloat, gap: CGFloat, in visible: CGRect, card: CGRect?) -> CGPoint {
        guard let card, visible.intersects(card) else { return cardOrigin(size: size, margin: margin, in: visible) }
        return CGPoint(x: card.midX < visible.midX ? visible.minX + margin : visible.maxX - margin - size.width, y: card.maxY + gap)
    }

    func slide(_ distance: CGFloat) -> CGFloat {
        onLeft ? -distance : distance
    }
}

enum CursorScreenshotCloseAction: String, Codable, Sendable {
    case saveAndClose, close

    func savesFirst(saved: Bool) -> Bool {
        self == .saveAndClose && !saved
    }
}

enum CursorScreenshotSaveButton: String, Codable, Sendable {
    case exportLocation, askForDestination

    func asks(optionHeld: Bool) -> Bool {
        (self == .askForDestination) != optionHeld
    }
}

struct CursorScreenshotCardClock {
    private(set) var deadline: Date?

    mutating func restart(held: Bool, at now: Date, seconds: Int?) {
        deadline = held ? nil : seconds.map { now.addingTimeInterval(TimeInterval($0)) }
    }
}

struct CursorScreenshotCardPress {
    static let dragReach: CGFloat = 4

    private var start: CGPoint?
    private var count = 0
    private var dragged = false

    mutating func down(at point: CGPoint, count: Int) {
        start = point
        self.count = dragged ? 1 : count
        dragged = false
    }

    mutating func startsDrag(at point: CGPoint) -> Bool {
        guard let start, hypot(point.x - start.x, point.y - start.y) >= Self.dragReach else { return false }
        self.start = nil
        dragged = count == 1
        return dragged
    }

    mutating func opensEditor() -> Bool {
        defer { start = nil }
        return start != nil && count == 2
    }
}

struct CursorScreenshotArea: Codable, Equatable {
    var display: UInt32
    var box: CGRect
}

enum CursorScreenshotBox {
    static let smallest: CGFloat = 4
    static let loupeSpan: CGFloat = 19
    static let loupeSize = loupeSpan * 7
    static let loupeGap: CGFloat = 20
    static let loupeDrop: CGFloat = 40

    static func guides(through pointer: CGPoint, in bounds: CGRect) -> CGPath {
        let x = pointer.x.rounded(.down) + 0.5
        let y = pointer.y.rounded(.down) + 0.5
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: bounds.minY))
        path.addLine(to: CGPoint(x: x, y: bounds.maxY))
        path.move(to: CGPoint(x: bounds.minX, y: y))
        path.addLine(to: CGPoint(x: bounds.maxX, y: y))
        return path
    }

    static func loupeOrigin(pointer: CGPoint, in bounds: CGRect) -> CGPoint {
        let right = pointer.x + loupeGap
        let below = pointer.y - loupeDrop - loupeSize
        return CGPoint(x: right + loupeSize > bounds.maxX ? pointer.x - loupeGap - loupeSize : right,
                       y: below < bounds.minY ? pointer.y + loupeDrop : below)
    }

    static func loupeSource(pointer: CGPoint, in bounds: CGRect) -> CGRect {
        let reach = (loupeSpan - 1) / 2
        return CGRect(x: (pointer.x.rounded(.down) - reach - bounds.minX) / bounds.width, y: (pointer.y.rounded(.down) - reach - bounds.minY) / bounds.height,
                      width: loupeSpan / bounds.width, height: loupeSpan / bounds.height)
    }

    static func box(from start: CGPoint, to end: CGPoint, in frame: CGRect) -> CGRect {
        let left = min(max(start.x, frame.minX), frame.maxX)
        let right = min(max(end.x, frame.minX), frame.maxX)
        let bottom = min(max(start.y, frame.minY), frame.maxY)
        let top = min(max(end.y, frame.minY), frame.maxY)
        return CGRect(x: min(left, right), y: min(bottom, top), width: abs(right - left), height: abs(top - bottom))
    }

    static func isTooSmall(_ box: CGRect) -> Bool {
        box.width < smallest || box.height < smallest
    }

    static func pixels(of box: CGRect, in frame: CGRect, width: Int, height: Int) -> CGRect {
        let across = CGFloat(width) / frame.width
        let down = CGFloat(height) / frame.height
        let left = ((box.minX - frame.minX) * across).rounded(.down)
        let right = ((box.maxX - frame.minX) * across).rounded(.up)
        let top = ((frame.maxY - box.maxY) * down).rounded(.down)
        let bottom = ((frame.maxY - box.minY) * down).rounded(.up)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func shown(_ box: CGRect, in frame: CGRect, width: Int, height: Int) -> CGRect {
        let kept = pixels(of: box, in: frame, width: width, height: height)
        let across = CGFloat(width) / frame.width
        let down = CGFloat(height) / frame.height
        return CGRect(x: kept.minX / across, y: (CGFloat(height) - kept.maxY) / down, width: kept.width / across, height: kept.height / down)
    }

    static func label(_ pixels: CGRect) -> String {
        "\(Int(pixels.width))\n\(Int(pixels.height))"
    }

    static func labelOrigin(pointer: CGPoint, size: NSSize, in bounds: CGRect) -> CGPoint {
        let right = pointer.x + 12
        let below = pointer.y - 4 - size.height
        return CGPoint(x: right + size.width > bounds.maxX ? pointer.x - 12 - size.width : right,
                       y: below < bounds.minY ? pointer.y + 12 : below)
    }

    static func repeated(_ area: CursorScreenshotArea?, displays: [UInt32: CGRect]) -> CGRect? {
        guard let area, let frame = displays[area.display], !isTooSmall(area.box),
              CGRect(origin: .zero, size: frame.size).contains(area.box) else { return nil }
        return area.box.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    static func moved(_ box: CGRect, by delta: CGVector, in frame: CGRect) -> CGRect {
        CGRect(x: min(max(box.minX + delta.dx, frame.minX), frame.maxX - box.width),
               y: min(max(box.minY + delta.dy, frame.minY), frame.maxY - box.height), width: box.width, height: box.height)
    }

    static func movable(_ box: CGRect, in frame: CGRect) -> Bool {
        box.width < frame.width || box.height < frame.height
    }

    static func startsNewBox(from start: CGPoint, to end: CGPoint, in frame: CGRect) -> Bool {
        !isTooSmall(box(from: start, to: end, in: frame))
    }
}

struct CursorScreenshotWindow: Equatable, Sendable {
    let id: CGWindowID
    let frame: CGRect
    var shown: CGRect
    var owner: String?
    var title: String?
}

struct CursorScreenshotPick: Equatable {
    var box: CGRect
    var window: CursorScreenshotWindow?
}

enum CursorScreenshotWindows {
    static let systemBundles = ["com.apple.dock", "com.apple.WindowManager"]
    static let smallest: CGFloat = 50
    static let chromeAbove = Int(CGWindowLevelForKey(.popUpMenuWindow))
    static let shadowPadding: CGFloat = 128
    static let wallpaperPadding: CGFloat = 90
    static let wallpaperStyle = CursorScreenshotBackgroundStyle(fill: .desktop, padding: wallpaperPadding)

    static func isChrome(layer: Int) -> Bool {
        layer > chromeAbove
    }

    static func isDesktopIconOrWidget(bundle: String?, layer: Int) -> Bool {
        switch bundle {
        case "com.apple.finder": return layer == Int(CGWindowLevelForKey(.desktopIconWindow))
        case "com.apple.notificationcenterui": return layer < Int(CGWindowLevelForKey(.normalWindow))
        default: return false
        }
    }

    static func trimmed(_ windows: [CursorScreenshotWindow], panel: CGRect, to card: CGRect) -> [CursorScreenshotWindow] {
        windows.map { window in
            let frame = window.frame
            guard [frame.minX - panel.minX, frame.minY - panel.minY, frame.maxX - panel.maxX, frame.maxY - panel.maxY].allSatisfy({ abs($0) <= 1 }) else { return window }
            var kept = window
            kept.shown = card
            return kept
        }
    }

    static func top(_ list: [[String: Any]], skipping owners: Set<pid_t>) -> CursorScreenshotWindow? {
        windows(list, skipping: owners, primaryHeight: 0).first
    }

    static func windows(_ list: [[String: Any]], skipping owners: Set<pid_t>, primaryHeight: CGFloat) -> [CursorScreenshotWindow] {
        let appLayers = 0..<Int(CGWindowLevelForKey(.dockWindow))
        return list.compactMap { info in
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, appLayers.contains(layer),
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0) > 0,
                  let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, !owners.contains(owner),
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  bounds.width >= smallest, bounds.height >= smallest else { return nil }
            let frame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return CursorScreenshotWindow(id: id, frame: frame, shown: frame, owner: info[kCGWindowOwnerName as String] as? String, title: info[kCGWindowName as String] as? String)
        }
    }

    static func front(at point: CGPoint, in windows: [CursorScreenshotWindow], on display: CGRect) -> CursorScreenshotPick? {
        guard NSMouseInRect(point, display, false), let window = windows.first(where: { NSMouseInRect(point, $0.shown, false) }) else { return nil }
        let box = window.shown.intersection(display)
        return CursorScreenshotBox.isTooSmall(box) ? nil : CursorScreenshotPick(box: box, window: window)
    }

    static func display(holding frame: CGRect, among displays: [UInt32: CGRect]) -> UInt32? {
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        if let held = displays.first(where: { $0.value.contains(middle) }) { return held.key }
        let covered = displays.mapValues { $0.intersection(frame) }.filter { !$0.value.isEmpty }
        return covered.max { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?.key
    }
}
