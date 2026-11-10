import SwiftUI

extension View {
    func rightClickMenuCard() -> some View {
        background(Color.quaternaryFill, in: RoundedRectangle(cornerRadius: RightClickMenuLayout.cardRadius, style: .continuous))
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

final class EqualWhenFitsSegmentedControl: NSSegmentedControl {
    var widestLabel: CGFloat = 0

    override func layout() {
        let distribution: NSSegmentedControl.Distribution =
            RightClickMenuLayout.segmentsAreEqual(width: bounds.width, count: segmentCount, widestLabel: widestLabel) ? .fillEqually : .fill
        if segmentDistribution != distribution { segmentDistribution = distribution }
        super.layout()
    }
}

struct TabBar: NSViewRepresentable {
    let titles: [String]
    let label: String
    @Binding var selection: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> EqualWhenFitsSegmentedControl {
        let control = EqualWhenFitsSegmentedControl(labels: titles, trackingMode: .selectOne, target: context.coordinator,
                                                    action: #selector(Coordinator.changed(_:)))
        control.setAccessibilityLabel(label)
        control.widestLabel = titles.map { RightClickMenuSettingsView.textWidth($0, size: RightClickMenuLayout.bodyFontSize) }.max() ?? 0
        return control
    }

    func updateNSView(_ control: EqualWhenFitsSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.selectedSegment = selection
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: EqualWhenFitsSegmentedControl, context: Context) -> CGSize? {
        let ideal = nsView.fittingSize
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal.width
        return CGSize(width: width, height: ideal.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<Int>

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            selection.wrappedValue = sender.selectedSegment
        }
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
        GeometryReader { pane in
            let column = RightClickMenuLayout.tableWidth(contentWidth: pane.size.width - 2 * RightClickMenuLayout.pageMargin)
            ScrollView {
                VStack(alignment: .leading, spacing: RightClickMenuLayout.blockSpacing) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Right-Click Menu")
                            Text("Adds MaCursor’s shortcuts to the right-click menu in Finder and on the Desktop.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Toggle("Right-Click Menu", isOn: Binding(
                            get: { isOn },
                            set: { _ in toggle() }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .disabled(manager.isBusy || (manager.isTranslocated && !isOn))
                    }
                    .padding(RightClickMenuLayout.inset)
                    .frame(minHeight: RightClickMenuLayout.twoLineRowHeight)
                    .rightClickMenuCard()

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
                        .padding(.horizontal, RightClickMenuLayout.inset)
                    }

                    if RightClickMenuState.showsItems(settings: manager.settings, election: manager.election) {
                        TabBar(
                            titles: RightClickMenuTab.allCases.map(\.title),
                            label: String(localized: "Right-Click Menu"),
                            selection: Binding(
                                get: { RightClickMenuTab.allCases.firstIndex(of: manager.selectedTab) ?? 0 },
                                set: { manager.selectedTab = RightClickMenuTab.allCases[$0] }
                            )
                        )
                        .frame(maxWidth: .infinity)

                        VStack(alignment: .leading, spacing: RightClickMenuLayout.blockSpacing) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manager.selectedTab.title)
                                    .fontWeight(.semibold)
                                Text(manager.selectedTab.note)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, RightClickMenuLayout.inset)

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
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, RightClickMenuLayout.inset)
                        }
                        .padding(.top, RightClickMenuLayout.headerSpacing - RightClickMenuLayout.blockSpacing)
                    }
                }
                .frame(width: column)
                .padding(.leading, (pane.size.width - column) / 2)
                .padding(.vertical, RightClickMenuLayout.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { manager.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cursorSettingsDidReset)) { _ in
            requestTask?.cancel()
            manager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: SettingsWindowController.shared.window)) { _ in
            errorMessage = nil
        }
        .onDisappear { requestTask?.cancel() }
        .onChangeCompat(of: manager.selectedTab) { _ in
            selectedApplication = nil
            errorMessage = nil
        }
        .onChangeCompat(of: manager.election) { _ in errorMessage = nil }
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
        case .file(let type): return type.itemTitle
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
            }
        }
        .rightClickMenuCard()
    }

    private var newFileTable: some View {
        VStack(spacing: 0) {
            optionsHeading("File Type")
            Divider()
            ForEach(Array(RightClickMenuFileType.allCases.enumerated()), id: \.element) { index, type in
                HStack(spacing: 0) {
                    Text(verbatim: "\(type.name) (.\(type.fileExtension))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    rowOptions(enabled: fileBinding(type, \.enabled), addToMainMenu: fileBinding(type, \.addToMainMenu), submenu: .newFile)
                }
                .padding(.horizontal, RightClickMenuLayout.inset)
                .frame(height: RightClickMenuLayout.rowHeight)
                .background(Self.stripe(index))
            }
        }
        .rightClickMenuCard()
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
            HStack(spacing: 0) {
                Button { presentAppPicker(for: list) } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .accessibilityLabel("Add App…")
                .help("Add App…")
                Divider()
                    .frame(height: 14)
                Button {
                    guard let selectedApplication else { return }
                    if save({ try manager.change({ $0[keyPath: list.keyPath].removeAll { $0.id == selectedApplication } }) }) {
                        self.selectedApplication = nil
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 22)
                }
                .accessibilityLabel("Remove App")
                .help("Remove App")
                .disabled(!manager.settings[keyPath: list.keyPath].contains { $0.id == selectedApplication })
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
            .frame(height: RightClickMenuLayout.rowHeight)
        }
        .rightClickMenuCard()
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

    private func fileBinding(_ type: RightClickMenuFileType, _ field: WritableKeyPath<RightClickMenuRowOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { manager.settings[keyPath: type.keyPath][keyPath: field] },
            set: { value in save { try manager.change { $0[keyPath: type.keyPath][keyPath: field] = value } } }
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
