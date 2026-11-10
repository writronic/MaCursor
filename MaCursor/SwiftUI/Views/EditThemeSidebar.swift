import AppKit
import Foundation
import SwiftUI

enum EditThemeSidebarLayout: String {
    case list
    case grid
}

enum EditThemeSidebarModel {
    static let emptyRowPrefix = "empty:"

    enum Row: Identifiable {
        case cursor(CursorModel)
        case empty(identifier: String, displayName: String)

        var id: String {
            switch self {
            case .cursor(let model): return model.id
            case .empty(let identifier, _): return EditThemeSidebarModel.emptyRowPrefix + identifier
            }
        }

        var displayName: String {
            switch self {
            case .cursor(let model): return model.name
            case .empty(_, let displayName): return displayName
            }
        }

        var cursorIdentifier: String {
            switch self {
            case .cursor(let model): return model.identifier
            case .empty(let identifier, _): return identifier
            }
        }

        func matches(query: String) -> Bool {
            displayName.localizedCaseInsensitiveContains(query)
                || cursorIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    static func rows(cursors: [CursorModel],
                     availableTypes: [(identifier: String, name: String)],
                     showAll: Bool,
                     searchText: String = "") -> [Row] {
        let allRows: [Row]
        let present = cursors.map(Row.cursor)
        if showAll {
            let used = Set(cursors.map(\.identifier))
            let empties = availableTypes
                .filter { !used.contains($0.identifier) }
                .map { Row.empty(identifier: $0.identifier, displayName: $0.name) }
            allRows = (present + empties).sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } else {
            allRows = present
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allRows }
        return allRows.filter { $0.matches(query: query) }
    }
}

@MainActor
final class TextEditingFocusCoordinator {
    static let shared = TextEditingFocusCoordinator()

    private var eventMonitor: Any?
    private(set) var interactionCount = 0

    var isMonitoring: Bool { eventMonitor != nil }

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: NSEvent.EventTypeMask([.leftMouseDown, .keyDown])
        ) { [weak self] (event: NSEvent) -> NSEvent? in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.noteUserInteraction()
                if event.type == .leftMouseDown {
                    self.handleMouseDown(at: event.locationInWindow, in: event.window)
                }
            }
            return event
        }
    }

    func stop() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func noteUserInteraction() {
        interactionCount += 1
    }

    func handleMouseDown(at locationInWindow: NSPoint, in window: NSWindow?) {
        guard let window,
              let fieldEditor = window.firstResponder as? NSTextView,
              fieldEditor.isFieldEditor else { return }
        let target: NSView = (fieldEditor.delegate as? NSControl) ?? fieldEditor
        let local = target.convert(locationInWindow, from: nil)
        if !target.bounds.contains(local) {
            window.makeFirstResponder(nil)
        }
    }
}

@MainActor
final class EditorTextShortcutCoordinator {
    static let shared = EditorTextShortcutCoordinator()

    private var eventMonitor: Any?
    private static var recorders: [AnyObject] = []
    private static var stopOpenRecorder: (() -> Void)?
    static var postRecording: (Notification.Name) -> Void = { name in
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    var isMonitoring: Bool { eventMonitor != nil }

    static func addRecorder(stop: (() -> Void)? = nil, _ handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
        if let monitor {
            recorders.append(monitor as AnyObject)
            if recorders.count == 1 { postRecording(.MACShortcutRecordingDidStart) }
        }
        let older = stopOpenRecorder
        stopOpenRecorder = stop
        older?()
        return monitor
    }

    static func removeRecorder(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
        let wasRecording = !recorders.isEmpty
        recorders.removeAll { $0 === monitor as AnyObject }
        if recorders.isEmpty { stopOpenRecorder = nil }
        if wasRecording, recorders.isEmpty { postRecording(.MACShortcutRecordingDidStop) }
    }

    static func editingSelector(
        forCharacters characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> Selector? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.shift),
              !flags.contains(.option),
              !flags.contains(.control),
              let characters else { return nil }

        switch characters.lowercased() {
        case "x": return #selector(NSText.cut(_:))
        case "c": return #selector(NSText.copy(_:))
        case "v": return #selector(NSText.paste(_:))
        case "a": return #selector(NSText.selectAll(_:))
        default: return nil
        }
    }

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: NSEvent.EventTypeMask([.keyDown])
        ) { [weak self] (event: NSEvent) -> NSEvent? in
            var handled = false
            MainActor.assumeIsolated {
                handled = self?.handle(event, in: event.window) ?? false
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    @discardableResult
    func performEditingSelector(_ selector: Selector, in window: NSWindow) -> Bool {
        guard let fieldEditor = window.firstResponder as? NSTextView,
              fieldEditor.isFieldEditor else { return false }
        return NSApp.sendAction(selector, to: fieldEditor, from: nil)
    }

    func handle(_ event: NSEvent, in window: NSWindow?) -> Bool {
        guard Self.recorders.isEmpty,
              let window,
              let selector = Self.editingSelector(
                  forCharacters: event.characters(byApplyingModifiers: .command),
                  modifiers: event.modifierFlags)
        else { return false }
        return performEditingSelector(selector, in: window)
    }
}

struct SearchFieldView: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    var focusToken: Int? = nil
    var onDismiss: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusingSearchField()
        field.focusesWhenShown = focusToken != nil
        context.coordinator.focusToken = focusToken
        context.coordinator.onDismiss = onDismiss
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchFieldDidSend(_:))
        field.sendsSearchStringImmediately = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onDismiss = onDismiss
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != prompt {
            nsView.placeholderString = prompt
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            if focusToken != nil, nsView.currentEditor() == nil {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class FocusingSearchField: NSSearchField {
        var focusesWhenShown = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard focusesWhenShown, window != nil else { return }
            focusesWhenShown = false
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var onDismiss: (() -> Void)?
        var focusToken: Int?

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            push(field.stringValue)
        }

        @objc func searchFieldDidSend(_ sender: NSSearchField) {
            push(sender.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            if control.stringValue.isEmpty {
                guard let onDismiss else { return false }
                onDismiss()
                return true
            }
            control.stringValue = ""
            push("")
            return true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField, field.stringValue.isEmpty else { return }
            onDismiss?()
        }

        private func push(_ value: String) {
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }
    }
}
