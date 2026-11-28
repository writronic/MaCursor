import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject private var router: MainWindowRouter
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var searchFocusToken = 0
    @State private var themeCount = 0
    @State private var pendingDelete: CursorThemeModel?
    @FocusState private var listFocused: Bool

    private var visibleThemes: [CursorThemeModel] {
        Self.themes(library.cursorThemes, matching: router.themeSearchText)
    }

    var body: some View {
        if router.showsThemeGallery {
            ThemeGalleryView()
        } else {
            themesPage
        }
    }

    private var themesPage: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ScrollViewReader { proxy in
            VStack(spacing: 0) {
                Group {
                    switch library.themesLayout {
                    case .list:
                        themeList(proxy)
                    case .grid:
                        SidebarTileGrid(items: visibleThemes, selection: $router.selectedThemeId, focus: $listFocused,
                                        onOpen: { handleDoubleClick(on: $0) }, metrics: .editTheme) { cursorTheme in
                            CursorThemeRowView(cursorTheme: cursorTheme, isSelected: router.selectedThemeId == cursorTheme.id,
                                               layout: .grid)
                        } menu: { cursorTheme in
                            themeMenu(cursorTheme, proxy: proxy)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    let query = router.themeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !query.isEmpty && visibleThemes.isEmpty {
                        UnavailableContent.search(text: query)
                    }
                }

                SidebarBottomBar(layout: $library.themesLayout, count: Text("\(visibleThemes.count) themes"))
            }
            .onChangeCompat(of: router.themeSearchOpen) { open in
                if !open, let themeId = router.selectedThemeId {
                    proxy.scrollTo(themeId, anchor: .center)
                }
            }
            .onAppear {
                if let themeId = router.selectedThemeId {
                    proxy.scrollTo(themeId, anchor: .center)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .sidebarToggleRemoved()
            .toolbar {
                ToolbarItem { Spacer() }
                ToolbarItemGroup(placement: .primaryAction) {
                    if router.themeSearchOpen {
                        SearchFieldView(text: $router.themeSearchText, prompt: String(localized: "Search"),
                                        focusToken: searchFocusToken, onDismiss: closeSearch)
                            .frame(width: 170)
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
                            router.selectedThemeId = newId
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
            .toolbarTitleItem("MaCursor")
            .toolbar {
                ToolbarItem {
                    Button { router.back() } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .help("Back")
                }
            }
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 400, max: 500)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                if let themeId = router.selectedThemeId, let cursorTheme = library.theme(withId: themeId) {
                    CursorThemeDetailView(cursorTheme: cursorTheme)
                        .id(cursorTheme.id)
                } else {
                    UnavailableContent(
                        title: Text("Select a Cursor Theme"),
                        systemImage: "cursorarrow.and.square.on.square.dashed",
                        description: Text("Choose a cursor theme from the sidebar to view its cursors.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItem { Spacer() }
                if let themeId = router.selectedThemeId, let cursorTheme = library.theme(withId: themeId) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Apply") { library.apply(cursorTheme) }
                            .disabled(cursorTheme.isApplied || !cursorTheme.isApplicable)
                            .modifier(ApplyBlockedHelp(cursorTheme: cursorTheme))
                    }
                    ToolbarItem {
                        Button("Edit") {
                            router.edit(cursorTheme.id)
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
            }
            .toolbarTitleItem("Cursor Themes")
        }
        .navigationTitle("MaCursor")
        .background(WindowTitleHidden())
        .background(OpaqueTitleBar())
        .onExitCommand { router.selectedThemeId = nil }
        .focusedSceneValue(\.librarySearch, openSearch)
        .onAppear { themeCount = library.cursorThemes.count }
        .onChangeCompat(of: library.cursorThemes.count) { count in
            if count > themeCount {
                closeSearch()
            }
            themeCount = count
        }
        .onChangeCompat(of: visibleThemes.map(\.id)) { visibleIds in
            if let themeId = router.selectedThemeId, !visibleIds.contains(themeId),
               library.theme(withId: themeId) != nil {
                router.selectedThemeId = nil
            }
        }
        .onChangeCompat(of: columnVisibility) { newValue in
            if newValue != .all {
                columnVisibility = .all
            }
        }
        .onDeleteCommand {
            if let themeId = router.selectedThemeId, let cursorTheme = library.theme(withId: themeId) {
                pendingDelete = cursorTheme
            }
        }
        .alert(String(format: NSLocalizedString("Delete “%@”?", comment: "Alert title before a cursor theme is deleted"),
                      pendingDelete?.name ?? ""),
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { cursorTheme in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do {
                    try library.remove(cursorTheme)
                    if router.selectedThemeId == cursorTheme.id {
                        router.selectedThemeId = nil
                    }
                } catch {
                    NSApp.presentError(error)
                }
            }
        }
    }

    private func themeList(_ proxy: ScrollViewProxy) -> some View {
        List(visibleThemes, selection: $router.selectedThemeId) { cursorTheme in
            CursorThemeRowView(
                cursorTheme: cursorTheme,
                isSelected: router.selectedThemeId == cursorTheme.id,
                boxedArrow: true
            )
            .tag(cursorTheme.id)
        }
        .contextMenu(forSelectionType: String.self) { selectedIds in
            if let themeId = selectedIds.first,
               let cursorTheme = library.theme(withId: themeId) {
                themeMenu(cursorTheme, proxy: proxy)
            }
        } primaryAction: { selectedIds in
            guard let themeId = selectedIds.first,
                  let cursorTheme = library.theme(withId: themeId) else { return }
            handleDoubleClick(on: cursorTheme)
        }
        .listStyle(.sidebar)
        .focused($listFocused)
        .overlay(ListMenuOwner())
    }

    @ViewBuilder
    private func themeMenu(_ cursorTheme: CursorThemeModel, proxy: ScrollViewProxy) -> some View {
        Button("Apply") { library.apply(cursorTheme) }
            .disabled(!cursorTheme.isApplicable)
        Button("Edit") {
            router.edit(cursorTheme.id)
        }
        Button(favoriteTitle(for: cursorTheme)) {
            library.toggleFavorite(cursorTheme)
        }
        Divider()
        Button("Duplicate") {
            if let newId = library.duplicateTheme(cursorTheme) {
                router.selectedThemeId = newId
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
        Button("Delete", role: .destructive) { pendingDelete = cursorTheme }
    }

    private func openSearch() {
        router.themeSearchOpen = true
        searchFocusToken += 1
    }

    private func closeSearch() {
        guard router.themeSearchOpen else { return }
        router.themeSearchOpen = false
        router.themeSearchText = ""
        listFocused = true
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
        let query = MainSearch.folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return themes }
        return themes.filter {
            MainSearch.folded($0.name).contains(query) || MainSearch.folded($0.creator).contains(query)
        }
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
                  event.type == .rightMouseDown || event.type == .leftMouseDown,
                  superview.convert(event.locationInWindow, from: nil) == point
            else { return nil }
            let local = table.convert(point, from: superview)
            guard table.visibleRect.contains(local) else { return nil }
            let onRow = table.row(at: local) >= 0
            let menuClick = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
            return onRow == menuClick ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            guard let table, !event.modifierFlags.contains(.control) else { return super.mouseDown(with: event) }
            window?.makeFirstResponder(table)
            table.deselectAll(nil)
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

enum SidebarGrid {
    static let box: CGFloat = 96
    static let minimumColumn: CGFloat = 112
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16

    struct Metrics {
        let box: CGFloat
        let picture: CGFloat
        let minimumColumn: CGFloat
        let rowSpacing: CGFloat
        let truncation: Text.TruncationMode

        static let gallery = Metrics(box: SidebarGrid.box, picture: 64, minimumColumn: SidebarGrid.minimumColumn,
                                     rowSpacing: SidebarGrid.spacing, truncation: .middle)
        static let editTheme = Metrics(box: 76, picture: 60, minimumColumn: 76, rowSpacing: 14, truncation: .tail)
    }

    static func columns(width: CGFloat, minimumColumn: CGFloat = SidebarGrid.minimumColumn) -> Int {
        max(1, Int((width - 2 * padding + spacing) / (minimumColumn + spacing)))
    }

    static func moved<ID: Equatable>(_ selection: ID?, in ids: [ID], columns: Int, direction: MoveCommandDirection,
                                     layoutDirection: LayoutDirection = .leftToRight) -> ID? {
        guard let first = ids.first else { return nil }
        guard let selection, let index = ids.firstIndex(of: selection) else { return first }
        let forward = layoutDirection == .rightToLeft ? -1 : 1
        let step: Int
        switch direction {
        case .left: step = -forward
        case .right: step = forward
        case .up: step = -columns
        case .down: step = columns
        @unknown default: step = 0
        }
        return ids.indices.contains(index + step) ? ids[index + step] : selection
    }
}

struct SidebarLayoutPicker: View {
    @Binding var layout: EditThemeSidebarLayout

    var body: some View {
        Picker("", selection: $layout) {
            Image(systemName: "list.bullet")
                .help(NSLocalizedString("List View", comment: "Sidebar list layout"))
                .tag(EditThemeSidebarLayout.list)
            Image(systemName: "square.grid.2x2")
                .help(NSLocalizedString("Grid View", comment: "Sidebar grid layout"))
                .tag(EditThemeSidebarLayout.grid)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

struct SidebarBottomBar: View {
    @Binding var layout: EditThemeSidebarLayout
    let count: Text

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.editThemeLine)
            HStack(spacing: 8) {
                SidebarLayoutPicker(layout: $layout)
                Spacer(minLength: 8)
                count
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(minHeight: 24)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}

struct SidebarTile<Picture: View, Badges: View>: View {
    let name: String
    let isSelected: Bool
    var metrics: SidebarGrid.Metrics = .gallery
    @ViewBuilder let picture: Picture
    @ViewBuilder let badges: Badges

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.editThemeTile)
                .frame(width: metrics.box, height: metrics.box)
                .overlay { picture.frame(maxWidth: metrics.picture, maxHeight: metrics.picture).accessibilityHidden(true) }
                .overlay { badges.padding(6) }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: RowSelectionStyle.strokeWidth)
                }
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(metrics.truncation)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .help(name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SidebarTileGrid<Item: Identifiable, Tile: View, Menu: View>: View {
    let items: [Item]
    @Binding var selection: Item.ID?
    var focus: FocusState<Bool>.Binding
    var onOpen: ((Item) -> Void)? = nil
    var metrics: SidebarGrid.Metrics = .gallery
    @ViewBuilder let tile: (Item) -> Tile
    @ViewBuilder let menu: (Item) -> Menu
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { geometry in
            let columns = SidebarGrid.columns(width: geometry.size.width, minimumColumn: metrics.minimumColumn)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SidebarGrid.spacing, alignment: .top), count: columns),
                              spacing: metrics.rowSpacing) {
                        ForEach(items) { item in
                            Button { pick(item.id) } label: {
                                tile(item)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen?(item) })
                            .id(item.id)
                            .contextMenu { menu(item) }
                        }
                    }
                    .padding(SidebarGrid.padding)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                    .background {
                        Button { pick(nil) } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHidden(true)
                    }
                }
                .onChangeCompat(of: selection) { id in
                    if let id { proxy.scrollTo(id) }
                }
                .task(id: geometry.size.height > 0) {
                    if geometry.size.height > 0, let selection { proxy.scrollTo(selection, anchor: .center) }
                }
            }
            .focusable()
            .focusEffectDisabledCompat()
            .focused(focus)
            .onMoveCommand { direction in
                selection = SidebarGrid.moved(selection, in: items.map(\.id), columns: columns, direction: direction,
                                              layoutDirection: layoutDirection)
            }
            .onCommand(#selector(NSResponder.insertNewline(_:))) {
                if let item = items.first(where: { $0.id == selection }) { onOpen?(item) }
            }
        }
    }

    private func pick(_ id: Item.ID?) {
        selection = id
        focus.wrappedValue = true
    }
}

enum RowSelectionStyle {
    static let strokeWidth: CGFloat = 2
    static let cornerRadius: CGFloat = 8
    static let fillOpacity: Double = 0.08
    static let horizontalInset: CGFloat = 10
}

struct CursorThemeRowView: View {
    @ObservedObject var cursorTheme: CursorThemeModel
    var isSelected: Bool = false
    var boxedArrow: Bool = false
    var layout: EditThemeSidebarLayout = .list

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
        Group {
            switch layout {
            case .list: row
            case .grid: tile
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hideTahoeCursorsChanged)) { _ in
            preferenceRevision += 1
        }
    }

    private var hdBadge: some View {
        Text("HD")
            .font(.caption2.bold())
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.blue.opacity(0.15))
            .foregroundStyle(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var tile: some View {
        SidebarTile(name: cursorTheme.name, isSelected: isSelected, metrics: .editTheme) {
            if let hero = heroCursor {
                CursorThumbnailView(cursor: hero, size: SidebarGrid.Metrics.editTheme.picture, trimmed: true)
            }
        } badges: {
            HStack(alignment: .top) {
                if cursorTheme.isApplied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                        .accessibilityLabel(Text("Applied"))
                }
                Spacer(minLength: 0)
                if cursorTheme.isHiDPI {
                    hdBadge
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var row: some View {
        HStack(spacing: 5) {
            Image(systemName: cursorTheme.isApplied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(cursorTheme.isApplied ? .green : .secondary.opacity(0.3))
                .font(.system(size: 14))

            if boxedArrow {
                CursorPictureBox {
                    if let hero = heroCursor {
                        CursorThumbnailView(cursor: hero, size: 28, trimmed: true)
                    }
                }
            } else if let hero = heroCursor {
                CursorThumbnailView(cursor: hero, size: 40)
            } else {
                Color.clear.frame(width: 40, height: 40)
            }

            HStack(spacing: 6) {
                Text(cursorTheme.name)
                    .font(.headline)
                    .lineLimit(1)

                if cursorTheme.isHiDPI {
                    hdBadge
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
                        .fill(boxedArrow ? AnyShapeStyle(Color.editThemeTile) : AnyShapeStyle(.quaternary))
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
