import AppKit
import Carbon
import Foundation

enum HelperEventPolicy {
    struct Shortcut: Equatable, Sendable {
        let id: UInt32
        let themeIdentifier: String
        let keyCode: UInt32
        let modifiers: UInt32
    }

    struct DisplayDebounce {
        private(set) var deadline: DispatchTime?

        mutating func replaceDeadline(at now: DispatchTime) -> DispatchTime {
            let next = now + .milliseconds(500)
            deadline = next
            return next
        }

        mutating func consume(_ firedDeadline: DispatchTime) -> Bool {
            guard deadline == firedDeadline else { return false }
            deadline = nil
            return true
        }
    }

    static func route(arguments: [String], probe: () -> Int32, screenProbe: () -> Int32 = { EXIT_FAILURE }, reader: () -> Int32 = { EXIT_FAILURE },
                      runtime: () -> Void) -> Int32 {
        if arguments.dropFirst().first == MACFFMTrustProbeArgument {
            return probe()
        }
        if arguments.dropFirst().first == MACTranslatorScreenProbeArgument {
            return screenProbe()
        }
        if arguments.dropFirst().first == MACTranslatorReaderArgument {
            return reader()
        }
        runtime()
        return EXIT_SUCCESS
    }

    static func shortcuts(from value: Any?) -> [Shortcut] {
        guard let data = value as? Data,
              let slots = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return slots.enumerated().compactMap { index, value in
            guard let slot = value as? [String: Any],
                  let identifier = slot["themeIdentifier"] as? String,
                  let shortcut = slot["shortcut"] as? [String: Any],
                  let keyCode = shortcut["keyCode"] as? NSNumber,
                  let modifiers = shortcut["modifierFlagsRaw"] as? NSNumber,
                  MACShortcutIsAllowed(modifiers.uintValue, keyCode.uint16Value) else { return nil }
            return Shortcut(id: UInt32(index + 1), themeIdentifier: identifier,
                            keyCode: keyCode.uint32Value, modifiers: carbonModifiers(modifiers.uintValue))
        }
    }

    static func carbonModifiers(_ rawValue: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: rawValue)
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func handleActivation(
        bundleID: String?,
        consumeRecentRaise: (String?) -> Bool,
        noteForeground: (String?) -> Void,
        cancelDwell: () -> Void,
        scheduleReassert: (String?, TimeInterval) -> Void
    ) {
        if MACMenuBarIsHelperBundleIdentifier(bundleID) {
            cancelDwell()
            return
        }
        noteForeground(bundleID)
        if consumeRecentRaise(bundleID) { return }
        cancelDwell()
        scheduleReassert(bundleID, 0.1)
    }

    static func foregroundBundleID(cached: String?, live: String?) -> String? {
        if let cached, !cached.isEmpty { return cached }
        return MACMenuBarIsHelperBundleIdentifier(live) ? nil : live
    }
}

enum HelperFinderHandoff {
    private static let queue = DispatchQueue(label: "HelperFinderHandoff")

    static func receive(_ request: RightClickMenuHandoff.Request, frontmost: String?, settings: RightClickMenuSettings,
                        folder: @escaping @Sendable () throws -> String, makeFile: @escaping @Sendable (String) throws -> Bool,
                        copy: @escaping @MainActor (URL) -> Void, open: @escaping @MainActor (URL, String) -> Void,
                        fail: @escaping @MainActor (Int) -> Void) {
        guard frontmost == "com.apple.finder", settings.isActive else { return }
        switch request {
        case .copyPath:
            guard settings.copyPathEnabled else { return }
            inFolder(folder, fail: fail, then: copy)
        case .openCommonApp(let index):
            guard let (_, row) = RightClickMenuActions.applicationRow(tag: settings.openWithApps.count + index, shown: settings, latest: settings) else { return }
            inFolder(folder, fail: fail) { open($0, row.bundleIdentifier) }
        case .newFile(let type):
            guard settings[keyPath: type.keyPath].enabled else { return }
            let baseName = type.itemTitle, ext = type.fileExtension
            queue.async {
                do {
                    _ = try RightClickMenuActions.createFile(in: URL(fileURLWithPath: "/", isDirectory: true), baseName: baseName, ext: ext) {
                        guard try makeFile($0.lastPathComponent) else { throw CocoaError(.fileWriteFileExists) }
                    }
                } catch {
                    report(error, to: fail)
                }
            }
        }
    }

    private static func inFolder(_ folder: @escaping @Sendable () throws -> String, fail: @escaping @MainActor (Int) -> Void,
                                 then act: @escaping @MainActor (URL) -> Void) {
        queue.async {
            do {
                guard let url = RightClickMenuActions.usableFolder(URL(string: try folder())) else { throw CocoaError(.fileNoSuchFile) }
                DispatchQueue.main.async { act(url) }
            } catch {
                report(error, to: fail)
            }
        }
    }

    private static func report(_ error: Error, to fail: @escaping @MainActor (Int) -> Void) {
        let code = (error as NSError).code
        DispatchQueue.main.async { fail(code) }
    }
}
