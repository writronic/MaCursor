import SwiftUI
import UniformTypeIdentifiers

struct CursorThemeEditorView: View {
    @State private var viewModel: CursorThemeEditorViewModel
    @State private var isListDropTargeted = false
    @State private var editorWindow: NSWindow?
    
    init(cursorTheme: CursorThemeModel) {
        self._viewModel = State(initialValue: CursorThemeEditorViewModel(cursorTheme: cursorTheme))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            themeMetadataSection
            
            Divider()
            
            HSplitView {
                cursorListPane
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 280)
                
                cursorDetailPane
                    .frame(minWidth: 380, idealWidth: 500)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ToolbarConfigurator())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let error = viewModel.save() {
                        NSApp.presentError(error)
                    }
                }
                .disabled(!viewModel.isDirty)
            }
            
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
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
                if viewModel.save() == nil {
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
            if viewModel.isDirty {
                viewModel.isShowingUnsavedAlert = true
                return false
            }
            return true
        }))
    }
    
    private func closeWindow() {
        editorWindow?.close()
    }
    
    
    private var themeMetadataSection: some View {
        HStack(spacing: 12) {
            LabeledContent("Name:") {
                TextField("Theme Name", text: $viewModel.editingName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .onChange(of: viewModel.editingName) { _, _ in viewModel.markDirty() }
            }
            
            LabeledContent("Author:") {
                TextField("Author", text: $viewModel.editingAuthor)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 130)
                    .onChange(of: viewModel.editingAuthor) { _, _ in viewModel.markDirty() }
            }
            
            LabeledContent("Version:") {
                TextField("", value: $viewModel.editingVersion, format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .onChange(of: viewModel.editingVersion) { _, _ in viewModel.markDirty() }
            }
            
            Toggle("HiDPI", isOn: $viewModel.editingHiDPI)
                .toggleStyle(.checkbox)
                .onChange(of: viewModel.editingHiDPI) { _, _ in viewModel.markDirty() }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
    
    
    private var cursorListPane: some View {
        VStack(spacing: 0) {
            List(viewModel.visibleEditingCursors, selection: $viewModel.selectedCursorId) { cursor in
                HStack(spacing: 8) {
                    CursorThumbnailView(cursor: cursor)
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
            }
            .listStyle(.sidebar)
            .frame(maxHeight: .infinity)
            
            HStack(spacing: 4) {
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
                .disabled(viewModel.selectedCursor == nil)
                
                Spacer()
                
                Text("\(viewModel.visibleEditingCursors.count) cursors")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            let cursorURLs = urls.filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "cur" || ext == "ani"
            }
            guard !cursorURLs.isEmpty else { return false }
            viewModel.importWindowsCursors(from: cursorURLs)
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
    
    
    private var cursorDetailPane: some View {
        Group {
            if let cursor = viewModel.selectedCursor {
                CursorEditorView(
                    cursor: cursor,
                    usedIdentifiers: viewModel.usedIdentifiers(excluding: cursor.id),
                    onDirty: { viewModel.markDirty() }
                )
                    .id(cursor.id)
            } else {
                ContentUnavailableView(
                    "Select a Cursor",
                    systemImage: "cursorarrow.click.2",
                    description: Text("Choose a cursor from the list to edit its properties.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            view.window?.toolbar?.allowsDisplayModeCustomization = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
