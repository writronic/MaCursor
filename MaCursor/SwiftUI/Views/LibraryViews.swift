import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedThemeId: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isSearchOpen = false
    @State private var searchText = ""
    @State private var searchFocusToken = 0
    @State private var themeCount = 0

    private var visibleThemes: [CursorThemeModel] {
        Self.themes(library.cursorThemes, matching: searchText)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ScrollViewReader { proxy in
            List(visibleThemes, selection: $selectedThemeId) { cursorTheme in
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
                    Button("Delete", role: .destructive) {
                        do {
                            try library.remove(cursorTheme)
                        } catch {
                            NSApp.presentError(error)
                        }
                    }
                }
            } primaryAction: { selectedIds in
                guard let themeId = selectedIds.first,
                      let cursorTheme = library.theme(withId: themeId) else { return }
                handleDoubleClick(on: cursorTheme)
            }
            .listStyle(.sidebar)
            .overlay(ListMenuOwner())
            .overlay {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty && visibleThemes.isEmpty {
                    UnavailableContent.search(text: query)
                }
            }
            .onChangeCompat(of: isSearchOpen) { open in
                if !open, let themeId = selectedThemeId {
                    proxy.scrollTo(themeId, anchor: .center)
                }
            }
            .sidebarToggleRemoved()
            .toolbar {
                ToolbarItem { Spacer() }
                ToolbarItemGroup(placement: .primaryAction) {
                    if isSearchOpen {
                        SearchFieldView(text: $searchText, prompt: String(localized: "Search"),
                                        focusToken: searchFocusToken, onDismiss: closeSearch)
                            .frame(width: 240)
                    } else {
                        Button(action: openSearch) {
                            Label("Search Themes", systemImage: "magnifyingglass")
                                .padding(.horizontal, 5)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }
                        .help("Search Themes")

                        Button(action: {
                            guard let newId = library.addNewTheme() else { return }
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
        .focusedSceneValue(\.librarySearch, openSearch)
        .onAppear { themeCount = library.cursorThemes.count }
        .onChangeCompat(of: library.cursorThemes.count) { count in
            if count > themeCount {
                closeSearch()
            }
            themeCount = count
        }
        .onChangeCompat(of: visibleThemes.map(\.id)) { visibleIds in
            if let themeId = selectedThemeId, !visibleIds.contains(themeId),
               library.theme(withId: themeId) != nil {
                selectedThemeId = nil
            }
        }
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
                do {
                    try library.remove(cursorTheme)
                    selectedThemeId = nil
                } catch {
                    NSApp.presentError(error)
                }
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

    private func openSearch() {
        isSearchOpen = true
        searchFocusToken += 1
    }

    private func closeSearch() {
        guard isSearchOpen else { return }
        isSearchOpen = false
        searchText = ""
    }

    private func favoriteTitle(for cursorTheme: CursorThemeModel) -> LocalizedStringKey {
        library.isFavorite(cursorTheme) ? "Remove from Favorites" : "Add to Favorites"
    }
}

extension LibraryView {
    func handleDoubleClick(on cursorTheme: CursorThemeModel) {
        library.apply(cursorTheme)
    }

    static func themes(_ themes: [CursorThemeModel], matching query: String) -> [CursorThemeModel] {
        let query = searchFolded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return themes }
        return themes.filter {
            searchFolded($0.name).contains(query) || searchFolded($0.creator).contains(query)
        }
    }

    private static func searchFolded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }
}

struct LibrarySearchKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var librarySearch: LibrarySearchKey.Value? {
        get { self[LibrarySearchKey.self] }
        set { self[LibrarySearchKey.self] = newValue }
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

struct ListMenuOwner: NSViewRepresentable {
    func makeNSView(context: Context) -> Owner {
        Owner()
    }

    func updateNSView(_ view: Owner, context: Context) {
        view.attach()
    }

    final class Owner: NSView {
        private weak var table: NSTableView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        func attach() {
            guard window != nil else { return }
            adopt()
            DispatchQueue.main.async { [weak self] in self?.adopt() }
        }

        private func adopt() {
            var ancestor = superview
            while let view = ancestor {
                let found = Self.tables(in: view)
                if found.count == 1 {
                    table = found[0]
                    if found[0].selectionHighlightStyle != .none {
                        found[0].selectionHighlightStyle = .none
                    }
                    return
                }
                if found.count > 1 { return }
                ancestor = view.superview
            }
        }

        private static func tables(in view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables(in: $0) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let table, let superview, let event = NSApp.currentEvent, event.window === window,
                  event.type == .rightMouseDown || event.type == .leftMouseDown && event.modifierFlags.contains(.control),
                  superview.convert(event.locationInWindow, from: nil) == point
            else { return nil }
            let local = table.convert(point, from: superview)
            return table.visibleRect.contains(local) && table.row(at: local) >= 0 ? self : nil
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let source = table?.menu(for: event) else { return nil }
            let items = source.items
            source.removeAllItems()
            guard let menu = source.copy() as? NSMenu else {
                source.items = items
                return nil
            }
            menu.items = items
            return menu
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }
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
                !MACCursorDefinitions.hiddenCursorAliases.contains($0.identifier)
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
            } else {
                Color.clear.frame(width: 40, height: 40)
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
                !MACCursorDefinitions.hiddenCursorAliases.contains($0.identifier)
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
