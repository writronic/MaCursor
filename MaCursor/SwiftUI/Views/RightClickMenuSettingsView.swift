import SwiftUI

extension View {
    func rightClickMenuCard() -> some View {
        background(Color.boxFill, in: RoundedRectangle(cornerRadius: RightClickMenuLayout.cardRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: RightClickMenuLayout.cardRadius, style: .continuous))
    }

    func rightClickMenuHeading() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, RightClickMenuLayout.inset)
            .frame(height: RightClickMenuLayout.rowHeight)
    }

    func rightClickMenuListRow(_ index: Int) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: -RightClickMenuSettingsView.listCellInset,
                                 bottom: 0, trailing: -RightClickMenuSettingsView.listCellInset))
            .listRowSeparator(.hidden)
            .listRowBackground(RightClickMenuSettingsView.stripe(index))
    }
}

struct RightClickMenuSettingsView: View {
    static let listCellInset: CGFloat = 8.5

    static func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width)
    }

    static var showsOnColumnWidth: CGFloat {
        RightClickMenuLayout.showsOnColumnWidth(
            valueWidths: RightClickMenuShowsOn.allCases.map { textWidth($0.title, size: RightClickMenuLayout.bodyFontSize) },
            headingWidth: textWidth(String(localized: "Shows on"), size: RightClickMenuLayout.calloutFontSize))
    }

    static var enableColumnWidth: CGFloat {
        max(textWidth(String(localized: "Enable"), size: RightClickMenuLayout.calloutFontSize), RightClickMenuLayout.miniSwitchWidth)
    }

    static var showInColumnWidth: CGFloat {
        RightClickMenuLayout.showInColumnWidth(
            titleWidths: ([RightClickMenuTab.mainMenu.title] + RightClickMenuGroup.allCases.map(\.title)).map { textWidth($0, size: RightClickMenuLayout.bodyFontSize) },
            headingWidth: textWidth(String(localized: "Show in"), size: RightClickMenuLayout.calloutFontSize))
    }

    @ObservedObject private var manager = FinderExtensionManager.shared
    @State private var requestTask: Task<Void, Never>?
    @State private var selectedApplication: String?
    @State private var selectedFile: RightClickMenuFile?
    @State private var addingFile = false
    @State private var editedFile: String?
    @State private var deletingFile: RightClickMenuFile?
    @State private var draftMenuName = ""
    @State private var draftName = ""
    @State private var draftExtension = ""
    @State private var errorMessage: String?

    private var isOn: Bool {
        RightClickMenuState.isOn(settings: manager.settings, election: manager.election)
    }

    private var showsAccessWarning: Bool {
        manager.settings.isEnabled && manager.election != .elected
    }

    private var showsFullDiskAccessWarning: Bool {
        manager.settings.isEnabled && manager.election == .elected && !manager.settings.hasFullDiskAccess
    }

    private var showsRegistrationFailure: Bool {
        !manager.isBusy && (manager.registrationFailed || manager.election == .unregistered)
    }

    var body: some View {
        FeaturePageFrame(header: {
            header
        }, tabs: {
            if RightClickMenuState.showsItems(settings: manager.settings, election: manager.election) {
                FeatureTabList(titles: RightClickMenuTab.allCases.map(\.title), styles: FeatureTabCatalog.styles(for: .rightClickMenu),
                               label: String(localized: "Right-Click Menu"),
                               selection: Binding(get: { RightClickMenuTab.allCases.firstIndex(of: manager.selectedTab) ?? 0 },
                                                  set: { manager.selectedTab = RightClickMenuTab.allCases[$0] }))
            }
        }, pane: {
            if RightClickMenuState.showsItems(settings: manager.settings, election: manager.election) {
                GeometryReader { pane in
                    let column = RightClickMenuLayout.tableWidth(contentWidth: pane.size.width - 2 * RightClickMenuLayout.pageMargin)
                    ScrollView {
                        VStack(alignment: .leading, spacing: RightClickMenuLayout.blockSpacing) {
                            ExplainerCard(manager.selectedTab.note)

                            switch manager.selectedTab {
                            case .mainMenu:
                                mainMenuTable
                            case .actions:
                                actionsList
                            case .newFile:
                                newFileTable
                            case .openWith:
                                appList(.openWith)
                            case .commonApps:
                                appList(.commonApps)
                            }

                            Text("If the menu does not appear right away, quit and reopen Finder.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, RightClickMenuLayout.inset)
                        }
                        .frame(width: column)
                        .padding(.leading, (pane.size.width - column) / 2)
                        .padding(.vertical, RightClickMenuLayout.pageMargin)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        })
        .onAppear { manager.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorSettingsDidReset)) { _ in
            requestTask?.cancel()
            manager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: ModalWindowCoordinator.shared.resolvedMainWindow)) { _ in
            errorMessage = nil
        }
        .onDisappear { requestTask?.cancel() }
        .onChangeCompat(of: manager.selectedTab) { _ in
            selectedApplication = nil
            selectedFile = nil
            errorMessage = nil
        }
        .onChangeCompat(of: manager.election) { _ in errorMessage = nil }
    }

    private var header: some View {
        VStack(spacing: 10) {
            FeatureOnOffBox(title: String(localized: "Right-Click Menu"),
                            subtitle: String(localized: "Adds MaCursor’s shortcuts to the right-click menu in Finder and on the Desktop."),
                            symbol: "contextualmenu.and.cursorarrow", tint: .indigo, isOn: Binding(
                                get: { isOn },
                                set: { _ in toggle() }
                            ))
            .disabled(manager.isBusy || (manager.isTranslocated && !isOn))

            if showsAccessWarning || showsFullDiskAccessWarning || showsRegistrationFailure || manager.isTranslocated || errorMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if showsAccessWarning {
                        Label("The Finder extension is turned off.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                        FinderExtensionAccessControls()
                    }

                    if showsFullDiskAccessWarning {
                        Label("Full Disk Access is turned off.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                        Text("MaCursor needs Full Disk Access. Turn on MaCursor in System Settings, then quit and reopen MaCursor if macOS asks.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open System Settings") { manager.openFullDiskAccessSettings() }
                    }

                    if showsRegistrationFailure {
                        HStack {
                            Text("MaCursor could not register its Finder extension.")
                                .font(.callout)
                            Spacer()
                            Button("Try Again") { manager.registerIfNeeded() }
                                .disabled(manager.isTranslocated)
                        }
                    }

                    if manager.isTranslocated {
                        Text("Move MaCursor to the Applications folder to use the Right-Click Menu.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .featureNotice()
            }
        }
    }

    private var mainMenuTable: some View {
        let items = manager.settings.menuItems(isAvailable: Self.hasApplication)
        let itemWidth = mainMenuItemColumnWidth(items)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: RightClickMenuLayout.handleColumn, height: 1)
                HStack(spacing: RightClickMenuLayout.columnSpacing) {
                    Text("Item")
                        .padding(.leading, RightClickMenuLayout.iconColumn)
                        .frame(width: itemWidth, alignment: .leading)
                    Text("Contains")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Shows on")
                        .frame(width: Self.showsOnColumnWidth, alignment: .leading)
                }
            }
            .rightClickMenuHeading()
            Divider()
            if items.isEmpty {
                Text("Nothing is turned on.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, RightClickMenuLayout.inset)
                    .frame(height: 2 * RightClickMenuLayout.rowHeight)
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.element) { index, item in
                        mainMenuRow(item, at: index, in: items, itemWidth: itemWidth)
                    }
                    .onMove { source, destination in move(items, from: source, to: destination) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(items.count) * RightClickMenuLayout.rowHeight)
            }
        }
        .rightClickMenuCard()
    }

    private func mainMenuItemColumnWidth(_ items: [RightClickMenuItem]) -> CGFloat {
        var plain: [CGFloat] = []
        var groups: [CGFloat] = []
        for item in items {
            let width = Self.textWidth(itemTitle(item), size: RightClickMenuLayout.bodyFontSize)
            if case .group = item { groups.append(width) } else { plain.append(width) }
        }
        return RightClickMenuLayout.itemColumnWidth(
            plainTitleWidths: plain,
            groupTitleWidths: groups,
            headingWidth: Self.textWidth(String(localized: "Item"), size: RightClickMenuLayout.calloutFontSize))
    }

    private func mainMenuRow(_ item: RightClickMenuItem, at index: Int, in items: [RightClickMenuItem], itemWidth: CGFloat) -> some View {
        let contents = itemContents(item)
        var anchor = ""
        if case .group(let group) = item { anchor = "rcm.\(group.rawValue)" }
        return HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: RightClickMenuLayout.handleColumn, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: RightClickMenuLayout.columnSpacing) {
                HStack(spacing: RightClickMenuLayout.iconGap) {
                    itemIcon(item)
                    Text(itemTitle(item))
                        .lineLimit(1)
                        .help(itemTitle(item))
                    if case .group = item {
                        Image(systemName: "chevron.forward")
                            .font(.callout)
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: itemWidth, alignment: .leading)
                Text(contents)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(contents)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(RightClickMenuShowsOn(item).title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.showsOnColumnWidth, alignment: .leading)
            }
        }
        .padding(.horizontal, RightClickMenuLayout.inset)
        .frame(height: RightClickMenuLayout.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Move Up") { move(items, from: IndexSet(integer: index), to: index - 1) }
                .disabled(index == 0)
            Button("Move Down") { move(items, from: IndexSet(integer: index), to: index + 2) }
                .disabled(index == items.count - 1)
        }
        .rightClickMenuListRow(index)
        .searchAnchor(anchor)
    }

    @ViewBuilder
    private func itemIcon(_ item: RightClickMenuItem) -> some View {
        switch item {
        case .application(_, let identifier):
            Image(nsImage: RightClickMenuApplication.resolve(identifier)?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable()
                .frame(width: RightClickMenuLayout.iconSize, height: RightClickMenuLayout.iconSize)
                .accessibilityHidden(true)
        case .group(let group):
            symbol(group.symbolName)
        case .action(let action):
            symbol(action.symbolName)
        case .file:
            symbol(RightClickMenuGroup.newFile.symbolName)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: RightClickMenuLayout.iconSize, height: RightClickMenuLayout.iconSize)
            .accessibilityHidden(true)
    }

    private func itemTitle(_ item: RightClickMenuItem) -> String {
        switch item {
        case .group(let group): return group.title
        case .action(let action): return action.title
        case .file(let file): return file.name
        case .application(let list, let identifier): return list.itemTitle(applicationName(identifier))
        }
    }

    private func applicationName(_ identifier: String) -> String {
        RightClickMenuApplication.resolve(identifier)?.displayName ?? identifier
    }

    private func itemContents(_ item: RightClickMenuItem) -> String {
        guard case .group(let group) = item else { return "" }
        return manager.settings.submenuItems(of: group, isAvailable: Self.hasApplication).map { child in
            switch child {
            case .file(let type): return type.name
            case .application(_, let identifier): return applicationName(identifier)
            case .group, .action: return ""
            }
        }
        .joined(separator: ", ")
    }

    private func move(_ items: [RightClickMenuItem], from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        save { try manager.change { $0.setMenuOrder(reordered, isAvailable: Self.hasApplication) } }
    }

    static func stripe(_ index: Int) -> Color {
        index.isMultiple(of: 2) ? .clear : .quaternaryFill
    }

    private var actionsList: some View {
        VStack(spacing: 0) {
            ForEach(RightClickMenuSwitch.allCases, id: \.self) { action in
                if action != RightClickMenuSwitch.allCases.first {
                    Divider()
                        .padding(.horizontal, RightClickMenuLayout.inset)
                }
                HStack(spacing: 12) {
                    Image(systemName: action.symbolName)
                        .frame(width: 28, height: 28)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.title)
                        Text(RightClickMenuShowsOn(.action(action)).caption)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Toggle(action.title, isOn: itemBinding(action.keyPath))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                .padding(.horizontal, RightClickMenuLayout.inset)
                .frame(height: RightClickMenuLayout.twoLineRowHeight)
                .searchAnchor("rcm.\(action.rawValue)")
            }
        }
        .rightClickMenuCard()
    }

    private var newFileTable: some View {
        let files = manager.settings.files
        return VStack(spacing: 0) {
            optionsHeading("File Type")
            Divider()
            List(selection: $selectedFile) {
                ForEach(Array(files.enumerated()), id: \.element) { index, file in
                    HStack(spacing: 0) {
                        Text(verbatim: file.rowTitle)
                            .lineLimit(1)
                            .help(file.rowTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        rowOptions(enabled: fileBinding(file, \.enabled), addToMainMenu: fileBinding(file, \.addToMainMenu), submenu: .newFile)
                    }
                    .padding(.horizontal, RightClickMenuLayout.inset)
                    .frame(height: RightClickMenuLayout.rowHeight)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Edit…") { editFile(file.key) }
                        Button("Delete") { deletingFile = file }
                    }
                    .tag(file)
                    .rightClickMenuListRow(index)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(files.count) * RightClickMenuLayout.rowHeight)
            Divider()
            addRemoveBar(add: "Add File Type…", remove: "Remove File Type", canAdd: files.count < RightClickMenuSettings.maximumFileTypes,
                         canRemove: selectedFile.map(manager.settings.files.contains) ?? false) {
                editedFile = nil
                draftMenuName = ""
                draftName = ""
                draftExtension = ""
                addingFile = true
            } onRemove: {
                deletingFile = selectedFile
            }
        }
        .rightClickMenuCard()
        .sheet(isPresented: $addingFile) { addFileSheet }
        .alert("Are you sure you want to delete “\(deletingFile?.name ?? "")”?",
               isPresented: Binding(get: { deletingFile != nil }, set: { if !$0 { deletingFile = nil } })) {
            Button("Delete", role: .destructive) {
                if let deletingFile { removeFile(deletingFile.key) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func editFile(_ id: String) {
        guard let file = manager.settings.addedFiles.first(where: { $0.id == id }) else { return }
        editedFile = id
        draftMenuName = file.menuName
        draftName = file.name
        draftExtension = file.fileExtension
        addingFile = true
    }

    private func removeFile(_ id: String) {
        if save({ try manager.change { $0.addedFiles.removeAll { $0.id == id } } }), selectedFile?.key == id {
            selectedFile = nil
        }
    }

    private var addFileSheet: some View {
        let added: RightClickMenuAddedFile?, reason: String?
        switch manager.settings.addedFile(menuName: draftMenuName, name: draftName, fileExtension: draftExtension, replacing: editedFile) {
        case .success(let file): (added, reason) = (file, nil)
        case .failure(let problem): (added, reason) = (nil, problem.reason)
        }
        return VStack(alignment: .leading, spacing: 16) {
            Text(editedFile == nil ? "Add File Type" : "Edit File Type")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("Menu Name")
                        .gridColumnAlignment(.trailing)
                    TextField("Menu Name", text: $draftMenuName, prompt: Text(verbatim: "Swift File"))
                        .labelsHidden()
                }
                GridRow {
                    Text("File Name")
                    TextField("File Name", text: $draftName, prompt: Text(verbatim: "hello"))
                        .labelsHidden()
                }
                GridRow {
                    Text("Extension")
                    TextField("Extension", text: $draftExtension, prompt: Text(verbatim: "swift"))
                        .labelsHidden()
                }
            }
            if let reason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { addingFile = false }
                    .keyboardShortcut(.cancelAction)
                Button(editedFile == nil ? "Add" : "Save") {
                    guard let added else { return }
                    addingFile = false
                    if save({
                        try manager.change {
                            if let editedFile {
                                try $0.editFile(editedFile, menuName: added.menuName, name: added.name, fileExtension: added.fileExtension)
                            } else {
                                try $0.addFile(menuName: added.menuName, name: added.name, fileExtension: added.fileExtension)
                            }
                        }
                    }) {
                        selectedFile = added.file
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(added == nil)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func appList(_ list: RightClickMenuAppList) -> some View {
        let rows = manager.settings[keyPath: list.keyPath]
        return VStack(spacing: 0) {
            optionsHeading("App", leadingIndent: RightClickMenuLayout.iconColumn)
            Divider()
            if !rows.isEmpty {
                List(selection: $selectedApplication) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        let application = RightClickMenuApplication.resolve(row.bundleIdentifier)
                        HStack(spacing: RightClickMenuLayout.iconGap) {
                            Image(nsImage: application?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                                .resizable()
                                .frame(width: RightClickMenuLayout.iconSize, height: RightClickMenuLayout.iconSize)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(application?.displayName ?? row.bundleIdentifier)
                                    .lineLimit(1)
                                    .help(application?.displayName ?? row.bundleIdentifier)
                                if application == nil {
                                    Text("The chosen app is not installed.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            rowOptions(enabled: appBinding(list, row.id, \.enabled), addToMainMenu: appBinding(list, row.id, \.addToMainMenu), submenu: list.group)
                        }
                        .padding(.horizontal, RightClickMenuLayout.inset)
                        .frame(height: application == nil ? RightClickMenuLayout.twoLineRowHeight : RightClickMenuLayout.rowHeight)
                        .tag(row.id)
                        .rightClickMenuListRow(index)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: appListHeight(rows))
            }
            Divider()
            addRemoveBar(add: "Add App…", remove: "Remove App",
                         canRemove: manager.settings[keyPath: list.keyPath].contains { $0.id == selectedApplication }) {
                presentAppPicker(for: list)
            } onRemove: {
                guard let selectedApplication else { return }
                if save({ try manager.change({ $0[keyPath: list.keyPath].removeAll { $0.id == selectedApplication } }) }) {
                    self.selectedApplication = nil
                }
            }
        }
        .rightClickMenuCard()
    }

    private func addRemoveBar(add: LocalizedStringKey, remove: LocalizedStringKey, canAdd: Bool = true, canRemove: Bool,
                              onAdd: @escaping () -> Void, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .frame(width: 24, height: 22)
            }
            .accessibilityLabel(add)
            .help(add)
            .disabled(!canAdd)
            Divider()
                .frame(height: 14)
            Button(action: onRemove) {
                Image(systemName: "minus")
                    .frame(width: 24, height: 22)
            }
            .accessibilityLabel(remove)
            .help(remove)
            .disabled(!canRemove)
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .frame(height: RightClickMenuLayout.rowHeight)
    }

    private func appListHeight(_ rows: [RightClickMenuAppRow]) -> CGFloat {
        rows.reduce(0) { height, row in
            height + (RightClickMenuApplication.resolve(row.bundleIdentifier) == nil ? RightClickMenuLayout.twoLineRowHeight : RightClickMenuLayout.rowHeight)
        }
    }

    private func optionsHeading(_ title: LocalizedStringKey, leadingIndent: CGFloat = 0) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .padding(.leading, leadingIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: RightClickMenuLayout.columnSpacing) {
                Text("Enable")
                    .frame(width: Self.enableColumnWidth)
                Text("Show in")
                    .frame(width: Self.showInColumnWidth, alignment: .leading)
            }
        }
        .rightClickMenuHeading()
    }

    private func rowOptions(enabled: Binding<Bool>, addToMainMenu: Binding<Bool>, submenu: RightClickMenuGroup) -> some View {
        HStack(spacing: RightClickMenuLayout.columnSpacing) {
            Toggle("Enable", isOn: enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .frame(width: Self.enableColumnWidth)
            Picker("Show in", selection: addToMainMenu) {
                Text(RightClickMenuTab.mainMenu.title).tag(true)
                Text(submenu.title).tag(false)
            }
            .pickerStyle(.menu)
            .disabled(!enabled.wrappedValue)
            .frame(width: Self.showInColumnWidth, alignment: .leading)
        }
        .labelsHidden()
    }

    private func fileBinding(_ file: RightClickMenuFile, _ field: WritableKeyPath<RightClickMenuRowOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { manager.settings[file: file][keyPath: field] },
            set: { value in save { try manager.change { $0[file: file][keyPath: field] = value } } }
        )
    }

    private func appBinding(_ list: RightClickMenuAppList, _ identifier: String, _ field: WritableKeyPath<RightClickMenuAppRow, Bool>) -> Binding<Bool> {
        Binding(
            get: { manager.settings[keyPath: list.keyPath].first { $0.id == identifier }?[keyPath: field] ?? false },
            set: { value in
                save {
                    try manager.change { settings in
                        guard let index = settings[keyPath: list.keyPath].firstIndex(where: { $0.id == identifier }) else { return }
                        settings[keyPath: list.keyPath][index][keyPath: field] = value
                    }
                }
            }
        )
    }

    private func itemBinding(_ keyPath: WritableKeyPath<RightClickMenuSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { manager.settings[keyPath: keyPath] },
            set: { value in save { try manager.update(keyPath, to: value) } }
        )
    }

    nonisolated private static func hasApplication(_ bundleIdentifier: String) -> Bool {
        RightClickMenuApplication.resolve(bundleIdentifier) != nil
    }

    @discardableResult
    private func save(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func presentAppPicker(for list: RightClickMenuAppList) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let application = RightClickMenuApplication(url: url) else { return }
        if save({ try manager.change({ try $0.addApplication(application.bundleIdentifier, to: list) }) }) {
            selectedApplication = application.bundleIdentifier
        }
    }

    private func toggle() {
        requestTask = AccessWindowController.tapRightClickMenu(save: { save($0) }) ?? requestTask
    }
}

extension AccessWindowController {
    @discardableResult
    static func tapRightClickMenu(save: (() throws -> Void) -> Void) -> Task<Void, Never>? {
        let manager = FinderExtensionManager.shared
        switch RightClickMenuState.toggleAction(settings: manager.settings, election: manager.election) {
        case .enable:
            save { try manager.setEnabled(true) }
        case .disable:
            save { try manager.setEnabled(false) }
        case .requestAccess:
            return Task {
                await manager.prepareAccessRequest()
                guard !Task.isCancelled else { return }
                AccessWindowController.rightClickMenu.present()
            }
        }
        return nil
    }
}
