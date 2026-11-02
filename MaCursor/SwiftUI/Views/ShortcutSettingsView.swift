import SwiftUI

struct FavoriteCursorSlot: Identifiable, Codable, Hashable {
    let id: UUID
    var themeIdentifier: String?
    var shortcut: KeyboardShortcutData?

    init(id: UUID = UUID(), themeIdentifier: String? = nil, shortcut: KeyboardShortcutData? = nil) {
        self.id = id
        self.themeIdentifier = themeIdentifier
        self.shortcut = shortcut
    }
}

struct ShortcutSettingsView: View {
    @EnvironmentObject private var library: LibraryViewModel

    @ObservedObject private var helperManager = HelperToolManager.shared
    @State private var slots: [FavoriteCursorSlot] = []
    @State private var selectedSlotId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if !helperManager.isInstalled {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.title3)

                    Text("Shortcuts require the Helper Tool to be installed. You can install it from General → Helper Tool.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.yellow.opacity(0.25), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if slots.isEmpty {
                        UnavailableContent(
                            title: Text("No Shortcuts"),
                            systemImage: "star.slash",
                            description: Text("Press + to add a favorite cursor shortcut.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(slots) { slot in
                            SlotCardView(
                                slot: binding(for: slot),
                                themes: library.cursorThemes.map { ThemeChoice(id: $0.id, name: $0.name) },
                                isSelected: selectedSlotId == slot.id,
                                isTaken: { isShortcut($0, takenByOtherThan: slot.id) },
                                isShadowed: isShortcutShadowed(slot)
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedSlotId = (selectedSlotId == slot.id) ? nil : slot.id
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .disabled(!helperManager.isInstalled)
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let newSlot = FavoriteCursorSlot()
                        slots.append(newSlot)
                        saveSlots()
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Add shortcut slot")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if let selectedId = selectedSlotId {
                            slots.removeAll { $0.id == selectedId }
                            selectedSlotId = nil
                            saveSlots()
                        }
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(selectedSlotId == nil)
                .help("Remove selected slot")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .disabled(!helperManager.isInstalled)
        }
        .navigationTitle("Shortcut")
        .onAppear {
            loadSlots()
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: .init("MACShortcutsDidChange"))) { _ in
            loadSlots()
        }
    }


    private func binding(for slot: FavoriteCursorSlot) -> Binding<FavoriteCursorSlot> {
        let id = slot.id
        return Binding(
            get: { slots.first(where: { $0.id == id }) ?? FavoriteCursorSlot(id: id) },
            set: { newValue in
                guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
                slots[index] = newValue
                saveSlots()
            }
        )
    }

    private func isShortcut(_ candidate: KeyboardShortcutData, takenByOtherThan id: UUID) -> Bool {
        slots.filter { $0.id != id }.compactMap(\.shortcut).contains {
            MACShortcutsCollide($0.keyCode, $0.modifierFlagsRaw, candidate.keyCode, candidate.modifierFlagsRaw)
        }
    }

    private func isShortcutShadowed(_ slot: FavoriteCursorSlot) -> Bool {
        guard let shortcut = slot.shortcut else { return false }
        return slots.prefix(while: { $0.id != slot.id }).contains { earlier in
            guard earlier.themeIdentifier != nil, let held = earlier.shortcut else { return false }
            return MACShortcutsCollide(held.keyCode, held.modifierFlagsRaw, shortcut.keyCode, shortcut.modifierFlagsRaw)
        }
    }


    private func loadSlots() {
        guard let data = MACPreferences.value(forKey: MACPreferences.favoriteCursorsKey) as? Data,
              let decoded = try? JSONDecoder().decode([FavoriteCursorSlot].self, from: data) else {
            slots = [FavoriteCursorSlot(), FavoriteCursorSlot()]
            return
        }
        slots = decoded
    }

    private func saveSlots() {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        MACPreferences.set(data, forKey: MACPreferences.favoriteCursorsKey)
        ShortcutManager.shared.notifyConfigChanged()
    }
}

@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()
    private init() {}

    func notifyConfigChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            .init("MACShortcutsDidChange"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

private struct ThemeChoice: Identifiable, Equatable {
    let id: String
    let name: String
}

private struct SlotCardView: View {
    @Binding var slot: FavoriteCursorSlot
    let themes: [ThemeChoice]
    let isSelected: Bool
    let isTaken: (KeyboardShortcutData) -> Bool
    let isShadowed: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cursor Theme")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Picker("", selection: themeSelection) {
                    Text("None")
                        .tag(nil as String?)

                    ForEach(themes) { theme in
                        Text(theme.name)
                            .tag(theme.id as String?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 32)

            VStack(alignment: .center, spacing: 4) {
                Text("Shortcut")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                KeyRecorderView(shortcut: $slot.shortcut, isTaken: isTaken, isShadowed: isShadowed)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .shortcutCard(selected: isSelected)
    }

    private var themeSelection: Binding<String?> {
        Binding(
            get: { themes.contains { $0.id == slot.themeIdentifier } ? slot.themeIdentifier : nil },
            set: { slot.themeIdentifier = $0 }
        )
    }
}

private extension View {
    func shortcutCard(selected: Bool) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                selected ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.5),
                                lineWidth: 1
                            )
                    }
            }
            .contentShape(Rectangle())
    }
}

struct KeyRecorderView: View {
    @Binding var shortcut: KeyboardShortcutData?
    let isTaken: (KeyboardShortcutData) -> Bool
    let isShadowed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isRecording: Bool = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            ZStack {
                Text("Record Shortcut").font(.callout).hidden()
                Text("Press shortcut…").font(.callout).hidden()
                if isRecording {
                    Text("Press shortcut…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let shortcut, !isShadowed, MACShortcutIsAllowed(shortcut.modifierFlagsRaw, shortcut.keyCode) {
                    Text(shortcut.displayString)
                        .font(.system(.callout, design: .rounded, weight: .medium))
                } else {
                    Text("Record Shortcut")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 130, minHeight: 25, maxHeight: 25)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.quaternaryFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isRecording ? Color.accentColor : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onChangeCompat(of: isEnabled) { enabled in
            if !enabled {
                stopRecording()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification,
                                                        object: SettingsWindowController.shared.window)) { _ in
            stopRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true

        eventMonitor = EditorTextShortcutCoordinator.addRecorder { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            if event.keyCode == 51 || event.keyCode == 117 {
                shortcut = nil
                stopRecording()
                return nil
            }

            let candidate = KeyboardShortcutData(
                keyCode: event.keyCode,
                modifierFlagsRaw: flags.rawValue,
                keyCharacter: event.charactersIgnoringModifiers
            )
            guard event.specialKey == nil,
                  MACShortcutIsAllowed(candidate.modifierFlagsRaw, candidate.keyCode),
                  !isTaken(candidate) else {
                NSSound.beep()
                return nil
            }

            shortcut = candidate
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            EditorTextShortcutCoordinator.removeRecorder(eventMonitor)
        }
        eventMonitor = nil
    }
}
