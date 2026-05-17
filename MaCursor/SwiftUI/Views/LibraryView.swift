import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryViewModel.self) var library
    @Environment(\.openWindow) private var openWindow
    @State private var selectedThemeId: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        @Bindable var library = library
        
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ScrollViewReader { proxy in
            List(library.cursorThemes, selection: $selectedThemeId) { cursorTheme in
                CursorThemeRowView(cursorTheme: cursorTheme)
                    .tag(cursorTheme.id)
            }
            .contextMenu(forSelectionType: String.self) { selectedIds in
                if let themeId = selectedIds.first,
                   let cursorTheme = library.theme(withId: themeId) {
                    Button("Apply") { library.apply(cursorTheme) }
                    Button("Edit") {
                        openEditorWindow(for: cursorTheme)
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
            .toolbar(removing: .sidebarToggle)
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
                                .disabled(cursorTheme.isApplied)
                        }
                        ToolbarItem {
                            Button("Edit") {
                                openEditorWindow(for: cursorTheme)
                            }
                        }
                    }
            } else {
                ContentUnavailableView(
                    "Select a Cursor Theme",
                    systemImage: "cursorarrow.and.square.on.square.dashed",
                    description: Text("Choose a cursor theme from the sidebar to view its cursors.")
                )
            }
        }
        .navigationTitle("MaCursor")
        .onChange(of: columnVisibility) { _, newValue in
            if newValue != .all {
                columnVisibility = .all
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            library.handleDrop(providers)
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
}

extension LibraryView {
    func handleDoubleClick(on cursorTheme: CursorThemeModel) {
        library.apply(cursorTheme)
    }
}
