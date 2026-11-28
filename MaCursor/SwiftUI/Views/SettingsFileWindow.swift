import Combine
import SwiftUI
import UniformTypeIdentifiers

struct SettingsFileEffects {
    var imported: @MainActor (Set<SettingsFileGroup>) -> Void = { _ in }
}

enum SettingsFileLayout {
    static let width: CGFloat = 420
}

private final class SettingsFilePanel: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private final class SettingsFileHost: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
}

@MainActor
final class SettingsFileWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsFileWindowController()

    var effects = SettingsFileEffects()
    var place = SettingsFilePlace.live
    var activate: @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    weak var library: LibraryViewModel?
    var isLanding = false
    private var modalChange: AnyCancellable?

    private init() {
        let window = SettingsFilePanel(contentRect: NSRect(x: 0, y: 0, width: SettingsFileLayout.width, height: 300),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        modalChange = ModalWindowCoordinator.shared.activeModalDidChange.sink { [weak self] in self?.anchor() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentExport() {
        guard !stillLanding() else { return }
        show(String(localized: "Export Settings"),
             AnyView(SettingsFileExportView(place: place, library: library, save: Self.saveURL, close: dismiss, resized: fit)))
    }

    func chooseAndImport() {
        guard !stillLanding(), let url = Self.openURL() else { return }
        presentImport(url)
    }

    func presentImport(_ url: URL) {
        guard !stillLanding() else { return }
        let read: Result<SettingsFileContents, SettingsFile.Refusal>
        do {
            read = .success(try SettingsFile.read(url))
        } catch {
            read = .failure(error as? SettingsFile.Refusal ?? .unreadable)
        }
        show(String(localized: "Import Settings"),
             AnyView(SettingsFileImportView(name: url.lastPathComponent, read: read, place: place, library: library, effects: effects,
                                            close: dismiss, resized: fit)))
    }

    func dismiss() {
        window?.close()
    }

    private func stillLanding() -> Bool {
        guard isLanding else { return false }
        NSSound.beep()
        front()
        return true
    }

    private func show(_ title: String, _ content: AnyView) {
        guard let window else { return }
        window.title = title
        fill(content)
        let anchor = [ModalWindowCoordinator.shared.activeModalWindow, ModalWindowCoordinator.shared.resolvedMainWindow]
            .compactMap { $0 }.first { $0 !== window && $0.isVisible }
        if let anchor, let visible = anchor.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            window.setFrameOrigin(ModalWindowPlacement.centeredOrigin(size: window.frame.size, over: anchor.frame, constrainedTo: visible))
        } else {
            window.center()
        }
        front()
    }

    private func front() {
        guard let window else { return }
        ModalWindowCoordinator.shared.register(window, as: .modal)
        window.makeKeyAndOrderFront(nil)
        activate()
        if window.isVisible { ModalWindowCoordinator.shared.windowDidBecomeKey(window) }
    }

    private func anchor() {
        guard let window else { return }
        let below = window.isVisible ? ModalWindowCoordinator.shared.trackedModalWindows.last { $0 !== window && $0.isVisible } : nil
        guard window.parent !== below else { return }
        window.parent?.removeChildWindow(window)
        below?.addChildWindow(window, ordered: .above)
    }

    func fill(_ content: AnyView) {
        window?.contentView = SettingsFileHost(rootView: content)
        fit()
    }

    private func fit() {
        guard let window, let content = window.contentView else { return }
        let top = window.frame.maxY
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content.fittingSize))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        frame.size.height = min(frame.height, visible?.height ?? .infinity)
        frame.origin = NSPoint(x: window.frame.minX, y: window.isVisible ? max(top - frame.height, visible?.minY ?? -.infinity) : window.frame.minY)
        window.setFrame(frame, display: true)
    }

    static func saveURL() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [SettingsFile.type]
        panel.nameFieldStringValue = String(localized: "MaCursor Settings") + ".macursor"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func openURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SettingsFile.type]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Import")
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct SettingsFileSection: View {
    var body: some View {
        Section {
            EmptyView()
        } header: {
            Text(verbatim: " ").accessibilityHidden(true)
        } footer: {
            SettingsFileCards()
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

struct SettingsFileCards: View {
    var body: some View {
        HStack(spacing: 10) {
            card(Text("Import Settings")) {
                Button("Import…") { SettingsFileWindowController.shared.chooseAndImport() }
                    .accessibilityLabel(Text("Import Settings…"))
            }
            .searchAnchor("setImport")
            card(Text("Export Settings")) {
                Button("Export…") { SettingsFileWindowController.shared.presentExport() }
                    .accessibilityLabel(Text("Export Settings…"))
            }
            .searchAnchor("setExport")
        }
        .padding(.horizontal, -10)
    }

    private func card<Content: View>(_ label: Text, @ViewBuilder button: () -> Content) -> some View {
        GroupBox {
            HStack {
                label.frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
                button()
            }
            .padding(5)
        }
        .accessibilityElement(children: .contain)
    }
}

struct SettingsFileExportView: View {
    enum Problem { case tooBig, failed }

    let place: SettingsFilePlace
    let library: LibraryViewModel?
    let limit: Int
    let save: @MainActor () -> URL?
    let close: @MainActor () -> Void
    let resized: @MainActor () -> Void
    private let themes: [CursorThemeModel]
    private let sizes: [String: Int]
    private let historySizes: [SettingsFileHistoryGroup: Int]
    @State private var ticked = Set(SettingsFileGroup.allCases)
    @State private var themesOn: Bool
    @State private var tickedThemes: Set<String>
    @State private var tickedHistory: Set<SettingsFileHistoryGroup> = []
    @State private var problem: Problem?

    init(place: SettingsFilePlace, library: LibraryViewModel? = nil, problem: Problem? = nil, limit: Int = SettingsFile.maxBytes,
         save: @escaping @MainActor () -> URL?, close: @escaping @MainActor () -> Void, resized: @escaping @MainActor () -> Void = {}) {
        self.place = place
        self.library = library
        self.limit = limit
        self.save = save
        self.close = close
        self.resized = resized
        let themes = library?.cursorThemes ?? []
        self.themes = themes
        sizes = Dictionary(themes.map { ($0.id, SettingsFile.diskSize($0.fileURL)) }, uniquingKeysWith: +)
        historySizes = Dictionary(uniqueKeysWithValues: SettingsFileHistoryGroup.allCases.compactMap { group in
            SettingsFileHistory.size(group, place: place).map { (group, $0) }
        })
        _themesOn = State(initialValue: !themes.isEmpty)
        _tickedThemes = State(initialValue: Set(themes.map(\.id)))
        _problem = State(initialValue: problem)
    }

    private var chosenThemes: [CursorThemeModel] {
        themesOn ? themes.filter { tickedThemes.contains($0.id) } : []
    }

    private var tooBig: Bool {
        problem == .tooBig
            || chosenThemes.reduce(0) { $0 + sizes[$1.id, default: 0] } + tickedHistory.reduce(0) { $0 + historySizes[$1, default: 0] } > limit
    }

    var body: some View {
        SettingsFileDialog(title: Text("Export Settings"), lead: Text("Choose what goes into the file.")) {
            SettingsFileRows(themes: themes.map { SettingsFileThemeRow(id: $0.id, name: $0.name, replaces: false) },
                             themesOn: $themesOn, tickedThemes: $tickedThemes, groups: SettingsFileGroup.allCases, ticked: $ticked,
                             histories: SettingsFileHistoryGroup.allCases.filter { historySizes[$0] != nil }, tickedHistory: $tickedHistory,
                             caption: { $0 == .cursorTranslator ? Text("Your API keys stay on this Mac.") : nil },
                             historyCaption: \.exportCaption)
            if tooBig {
                SettingsFileProblem(text: Text("This is too big for one file. Untick some themes or history."))
            } else if problem == .failed {
                SettingsFileProblem(text: Text("MaCursor could not export the settings."))
            }
        } buttons: {
            Button { close() } label: { SettingsFileButtonLabel(text: Text("Cancel")) }
                .keyboardShortcut(.cancelAction)
            Button { export() } label: { SettingsFileButtonLabel(text: Text("Export…")) }
                .keyboardShortcut(.defaultAction)
                .disabled((ticked.isEmpty && chosenThemes.isEmpty && tickedHistory.isEmpty) || tooBig)
        }
        .onChangeCompat(of: ticked) { _ in problem = nil }
        .onChangeCompat(of: tickedHistory) { _ in problem = nil }
        .onChangeCompat(of: tickedThemes) { _ in problem = nil }
        .onChangeCompat(of: themesOn) { _ in problem = nil }
        .onChangeCompat(of: [themesOn, tooBig, problem == .failed]) { _ in DispatchQueue.main.async { resized() } }
    }

    private func export() {
        guard let data = try? SettingsFile.export(ticked, themes: chosenThemes.map(\.backingLibrary),
                                                  favorites: library?.favoriteThemeIds ?? [], history: tickedHistory, place: place) else {
            problem = .failed
            return
        }
        guard data.count <= SettingsFile.maxBytes else {
            problem = .tooBig
            return
        }
        guard let url = save() else { return }
        do {
            try data.write(to: url, options: .atomic)
            close()
        } catch {
            problem = .failed
        }
    }
}

struct SettingsFileImportView: View {
    let name: String
    let read: Result<SettingsFileContents, SettingsFile.Refusal>
    let place: SettingsFilePlace
    let library: LibraryViewModel?
    let effects: SettingsFileEffects
    let close: @MainActor () -> Void
    let resized: @MainActor () -> Void
    private let fileThemes: [CursorLibrary]
    private let here: [CursorLibrary]
    @State private var ticked: Set<SettingsFileGroup>
    @State private var themesOn: Bool
    @State private var tickedThemes: Set<String>
    @State private var tickedHistory: Set<SettingsFileHistoryGroup> = []
    @State private var confirming = false
    @State private var landing = false
    @State private var result: SettingsFileResult?
    @State private var skipped: [SettingsFileHistoryGroup]
    @State private var editing: Bool

    init(name: String, read: Result<SettingsFileContents, SettingsFile.Refusal>, place: SettingsFilePlace, library: LibraryViewModel? = nil,
         effects: SettingsFileEffects, result: SettingsFileResult? = nil, skipped: [SettingsFileHistoryGroup] = [],
         close: @escaping @MainActor () -> Void, resized: @escaping @MainActor () -> Void = {}) {
        self.name = name
        self.read = read
        self.place = place
        self.library = library
        self.effects = effects
        self.close = close
        self.resized = resized
        let contents = try? read.get()
        here = library?.cursorThemes.map(\.backingLibrary) ?? []
        fileThemes = library == nil ? [] : contents?.themes ?? []
        _ticked = State(initialValue: Set(contents?.groups ?? []))
        _themesOn = State(initialValue: !fileThemes.isEmpty)
        _tickedThemes = State(initialValue: Set(fileThemes.map(\.identifier)))
        _result = State(initialValue: result)
        _skipped = State(initialValue: skipped)
        _editing = State(initialValue: library?.isEditingTheme == true)
    }

    static func confirmation(settings: [String], replaced: [String], added: Bool) -> String {
        var lines: [String] = []
        if !settings.isEmpty {
            lines.append(String(localized: "Settings that are replaced: \(ListFormatter.localizedString(byJoining: settings))"))
        }
        if !replaced.isEmpty {
            lines.append(String(localized: "Themes that are replaced: \(ListFormatter.localizedString(byJoining: replaced))"))
        }
        if added {
            lines.append(String(localized: "New themes are added."))
        }
        lines.append(String(localized: "You can’t undo this."))
        return lines.joined(separator: "\n")
    }

    static func allowsScripts(_ contents: SettingsFileContents, groups: Set<SettingsFileGroup>, ask: @MainActor (String) -> Bool) -> Bool {
        SettingsFile.scriptWarning(contents, groups: groups).map(ask) ?? true
    }

    static func askAboutScripts(_ list: String) -> Bool {
        scriptAlert(list).runModal() == .alertFirstButtonReturn
    }

    static func scriptAlert(_ list: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "This file has actions that run scripts, shortcuts or commands, or open links")
        alert.informativeText = String(localized: "These actions run with your rights and can change or delete your files. Import only files you trust.")
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let most = NSTextField(labelWithString: String(repeating: "0", count: 64))
        most.font = font
        let rows = list.components(separatedBy: "\n").map { line in
            let text = NSTextField(labelWithString: line)
            text.font = font
            text.isSelectable = true
            text.lineBreakMode = .byTruncatingTail
            text.clipsToBounds = false
            let room: (top: CGFloat, bottom: CGFloat) = line.unicodeScalars.allSatisfy(\.isASCII) ? (0, 0) : (2, 4)
            let row = NSView(frame: NSRect(x: 0, y: 0, width: min(text.fittingSize.width, most.fittingSize.width), height: text.fittingSize.height + room.top + room.bottom))
            row.clipsToBounds = true
            text.frame = NSRect(x: 0, y: room.bottom, width: row.frame.width, height: text.fittingSize.height)
            row.addSubview(text)
            return row
        }
        let box = NSView(frame: NSRect(x: 0, y: 0, width: rows.map(\.frame.width).max() ?? 0, height: rows.map(\.frame.height).reduce(0, +)))
        var top = box.frame.height
        for row in rows {
            top -= row.frame.height
            row.frame.origin.y = top
            box.addSubview(row)
        }
        alert.accessoryView = box
        alert.addButton(withTitle: String(localized: "Import Anyway")).keyEquivalent = ""
        alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
        return alert
    }

    var body: some View {
        switch read {
        case .failure(let refusal):
            refused(refusal)
        case .success(let contents) where contents.groups.isEmpty && themeRows.isEmpty && contents.histories.isEmpty && result == nil:
            refused(.unreadable)
        case .success(let contents):
            if let result {
                finished {
                    Text("Import finished.")
                    if !result.failed.isEmpty {
                        Text("MaCursor could not import: \(ListFormatter.localizedString(byJoining: result.failed))")
                            .foregroundStyle(.red)
                    }
                    if !result.cleared.isEmpty {
                        Text("Shortcuts already used by another feature were cleared: \(ListFormatter.localizedString(byJoining: result.cleared))")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(skipped) { group in
                        (group == .captureHistory
                            ? Text("Capture History was not added: Keep history is set to Disabled.")
                            : Text("Cursor Board History was not added: Keep history is off."))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                form(contents)
            }
        }
    }

    private func refused(_ refusal: SettingsFile.Refusal) -> some View {
        finished {
            (refusal == .newer
                ? Text("This file is from a newer version of MaCursor. Update MaCursor, then try again.")
                : Text("MaCursor could not read this settings file."))
                .foregroundStyle(.red)
        }
    }

    static func themeRows(_ themes: [CursorLibrary], here: [CursorLibrary], ticked: Set<String>) -> [SettingsFileThemeRow] {
        var claimed: [CursorLibrary] = []
        return themes.map { lib in
            let old = LibraryController.existingTheme(sameNameAs: lib.identifier, in: here, excluding: claimed)
            if let old, ticked.contains(lib.identifier) { claimed.append(old) }
            return SettingsFileThemeRow(id: lib.identifier, name: lib.name, replaces: old != nil)
        }
    }

    private var themeRows: [SettingsFileThemeRow] {
        Self.themeRows(fileThemes, here: here, ticked: tickedThemes)
    }

    private var chosenRows: [SettingsFileThemeRow] {
        themesOn ? themeRows.filter { tickedThemes.contains($0.id) } : []
    }

    private func form(_ contents: SettingsFileContents) -> some View {
        let blocked = !chosenRows.isEmpty && editing
        return SettingsFileDialog(title: Text("Import Settings"), lead: Text("Choose what to import from “\(name)”.")) {
            SettingsFileRows(themes: themeRows, themesOn: $themesOn, tickedThemes: $tickedThemes, groups: contents.groups, ticked: $ticked,
                             histories: contents.histories, tickedHistory: $tickedHistory,
                             caption: { $0 == .cursorGestures ? Text("Gestures can open apps and links, and run scripts and commands. Import only files you trust.") : nil },
                             historyCaption: { _ in SettingsFileHistoryGroup.importCaption })
            if blocked {
                SettingsFileProblem(text: Text("Close the Edit Theme window, then try again."))
            }
        } buttons: {
            Button { close() } label: { SettingsFileButtonLabel(text: Text("Cancel")) }
                .keyboardShortcut(.cancelAction)
            Button { if Self.allowsScripts(contents, groups: ticked, ask: Self.askAboutScripts) { confirming = true } } label: { SettingsFileButtonLabel(text: Text("Import…")) }
                .keyboardShortcut(.defaultAction)
                .disabled((ticked.isEmpty && chosenRows.isEmpty && tickedHistory.isEmpty) || blocked || landing)
        }
        .alert(Text("Import?"), isPresented: $confirming) {
            Button("Import") { run(contents) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.confirmation(settings: SettingsFileGroup.allCases.filter(ticked.contains).map(\.title),
                                   replaced: chosenRows.filter(\.replaces).map(\.name), added: chosenRows.contains { !$0.replaces }))
        }
        .onChangeCompat(of: [themesOn, blocked]) { _ in DispatchQueue.main.async { resized() } }
    }

    private func run(_ contents: SettingsFileContents) {
        let ids = Set(chosenRows.map(\.id))
        var failed: [String] = []
        var landed: [String: String] = [:]
        if let library, !ids.isEmpty {
            (failed, landed) = library.importSettingsThemes(contents.themes.filter { ids.contains($0.identifier) }, favorites: contents.favoriteThemes)
        }
        if themesOn || themeRows.isEmpty {
            failed += contents.failedThemes
        }
        var outcome = SettingsFile.apply(contents, groups: ticked, place: place, landed: landed)
        let history = tickedHistory
        outcome.failed = failed + outcome.failed
            + SettingsFileHistoryGroup.allCases.filter { contents.failedHistory.contains($0) && (history.contains($0) || !contents.histories.contains($0)) }.map(\.title)
        effects.imported(ticked)
        landing = true
        SettingsFileWindowController.shared.isLanding = true
        let finished = outcome
        Task { @MainActor in
            skipped = await SettingsFileHistory.land(contents, groups: history, place: place)
            result = finished
            SettingsFileWindowController.shared.isLanding = false
            DispatchQueue.main.async { resized() }
        }
    }

    private func finished<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        SettingsFileDialog(title: Text("Import Settings"), lead: nil) {
            VStack(spacing: 8) { content() }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(EdgeInsets(top: 16, leading: 24, bottom: 0, trailing: 24))
        } buttons: {
            Button { close() } label: { SettingsFileButtonLabel(text: Text("Close")) }
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct SettingsFileDialog<Content: View, Buttons: View>: View {
    let title: Text
    let lead: Text?
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                title.font(.title2.weight(.semibold))
                lead?.foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(EdgeInsets(top: 36, leading: 20, bottom: 0, trailing: 20))
            ScrollView { VStack(spacing: 0) { content } }
            HStack(spacing: 8) {
                Spacer()
                buttons
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
        }
        .frame(width: SettingsFileLayout.width)
    }
}

struct SettingsFileThemeRow: Identifiable {
    let id: String
    let name: String
    let replaces: Bool
}

private struct SettingsFileRows: View {
    private enum Row: Hashable {
        case group(SettingsFileGroup)
        case history(SettingsFileHistoryGroup)
    }

    let themes: [SettingsFileThemeRow]
    @Binding var themesOn: Bool
    @Binding var tickedThemes: Set<String>
    let groups: [SettingsFileGroup]
    @Binding var ticked: Set<SettingsFileGroup>
    let histories: [SettingsFileHistoryGroup]
    @Binding var tickedHistory: Set<SettingsFileHistoryGroup>
    let caption: (SettingsFileGroup) -> Text?
    let historyCaption: (SettingsFileHistoryGroup) -> Text

    private static let fill = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor.white.withAlphaComponent(0.06) : .white
    })

    private var rows: [Row] {
        SettingsFileGroup.allCases.flatMap { group -> [Row] in
            (groups.contains(group) ? [.group(group)] : []) + histories.filter { $0.parent == group }.map { .history($0) }
        }
    }

    private func attached(_ index: Int) -> Bool {
        guard index > 0, case .history(let history) = rows[index] else { return false }
        return rows[index - 1] == .group(history.parent)
    }

    private func row(_ title: String, isOn: Binding<Bool>, caption: Text?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn)
                .toggleStyle(.checkbox)
            if let caption {
                caption.font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !themes.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Themes", isOn: $themesOn)
                        .toggleStyle(.checkbox)
                    if themesOn {
                        SettingsFileThemeList(themes: themes, ticked: $tickedThemes)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.element) { index, item in
                if (index > 0 || !themes.isEmpty) && !attached(index) { Divider() }
                switch item {
                case .group(let group):
                    row(group.title, isOn: Binding(
                        get: { ticked.contains(group) },
                        set: { if $0 { ticked.insert(group) } else { ticked.remove(group) } }
                    ), caption: caption(group))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                case .history(let history):
                    row(history.title, isOn: Binding(
                        get: { tickedHistory.contains(history) },
                        set: { if $0 { tickedHistory.insert(history) } else { tickedHistory.remove(history) } }
                    ), caption: historyCaption(history))
                    .padding(EdgeInsets(top: attached(index) ? 0 : 6, leading: attached(index) ? 34 : 12, bottom: 6, trailing: 12))
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Self.fill))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        .padding(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
    }
}

private struct SettingsFileThemeList: View {
    let themes: [SettingsFileThemeRow]
    @Binding var ticked: Set<String>
    @State private var atEnd = false

    private static let rowHeight: CGFloat = 26
    private static let tallest: CGFloat = 118
    private static let fadeHeight: CGFloat = 22
    private static let fill = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor.white.withAlphaComponent(0.04) : NSColor.black.withAlphaComponent(0.025)
    })

    private var contentHeight: CGFloat {
        CGFloat(themes.count) * (Self.rowHeight + 1) - 1
    }

    private var height: CGFloat {
        min(contentHeight, Self.tallest)
    }

    private var fades: Bool {
        contentHeight > Self.tallest && !atEnd
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(themes.enumerated()), id: \.element.id) { index, theme in
                    if index > 0 { Divider() }
                    Toggle(isOn: Binding(
                        get: { ticked.contains(theme.id) },
                        set: { if $0 { ticked.insert(theme.id) } else { ticked.remove(theme.id) } }
                    )) {
                        HStack(spacing: 6) {
                            Text(theme.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if theme.replaces {
                                Text("Replaces yours")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
                    .padding(.horizontal, 8)
                }
            }
            .background(GeometryReader { geometry in
                Color.clear.onChangeCompat(of: geometry.frame(in: .named("list")).maxY) { atEnd = $0 <= height + 2 }
            })
        }
        .coordinateSpace(name: "list")
        .frame(height: height)
        .background(Self.fill)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)))
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 1 - Self.fadeHeight / height),
                                     .init(color: fades ? .clear : .black, location: 1)], startPoint: .top, endPoint: .bottom))
        .padding(EdgeInsets(top: 6, leading: 20, bottom: 2, trailing: 0))
    }
}

private struct SettingsFileProblem: View {
    let text: Text

    var body: some View {
        text.font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
    }
}

private struct SettingsFileButtonLabel: View {
    let text: Text

    var body: some View {
        text.frame(minWidth: 62)
    }
}
