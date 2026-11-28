import SwiftUI
import UniformTypeIdentifiers

enum CursorSourceAlert {
    @MainActor
    static func present(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    static func reportUnusable(_ message: String) {
        DispatchQueue.main.async {
            present(title: NSLocalizedString(
                        "Could Not Use File",
                        comment: "Alert title when a chosen or dropped file cannot become a cursor or slot image"),
                    message: message)
        }
    }

    static func reportUnreadable(fileName: String?, error: Error?) {
        reportUnusable(unreadableMessage(fileName: fileName, error: error))
    }

    static func unreadableMessage(fileName: String?, error: Error?) -> String {
        let detail = (error as? LocalizedError)?.errorDescription
        guard let fileName else { return detail ?? "" }
        let sentence = String(
            format: NSLocalizedString(
                "“%@” could not be read as a cursor or image file.",
                comment: "Replace source failure alert message"),
            fileName)
        return [sentence, detail].compactMap { $0 }.joined(separator: "\n\n")
    }
}

struct CursorEditorView: View {
    @ObservedObject var cursor: CursorModel
    var usedIdentifiers: Set<String> = []
    var onDirty: (() -> Void)? = nil
    var onReplaceSource: ((URL) throws -> Void)? = nil
    var onClearSlot: (() -> Void)? = nil

    @State private var confirmingClear = false

    private var availableIdentifiers: [(identifier: String, name: String)] {
        CursorIdentifier.allIdentifiers.filter {
            $0.identifier == cursor.identifier || !usedIdentifiers.contains($0.identifier)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox {
                    cell("Cursor Type") {
                        Picker("Cursor Type", selection: $cursor.identifier) {
                            ForEach(availableIdentifiers, id: \.identifier) { entry in
                                Text(entry.name).tag(entry.identifier)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChangeCompat(of: cursor.identifier) { _ in onDirty?() }
                    }
                }

                box("Representations") {
                    HStack(spacing: 0) {
                        RepresentationDropZone(cursor: cursor, scale: 100, label: "1×", onDirty: onDirty)
                            .frame(maxWidth: .infinity)
                        RepresentationDropZone(cursor: cursor, scale: 200, label: "2×", onDirty: onDirty)
                            .frame(maxWidth: .infinity)
                        RepresentationDropZone(cursor: cursor, scale: 500, label: "5×", onDirty: onDirty)
                            .frame(maxWidth: .infinity)
                        RepresentationDropZone(cursor: cursor, scale: 1000, label: "10×", onDirty: onDirty)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                }

                section("Animation and Hot Spot") {
                    HStack(spacing: 10) {
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                GroupBox {
                                    cell("X") {
                                        NumericTextField(value: Binding(
                                            get: { Double(cursor.hotSpot.x) },
                                            set: { cursor.hotSpot.x = CGFloat($0); onDirty?() }
                                        ), fractionDigits: 1)
                                            .frame(width: 50)
                                    }
                                }
                                GroupBox {
                                    cell("Y") {
                                        NumericTextField(value: Binding(
                                            get: { Double(cursor.hotSpot.y) },
                                            set: { cursor.hotSpot.y = CGFloat($0); onDirty?() }
                                        ), fractionDigits: 1)
                                            .frame(width: 50)
                                    }
                                }
                            }
                            HStack(spacing: 10) {
                                GroupBox {
                                    cell("Frame Count") {
                                        NumericTextField(value: Binding(
                                            get: { Double(cursor.frameCount) },
                                            set: { cursor.applyFrameCount(NumericFieldValue.integer(from: $0)) }
                                        ), fractionDigits: 0)
                                            .frame(width: 50)
                                            .onChangeCompat(of: cursor.frameCount) { _ in onDirty?() }
                                    }
                                }
                                GroupBox {
                                    cell("Frame Duration") {
                                        NumericTextField(
                                            value: $cursor.frameDuration,
                                            fractionDigits: ThemeFieldLimits.frameDurationFractionDigits)
                                            .frame(width: 50)
                                            .onChangeCompat(of: cursor.frameDuration) { _ in onDirty?() }
                                        Text("sec")
                                            .foregroundStyle(.secondary)
                                            .fixedSize()
                                    }
                                }
                            }
                            GroupBox {
                                cell("Size") {
                                    Text("\(Int(cursor.size.width)) × \(Int(cursor.size.height))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        HotspotEditorView(cursor: cursor, onDirty: onDirty)
                    }
                }

                box("Preview") {
                    VStack(alignment: .leading, spacing: 6) {
                        CursorTryAreaView(cursor: cursor)
                        Text(NSLocalizedString("Hover to try the cursor — click to check the hotspot",
                                               comment: "Try area hint"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if onReplaceSource != nil || onClearSlot != nil {
                    GroupBox { actionBar }
                }
            }
            .groupBoxStyle(PaneBoxStyle())
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .alert("Clear This Slot?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button(NSLocalizedString("Clear Slot", comment: "Clear slot button"), role: .destructive) {
                onClearSlot?()
            }
        } message: {
            Text("The cursor in this slot is removed from the theme when you save.")
        }
    }

    private var actionBar: some View {
        HStack {
            if let onReplaceSource {
                Button(NSLocalizedString("Replace Source…",
                                         comment: "Replace cursor source button")) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.message = NSLocalizedString(
                        "Choose a cursor or image file (.cur, .ani, Xcursor, .png, .gif)",
                        comment: "Choose source panel message")
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            try onReplaceSource(url)
                        } catch {
                            CursorSourceAlert.present(
                                title: NSLocalizedString(
                                    "Could Not Replace Cursor",
                                    comment: "Replace source failure alert title"),
                                message: CursorSourceAlert.unreadableMessage(
                                    fileName: url.lastPathComponent, error: error))
                        }
                    }
                }
            }
            Spacer()
            if onClearSlot != nil {
                Button(role: .destructive) {
                    confirmingClear = true
                } label: {
                    Text(NSLocalizedString("Clear Slot", comment: "Clear slot button"))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func box<Content: View>(_ title: LocalizedStringKey,
                                    @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            content()
        } label: {
            Text(title)
                .fontWeight(.semibold)
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .fontWeight(.semibold)
                .font(.subheadline)
                .padding(.leading, 10)
            content()
        }
    }

    private func cell<Content: View>(_ title: LocalizedStringKey,
                                     @ViewBuilder content: () -> Content) -> some View {
        LabeledContent {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                content()
            }
        } label: {
            Text(title)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PaneBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            configuration.label
                .font(.subheadline)
                .padding(.leading, 10)
            configuration.content
                .padding(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.editThemeLine, lineWidth: 0.5))
        }
    }
}

extension Color {
    static let editThemeLine = editThemeGrey(light: 229, dark: 46)
    static let editThemeTile = editThemeGrey(light: 243, dark: 44)

    private static func editThemeGrey(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let shade = (appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light) / 255
            return NSColor(srgbRed: shade, green: shade, blue: shade, alpha: 1)
        })
    }
}

struct RepresentationDropZone: View {
    @ObservedObject var cursor: CursorModel
    let scale: Int
    let label: String
    var onDirty: (() -> Void)? = nil

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                        )

                    if let image = cursor.thumbnailImage(forScale: scale) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .padding(4)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Drop")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if cursor.thumbnailImage(forScale: scale) != nil {
                    Button {
                        removeRepresentation()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .help("Remove \(label) representation")
                }
            }
            .frame(width: 80, height: 80)
            .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
        }
    }

    private func removeRepresentation() {
        cursor.removeRepresentation(forScale: scale)
        onDirty?()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSURL.self) {
                _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                    guard let nsurl = object as? NSURL else { return }
                    handleFileDrop(SlotImageImporter.normalizedFileURL(nsurl as URL))
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.gif.identifier) { data, _ in
                    guard let data else { return }
                    handleImageDataDrop(data)
                }
                return true
            }

            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let nsImage = image as? NSImage,
                          let rep = nsImage.representations.first as? NSBitmapImageRep else {
                        CursorSourceAlert.reportUnreadable(fileName: nil, error: nil)
                        return
                    }
                    DispatchQueue.main.async {
                        if let conflict = cursor.applyOrderedRepresentation(rep, forScale: scale) {
                            presentSlotOrderAlert(conflict)
                            return
                        }
                        onDirty?()
                    }
                }
                return true
            }
        }
        return false
    }

    private func slotDisplayName(_ scale: Int) -> String {
        "\(scale / 100)×"
    }

    private func presentSlotOrderAlert(_ conflict: CursorModel.SlotOrderConflict) {
        CursorSourceAlert.present(
            title: NSLocalizedString(
                "Slot Sizes Out of Order",
                comment: "Slot order rejection alert title"),
            message: String(
                format: NSLocalizedString(
                    "Slot images must stay in size order (10× > 5× > 2× > 1×). This image does not fit the %1$@ slot because of the image in the %2$@ slot.",
                    comment: "Slot order rejection alert message"),
                slotDisplayName(conflict.targetScale),
                slotDisplayName(conflict.conflictingScale)))
    }

    private func applyAnimatedImport(_ animated: SlotImageImporter.AnimatedImport) {
        DispatchQueue.main.async {
            if let conflict = cursor.slotOrderConflict(
                pixelsWide: animated.spriteSheet.pixelsWide,
                pixelsHigh: animated.spriteSheet.pixelsHigh,
                frameCount: animated.frameCount,
                targetScale: scale) {
                presentSlotOrderAlert(conflict)
                return
            }
            guard cursor.canAcceptAnimatedRepresentation(
                frameCount: animated.frameCount,
                pixelsWide: animated.spriteSheet.pixelsWide,
                pixelsHigh: animated.spriteSheet.pixelsHigh,
                replacingScale: scale) else {
                CursorSourceAlert.reportUnusable(NSLocalizedString(
                    "This animation does not match the other slots of this cursor. Every slot needs the same number of frames and the same proportions.",
                    comment: "Alert message when an animated GIF dropped on a slot has a different frame count or shape than the cursor's other slots"))
                return
            }
            if cursor.applyOrderedRepresentation(
                animated.spriteSheet,
                forScale: scale,
                frameCount: animated.frameCount,
                frameDuration: animated.frameDuration) != nil {
                return
            }
            onDirty?()
        }
    }

    private func handleImageDataDrop(_ data: Data) {
        do {
            if let animated = try SlotImageImporter.importAnimatedGIF(from: data) {
                applyAnimatedImport(animated)
                return
            }
        } catch {
            CursorSourceAlert.reportUnreadable(fileName: nil, error: error)
            return
        }
        guard let rep = NSBitmapImageRep(data: data) else {
            CursorSourceAlert.reportUnreadable(fileName: nil, error: nil)
            return
        }
        DispatchQueue.main.async {
            if let conflict = cursor.applyOrderedRepresentation(rep, forScale: scale) {
                presentSlotOrderAlert(conflict)
                return
            }
            onDirty?()
        }
    }

    private func handleFileDrop(_ droppedURL: URL) {
        let url = SlotImageImporter.normalizedFileURL(droppedURL)
        let ext = url.pathExtension.lowercased()

        if ext == "cur" || ext == "ani" {
            do {
                let result = try WindowsCursorImporter.parseForRepresentation(from: url)
                DispatchQueue.main.async {
                    if let conflict = cursor.applyOrderedRepresentation(
                        result.image,
                        forScale: scale,
                        frameCount: result.frameCount > 1 ? result.frameCount : nil,
                        frameDuration: result.frameDuration) {
                        presentSlotOrderAlert(conflict)
                        return
                    }
                    let sourceWidth = CGFloat(result.image.pixelsWide)
                    let hotSpotScale = sourceWidth > 0 ? cursor.size.width / sourceWidth : 1
                    cursor.hotSpot = CGPoint(x: result.hotspot.x * hotSpotScale,
                                             y: result.hotspot.y * hotSpotScale)
                    onDirty?()
                }
            } catch {
                CursorSourceAlert.reportUnreadable(fileName: url.lastPathComponent, error: error)
            }
            return
        }

        if SlotImageImporter.isGIF(url) {
            do {
                if let animated = try SlotImageImporter.importAnimatedGIF(from: url) {
                    applyAnimatedImport(animated)
                    return
                }
            } catch {
                CursorSourceAlert.reportUnreadable(fileName: url.lastPathComponent, error: error)
                return
            }
        }

        guard let nsImage = NSImage(contentsOf: url),
              let rep = nsImage.representations.first as? NSBitmapImageRep else {
            CursorSourceAlert.reportUnreadable(fileName: url.lastPathComponent, error: nil)
            return
        }
        DispatchQueue.main.async {
            if let conflict = cursor.applyOrderedRepresentation(rep, forScale: scale) {
                presentSlotOrderAlert(conflict)
                return
            }
            onDirty?()
        }
    }
}
