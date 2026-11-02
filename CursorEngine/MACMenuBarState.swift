import AppKit
import Carbon
import Darwin
import SwiftUI

let MACHelperBundleIdentifier = "com.writronic.macursor.helper"
let MACHelperBundleName = "MaCursorHelper"
let MACAppBundleIdentifier = "com.writronic.macursor"
let MACMenuBarMinCursorScale = 0.5
let MACMenuBarMaxCursorScale = 4.0
let MACMenuBarPanelBackgroundDefault = 0.5

extension Notification.Name {
    static let MACMenuBarDidChange = Notification.Name("MACMenuBarDidChange")
    static let MACOpenSettingsRequested = Notification.Name("MACOpenSettingsRequested")
    static let MACFocusFollowsMouseShowAccessWindow = Notification.Name("MACFocusFollowsMouseShowAccessWindow")
    static let MACCursorGesturesShowAccessWindow = Notification.Name("MACCursorGesturesShowAccessWindow")
    static let MACCursorShakerShowAccessWindow = Notification.Name("MACCursorShakerShowAccessWindow")
    static let MACCursorTranslatorShowAccessWindow = Notification.Name("MACCursorTranslatorShowAccessWindow")
    static let MACCursorPreferencesDidChange = Notification.Name("MACCursorPreferencesDidChange")
}

struct MACMenuBarThemeEntry: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

@MainActor
final class MACMenuBarState {
    static let shared = MACMenuBarState()

    private struct CatalogRecord {
        let modified: Date
        let entry: MACMenuBarThemeEntry?
    }

    private var catalogCache: [String: CatalogRecord] = [:]
    private(set) var lastForegroundBundleID: String?

    func noteForegroundBundleID(_ identifier: String?) {
        guard let identifier = nonEmptyString(identifier), !MACMenuBarIsHelperBundleIdentifier(identifier) else { return }
        lastForegroundBundleID = identifier
    }

    func catalog() -> [MACMenuBarThemeEntry] {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return [] }
        return catalog(at: support.appendingPathComponent("MaCursor/cursors").path)
    }

    func catalog(at directory: String?) -> [MACMenuBarThemeEntry] {
        guard let directory = nonEmptyString(directory),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        var seen = Set<String>()
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { name in
            guard !name.hasPrefix("."), (name as NSString).pathExtension == "cursor",
                  let entry = catalogEntry(at: (directory as NSString).appendingPathComponent(name)),
                  seen.insert(entry.id).inserted else { return nil }
            return entry
        }
    }

    private func catalogEntry(at path: String) -> MACMenuBarThemeEntry? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        if let cached = catalogCache[path], cached.modified == modified { return cached.entry }
        let plist = menuBarTheme(at: path)
        let entry = nonEmptyString(plist?[MACCursorDefinitions.identifierKey]).map {
            MACMenuBarThemeEntry(id: $0, name: nonEmptyString(plist?[MACCursorDefinitions.themeNameKey]) ?? $0)
        }
        catalogCache[path] = CatalogRecord(modified: modified, entry: entry)
        return entry
    }
}

private func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else { return nil }
    return string
}

private func menuBarTheme(at path: String) -> [AnyHashable: Any]? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [AnyHashable: Any]
}

func MACMenuBarVisibleThemeIdentifier(_ appliedIdentifier: String?, _ activeOverride: String?) -> String? {
    nonEmptyString(activeOverride) ?? nonEmptyString(appliedIdentifier)
}

func MACMenuBarConfigBySettingSwitchByApp(_ config: [AnyHashable: Any]?, _ enabled: Bool) -> [AnyHashable: Any] {
    var updated = config ?? [:]
    updated["switchByApp"] = enabled
    return updated
}

func MACMenuBarConfigBySettingRule(
    _ config: [AnyHashable: Any]?, _ bundleIdentifier: String?, _ displayName: String?, _ themeIdentifier: String?
) -> [AnyHashable: Any] {
    var updated = config ?? [:]
    guard let bundle = nonEmptyString(bundleIdentifier) else { return updated }
    var rules = updated["appRules"] as? [Any] ?? []
    let index = rules.firstIndex { candidate in
        guard let rule = candidate as? [AnyHashable: Any] else { return false }
        return nonEmptyString(rule["bundleIdentifier"]) == bundle
    }
    var rule = index.flatMap { rules[$0] as? [AnyHashable: Any] } ?? ["bundleIdentifier": bundle]
    if nonEmptyString(rule["id"]) == nil { rule["id"] = UUID().uuidString }
    rule["themeIdentifier"] = nonEmptyString(themeIdentifier)
    if let name = nonEmptyString(displayName) { rule["displayName"] = name }
    if let index {
        rules[index] = rule
    } else {
        rules.append(rule)
    }
    updated["appRules"] = rules
    return updated
}

func MACMenuBarRuleThemeForBundleID(_ config: [AnyHashable: Any]?, _ bundleIdentifier: String?) -> String? {
    guard let bundle = nonEmptyString(bundleIdentifier), let rules = config?["appRules"] as? [Any] else { return nil }
    for candidate in rules {
        guard let rule = candidate as? [AnyHashable: Any], nonEmptyString(rule["bundleIdentifier"]) == bundle else { continue }
        return nonEmptyString(rule["themeIdentifier"])
    }
    return nil
}

@MainActor
@discardableResult
func MACMenuBarWriteConfig(_ config: [AnyHashable: Any]?) -> Bool {
    guard let config, JSONSerialization.isValidJSONObject(config),
          let data = try? JSONSerialization.data(withJSONObject: config) else { return false }
    MACPreferences.set(data, forKey: MACPreferences.autoSwitchRulesKey)
    DistributedNotificationCenter.default().postNotificationName(.MACAutoSwitchDidChange, object: nil,
                                                                 userInfo: nil, deliverImmediately: true)
    return true
}

func MACMenuBarIsHelperBundleIdentifier(_ identifier: String?) -> Bool {
    nonEmptyString(identifier)?.caseInsensitiveCompare(MACHelperBundleIdentifier) == .orderedSame
}

func MACMenuBarFFMConfigBySettingEnabled(_ config: [AnyHashable: Any]?, _ enabled: Bool) -> [AnyHashable: Any] {
    var updated = config ?? [:]
    updated["enabled"] = enabled
    return updated
}

func MACMenuBarFFMConfigBySettingDelay(_ config: [AnyHashable: Any]?, delayMs: Int) -> [AnyHashable: Any] {
    var updated = config ?? [:]
    updated["delayMs"] = min(max(delayMs, 0), MACFFMMaxDelayMs)
    return updated
}

func MACMenuBarPanelBackgroundLevel(_ stored: Any?) -> Double {
    guard let number = stored as? NSNumber, number.doubleValue.isFinite else { return MACMenuBarPanelBackgroundDefault }
    return min(1, max(0, number.doubleValue))
}

func MACMenuBarPanelGlassAlpha(_ level: Double) -> Double {
    min(1, max(0, level / MACMenuBarPanelBackgroundDefault))
}

func MACMenuBarPanelBackdropAlpha(_ level: Double) -> Double {
    min(1, max(0, (level - MACMenuBarPanelBackgroundDefault) / (1 - MACMenuBarPanelBackgroundDefault)))
}

func MACMenuBarFavoriteThemeIdentifiers(_ stored: Any?) -> [String] {
    guard let values = stored as? [Any] else { return [] }
    var seen = Set<String>()
    return values.compactMap { value in
        guard let identifier = nonEmptyString(value), seen.insert(identifier).inserted else { return nil }
        return identifier
    }
}

func MACMenuBarFavoriteCatalog(_ catalog: [MACMenuBarThemeEntry]?, _ stored: Any?) -> [MACMenuBarThemeEntry] {
    let wanted = Set(MACMenuBarFavoriteThemeIdentifiers(stored))
    return (catalog ?? []).filter { !$0.id.isEmpty && wanted.contains($0.id) }
}

func MACMenuBarClampCursorScale(_ scale: Double) -> Double {
    guard scale.isFinite else { return 1 }
    return min(MACMenuBarMaxCursorScale, max(MACMenuBarMinCursorScale, scale))
}

func MACMenuBarAppearanceNameForMode(_ mode: Any?) -> NSAppearance.Name? {
    guard let number = mode as? NSNumber else { return nil }
    switch number.intValue {
    case 1: return .aqua
    case 2: return .darkAqua
    default: return nil
    }
}

func MACMenuBarClickIsSecondary(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags) -> Bool {
    type == .rightMouseUp || type == .rightMouseDown || (type == .leftMouseUp && flags.contains(.control))
}

struct MACMenuBarThumbnail: Sendable {
    let data: Data
    let frameCount: UInt
}

func MACMenuBarThemeThumbnailData(_ theme: [AnyHashable: Any]?) -> MACMenuBarThumbnail? {
    guard let cursors = theme?[MACCursorDefinitions.cursorsKey] as? [AnyHashable: Any] else { return nil }
    for identifier in ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS"] {
        guard let entry = cursors[identifier] as? [AnyHashable: Any],
              let reps = entry[MACCursorDefinitions.representationsKey] as? [Any], !reps.isEmpty else { continue }
        var best: Data?
        for case let rep as Data in reps {
            if best == nil || rep.count > best!.count { best = rep }
        }
        guard let best else { return nil }
        let frames = (entry[MACCursorDefinitions.frameCountKey] as? NSNumber)?.intValue ?? 1
        return MACMenuBarThumbnail(data: best, frameCount: UInt(max(1, frames)))
    }
    return nil
}

@MainActor
func MACMenuBarThumbnailImageFromData(_ data: Data?, _ frameCount: UInt) -> NSImage? {
    guard let data, !data.isEmpty, let rep = NSBitmapImageRep(data: data), let source = rep.cgImage,
          rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
    let frames = max(1, frameCount)
    let height = max(1, Int(UInt(rep.pixelsHigh) / frames))
    guard let cropped = frames > 1
        ? source.cropping(to: CGRect(x: 0, y: 0, width: rep.pixelsWide, height: height)) : source else { return nil }
    let frameRep = NSBitmapImageRep(cgImage: cropped)
    let points = NSSize(width: Double(rep.pixelsWide) / 2, height: Double(height) / 2)
    frameRep.size = points
    let image = NSImage(size: points)
    image.addRepresentation(frameRep)
    return image
}

@MainActor
func MACMenuBarThumbnailImageForThemeAtPath(_ path: String?) -> NSImage? {
    guard let path = nonEmptyString(path), let thumbnail = MACMenuBarThemeThumbnailData(menuBarTheme(at: path)) else { return nil }
    return MACMenuBarThumbnailImageFromData(thumbnail.data, thumbnail.frameCount)
}

func MACHelperBuildIdentityAtPath(_ path: String?) -> String? {
    guard let path = nonEmptyString(path) else { return nil }
    var info = stat()
    guard stat((path as NSString).fileSystemRepresentation, &info) == 0 else { return nil }
    return String(format: "%lld:%llu:%lld.%09ld", Int64(info.st_dev), UInt64(info.st_ino),
                  Int64(info.st_ctimespec.tv_sec), info.st_ctimespec.tv_nsec)
}

func MACHelperNeedsRestart(_ running: Bool, _ runningBuild: String?, _ bundledBuild: String?) -> Bool {
    guard let bundledBuild else { return false }
    return !running || bundledBuild != (runningBuild ?? "")
}

func MACShortcutSlotsByReplacingTheme(_ stored: Any?, _ oldIdentifier: String, _ newIdentifier: String?) -> Data? {
    guard oldIdentifier != newIdentifier, let data = stored as? Data,
          var slots = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
    var changed = false
    for index in slots.indices {
        guard var slot = slots[index] as? [String: Any], slot["themeIdentifier"] as? String == oldIdentifier else { continue }
        slot["themeIdentifier"] = newIdentifier
        slots[index] = slot
        changed = true
    }
    return changed ? try? JSONSerialization.data(withJSONObject: slots) : nil
}

private func shortcutModifiers(_ rawValue: UInt) -> NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: rawValue).intersection([.command, .option, .control, .shift])
}

extension Notification.Name {
    nonisolated static let inputSourceChanged = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
}

func shortcutLayout() -> Data? {
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    return Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
}

func shortcutKey(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags, _ layout: Data) -> String? {
    let state = modifiers.contains(.command) ? UInt32(cmdKey >> 8) : 0
    var deadKeyState: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = layout.withUnsafeBytes { bytes in
        UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode, UInt16(kUCKeyActionDown), state,
                       UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                       &deadKeyState, characters.count, &length, &characters)
    }
    return status == noErr ? String(utf16CodeUnits: characters, count: length) : nil
}

struct KeyboardShortcutData: Codable, Hashable, Equatable {
    var keyCode: UInt16
    var modifierFlagsRaw: UInt
    var keyCharacter: String?

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRaw)
    }

    var displayString: String {
        var parts: [String] = []
        if modifierFlags.contains(.control) { parts.append("⌃") }
        if modifierFlags.contains(.option) { parts.append("⌥") }
        if modifierFlags.contains(.shift) { parts.append("⇧") }
        if modifierFlags.contains(.command) { parts.append("⌘") }

        let keyStr: String
        if let char = keyCharacter, !char.isEmpty {
            keyStr = char == " " ? "Space" : char.uppercased()
        } else {
            keyStr = "?"
        }

        parts.append(keyStr)
        return parts.joined()
    }
}

func MACShortcutIsAllowed(_ modifierFlagsRaw: UInt, _ keyCode: UInt16, _ layout: Data? = shortcutLayout()) -> Bool {
    let modifiers = shortcutModifiers(modifierFlagsRaw)
    guard !modifiers.isDisjoint(with: [.command, .control]),
          modifiers != .command, modifiers != [.command, .shift] else { return false }
    guard let layout, let key = shortcutKey(keyCode, modifiers, layout) else { return true }
    let reserved: Set<String>
    switch modifiers {
    case .control: reserved = ["a", "b", "d", "e", "f", "h", "k", "l", "n", "o", "p", "t", "y", " "]
    case [.option, .command]: reserved = ["h", "m", "w", " ", "l", "d", "p", "s", "n", "t", "v", "y", "f", "c", "i", "`"]
    case [.control, .command]: reserved = [" ", "f", "n", "q", "t", "a", "d"]
    case [.control, .option]: reserved = [" "]
    case [.control, .option, .command]: reserved = ["8", ",", "."]
    case [.control, .shift, .command]: reserved = ["t"]
    case [.option, .shift, .command]: reserved = ["v", "q"]
    default: reserved = []
    }
    return !reserved.contains(key)
}

func MACShortcutsCollide(_ keyCode: UInt16, _ modifierFlagsRaw: UInt,
                         _ otherKeyCode: UInt16, _ otherModifierFlagsRaw: UInt) -> Bool {
    keyCode == otherKeyCode && shortcutModifiers(modifierFlagsRaw) == shortcutModifiers(otherModifierFlagsRaw)
}

struct ThemeCard<Preview: View>: View {
    let name: String
    let isApplied: Bool
    let help: String?
    let action: () -> Void
    let preview: Preview

    @State private var hovering = false

    init(name: String, isApplied: Bool, help: String? = nil, action: @escaping () -> Void, @ViewBuilder preview: () -> Preview) {
        self.name = name
        self.isApplied = isApplied
        self.help = help
        self.action = action
        self.preview = preview()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                Text(name)
                    .font(.system(size: 10.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isApplied ? Color.accentColor.opacity(0.14) : Color.primary.opacity(hovering ? 0.09 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isApplied ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .padding(4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help ?? name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isApplied ? .isSelected : [])
    }
}
