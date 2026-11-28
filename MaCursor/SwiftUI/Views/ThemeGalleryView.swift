import SwiftUI

struct ThemeGalleryView: View {
    @EnvironmentObject private var library: LibraryViewModel
    @EnvironmentObject private var router: MainWindowRouter
    @StateObject private var model: ThemeGalleryModel
    @State private var attempt = 0
    @State private var searchFocusToken: Int?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @FocusState private var listFocused: Bool

    init(model: @autoclosure @escaping () -> ThemeGalleryModel = ThemeGalleryModel()) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: attempt) { await model.load() }
            .background(WindowTitleHidden())
            .background(OpaqueTitleBar())
            .modifier(EscapeGoesBack { router.back() })
            .focusedSceneValue(\.librarySearch, openSearch)
    }

    @ViewBuilder
    private var content: some View {
        if model.entries.isEmpty {
            Group {
                if model.phase == .failed {
                    VStack(spacing: 16) {
                        UnavailableContent(
                            title: Text("Cannot Load the Gallery"),
                            systemImage: "wifi.exclamationmark",
                            description: Text("Check your internet connection, then try again.")
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        Button("Try Again") { attempt += 1 }
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .toolbarTitleItem(Text("Theme Gallery"), placement: .navigation, gap: 8)
            .toolbarTitleItem("MaCursor", placement: .navigation)
            .toolbar {
                ToolbarItem(placement: .navigation) { backButton }
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                list
                    .toolbarTitleItem("MaCursor")
                    .toolbar {
                        ToolbarItem { backButton }
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .sidebarToggleRemoved()
                    .navigationSplitViewColumnWidth(min: 400, ideal: 400, max: 500)
            } detail: {
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbarTitleItem("Theme Gallery")
            }
            .onChangeCompat(of: columnVisibility) { newValue in
                if newValue != .all {
                    columnVisibility = .all
                }
            }
        }
    }

    private var backButton: some View {
        Button { router.back() } label: {
            Label("Back", systemImage: "chevron.backward")
        }
        .help("Back")
    }

    private var selection: Binding<String?> {
        Binding(get: { model.selection }, set: { if let id = $0 { model.select(id) } })
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchFieldView(text: $model.searchText, prompt: String(localized: "Search"),
                                focusToken: searchFocusToken, onDismiss: { listFocused = true })
                    .frame(maxWidth: .infinity)
                SidebarLayoutPicker(layout: $library.galleryLayout)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color.editThemeLine)

            Group {
                switch library.galleryLayout {
                case .list:
                    List(model.visibleEntries, selection: selection) { entry in
                        ThemeGalleryRow(entry: entry, picture: model.pictures[entry.id],
                                        inLibrary: model.state(of: entry, in: library) == .inLibrary,
                                        isSelected: model.selection == entry.id)
                            .tag(entry.id)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .focused($listFocused)
                    .overlay(ListMenuOwner())
                case .grid:
                    SidebarTileGrid(items: model.visibleEntries, selection: selection, focus: $listFocused) { entry in
                        SidebarTile(name: entry.name, isSelected: model.selection == entry.id) {
                            if let picture = model.pictures[entry.id] {
                                Image(decorative: picture, scale: 1)
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                            }
                        } badges: {
                            if model.state(of: entry, in: library) == .inLibrary {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel(Text("In Library"))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            }
                        }
                    } menu: { _ in
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty && model.visibleEntries.isEmpty {
                    UnavailableContent.search(text: query)
                }
            }
        }
    }

    @ViewBuilder
    private var pane: some View {
        if let entry = model.entries.first(where: { $0.id == model.selection }) {
            VStack(spacing: 0) {
                ThemeGalleryHeader(entry: entry, count: model.preview.cursors?.count,
                                   state: model.state(of: entry, in: library),
                                   get: { Task { await model.get(entry, into: library) } })
                Divider()
                previewBody
            }
            .task(id: model.previewAttempt) { await model.loadPreview() }
        } else {
            UnavailableContent(
                title: Text("Select a Cursor Theme"),
                systemImage: "cursorarrow.and.square.on.square.dashed",
                description: Text("Select a theme to see its cursors.")
            )
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        switch model.preview {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: 16) {
                UnavailableContent(
                    title: Text("Cannot Load the Preview"),
                    systemImage: "exclamationmark.triangle",
                    description: Text("MaCursor could not download or open this theme.")
                )
                .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { model.retryPreview() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let cursors):
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 140), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(cursors) { cursor in
                        ThemeGalleryCursorCell(cursor: cursor)
                    }
                }
                .padding(20)
            }
        }
    }

    private func openSearch() {
        searchFocusToken = (searchFocusToken ?? 0) + 1
    }
}

struct ThemeGalleryRow: View {
    let entry: ThemeGalleryEntry
    let picture: CGImage?
    let inLibrary: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            CursorPictureBox {
                if let picture {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.creator)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if inLibrary {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .accessibilityLabel(Text("In Library"))
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
        .accessibilityElement(children: .combine)
    }
}

struct ThemeGalleryHeader: View {
    let entry: ThemeGalleryEntry
    let count: Int?
    let state: ThemeGalleryGetState
    let get: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if state == .failed {
                Text("Could not add this theme.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            button
                .controlSize(.large)
        }
        .padding()
    }

    private var subtitle: Text {
        guard let count else { return Text("by \(entry.creator)") }
        return Text("by \(entry.creator)") + Text(verbatim: " • ") + Text("\(count) cursors")
    }

    @ViewBuilder
    private var button: some View {
        switch state {
        case .get, .failed:
            Button(action: get) {
                Text("Get")
                    .frame(minWidth: 56)
            }
            .buttonStyle(.borderedProminent)
            .help("Add to Library")
        case .adding:
            Button(action: {}) {
                Text("Get")
                    .frame(minWidth: 56)
            }
            .buttonStyle(.borderedProminent)
            .hidden()
            .overlay(ProgressView().controlSize(.small))
        case .inLibrary:
            Button(action: {}) {
                Label("In Library", systemImage: "checkmark")
            }
            .disabled(true)
        }
    }
}

struct ThemeGalleryCursorCell: View {
    let cursor: ThemeGalleryCursor

    @State private var currentFrame = 0
    @State private var animationTimer: Timer?

    var body: some View {
        VStack(spacing: 6) {
            picture(cursor.frame(at: currentFrame))
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
        .onChangeCompat(of: cursor.frames.count) { _ in
            currentFrame = 0
            startAnimation()
        }
        .onChangeCompat(of: cursor.frameDuration) { _ in startAnimation() }
    }

    private func startAnimation() {
        stopAnimation()
        guard cursor.moves else { return }
        let count = cursor.frames.count
        animationTimer = Timer.scheduledTimer(withTimeInterval: cursor.frameDuration, repeats: true) { _ in
            DispatchQueue.main.async {
                currentFrame = (currentFrame + 1) % count
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    @ViewBuilder
    private func picture(_ image: CGImage?) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 64, maxHeight: 64)
        }
    }
}
