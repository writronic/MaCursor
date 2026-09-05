import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedThemeId: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ScrollViewReader { proxy in
            List(library.cursorThemes, selection: $selectedThemeId) { cursorTheme in
                CursorThemeRowView(
                    cursorTheme: cursorTheme,
                    isSelected: selectedThemeId == cursorTheme.id
                )
                .tag(cursorTheme.id)
            }
            .contextMenu(forSelectionType: String.self) { selectedIds in
                if let themeId = selectedIds.first,
                   let cursorTheme = library.theme(withId: themeId) {
                    Button("Apply") { library.apply(cursorTheme) }
                        .disabled(!cursorTheme.isApplicable)
                    Button("Edit") {
                        openEditorWindow(for: cursorTheme)
                    }
                    Button(favoriteTitle(for: cursorTheme)) {
                        library.toggleFavorite(cursorTheme)
                    }
                    Divider()
                    Button("Duplicate") {
                        if let newId = library.duplicateTheme(cursorTheme) {
                            selectedThemeId = newId
                            withAnimation {
                                proxy.scrollTo(newId, anchor: .center)
                            }
                        }
                    }
                    Button("Show in Finder") {
                        if let url = cursorTheme.fileURL {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { library.remove(cursorTheme) }
                }
            } primaryAction: { selectedIds in
                guard let themeId = selectedIds.first,
                      let cursorTheme = library.theme(withId: themeId) else { return }
                handleDoubleClick(on: cursorTheme)
            }
            .listStyle(.sidebar)
            .background(ListSelectionClearer())
            .sidebarToggleRemoved()
            .toolbar {
                ToolbarItem { Spacer() }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: {
                        let newId = library.addNewTheme()
                        selectedThemeId = newId
                        withAnimation {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }) {
                        Label("Add Theme", systemImage: "plus")
                            .padding(.horizontal, 5)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }

                    Button(action: { library.restoreCursors() }) {
                        Label("Restore", systemImage: "arrow.counterclockwise")
                            .padding(.horizontal, 5)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .help("Restore system cursors")
                }
            }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 400, max: 500)
        } detail: {
            if let themeId = selectedThemeId, let cursorTheme = library.theme(withId: themeId) {
                CursorThemeDetailView(cursorTheme: cursorTheme)
                    .id(cursorTheme.id)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Apply") { library.apply(cursorTheme) }
                                .disabled(cursorTheme.isApplied || !cursorTheme.isApplicable)
                                .modifier(ApplyBlockedHelp(cursorTheme: cursorTheme))
                        }
                        ToolbarItem {
                            Button("Edit") {
                                openEditorWindow(for: cursorTheme)
                            }
                        }
                        ToolbarItem {
                            Button {
                                library.toggleFavorite(cursorTheme)
                            } label: {
                                if library.isFavorite(cursorTheme) {
                                    Label("Remove from Favorites", systemImage: "star.fill")
                                        .foregroundStyle(.yellow)
                                } else {
                                    Label("Add to Favorites", systemImage: "star")
                                }
                            }
                            .help(favoriteTitle(for: cursorTheme))
                        }
                    }
            } else {
                UnavailableContent(
                    title: Text("Select a Cursor Theme"),
                    systemImage: "cursorarrow.and.square.on.square.dashed",
                    description: Text("Choose a cursor theme from the sidebar to view its cursors.")
                )
            }
        }
        .navigationTitle("MaCursor")
        .background(ToolbarConfigurator())
        .background(WindowRoleAccessor(role: .main))
        .onChangeCompat(of: columnVisibility) { newValue in
            if newValue != .all {
                columnVisibility = .all
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            library.handleDrop(providers)
        }
        .sheet(isPresented: Binding(
            get: { library.conversion.phase == .review },
            set: { showing in
                if !showing, library.conversion.phase == .review {
                    library.conversion.cancel()
                }
            }
        )) {
            if let outcome = library.conversion.outcome {
                ThemeConversionReviewView(
                    outcome: outcome,
                    onConfirm: { library.conversion.confirmAddToLibrary(using: library) },
                    onConfirmAndEdit: {
                        if let newId = library.conversion.confirmAndEditReturningId(using: library) {
                            openWindow(value: newId)
                        }
                    },
                    onCancel: { library.conversion.cancel() }
                )
            }
        }
        .alert(
            NSLocalizedString("Conversion Failed", comment: "Conversion failure alert title"),
            isPresented: Binding(
                get: { if case .failed = library.conversion.phase { return true } else { return false } },
                set: { showing in if !showing { library.conversion.cancel() } }
            )
        ) {
            Button(NSLocalizedString("OK", comment: "OK button"), role: .cancel) {
                library.conversion.cancel()
            }
        } message: {
            if case .failed(let reason) = library.conversion.phase {
                Text(reason)
            }
        }
        .onDeleteCommand {
            if let themeId = selectedThemeId, let cursorTheme = library.theme(withId: themeId) {
                library.remove(cursorTheme)
                selectedThemeId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorLibraryIdentifierDidChange)) { note in
            guard let oldId = note.userInfo?["oldId"] as? String,
                  let newId = note.userInfo?["newId"] as? String,
                  selectedThemeId == oldId else { return }
            selectedThemeId = newId
        }
    }

    private func openEditorWindow(for cursorTheme: CursorThemeModel) {
        openWindow(value: cursorTheme.id)
    }

    private func favoriteTitle(for cursorTheme: CursorThemeModel) -> LocalizedStringKey {
        library.isFavorite(cursorTheme) ? "Remove from Favorites" : "Add to Favorites"
    }
}

extension LibraryView {
    func handleDoubleClick(on cursorTheme: CursorThemeModel) {
        library.apply(cursorTheme)
    }
}

private struct ApplyBlockedHelp: ViewModifier {
    @ObservedObject var cursorTheme: CursorThemeModel

    func body(content: Content) -> some View {
        if cursorTheme.isApplicable {
            content
        } else if cursorTheme.cursors.isEmpty {
            content.help("Add at least one cursor to this theme before applying it.")
        } else {
            content.help("Assign at least one cursor to a cursor type before applying this theme.")
        }
    }
}

private struct ListSelectionClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let tableView = findTableView(in: view) {
                tableView.selectionHighlightStyle = .none
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let tableView = findTableView(in: nsView) {
                tableView.selectionHighlightStyle = .none
            }
        }
    }

    private func findTableView(in view: NSView) -> NSTableView? {
        var current: NSView? = view
        while let parent = current?.superview {
            if let tableView = parent as? NSTableView {
                return tableView
            }
            current = parent
        }

        return searchSubviews(of: view.window?.contentView)
    }

    private func searchSubviews(of view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let tableView = view as? NSTableView {
            return tableView
        }
        for subview in view.subviews {
            if let found = searchSubviews(of: subview) {
                return found
            }
        }
        return nil
    }
}

private enum RowSelectionStyle {
    static let strokeWidth: CGFloat = 2
    static let cornerRadius: CGFloat = 8
    static let fillOpacity: Double = 0.08
    static let horizontalInset: CGFloat = 10
}

struct CursorThemeRowView: View {
    @ObservedObject var cursorTheme: CursorThemeModel
    var isSelected: Bool = false

    @State private var preferenceRevision = 0

    private static let arrowIdentifiers = [
        "com.apple.coregraphics.Arrow",
        "com.apple.coregraphics.ArrowS",
    ]

    private var filteredCursors: [CursorModel] {
        _ = preferenceRevision
        if MACPreferences.hideTahoeCursors {
            return cursorTheme.cursors.filter {
                !MACConstants.hiddenCursorAliases.contains($0.identifier)
            }
        }
        return cursorTheme.cursors
    }

    private var heroCursor: CursorModel? {
        let cursors = filteredCursors
        for arrowId in Self.arrowIdentifiers {
            if let arrow = cursors.first(where: { $0.identifier == arrowId }) {
                return arrow
            }
        }
        return cursors.first
    }

    private static let secondaryIdentifiers = [
        "com.apple.coregraphics.IBeam",
        "com.apple.coregraphics.Copy",
        "com.apple.coregraphics.Move",
    ]

    private var secondaryCursors: [CursorModel] {
        let heroId = heroCursor?.id
        let candidates = filteredCursors.filter { $0.id != heroId }
        var result: [CursorModel] = []
        for id in Self.secondaryIdentifiers {
            if let match = candidates.first(where: { $0.identifier == id }) {
                result.append(match)
            }
        }
        for cursor in candidates where !result.contains(where: { $0.id == cursor.id }) {
            if result.count >= 3 { break }
            result.append(cursor)
        }
        return Array(result.prefix(3))
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: cursorTheme.isApplied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(cursorTheme.isApplied ? .green : .secondary.opacity(0.3))
                .font(.system(size: 14))

            if let hero = heroCursor {
                CursorThumbnailView(cursor: hero, size: 40)
            }

            HStack(spacing: 6) {
                Text(cursorTheme.name)
                    .font(.headline)
                    .lineLimit(1)

                if cursorTheme.isHiDPI {
                    Text("HD")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            Spacer()

            if !secondaryCursors.isEmpty {
                HStack(spacing: 6) {
                    ForEach(secondaryCursors) { cursor in
                        CursorThumbnailView(cursor: cursor, size: 28)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                )
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, RowSelectionStyle.horizontalInset)
        .background(
            RoundedRectangle(cornerRadius: RowSelectionStyle.cornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(RowSelectionStyle.fillOpacity) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RowSelectionStyle.cornerRadius)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: RowSelectionStyle.strokeWidth)
        )
        .onReceive(NotificationCenter.default.publisher(for: .hideTahoeCursorsChanged)) { _ in
            preferenceRevision += 1
        }
    }
}

struct CursorThemeDetailView: View {
    @ObservedObject var cursorTheme: CursorThemeModel

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 16)
    ]

    @State private var preferenceRevision = 0

    private var visibleCursors: [CursorModel] {
        _ = preferenceRevision
        if MACPreferences.hideTahoeCursors {
            return cursorTheme.cursors.filter {
                !MACConstants.hiddenCursorAliases.contains($0.identifier)
            }
        }
        return cursorTheme.cursors
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cursorTheme.name)
                        .font(.title2.bold())
                    Text("by \(cursorTheme.creator) • v\(cursorTheme.version, specifier: "%.1f")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if cursorTheme.isApplied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }

                Text("\(visibleCursors.count) cursors")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(visibleCursors) { cursor in
                        VStack(spacing: 6) {
                            CursorPreviewView(cursor: cursor, showHotSpot: false, showCheckerboard: false)
                                .frame(width: 64, height: 64)

                            Text(cursor.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.background)
                                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
                .padding()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hideTahoeCursorsChanged)) { _ in
            preferenceRevision += 1
        }
    }
}
