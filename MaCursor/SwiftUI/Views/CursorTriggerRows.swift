import SwiftUI

struct CursorTriggerRows: View {
    @Binding var trigger: CursorTrigger
    var isTaken: (CursorTrigger) -> Bool = { _ in false }
    var window: NSWindow?
    @Environment(\.isEnabled) private var isEnabled
    @State private var recorder: Any?
    @State private var refused = false

    var body: some View {
        LabeledContent("Hold Keys") {
            HStack(spacing: 6) {
                ForEach(CursorTrigger.keys.indices, id: \.self) { index in
                    let flag = CursorTrigger.keys[index].flag
                    Toggle(isOn: Binding(
                        get: { NSEvent.ModifierFlags(rawValue: trigger.holdKeys).contains(flag) },
                        set: { on in
                            var keys = NSEvent.ModifierFlags(rawValue: trigger.holdKeys)
                            if on { keys.insert(flag) } else { keys.remove(flag) }
                            change { $0.holdKeys = keys.rawValue }
                        }
                    )) {
                        Text(verbatim: CursorTrigger.keys[index].glyph)
                            .frame(minWidth: 18)
                    }
                    .toggleStyle(.button)
                }
            }
        }

        LabeledContent("Keyboard Shortcut") {
            keyField
        }

        Picker("Mouse Button", selection: Binding(
            get: { trigger.button.map { min($0, 3) } ?? -1 },
            set: { value in change { $0.button = value < 0 ? nil : value == 3 ? max(trigger.button ?? 3, 3) : value } }
        )) {
            Text("None").tag(-1)
            Text("Left Button").tag(0)
            Text("Right Button").tag(1)
            Text("Middle Button").tag(2)
            Text("Side Button").tag(3)
        }

        if let button = trigger.button, button >= 3 {
            GestureButtonField(button: button) { name in change { $0.button = name } }
        }

        if trigger.button != nil {
            Picker("Device", selection: Binding(get: { trigger.click.device }, set: { device in change { $0.click.device = device } })) {
                Text("Mouse").tag(CursorGestureDevice.mouse)
                Text("Trackpad").tag(CursorGestureDevice.trackpad)
                Text("Both").tag(CursorGestureDevice.both)
            }
            .pickerStyle(.segmented)
        }

        LabeledContent("Result") {
            Text(verbatim: trigger.result)
                .font(.body.weight(trigger.keyName == nil && trigger.button == nil ? .regular : .semibold))
                .foregroundStyle(trigger.keyName == nil && trigger.button == nil ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
        }

        if trigger.blocked || refused {
            Text("Hold ⌃ or ⌘, and pick a shortcut that macOS and most apps do not use.")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        if trigger.button != nil && !CursorTranslator.usable(trigger.click) {
            Text("Hold a key with the left or right button, so normal clicks still work.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private var keyField: some View {
        KeyField(record: "Record Key", press: "Press a key…", key: trigger.keyName, recording: recorder != nil) {
            if recorder == nil { start() } else { stop() }
        } clear: {
            stop()
            change { $0.removeKey() }
        }
        .onChangeCompat(of: isEnabled) { enabled in
            if !enabled { stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)) { _ in stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
        .onDisappear(perform: stop)
    }

    private func change(_ edit: (inout CursorTrigger) -> Void) {
        var next = trigger
        edit(&next)
        refused = trigger.refuses(next)
        guard !refused, !isTaken(next) else { return NSSound.beep() }
        trigger = next
    }

    private func start() {
        refused = false
        recorder = EditorTextShortcutCoordinator.addRecorder(stop: stop) { event in
            switch event.keyCode {
            case 53:
                stop()
            case 51, 117:
                change { $0.removeKey() }
                stop()
            default:
                guard event.specialKey == nil, let next = trigger.recording(event, isTaken: isTaken) else {
                    refused = event.specialKey == nil && trigger.recorded(event).keyCannotWork
                    NSSound.beep()
                    return nil
                }
                refused = false
                trigger = next
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let recorder { EditorTextShortcutCoordinator.removeRecorder(recorder) }
        if recorder != nil { refused = false }
        recorder = nil
    }
}

struct KeyField: View {
    let record: LocalizedStringKey
    let press: LocalizedStringKey
    let key: String?
    let recording: Bool
    let toggle: () -> Void
    let clear: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Text(record).hidden()
                Text(press).hidden()
                if recording {
                    Text(press)
                        .foregroundStyle(.secondary)
                } else if let key {
                    Text(verbatim: key)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                } else {
                    Text(record)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 22)
            .padding(.vertical, 4)
            .frame(minWidth: 130, minHeight: 25, maxHeight: 25)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(recording ? Color.accentColor.opacity(0.15) : Color.quaternaryFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(recording ? Color.accentColor : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if key != nil && !recording {
                Button(action: clear) {
                    Label("Clear Keyboard Shortcut", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear Keyboard Shortcut")
                .padding(.trailing, 5)
            }
        }
    }
}

struct GestureButtonField: View {
    let button: Int
    let name: (Int) -> Void
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(CursorGestureTrigger(button: button).label, systemImage: "computermouse")
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(monitor == nil ? Color.primary.opacity(0.05) : Color.accentColor.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(monitor == nil ? Color.clear : Color.accentColor))
                .contentShape(Rectangle())
                .onHover { $0 ? start() : stop() }
                .onDisappear(perform: stop)

            Text("Point here and click the side button you want.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard event.buttonNumber >= 3 else { return event }
            name(event.buttonNumber)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
