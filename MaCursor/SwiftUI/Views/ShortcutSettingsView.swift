import SwiftUI

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
    @Environment(LibraryViewModel.self) private var library
    
    @State private var helperManager = HelperToolManager.shared
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
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    if slots.isEmpty {
                        ContentUnavailableView(
                            "No Shortcuts",
                            systemImage: "star.slash",
                            description: Text("Press + to add a favorite cursor shortcut.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(slots) { slot in
                            SlotCardView(
                                slot: binding(for: slot),
                                themes: library.cursorThemes,
                                isSelected: selectedSlotId == slot.id
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedSlotId = (selectedSlotId == slot.id) ? nil : slot.id
                                }
                            }
                        }
                    }
                }
                .padding(16)
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
        }
        .navigationTitle("Shortcut")
        .onAppear {
            loadSlots()
        }
        .onChange(of: slots) { _, _ in
        }
    }
    
    
    private func binding(for slot: FavoriteCursorSlot) -> Binding<FavoriteCursorSlot> {
        guard let index = slots.firstIndex(where: { $0.id == slot.id }) else {
            return .constant(slot)
        }
        return Binding(
            get: { slots[index] },
            set: { newValue in
                slots[index] = newValue
                saveSlots()
            }
        )
    }
    
    
    private func loadSlots() {
        guard let data = MCPreferences.value(forKey: MCPreferences.favoriteCursorsKey) as? Data,
              let decoded = try? JSONDecoder().decode([FavoriteCursorSlot].self, from: data) else {
            slots = [FavoriteCursorSlot(), FavoriteCursorSlot()]
            return
        }
        slots = decoded
    }
    
    private func saveSlots() {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        MCPreferences.set(data, forKey: MCPreferences.favoriteCursorsKey)
        ShortcutManager.shared.notifyConfigChanged()
    }
}

@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()
    private init() {}
    
    func notifyConfigChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            .init("MCShortcutsDidChange"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

private struct SlotCardView: View {
    @Binding var slot: FavoriteCursorSlot
    let themes: [CursorThemeModel]
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cursor Theme")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Picker("", selection: $slot.themeIdentifier) {
                    Text("None")
                        .tag(nil as String?)
                    
                    ForEach(themes) { theme in
                        Text(theme.name)
                            .tag(theme.id as String?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 32)
            
            VStack(alignment: .center, spacing: 4) {
                Text("Shortcut")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                KeyRecorderView(shortcut: $slot.shortcut)
            }
            .frame(width: 145)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.5),
                            lineWidth: 1
                        )
                }
        }
        .contentShape(Rectangle())
    }
}

private struct KeyRecorderView: View {
    @Binding var shortcut: KeyboardShortcutData?
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
            HStack(spacing: 4) {
                if isRecording {
                    Text("Press shortcut…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let shortcut {
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
            .frame(width: 130, height: 25)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .quaternarySystemFill))
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
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
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
            
            let hasModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option) || flags.contains(.shift)
            guard hasModifier else {
                return nil
            }
            
            if event.specialKey != nil {
                return nil
            }
            
            shortcut = KeyboardShortcutData(
                keyCode: event.keyCode,
                modifierFlagsRaw: flags.rawValue,
                keyCharacter: event.charactersIgnoringModifiers
            )
            stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }
}
