import SwiftUI
import UniformTypeIdentifiers

struct CursorEditorView: View {
    @Bindable var cursor: CursorModel
    var onDirty: (() -> Void)? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Section {
                    Picker("Cursor Type:", selection: $cursor.identifier) {
                        ForEach(CursorIdentifier.allIdentifiers, id: \.identifier) { entry in
                            Text(entry.name).tag(entry.identifier)
                        }
                    }
                    .onChange(of: cursor.identifier) { _, _ in onDirty?() }
                }
                
                Divider()
                
                Section("Animation") {
                    HStack(spacing: 16) {
                        LabeledContent("Frame Count:") {
                            TextField("", value: $cursor.frameCount, format: .number)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: cursor.frameCount) { _, _ in onDirty?() }
                        }
                        
                        LabeledContent("Frame Duration:") {
                            TextField("", value: $cursor.frameDuration, format: .number.precision(.fractionLength(2)))
                                .frame(width: 80)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: cursor.frameDuration) { _, _ in onDirty?() }
                            Text("sec")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Divider()
                
                Section("Hot Spot") {
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
                
                Section("Preview") {
                    CursorPreviewView(cursor: cursor)
                        .frame(width: 128, height: 128)
                        .border(Color.secondary.opacity(0.2))
                }
            }
            .padding()
        }
    }
}

struct RepresentationDropZone: View {
    let cursor: CursorModel
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
                    
                    if let image = cursor.image(forScale: scale) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .padding(4)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Drop")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                
                if cursor.image(forScale: scale) != nil {
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
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let nsImage = image as? NSImage,
                          let rep = nsImage.representations.first as? NSBitmapImageRep else { return }
                    DispatchQueue.main.async {
                        cursor.setRepresentation(rep, forScale: scale)
                        onDirty?()
                    }
                }
                return true
            }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    
                    let ext = url.pathExtension.lowercased()
                    
                    if ext == "cur" || ext == "ani" {
                        do {
                            let result = try WindowsCursorImporter.parseForRepresentation(from: url)
                            DispatchQueue.main.async {
                                if result.frameCount > 1 {
                                    cursor.frameCount = result.frameCount
                                    cursor.frameDuration = result.frameDuration
                                }
                                cursor.setRepresentation(result.image, forScale: scale)
                                cursor.hotSpot = result.hotspot
                                onDirty?()
                            }
                        } catch {
                            NSLog("Failed to import Windows cursor: \(error.localizedDescription)")
                        }
                    } else {
                        guard let nsImage = NSImage(contentsOf: url),
                              let rep = nsImage.representations.first as? NSBitmapImageRep else { return }
                        DispatchQueue.main.async {
                            cursor.setRepresentation(rep, forScale: scale)
                            onDirty?()
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}
