import SwiftUI
import UniformTypeIdentifiers

struct CursorThemeEditorView: View {
    @StateObject private var viewModel: CursorThemeEditorViewModel
    @EnvironmentObject private var router: MainWindowRouter
    @State private var isListDropTargeted = false
    @State private var editorWindow: NSWindow?
    @State private var sidebarLayout: EditThemeSidebarLayout
    @State private var showAllSlots = false
    @State private var showsCursorIdentifiers: Bool
    @State private var sidebarSearchText = ""
    @State private var metadataFieldsEnabled = false
    @State private var hasPendingFieldEdit = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    private let showsPageBar: Bool
    private let preferences: MACPreferences.Operations

    init(cursorTheme: CursorThemeModel, showsPageBar: Bool = false, preferences: MACPreferences.Operations = .live) {
        self._viewModel = StateObject(wrappedValue: CursorThemeEditorViewModel(cursorTheme: cursorTheme))
        self._sidebarLayout = State(initialValue: EditThemeSidebarLayout(rawValue: MACPreferences.advancedEditorLayout(operations: preferences)) ?? .grid)
        self._showsCursorIdentifiers = State(initialValue: MACPreferences.flag(MACPreferences.showCursorIdentifiersKey, operations: preferences))
        self.showsPageBar = showsPageBar
        self.preferences = preferences
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Group {
                if showsPageBar {
                    cursorListPane
                        .toolbarTitleItem("MaCursor")
                        .toolbar {
                            ToolbarItem {
                                Button { router.back() } label: {
                                    Label("Back", systemImage: "chevron.backward")
                                }
                                .help("Back")
                            }
                        }
                } else {
                    cursorListPane
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .sidebarToggleRemoved()
            .navigationSplitViewColumnWidth(min: 310, ideal: 330, max: 380)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                themeMetadataSection
                    .disabled(!metadataFieldsEnabled)

                Divider().overlay(Color.editThemeLine)

                cursorDetailPane
            }
        }
        .onChangeCompat(of: columnVisibility) { newValue in
            if newValue != .all {
                columnVisibility = .all
            }
        }
        .environment(\.showsCursorIdentifiers, showsCursorIdentifiers)
        .onReceive(NotificationCenter.default.publisher(for: .cursorIdentifiersChanged)) { _ in
            showsCursorIdentifiers = MACPreferences.flag(MACPreferences.showCursorIdentifiersKey, operations: preferences)
        }
        .environment(\.numericFieldPendingEdit) { pending in
            DispatchQueue.main.async {
                hasPendingFieldEdit = pending
            }
        }
        .onAppear {
            let window = $editorWindow
            router.leaveEditor = { [weak viewModel] next in
                guard let viewModel else { return next() }
                window.wrappedValue?.makeFirstResponder(nil)
                viewModel.leave(then: next)
            }
            DispatchQueue.main.async {
                metadataFieldsEnabled = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Spacer() }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    commitPendingEdits()
                    if let error = viewModel.save() {
                        NSApp.presentError(error)
                    }
                }
                .disabled(!viewModel.isDirty && !hasPendingFieldEdit)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { router.back() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .toolbarTitleItem("Edit Theme", placement: .cancellationAction)
        .alert("Unsaved Changes", isPresented: $viewModel.isShowingUnsavedAlert) {
            Button("Save") {
                if let error = viewModel.save() {
                    DispatchQueue.main.async {
                        NSApp.presentError(error)
                    }
                } else {
                    viewModel.finishLeave()
                }
            }
            Button("Discard", role: .destructive) {
                viewModel.revertToSaved()
                viewModel.finishLeave()
            }
            Button("Cancel", role: .cancel) { viewModel.cancelLeave() }
        } message: {
            Text("Your changes will be discarded if you don't save them.")
        }
        .background(WindowAccessor(window: $editorWindow, onCloseAttempt: {
            router.back()
            return false
        }))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if let window = editorWindow, note.object as? NSWindow === window { viewModel.close() }
        }
        .onChangeCompat(of: editorWindow) { window in
            guard let window else { return }
            redirectInitialFocus(in: window)
        }
    }

    private func commitPendingEdits() {
        editorWindow?.makeFirstResponder(nil)
    }

    private func redirectInitialFocus(in window: NSWindow) {
        let baseline = TextEditingFocusCoordinator.shared.interactionCount
        Task { @MainActor in
            guard TextEditingFocusCoordinator.shared.interactionCount == baseline else { return }
            releaseSpontaneousTextFocus(in: window)
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard TextEditingFocusCoordinator.shared.interactionCount == baseline else { return }
            releaseSpontaneousTextFocus(in: window)
        }
    }

    private func releaseSpontaneousTextFocus(in window: NSWindow) {
        guard window.firstResponder is NSTextView || window.firstResponder === window,
              let content = window.contentView else { return }
        if let table = firstDescendant(ofType: NSTableView.self, in: content) {
            window.makeFirstResponder(table)
        } else {
            window.makeFirstResponder(nil)
        }
    }

    private func firstDescendant<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }
        for subview in view.subviews {
            if let found = firstDescendant(ofType: type, in: subview) {
                return found
            }
        }
        return nil
    }


    private var themeMetadataSection: some View {
        HStack(spacing: 12) {
            LabeledContent("Name:") {
                LimitedLengthTextField(
                    text: $viewModel.editingName,
                    placeholder: NSLocalizedString("Theme Name",
                                                   comment: "Theme name field placeholder"),
                    characterLimit: ThemeFieldLimits.nameCharacterLimit)
                    .frame(maxWidth: 180)
            }

            LabeledContent("Creator:") {
                LimitedLengthTextField(
                    text: $viewModel.editingCreator,
                    placeholder: NSLocalizedString("Creator",
                                                   comment: "Theme creator field placeholder"),
                    characterLimit: ThemeFieldLimits.creatorCharacterLimit)
                    .frame(maxWidth: 130)
            }

            LabeledContent("Version:") {
                NumericTextField(value: $viewModel.editingVersion,
                                 fractionDigits: ThemeFieldLimits.versionFractionDigits)
                    .frame(width: 50)
            }

            Toggle("HiDPI", isOn: $viewModel.editingHiDPI)
                .toggleStyle(.checkbox)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 40)
        .background(.bar)
    }


    private var trimmedSearchText: String {
        sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sidebarRows: [EditThemeSidebarModel.Row] {
        EditThemeSidebarModel.rows(
            cursors: viewModel.visibleEditingCursors,
            availableTypes: CursorIdentifier.allIdentifiers(
                hideTahoeCursors: viewModel.hideTahoeCursors),
            showAll: showAllSlots,
            searchText: sidebarSearchText)
    }

    private var cursorListPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchFieldView(
                    text: $sidebarSearchText,
                    prompt: NSLocalizedString("Search", comment: "Sidebar search field placeholder"))
                    .frame(maxWidth: .infinity)

                Picker("", selection: $sidebarLayout) {
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
                .onChangeCompat(of: sidebarLayout) { newLayout in
                    MACPreferences.set(newLayout.rawValue,
                                       forKey: MACPreferences.advancedEditorLayoutKey, operations: preferences)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color.editThemeLine)

            Group {
                if sidebarRows.isEmpty && !trimmedSearchText.isEmpty {
                    UnavailableContent.search(text: trimmedSearchText)
                } else {
                    switch sidebarLayout {
                    case .list:
                        cursorList
                    case .grid:
                        cursorGrid
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(Color.editThemeLine)

            HStack(spacing: 4) {
                Toggle(NSLocalizedString("Show All", comment: "Show all slots checkbox"),
                       isOn: $showAllSlots)
                    .toggleStyle(.checkbox)
                    .fixedSize()

                if !showAllSlots {
                    Button(action: { viewModel.addCursor() }) {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)

                    Button(action: {
                        if let cursor = viewModel.selectedCursor {
                            viewModel.removeCursor(cursor)
                        }
                    }) {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.selectedCursor == nil
                              || !sidebarRows.contains { $0.id == viewModel.selectedCursorId })

                    Spacer()

                    Text("\(viewModel.visibleEditingCursors.count) cursors")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Spacer()
                }
            }
            .frame(minHeight: 24)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .onChangeCompat(of: showAllSlots) { showing in
            if !showing, viewModel.selectedEmptySlotIdentifier != nil {
                viewModel.selectedCursorId = nil
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            let cursorURLs = urls.filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "cur" || ext == "ani"
            }
            guard !cursorURLs.isEmpty else { return false }
            let failures = viewModel.importWindowsCursors(from: cursorURLs)
            if !failures.isEmpty {
                CursorSourceAlert.reportUnusable(failures.map {
                    CursorSourceAlert.unreadableMessage(fileName: $0.url.lastPathComponent, error: $0.error)
                }.joined(separator: "\n\n"))
            }
            sidebarSearchText = ""
            return failures.count < cursorURLs.count
        } isTargeted: {
            isListDropTargeted = $0
        }
        .overlay {
            if isListDropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08)))
                    .allowsHitTesting(false)
            }
        }
    }


    private var cursorList: some View {
        List(selection: $viewModel.selectedCursorId) {
            ForEach(sidebarRows) { row in
                listRow(row)
                    .tag(row.id)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func listRow(_ row: EditThemeSidebarModel.Row) -> some View {
        switch row {
        case .cursor(let cursor):
            HStack(spacing: 8) {
                if cursor.hasRepresentations {
                    CursorThumbnailView(cursor: cursor)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.editThemeTile)
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 24, height: 24)
                }
                CursorNameLines(shown: showsCursorIdentifiers || cursor.identifier.isEmpty) {
                    Text(cursor.name)
                        .lineLimit(1)
                        .font(.system(size: 12, weight: .medium))
                } identifier: {
                    Text(cursor.cursorTypeName)
                        .lineLimit(1)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Duplicate") { viewModel.duplicateCursor(cursor) }
                Divider()
                Button("Delete", role: .destructive) { viewModel.removeCursor(cursor) }
            }
        case .empty(let identifier, let displayName):
            EmptySlotRowView(identifier: identifier, displayName: displayName)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first(where: { $0.isFileURL }) else { return false }
                    return assignSource(url, toIdentifier: identifier)
                }
        }
    }

    private func assignSource(_ url: URL, toIdentifier identifier: String) -> Bool {
        do {
            try viewModel.assignSource(url, toIdentifier: identifier)
            return true
        } catch {
            CursorSourceAlert.reportUnreadable(fileName: url.lastPathComponent, error: error)
            return false
        }
    }

    private var cursorGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)],
                      spacing: 14) {
                ForEach(sidebarRows) { row in
                    switch row {
                    case .cursor(let cursor):
                        CursorGridCellView(
                            cursor: cursor,
                            isSelected: viewModel.selectedCursorId == cursor.id,
                            onSelect: { viewModel.selectedCursorId = cursor.id },
                            onDuplicate: { viewModel.duplicateCursor(cursor) },
                            onDelete: { viewModel.removeCursor(cursor) })
                    case .empty(let identifier, let displayName):
                        EmptySlotCellView(
                            identifier: identifier,
                            displayName: displayName,
                            isSelected: viewModel.selectedCursorId == row.id,
                            onSelect: { viewModel.selectedCursorId = row.id })
                            .dropDestination(for: URL.self) { urls, _ in
                                guard let url = urls.first(where: { $0.isFileURL }) else {
                                    return false
                                }
                                return assignSource(url, toIdentifier: identifier)
                            }
                    }
                }
            }
            .padding()
        }
    }


    private var cursorDetailPane: some View {
        Group {
            if let cursor = viewModel.selectedCursor {
                CursorEditorView(
                    cursor: cursor,
                    usedIdentifiers: viewModel.usedIdentifiers(excluding: cursor.id),
                    onReplaceSource: { url in
                        try viewModel.replaceSource(url, for: cursor)
                    },
                    onClearSlot: {
                        viewModel.clearSlot(cursor, selectEmptyRow: showAllSlots)
                    }
                )
                    .id(cursor.id)
            } else if let emptyIdentifier = viewModel.selectedEmptySlotIdentifier {
                EmptySlotDetailView(
                    identifier: emptyIdentifier,
                    onAssign: { url in
                        assignSource(url, toIdentifier: emptyIdentifier)
                    })
                    .id(emptyIdentifier)
            } else {
                UnavailableContent(
                    title: Text("Select a Cursor"),
                    systemImage: "cursorarrow.click.2",
                    description: Text("Choose a cursor from the list to edit its properties.")
                )
            }
        }
        .frame(minWidth: 446, idealWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ShowsCursorIdentifiersKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var showsCursorIdentifiers: Bool {
        get { self[ShowsCursorIdentifiersKey.self] }
        set { self[ShowsCursorIdentifiersKey.self] = newValue }
    }
}

private struct CursorNameLines<Name: View, Identifier: View>: View {
    let shown: Bool
    let alignment: Alignment
    let spacing: CGFloat
    let name: Name
    let identifier: Identifier

    init(shown: Bool, alignment: Alignment = .leading, spacing: CGFloat = 1,
         @ViewBuilder name: () -> Name, @ViewBuilder identifier: () -> Identifier) {
        self.shown = shown
        self.alignment = alignment
        self.spacing = spacing
        self.name = name()
        self.identifier = identifier()
    }

    var body: some View {
        ZStack(alignment: alignment) {
            VStack(alignment: alignment.horizontal, spacing: spacing) {
                name
                identifier
            }
            .opacity(shown ? 1 : 0)
            .accessibilityHidden(!shown)
            if !shown {
                name
            }
        }
    }
}

private struct EmptySlotRowView: View {
    let identifier: String
    let displayName: String
    @Environment(\.showsCursorIdentifiers) private var showsIdentifier

    private var identifierTail: String {
        identifier.replacingOccurrences(of: "com.apple.", with: "")
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.editThemeTile)
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 24, height: 24)

            CursorNameLines(shown: showsIdentifier) {
                Text(displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            } identifier: {
                Text(identifierTail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .help(identifier)
    }
}

private struct CursorGridCellView: View {
    @ObservedObject var cursor: CursorModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @Environment(\.showsCursorIdentifiers) private var showsIdentifier

    private var identifierTail: String {
        cursor.identifier.replacingOccurrences(of: "com.apple.", with: "")
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.editThemeTile)
                if cursor.hasRepresentations {
                    CursorThumbnailView(cursor: cursor, size: 60)
                        .padding(8)
                } else {
                    Image(systemName: "plus")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 76, height: 76)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            CursorNameLines(shown: showsIdentifier, alignment: .top, spacing: 6) {
                Text(cursor.name)
                    .font(.caption)
                    .lineLimit(1)
            } identifier: {
                Text(identifierTail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .help(cursor.identifier)
    }
}

private struct EmptySlotCellView: View {
    let identifier: String
    let displayName: String
    var isSelected: Bool = false
    var onSelect: (() -> Void)? = nil
    @Environment(\.showsCursorIdentifiers) private var showsIdentifier

    private var identifierTail: String {
        identifier.replacingOccurrences(of: "com.apple.", with: "")
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.editThemeTile)
                Image(systemName: "plus")
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 76, height: 76)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            CursorNameLines(shown: showsIdentifier, alignment: .top, spacing: 6) {
                Text(displayName)
                    .font(.caption)
                    .lineLimit(1)
            } identifier: {
                Text(identifierTail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
        .help(identifier)
    }
}

private struct EmptySlotDetailView: View {
    let identifier: String
    let onAssign: (URL) -> Bool

    @State private var isDropTargeted = false
    @Environment(\.showsCursorIdentifiers) private var showsIdentifier

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CursorIdentifier.displayName(for: identifier))
                    .font(.title2)
                    .bold()
                if showsIdentifier {
                    Text(identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            UnavailableContent(
                title: Text(NSLocalizedString("No cursor assigned", comment: "Empty slot inspector title")),
                systemImage: "square.dashed",
                description: Text(NSLocalizedString(
                    "Choose a source file or drop one onto the cell.",
                    comment: "Empty slot inspector description")))
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                Button(NSLocalizedString("Choose Source…", comment: "Choose cursor source button")) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.message = NSLocalizedString(
                        "Choose a cursor or image file (.cur, .ani, Xcursor, .png, .gif)",
                        comment: "Choose source panel message")
                    if panel.runModal() == .OK, let url = panel.url {
                        _ = onAssign(url)
                    }
                }
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.isFileURL }) else { return false }
            return onAssign(url)
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08)))
                    .allowsHitTesting(false)
            }
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    var onCloseAttempt: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onCloseAttempt: onCloseAttempt)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
            self.installDelegate(on: view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        self.window = nsView.window
        context.coordinator.onCloseAttempt = onCloseAttempt
        installDelegate(on: nsView.window, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let window = coordinator.window, window.delegate === coordinator {
            window.delegate = coordinator.originalDelegate
        }
    }

    private func installDelegate(on window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        if window.delegate as? Coordinator !== coordinator {
            coordinator.window = window
            coordinator.originalDelegate = (window.delegate as? Coordinator)?.originalDelegate ?? window.delegate
            window.delegate = coordinator
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var onCloseAttempt: () -> Bool
        weak var originalDelegate: (any NSWindowDelegate)?
        weak var window: NSWindow?

        init(onCloseAttempt: @escaping () -> Bool) {
            self.onCloseAttempt = onCloseAttempt
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            return onCloseAttempt()
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || originalDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            originalDelegate
        }
    }
}

struct ToolbarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = !OpaqueTitleBar.Marker.holds(window)
            }
            if #available(macOS 15, *) {
                view.window?.toolbar?.allowsDisplayModeCustomization = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
