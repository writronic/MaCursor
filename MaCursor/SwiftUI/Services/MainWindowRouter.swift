import AppKit

enum MainEditor: Equatable {
    case theme(String)
    case gesture(CursorGesture, title: String)
    case trailStyle(CursorTrailsCustomStyle, title: String)
}

@MainActor
final class MainWindowRouter: ObservableObject {
    static let shared = MainWindowRouter()
    static let highlightDuration: TimeInterval = 1.5

    @Published private(set) var page: MainPage?
    @Published var selectedThemeId: String?
    @Published private(set) var pageID = UUID()
    @Published var query = ""
    @Published private(set) var highlight: String?
    @Published private(set) var searchFocus: Int?
    @Published private(set) var editor: MainEditor?
    @Published var showsThemeGallery = false
    @Published var themeSearchOpen = false
    @Published var themeSearchText = ""
    @Published var gestureSearch = ""
    @Published var gestureFilter = CursorGestureFilter.all
    var canLeavePage: () -> Bool = { true }
    var selectTab: (MainPage, Int) -> Void = { _, _ in }
    var snapshot: () -> OverviewSnapshot = { OverviewSnapshot() }
    var leaveEditor: ((@escaping () -> Void) -> Void)?
    var bringForward: () -> Void = {}
    var trailStyleInUse: () -> CursorTrailsCustomStyle = { CursorTrailsConfig.load().styleInUse }
    private var highlightGeneration = 0

    var editingThemeId: String? {
        if case .theme(let id)? = editor { return id }
        return nil
    }

    @discardableResult
    func open(_ page: MainPage?, tab: Int? = nil, highlight: String? = nil) -> Bool {
        guard editor == nil else {
            NSSound.beep()
            bringForward()
            return false
        }
        guard canLeavePage() else {
            NSSound.beep()
            return false
        }
        if let page, let tab {
            selectTab(page, tab)
        }
        self.page = page
        showsThemeGallery = page == .themes && highlight == MainSearch.galleryAnchor
        pageID = UUID()
        themeSearchOpen = false
        themeSearchText = ""
        gestureSearch = ""
        gestureFilter = .all
        query = ""
        searchFocus = nil
        self.highlight = highlight
        if page == .cursorTrails, CursorTrailsEditorStep.holding(highlight) != nil {
            editor = .trailStyle(trailStyleInUse(), title: String(localized: "Edit Style"))
        }
        if let highlight {
            highlightGeneration += 1
            let generation = highlightGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.highlightDuration) { [weak self] in
                guard let self, self.highlightGeneration == generation else { return }
                self.highlight = nil
            }
        }
        return true
    }

    func openGallery() {
        if open(.themes) { showsThemeGallery = true }
    }

    func edit(_ themeId: String) {
        guard editor != .theme(themeId) else { return }
        show(.theme(themeId))
    }

    func editGesture(_ gesture: CursorGesture, title: String) {
        show(.gesture(gesture, title: title))
    }

    func editTrailStyle(_ style: CursorTrailsCustomStyle, title: String) {
        show(.trailStyle(style, title: title))
    }

    func closeEditor() {
        showEditor(nil)
    }

    private func show(_ next: MainEditor) {
        guard canLeavePage() else {
            NSSound.beep()
            return
        }
        let show: () -> Void = { [weak self] in self?.showEditor(next) }
        if editor != nil, let leaveEditor {
            leaveEditor(show)
        } else {
            show()
        }
    }

    func back() {
        guard editor != nil else {
            open(nil)
            return
        }
        guard canLeavePage() else {
            NSSound.beep()
            return
        }
        let hide: () -> Void = { [weak self] in self?.showEditor(nil) }
        if let leaveEditor {
            leaveEditor(hide)
        } else {
            hide()
        }
    }

    func themeIdentifierChanged(from oldId: String, to newId: String) {
        if selectedThemeId == oldId { selectedThemeId = newId }
        if case .theme(oldId)? = editor { editor = .theme(newId) }
    }

    private func showEditor(_ next: MainEditor?) {
        leaveEditor = nil
        editor = next
        query = ""
        searchFocus = nil
        highlight = nil
    }

    func focusSearch() {
        searchFocus = (searchFocus ?? 0) + 1
    }

    func reloadPage() {
        pageID = UUID()
        themeSearchOpen = false
        themeSearchText = ""
        gestureSearch = ""
        gestureFilter = .all
    }
}
