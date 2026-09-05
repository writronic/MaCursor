import SwiftUI
import UniformTypeIdentifiers

struct CursorEditorView: View {
    @ObservedObject var cursor: CursorModel
    var usedIdentifiers: Set<String> = []
    var onDirty: (() -> Void)? = nil
    var onReplaceSource: ((URL) -> Bool)? = nil
    var onClearSlot: (() -> Void)? = nil

    private var availableIdentifiers: [(identifier: String, name: String)] {
        CursorIdentifier.allIdentifiers.filter {
            $0.identifier == cursor.identifier || !usedIdentifiers.contains($0.identifier)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Section {
                    Picker("Cursor Type:", selection: $cursor.identifier) {
                        ForEach(availableIdentifiers, id: \.identifier) { entry in
                            Text(entry.name).tag(entry.identifier)
                        }
                    }
                    .onChangeCompat(of: cursor.identifier) { _ in onDirty?() }
                }

                Divider()

                Section("Animation") {
                    HStack(spacing: 16) {
                        LabeledContent("Frame Count:") {
                            NumericTextField(value: Binding(
                                get: { Double(cursor.frameCount) },
                                set: { cursor.applyFrameCount(NumericFieldValue.integer(from: $0)) }
                            ), fractionDigits: 0)
                                .frame(width: 60)
                                .onChangeCompat(of: cursor.frameCount) { _ in onDirty?() }
                        }

                        LabeledContent("Frame Duration:") {
                            NumericTextField(
                                value: $cursor.frameDuration,
                                fractionDigits: ThemeFieldLimits.frameDurationFractionDigits)
                                .frame(width: 80)
                                .onChangeCompat(of: cursor.frameDuration) { _ in onDirty?() }
                            Text("sec")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                Section("Representations") {
                    HStack(spacing: 16) {
                        RepresentationDropZone(cursor: cursor, scale: 100, label: "1×", onDirty: onDirty)
                        RepresentationDropZone(cursor: cursor, scale: 200, label: "2×", onDirty: onDirty)
                        RepresentationDropZone(cursor: cursor, scale: 500, label: "5×", onDirty: onDirty)
                        RepresentationDropZone(cursor: cursor, scale: 1000, label: "10×", onDirty: onDirty)
                    }
                }

                Divider()

                Section("Hot Spot") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            LabeledContent("X:") {
                                TextField("", value: Binding(
                                    get: { Double(cursor.hotSpot.x) },
                                    set: { cursor.hotSpot.x = CGFloat($0); onDirty?() }
                                ), format: .number.precision(.fractionLength(1)))
                                    .frame(width: 60)
                                    .textFieldStyle(.roundedBorder)
                            }

                            LabeledContent("Y:") {
                                TextField("", value: Binding(
                                    get: { Double(cursor.hotSpot.y) },
                                    set: { cursor.hotSpot.y = CGFloat($0); onDirty?() }
                                ), format: .number.precision(.fractionLength(1)))
                                    .frame(width: 60)
                                    .textFieldStyle(.roundedBorder)
                            }

                            LabeledContent("Size:") {
                                Text("\(Int(cursor.size.width)) × \(Int(cursor.size.height))")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HotspotEditorView(cursor: cursor, onDirty: onDirty)
                    }
                }

                Divider()

                Section("Preview") {
                    CursorTryAreaView(cursor: cursor)
                }

                if onReplaceSource != nil || onClearSlot != nil {
                    actionBar
                }
            }
            .padding()
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
                    if panel.runModal() == .OK, let url = panel.url,
                       !onReplaceSource(url) {
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = NSLocalizedString(
                            "Could Not Replace Cursor",
                            comment: "Replace source failure alert title")
                        alert.informativeText = String(
                            format: NSLocalizedString(
                                "“%@” could not be read as a cursor or image file.",
                                comment: "Replace source failure alert message"),
                            url.lastPathComponent)
                        alert.runModal()
                    }
                }
            }
            if let onClearSlot {
                Button(NSLocalizedString("Clear Slot", comment: "Clear slot button"),
                       role: .destructive) {
                    onClearSlot()
                }
            }
            Spacer()
        }
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
                          let rep = nsImage.representations.first as? NSBitmapImageRep else { return }
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
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString(
            "Slot Sizes Out of Order",
            comment: "Slot order rejection alert title")
        alert.informativeText = String(
            format: NSLocalizedString(
                "Slot images must stay in size order (10× > 5× > 2× > 1×). This image does not fit the %1$@ slot because of the image in the %2$@ slot.",
                comment: "Slot order rejection alert message"),
            slotDisplayName(conflict.targetScale),
            slotDisplayName(conflict.conflictingScale))
        alert.runModal()
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
                NSLog("Rejected animated GIF drop: geometry or frame count conflicts with existing representations")
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
            NSLog("Failed to import dropped GIF data: \(error.localizedDescription)")
            return
        }
        guard let rep = NSBitmapImageRep(data: data) else { return }
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
                NSLog("Failed to import Windows cursor: \(error.localizedDescription)")
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
                NSLog("Failed to import GIF: \(error.localizedDescription)")
                return
            }
        }

        guard let nsImage = NSImage(contentsOf: url),
              let rep = nsImage.representations.first as? NSBitmapImageRep else { return }
        DispatchQueue.main.async {
            if let conflict = cursor.applyOrderedRepresentation(rep, forScale: scale) {
                presentSlotOrderAlert(conflict)
                return
            }
            onDirty?()
        }
    }
}
