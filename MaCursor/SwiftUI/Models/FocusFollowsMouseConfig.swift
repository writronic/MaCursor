import Foundation
import AppKit

enum FocusFollowsMouseToggleAction: Equatable {
    case enable
    case requestAccess
    case disable
    case ignore
}

struct FocusFollowsMouseConfig: Codable {
    var enabled: Bool
    var delayMs: Int
    var disableModifier: String
    var ignoreSpaceChange: Bool
    var ignoreBundleIdentifiers: [String]
    var stayFocusedBundleIdentifiers: [String]

    static let minDelayMs = 0
    static let maxDelayMs = 1000
    static let defaultDelayMs = 100
    static let defaultStayFocused = ["com.apple.SecurityAgent"]

    init(enabled: Bool = false,
         delayMs: Int = FocusFollowsMouseConfig.defaultDelayMs,
         disableModifier: String = "control",
         ignoreSpaceChange: Bool = false,
         ignoreBundleIdentifiers: [String] = [],
         stayFocusedBundleIdentifiers: [String] = FocusFollowsMouseConfig.defaultStayFocused) {
        self.enabled = enabled
        self.delayMs = delayMs
        self.disableModifier = disableModifier
        self.ignoreSpaceChange = ignoreSpaceChange
        self.ignoreBundleIdentifiers = ignoreBundleIdentifiers
        self.stayFocusedBundleIdentifiers = stayFocusedBundleIdentifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        delayMs = try container.decodeIfPresent(Int.self, forKey: .delayMs)
            ?? FocusFollowsMouseConfig.defaultDelayMs
        disableModifier = try container.decodeIfPresent(String.self, forKey: .disableModifier) ?? "control"
        ignoreSpaceChange = try container.decodeIfPresent(Bool.self, forKey: .ignoreSpaceChange) ?? false
        ignoreBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .ignoreBundleIdentifiers) ?? []
        stayFocusedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .stayFocusedBundleIdentifiers)
            ?? FocusFollowsMouseConfig.defaultStayFocused
    }

    mutating func normalize() {
        delayMs = min(max(delayMs, FocusFollowsMouseConfig.minDelayMs), FocusFollowsMouseConfig.maxDelayMs)
        ignoreBundleIdentifiers = ignoreBundleIdentifiers.filter { !$0.isEmpty }
        stayFocusedBundleIdentifiers = stayFocusedBundleIdentifiers.filter { !$0.isEmpty }
    }

    static func isOn(enabled: Bool, trusted: Bool) -> Bool {
        enabled && trusted
    }

    static func toggleAction(enabled: Bool,
                             helperInstalled: Bool,
                             trusted: Bool) -> FocusFollowsMouseToggleAction {
        guard helperInstalled else { return .ignore }
        guard !isOn(enabled: enabled, trusted: trusted) else { return .disable }
        return trusted ? .enable : .requestAccess
    }

    static func setEnabled(_ enabled: Bool) {
        var config = FocusFollowsMouseConfig.load()
        guard config.enabled != enabled else { return }
        config.enabled = enabled
        config.save()
    }

    static var accessibilityTrusted: Bool {
        CFPreferencesAppSynchronize(MACPreferences.domain)
        return (MACPreferences.value(forKey: MACPreferences.ffmAccessibilityTrustedKey) as? NSNumber)?.boolValue ?? false
    }

    static func load() -> FocusFollowsMouseConfig {
        guard let data = MACPreferences.value(forKey: MACPreferences.focusFollowsMouseKey) as? Data,
              var decoded = try? JSONDecoder().decode(FocusFollowsMouseConfig.self, from: data) else {
            var fresh = FocusFollowsMouseConfig()
            fresh.normalize()
            return fresh
        }
        decoded.normalize()
        return decoded
    }

    func save() {
        var normalized = self
        normalized.normalize()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        MACPreferences.set(data, forKey: MACPreferences.focusFollowsMouseKey)
        NotificationCenter.default.post(name: .macFocusFollowsMouseConfigDidChange, object: nil)
        FocusFollowsMouseConfig.notifyHelper()
    }

    static func notifyHelper() {
        DistributedNotificationCenter.default().postNotificationName(
            .MACFocusFollowsMouseDidChange,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func requestAccessibility() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension Notification.Name {
    static let macFocusFollowsMouseConfigDidChange = Notification.Name("MACFocusFollowsMouseConfigDidChangeLocally")
}
