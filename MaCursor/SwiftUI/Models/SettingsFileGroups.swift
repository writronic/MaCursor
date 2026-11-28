import AppKit
import SwiftUI

struct SettingsFileField {
    let key: String
    let read: (SettingsFilePlace) -> Any?
    let check: (Any) -> Any?
    let write: (Any?, SettingsFilePlace) throws -> Void
}

enum SettingsFileHistoryGroup: String, CaseIterable, Identifiable {
    case captureHistory, cursorBoardHistory

    var id: String { rawValue }

    var parent: SettingsFileGroup {
        self == .captureHistory ? .cursorCapture : .cursorBoard
    }

    var title: String {
        self == .captureHistory ? String(localized: "Capture History") : String(localized: "Cursor Board History")
    }

    var exportCaption: Text {
        self == .captureHistory
            ? Text("Your past screenshots. Anyone who gets the file can see them.")
            : Text("Your copied text and pictures. Anyone who gets the file can see them.")
    }

    static var importCaption: Text {
        Text("Items older than your Keep history setting are not added.")
    }
}

enum SettingsFileGroup: String, CaseIterable, Identifiable {
    case general, cursorControl, cursorCapture, cursorBoard, cursorTranslator, cursorGestures, cursorTrails, cursorHighlight, rightClickMenu, shortcut

    static let automaticChecksKey = "SUEnableAutomaticChecks"

    static let neverExported: [String] = [
        MACPreferences.appliedCursorKey,
        MACPreferences.appOverrideKey,
        MACPreferences.appOverrideBaseKey,
        MACPreferences.ffmAccessibilityTrustedKey,
        MACPreferences.cursorTranslatorScreenRecordingKey,
        MACPreferences.pendingOpenSettingsKey,
        MACPreferences.pendingSettingsTabKey,
        MACPreferences.pendingFFMAccessWindowKey,
        MACPreferences.pendingGesturesAccessWindowKey,
        MACPreferences.pendingShakerAccessWindowKey,
        MACPreferences.pendingScreenshotAccessWindowKey,
        MACPreferences.pendingTranslatorAccessWindowKey,
        MACPreferences.pendingBoardAccessWindowKey,
        MACPreferences.pendingMagnifierAccessWindowKey,
        MACPreferences.welcomeShownKey,
        "MACWelcomePage",
        MACPreferences.fullDiskAccessAskedKey,
        MACPreferences.helperBuildKey,
        MACPreferences.suppressDeleteLibraryKey,
        MACPreferences.suppressDeleteCursorKey,
        MACPreferences.advancedEditorLayoutKey,
        MACPreferences.themesLayoutKey,
        MACPreferences.galleryLayoutKey,
        MACPreferences.cursorScreenshotMarkupKey,
        MACPreferences.languageKey,
        MACPreferences.padCursorCanvasKey,
        "MACMenuBarCursorThemesExpanded",
        "MACMenuBarActiveAppExpanded",
        "MACMenuBarCursorCaptureExpanded",
        "MACMenuBarQuickControlsExpanded",
        "MACMenuBarCursorTrailsExpanded",
        "MACMenuBarCursorHighlightExpanded",
        "MACMenuBarFocusOnHoverExpanded"
    ]

    static var writeOrder: [SettingsFileGroup] {
        allCases.filter { $0 != .general } + [.general]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .cursorControl: return String(localized: "Cursor Control")
        case .cursorCapture: return String(localized: "Cursor Capture")
        case .cursorBoard: return String(localized: "Cursor Board")
        case .cursorTranslator: return String(localized: "Cursor Translator")
        case .cursorGestures: return String(localized: "Cursor Gestures")
        case .cursorTrails: return String(localized: "Cursor Trails")
        case .cursorHighlight: return String(localized: "Cursor Highlight")
        case .rightClickMenu: return String(localized: "Right-Click Menu")
        case .shortcut: return String(localized: "Shortcut")
        }
    }

    var fields: [SettingsFileField] {
        switch self {
        case .general:
            return [Self.preference(MACPreferences.appearanceModeKey) { Self.integer($0).flatMap { (0...2).contains($0) ? NSNumber(value: $0) : nil } },
                    Self.flag(MACPreferences.showCursorIdentifiersKey),
                    Self.flag(MACPreferences.showMenuBarIconKey),
                    Self.flag(MACPreferences.followReduceMotionKey),
                    Self.preference(MACPreferences.menuBarPanelBackgroundKey) { Self.number($0).map { NSNumber(value: min(1, max(0, $0))) } },
                    Self.rows(MACPreferences.menuBarItemOrderKey, MACMenuBarItem.self),
                    Self.rows(MACPreferences.menuBarHiddenItemsKey, MACMenuBarItem.self),
                    Self.rows(MACPreferences.menuBarCaptureOrderKey, MACMenuBarCaptureRow.self),
                    Self.rows(MACPreferences.menuBarHiddenCaptureRowsKey, MACMenuBarCaptureRow.self),
                    Self.automaticChecks]
        case .cursorControl:
            return [Self.preference(MACPreferences.cursorScaleKey) { Self.number($0).map { NSNumber(value: CursorScaleInput.clamp($0)) } },
                    Self.flag(MACPreferences.hideTahoeCursorsKey),
                    Self.flag(MACPreferences.handednessKey),
                    Self.flag(MACPreferences.cursorShadowKey),
                    Self.json(MACPreferences.autoSwitchRulesKey, AutoSwitchConfig.self) { $0.normalize() },
                    Self.json(MACPreferences.focusFollowsMouseKey, FocusFollowsMouseConfig.self) { $0.normalize() },
                    Self.shakerField]
        case .cursorCapture:
            return [Self.captureField]
        case .cursorBoard:
            return [Self.json(MACPreferences.cursorBoardKey, CursorBoardConfig.self)]
        case .cursorTranslator:
            return [Self.translatorField]
        case .cursorGestures:
            return [Self.gesturesField]
        case .cursorTrails:
            return [Self.json(MACPreferences.cursorTrailsKey, CursorTrailsConfig.self)]
        case .cursorHighlight:
            return [Self.json(MACPreferences.cursorHighlightKey, CursorHighlightConfig.self)]
        case .rightClickMenu:
            return [Self.rightClickMenuField]
        case .shortcut:
            return [Self.json(MACPreferences.favoriteCursorsKey, [FavoriteCursorSlot].self)]
        }
    }

    static func boolean(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    static func integer(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber, boolean(number) == nil, number.doubleValue == Double(number.intValue) else { return nil }
        return number.intValue
    }

    private static func number(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, boolean(number) == nil, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func preference(_ key: String, check: @escaping (Any) -> Any?) -> SettingsFileField {
        SettingsFileField(key: key,
                          read: { MACPreferences.value(forKey: key, operations: $0.preferences).flatMap(check) },
                          check: check,
                          write: { MACPreferences.set($0, forKey: key, operations: $1.preferences) })
    }

    private static func flag(_ key: String) -> SettingsFileField {
        preference(key) { boolean($0).map { NSNumber(value: $0) } }
    }

    private static func rows<Row: RawRepresentable>(_ key: String, _ type: Row.Type) -> SettingsFileField where Row.RawValue == String {
        preference(key) { raw in
            guard let values = raw as? [Any] else { return nil }
            return values.compactMap { ($0 as? String).flatMap(Row.init(rawValue:))?.rawValue }
        }
    }

    private static func json<Value: Codable>(_ key: String, _ type: Value.Type, tidy: @escaping (inout Value) -> Void = { _ in }) -> SettingsFileField {
        preference(key) { raw in
            guard let data = raw as? Data, var value = try? JSONDecoder().decode(Value.self, from: data) else { return nil }
            tidy(&value)
            return try? JSONEncoder().encode(value)
        }
    }

    private static var automaticChecks: SettingsFileField {
        let key = automaticChecksKey
        let check: (Any) -> Any? = { boolean($0).map { NSNumber(value: $0) } }
        return SettingsFileField(key: key,
                                 read: { MACPreferences.value(forKey: key, operations: $0.preferences).flatMap(check) },
                                 check: check,
                                 write: { value, place in
                                     place.preferences.write(key as CFString, value, MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                                     place.preferences.synchronize(MACPreferences.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                                 })
    }

    private static var shakerField: SettingsFileField {
        let shared = json(MACPreferences.cursorShakerKey, CursorShakerConfig.self) { $0.endTime = nil }
        return SettingsFileField(key: shared.key, read: shared.read, check: shared.check, write: { value, place in
            guard let data = value as? Data, var config = try? JSONDecoder().decode(CursorShakerConfig.self, from: data) else {
                return try shared.write(nil, place)
            }
            config.turn(false, at: Date())
            try shared.write(try? JSONEncoder().encode(config), place)
        })
    }

    private static var translatorField: SettingsFileField {
        let shared = json(MACPreferences.cursorTranslatorKey, CursorTranslatorConfig.self)
        return SettingsFileField(key: shared.key, read: shared.read, check: shared.check, write: { value, place in
            func decoded(_ raw: Any?) -> CursorTranslatorConfig? {
                (raw as? Data).flatMap { try? JSONDecoder().decode(CursorTranslatorConfig.self, from: $0) }
            }
            let here = decoded(MACPreferences.value(forKey: shared.key, operations: place.preferences)) ?? CursorTranslatorConfig()
            var config = decoded(value) ?? CursorTranslatorConfig()
            config.service = here.service
            config.addresses = here.addresses
            config.models = here.models
            try shared.write(try? JSONEncoder().encode(config), place)
        })
    }

    private static func movePaths(_ config: inout CursorGesturesConfig, _ move: (String) -> String) {
        for index in config.actions.indices {
            if case .app(let path) = config.actions[index].kind { config.actions[index].kind = .app(move(path)) }
            if case .appleScript(let script) = config.actions[index].kind, CursorGestures.scriptFile(script) != nil { config.actions[index].kind = .appleScript(move(script.trimmingCharacters(in: .whitespacesAndNewlines))) }
        }
    }

    private static var gesturesField: SettingsFileField {
        let key = MACPreferences.cursorGesturesKey
        let landed = json(key, CursorGesturesConfig.self) { movePaths(&$0, SettingsFile.homeExpanded) }
        let sent = json(key, CursorGesturesConfig.self) { movePaths(&$0, SettingsFile.fromHome) }
        return SettingsFileField(key: key, read: sent.read, check: landed.check, write: landed.write)
    }

    private static var captureField: SettingsFileField {
        let key = MACPreferences.cursorScreenshotKey
        return SettingsFileField(
            key: key,
            read: { place in
                guard let data = MACPreferences.value(forKey: key, operations: place.preferences) as? Data,
                      var config = try? JSONDecoder().decode(CursorScreenshotConfig.self, from: data) else { return nil }
                config.lastArea = nil
                config.folder = SettingsFile.fromHome(config.folder)
                return try? JSONEncoder().encode(config)
            },
            check: { raw in
                guard let data = raw as? Data, var config = try? JSONDecoder().decode(CursorScreenshotConfig.self, from: data) else { return nil }
                let folder = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["folder"] as? String ?? ""
                config.lastArea = nil
                config.folder = SettingsFile.onThisMac(folder)
                return try? JSONEncoder().encode(config)
            },
            write: { value, place in
                func decoded(_ raw: Any?) -> CursorScreenshotConfig? {
                    (raw as? Data).flatMap { try? JSONDecoder().decode(CursorScreenshotConfig.self, from: $0) }
                }
                let here = decoded(MACPreferences.value(forKey: key, operations: place.preferences))?.lastArea
                guard value != nil || here != nil else { return MACPreferences.set(nil, forKey: key, operations: place.preferences) }
                var config = decoded(value) ?? CursorScreenshotConfig()
                config.lastArea = here
                MACPreferences.set(try? JSONEncoder().encode(config), forKey: key, operations: place.preferences)
            })
    }

    private static var rightClickMenuField: SettingsFileField {
        let check: (Any) -> Any? = { raw in
            guard let data = raw as? Data, let settings = try? JSONDecoder().decode(RightClickMenuSettings.self, from: data),
                  let encoded = try? JSONEncoder().encode(settings),
                  var object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else { return nil }
            object["hasFullDiskAccess"] = nil
            return try? JSONSerialization.data(withJSONObject: object)
        }
        return SettingsFileField(
            key: "RightClickMenuSettings",
            read: { place in place.rightClickMenu.flatMap { try? Data(contentsOf: $0) }.flatMap(check) },
            check: check,
            write: { value, place in
                guard let data = value as? Data else {
                    _ = try RightClickMenuSettings.reset(to: place.rightClickMenu)
                    return
                }
                var settings = try JSONDecoder().decode(RightClickMenuSettings.self, from: data)
                settings.hasFullDiskAccess = RightClickMenuSettings.load(from: place.rightClickMenu).hasFullDiskAccess
                try settings.save(to: place.rightClickMenu)
            })
    }
}
