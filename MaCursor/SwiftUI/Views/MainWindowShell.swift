import SwiftUI
import AppKit

struct MainWindowShell<Overview: View, Page: View>: View {
    @ObservedObject private var router: MainWindowRouter
    @EnvironmentObject private var library: LibraryViewModel
    @State private var editAfterReview: String?
    private let overview: () -> Overview
    private let page: (MainPage) -> Page

    init(router: MainWindowRouter,
         @ViewBuilder overview: @escaping () -> Overview,
         @ViewBuilder page: @escaping (MainPage) -> Page) {
        self.router = router
        self.overview = overview
        self.page = page
    }

    var body: some View {
        content
            .background(showsThemesPage || showsEditTheme ? .clear : Color.pageFill)
            .navigationTitle("MaCursor")
            .environmentObject(router)
            .frame(minWidth: MainWindowLayout.minimumContentSize.width, minHeight: MainWindowLayout.minimumContentSize.height)
            .background(ToolbarConfigurator())
            .background(WindowRoleAccessor(role: .main))
            .dropDestination(for: URL.self) { urls, _ in
                guard router.editor == nil else { return false }
                return library.handleDrop(urls)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cursorLibraryIdentifierDidChange)) { note in
                guard let oldId = note.userInfo?["oldId"] as? String,
                      let newId = note.userInfo?["newId"] as? String else { return }
                router.themeIdentifierChanged(from: oldId, to: newId)
            }
            .alert(
                NSLocalizedString("To convert this, use File > Convert Theme…", comment: "Alert after a drop that held something other than a .cursor file"),
                isPresented: $library.showsConvertHint
            ) {
                Button(NSLocalizedString("OK", comment: "OK button"), role: .cancel) {}
            }
            .sheet(isPresented: Binding(
                get: { library.conversion.phase == .review },
                set: { showing in
                    if !showing, library.conversion.phase == .review {
                        library.conversion.cancel()
                    }
                }
            ), onDismiss: {
                if let id = editAfterReview {
                    editAfterReview = nil
                    DispatchQueue.main.async { router.edit(id) }
                }
            }) {
                if let outcome = library.conversion.outcome {
                    ThemeConversionReviewView(
                        outcome: outcome,
                        onConfirm: { library.conversion.confirmAddToLibrary(using: library) },
                        onConfirmAndEdit: {
                            editAfterReview = library.conversion.confirmAndEditReturningId(using: library)
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
    }

    private var showsThemesPage: Bool {
        router.editor == nil && router.page == .themes
    }

    private var showsEditTheme: Bool {
        router.editingThemeId.flatMap { library.theme(withId: $0) } != nil
    }

    private var searching: Bool {
        !router.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var content: some View {
        if let id = router.editingThemeId {
            editThemePage(id)
        } else if case .gesture(let gesture, let title)? = router.editor {
            gesturePage(gesture, title: title)
        } else if case .trailStyle(let style, let title)? = router.editor {
            trailStylePage(style, title: title)
        } else if router.page == .themes {
            LibraryView()
                .id(router.pageID)
        } else {
            ZStack {
                Group {
                    if let shown = router.page {
                        VStack(alignment: .leading, spacing: 0) {
                            PageHeading(shown.localizedName)
                            page(shown)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .id(router.pageID)
                        .modifier(EscapeGoesBack { router.back() })
                    } else {
                        overview()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .id(router.pageID)
                    }
                }
                .opacity(searching ? 0 : 1)
                .disabled(searching)
                .allowsHitTesting(!searching)
                .accessibilityHidden(searching)
                if searching {
                    MainSearchResultsView(router: router)
                        .background(Color.pageFill)
                }
            }
            .environment(\.searchHighlight, router.highlight)
            .toolbar {
                if router.page != nil {
                    backItem
                }
                searchItem
                settingsItem
            }
        }
    }

    @ViewBuilder
    private func editThemePage(_ id: String) -> some View {
        if let theme = library.theme(withId: id) {
            CursorThemeEditorView(cursorTheme: theme, showsPageBar: true, preferences: library.preferences)
                .id(ObjectIdentifier(theme))
                .background(WindowTitleHidden())
                .background(OpaqueTitleBar())
        } else {
            UnavailableContent(
                title: Text("Theme Not Found"),
                systemImage: "exclamationmark.triangle",
                description: Text("The cursor theme could not be loaded.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbarTitleItem("Edit Theme", placement: .navigation)
            .toolbar { backItem }
        }
    }

    private func gesturePage(_ gesture: CursorGesture, title: String) -> some View {
        GestureEditorPage(gesture: gesture, themes: library.cursorThemes.map { (id: $0.id, name: $0.name) }, preferences: library.preferences, pageTitle: title)
            .id(gesture.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(WindowTitleHidden())
            .background(OpaqueTitleBar())
    }

    private func trailStylePage(_ style: CursorTrailsCustomStyle, title: String) -> some View {
        let preferences = library.preferences
        return CursorTrailsStylePage(style: style, config: CursorTrailsConfig.load(operations: preferences), pageTitle: title, step: CursorTrailsEditorStep.holding(router.highlight) ?? .layers,
                                     save: { CursorTrailsConfig.load(operations: preferences).saving($0).save(operations: preferences) })
            .id(style.id)
            .environment(\.searchHighlight, router.highlight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(WindowTitleHidden())
            .background(OpaqueTitleBar())
    }

    private var backItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { router.back() } label: {
                Label("Back", systemImage: "chevron.backward")
            }
            .help("Back")
        }
    }

    private var searchItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            SearchFieldView(text: $router.query, prompt: String(localized: "Search"), focusToken: router.searchFocus,
                            onDismiss: { NSApp.keyWindow?.makeFirstResponder(nil) })
                .frame(width: 220)
                .id(router.pageID)
        }
    }

    private var settingsItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { router.open(.settings, tab: 0) } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Settings")
        }
    }
}

struct PageHeading: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 26, weight: .bold))
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 14)
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EscapeGoesBack: ViewModifier {
    let action: () -> Void
    @State private var anchor = Anchor()

    func body(content: Content) -> some View {
        content
            .background(Host(anchor: anchor, action: action).frame(width: 0, height: 0))
            .onExitCommand {
                if !anchor.fieldHasKeyboard { action() }
            }
    }

    private struct Host: NSViewRepresentable {
        let anchor: Anchor
        let action: () -> Void

        func makeNSView(context: Context) -> Anchor {
            anchor.action = action
            anchor.isActive = context.environment.isEnabled
            return anchor
        }

        func updateNSView(_ nsView: Anchor, context: Context) {
            nsView.action = action
            nsView.isActive = context.environment.isEnabled
        }
    }

    final class Anchor: NSView {
        var action: () -> Void = {}
        var isActive = true
        private var watch: NSKeyValueObservation?

        var fieldHasKeyboard: Bool {
            (window?.firstResponder as? NSTextView)?.isFieldEditor == true
        }

        override var acceptsFirstResponder: Bool { true }

        override var canBecomeKeyView: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            watch = window?.observe(\.firstResponder, options: [.initial]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.claim() }
            }
        }

        private func claim() {
            guard isActive, let window, window.firstResponder === window else { return }
            window.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard isActive, event.keyCode == 53 else { return super.keyDown(with: event) }
            action()
        }

        override func cancelOperation(_ sender: Any?) {
            guard isActive else { return }
            action()
        }
    }
}

struct WindowTitleHidden: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker {
        Marker()
    }

    func updateNSView(_ nsView: Marker, context: Context) {}

    final class Marker: NSView {
        private static var markers: [ObjectIdentifier: Int] = [:]

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let window { Self.count(window, by: -1) }
            if let newWindow { Self.count(newWindow, by: 1) }
        }

        private static func count(_ window: NSWindow, by step: Int) {
            let key = ObjectIdentifier(window)
            let count = (markers[key] ?? 0) + step
            markers[key] = count > 0 ? count : nil
            window.titleVisibility = count > 0 ? .hidden : .visible
        }
    }
}

struct OpaqueTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker {
        Marker()
    }

    func updateNSView(_ nsView: Marker, context: Context) {}

    final class Marker: NSView {
        private static var markers: [ObjectIdentifier: Int] = [:]

        static func holds(_ window: NSWindow) -> Bool {
            markers[ObjectIdentifier(window)] != nil
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let window { Self.count(window, by: -1) }
            if let newWindow { Self.count(newWindow, by: 1) }
        }

        private static func count(_ window: NSWindow, by step: Int) {
            let key = ObjectIdentifier(window)
            let count = (markers[key] ?? 0) + step
            markers[key] = count > 0 ? count : nil
            window.titlebarAppearsTransparent = count <= 0
        }
    }
}

private struct SearchHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var searchHighlight: String? {
        get { self[SearchHighlightKey.self] }
        set { self[SearchHighlightKey.self] = newValue }
    }
}

extension View {
    func searchAnchor(_ key: String) -> some View {
        modifier(SearchAnchor(key: key))
    }
}

private struct SearchAnchor: ViewModifier {
    let key: String
    @Environment(\.searchHighlight) private var highlight

    func body(content: Content) -> some View {
        let shown = highlight == key
        content
            .background {
                if shown { SearchAnchorScroller() }
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(shown ? 0.12 : 0))
                    .padding(-4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(shown ? 1 : 0), lineWidth: 1.5)
                    .padding(-4)
                    .allowsHitTesting(false)
            )
            .animation(.easeInOut(duration: 0.2), value: shown)
    }
}

struct SearchAnchorScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ nsView: Probe, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                var view: NSView = self
                var rect = self.bounds.insetBy(dx: 0, dy: -80)
                while true {
                    view.scrollToVisible(rect)
                    guard let scroll = view.enclosingScrollView else { return }
                    rect = view.convert(rect, to: scroll)
                    view = scroll
                }
            }
        }
    }
}

struct MainSearchResultsView: View {
    @ObservedObject var router: MainWindowRouter
    @EnvironmentObject private var library: LibraryViewModel

    var body: some View {
        let query = router.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let themes = LibraryView.themes(library.cursorThemes, matching: query)
        let settings = MainSearch.settings(matching: query, snapshot: router.snapshot())
        if themes.isEmpty && settings.isEmpty {
            UnavailableContent.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                if !themes.isEmpty {
                    Section("Cursor Themes") {
                        ForEach(themes) { cursorTheme in
                            Button {
                                router.selectedThemeId = cursorTheme.id
                                router.open(.themes)
                            } label: {
                                CursorThemeRowView(cursorTheme: cursorTheme)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !settings.isEmpty {
                    Section("Settings") {
                        ForEach(settings, id: \.anchor) { entry in
                            Button {
                                router.open(entry.page, tab: entry.tab, highlight: entry.anchor)
                            } label: {
                                HStack {
                                    Text(entry.text)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.forward")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: FeaturePageLayout.formColumn)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
