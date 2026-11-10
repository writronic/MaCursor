import AppKit
import SwiftUI

enum CursorScreenshotHistoryAction {
    case restore, edit, pin
}

struct CursorScreenshotHistoryItem: Identifiable, Sendable {
    let entry: CursorScreenshotHistoryEntry
    let thumbnail: CGImage?

    var id: UUID { entry.id }
}

@MainActor
final class CursorScreenshotHistoryModel: ObservableObject {
    @Published private(set) var items: [CursorScreenshotHistoryItem] = []
    @Published private(set) var disabled = false
    @Published var selection: UUID?
    @Published var asksToClear = false

    let store: CursorScreenshotHistoryStore
    var acting: (CursorScreenshotHistoryAction, CursorScreenshotHistoryEntry) -> Void = { _, _ in }

    init(store: CursorScreenshotHistoryStore) {
        self.store = store
    }

    var selected: CursorScreenshotHistoryEntry? {
        items.first { $0.id == selection }?.entry
    }

    func reload() {
        let keep = CursorScreenshotConfig.load().keepHistory
        disabled = keep == .disabled
        let store = store
        let side = CursorScreenshotHistory.thumbnailSide
        Task {
            await store.prune(keeping: keep, now: Date())
            let entries = await store.entries()
            items = await Task.detached(priority: .userInitiated) {
                entries.map { entry in
                    CursorScreenshotHistoryItem(entry: entry, thumbnail: CursorScreenshotImageSource.image(from: CGImageSourceCreateWithURL(store.thumbnailURL(entry) as CFURL, nil), side: side))
                }
            }.value
            if selected == nil { selection = nil }
        }
    }

    func run(_ action: CursorScreenshotHistoryAction, on entry: CursorScreenshotHistoryEntry?) {
        guard let entry else { return NSSound.beep() }
        acting(action, entry)
    }

    func delete(_ id: UUID) {
        Task {
            await store.remove(id)
            reload()
        }
    }

    func clear() {
        Task {
            await store.removeAll()
            reload()
        }
    }
}

struct CursorScreenshotHistoryView: View {
    @ObservedObject var model: CursorScreenshotHistoryModel

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Button(MenuBarL("Restore")) { model.run(.restore, on: model.selected) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selected == nil)
                Spacer()
                Button(MenuBarL("Clear History...")) { model.asksToClear = true }
                    .disabled(model.items.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 480, minHeight: 360)
        .alert(MenuBarL("Are you sure you want to delete all files from history?"), isPresented: $model.asksToClear) {
            Button(MenuBarL("Delete"), role: .destructive) { model.clear() }
            Button(MenuBarL("Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder private var content: some View {
        if model.disabled {
            Text(MenuBarL("Capture History is disabled."))
                .foregroundStyle(.secondary)
        } else if model.items.isEmpty {
            Text(MenuBarL("No files to restore..."))
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(model.items) { cell($0) }
                }
                .padding(12)
            }
        }
    }

    private func cell(_ item: CursorScreenshotHistoryItem) -> some View {
        let selected = model.selection == item.id
        return VStack(spacing: 6) {
            Group {
                if let thumbnail = item.thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(item.entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.accentColor.opacity(0.15) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.selection = item.id
            model.run(.edit, on: item.entry)
        }
        .onTapGesture { model.selection = item.id }
        .contextMenu {
            Button(MenuBarL("Restore")) { model.run(.restore, on: item.entry) }
            Button(MenuBarL("Edit")) { model.run(.edit, on: item.entry) }
            Button(MenuBarL("Pin to the screen")) { model.run(.pin, on: item.entry) }
            Divider()
            Button(MenuBarL("Delete")) { model.delete(item.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selection = item.id }
    }
}
