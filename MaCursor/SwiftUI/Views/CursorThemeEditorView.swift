import SwiftUI
import UniformTypeIdentifiers

struct CursorThemeEditorView: View {
    @StateObject private var viewModel: CursorThemeEditorViewModel
    @State private var isListDropTargeted = false
    @State private var editorWindow: NSWindow?
    @State private var sidebarLayout =
        EditThemeSidebarLayout(rawValue: MACPreferences.advancedEditorLayout) ?? .list
    @State private var showAllSlots = false
    @State private var sidebarSearchText = ""
    @State private var metadataFieldsEnabled = false

    init(cursorTheme: CursorThemeModel) {
        self._viewModel = StateObject(wrappedValue: CursorThemeEditorViewModel(cursorTheme: cursorTheme))
    }

    var body: some View {
        VStack(spacing: 0) {
            themeMetadataSection
                .disabled(!metadataFieldsEnabled)

            Divider()

            HSplitView {
                cursorListPane
                    .frame(minWidth: 310, idealWidth: 330, maxWidth: 380)

                cursorDetailPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            DispatchQueue.main.async {
                metadataFieldsEnabled = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ToolbarConfigurator())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    commitPendingEdits()
                    if let error = viewModel.save() {
                        NSApp.presentError(error)
                    }
                }
                .disabled(!viewModel.isDirty)
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    commitPendingEdits()
                    if viewModel.isDirty {
                        viewModel.isShowingUnsavedAlert = true
                    } else {
                        closeWindow()
                    }
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .alert("Unsaved Changes", isPresented: $viewModel.isShowingUnsavedAlert) {
            Button("Save") {
                if let error = viewModel.save() {
                    DispatchQueue.main.async {
                        NSApp.presentError(error)
                    }
                } else {
                    closeWindow()
                }
            }
            Button("Discard", role: .destructive) {
                viewModel.revertToSaved()
                closeWindow()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your changes will be discarded if you don't save them.")
        }
        .background(WindowAccessor(window: $editorWindow, onCloseAttempt: {
            commitPendingEdits()
            if viewModel.isDirty {
                viewModel.isShowingUnsavedAlert = true
                return false
            }
            return true
        }))
        .background(WindowRoleAccessor(role: .modal))
        .onChangeCompat(of: editorWindow) { window in
            guard let window else { return }
            EditorTextShortcutCoordinator.shared.register(window)
            redirectInitialFocus(in: window)
        }
    }

    private func closeWindow() {
        editorWindow?.close()
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
        guard window.firstResponder is NSTextView,
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
                                       forKey: MACPreferences.advancedEditorLayoutKey)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

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

            Divider()

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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
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
            viewModel.importWindowsCursors(from: cursorURLs)
            sidebarSearchText = ""
            return true
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
                            .fill(.quaternary.opacity(0.4))
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 24, height: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(cursor.name)
                        .lineLimit(1)
                        .font(.system(size: 12, weight: .medium))
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
                    return viewModel.assignSource(url, toIdentifier: identifier)
                }
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
                                return viewModel.assignSource(url, toIdentifier: identifier)
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
                        viewModel.replaceSource(url, for: cursor)
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
                        viewModel.assignSource(url, toIdentifier: emptyIdentifier)
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
        .frame(minWidth: 380, idealWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptySlotRowView: View {
    let identifier: String
    let displayName: String

    private var identifierTail: String {
        identifier.replacingOccurrences(of: "com.apple.", with: "")
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.4))
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
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

    private var identifierTail: String {
        cursor.identifier.replacingOccurrences(of: "com.apple.", with: "")
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.4))
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
            Text(cursor.name)
                .font(.caption)
                .lineLimit(1)
            Text(identifierTail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

    private var identifierTail: String {
        identifier.replacingOccurrences(of: "com.apple.", with: "")
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.4))
                Image(systemName: "plus")
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 76, height: 76)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            Text(displayName)
                .font(.caption)
                .lineLimit(1)
            Text(identifierTail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CursorIdentifier.displayName(for: identifier))
                    .font(.title2)
                    .bold()
                Text(identifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            UnavailableContent(
                title: Text(NSLocalizedString("No cursor assigned", comment: "Empty slot inspector title")),
                systemImage: "square.dashed",
                description: Text(NSLocalizedString(
                    "Choose a source file or drop one onto the cell.",
                    comment: "Empty slot inspector description")))

            HStack {
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

private struct WindowAccessor: NSViewRepresentable {
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

    private func installDelegate(on window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        if window.delegate as? Coordinator !== coordinator {
            coordinator.originalDelegate = window.delegate
            window.delegate = coordinator
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var onCloseAttempt: () -> Bool
        weak var originalDelegate: (any NSWindowDelegate)?

        init(onCloseAttempt: @escaping () -> Bool) {
            self.onCloseAttempt = onCloseAttempt
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            return onCloseAttempt()
        }

        func windowWillClose(_ notification: Notification) {
            originalDelegate?.windowWillClose?(notification)
        }

        func windowDidBecomeKey(_ notification: Notification) {
            originalDelegate?.windowDidBecomeKey?(notification)
        }

        func windowDidResignKey(_ notification: Notification) {
            originalDelegate?.windowDidResignKey?(notification)
        }
    }
}

struct ToolbarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if #available(macOS 15, *) {
                view.window?.toolbar?.allowsDisplayModeCustomization = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
