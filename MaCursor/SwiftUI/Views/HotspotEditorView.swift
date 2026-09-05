import SwiftUI

struct HotspotEditorView: View {
    @ObservedObject var cursor: CursorModel
    var onDirty: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let image = displayImage
            let fitted = Self.fittedRect(imagePointSize: image?.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                CheckerboardTile()
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                }
                if cursor.size.width > 0, cursor.size.height > 0 {
                    HotspotMarker()
                        .position(x: fitted.minX + fitted.width * cursor.hotSpot.x / cursor.size.width,
                                  y: fitted.minY + fitted.height * cursor.hotSpot.y / cursor.size.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = Self.hotspotPoint(from: value.location,
                                                      fitted: fitted, size: cursor.size)
                        if point != cursor.hotSpot {
                            cursor.hotSpot = point
                            onDirty?()
                        }
                    })
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 256, maxHeight: 256)
    }

    private var displayImage: NSImage? {
        cursor.previewFrame(at: 0) ?? cursor.primaryImage
    }

    static func fittedRect(imagePointSize: CGSize?, in canvas: CGSize) -> CGRect {
        guard let size = imagePointSize, size.width > 0, size.height > 0,
              canvas.width > 0, canvas.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let scale = min(canvas.width / size.width, canvas.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: (canvas.width - fitted.width) / 2,
                      y: (canvas.height - fitted.height) / 2,
                      width: fitted.width, height: fitted.height)
    }

    static func hotspotPoint(from location: CGPoint, fitted: CGRect, size: CGSize) -> CGPoint {
        guard fitted.width > 0, fitted.height > 0, size.width > 0, size.height > 0 else {
            return .zero
        }
        let x = (location.x - fitted.minX) / fitted.width * size.width
        let y = (location.y - fitted.minY) / fitted.height * size.height
        return CGPoint(x: min(max(x, 0), max(size.width - 1, 0)),
                       y: min(max(y, 0), max(size.height - 1, 0)))
    }
}

struct HotspotMarker: View {
    var body: some View {
        ZStack {
            Circle().stroke(.black.opacity(0.6), lineWidth: 1.5).frame(width: 11, height: 11)
            Circle().fill(.red.opacity(0.55)).frame(width: 9, height: 9)
            Circle().fill(.blue).frame(width: 2.5, height: 2.5)
        }
    }
}

struct CheckerboardTile: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 8
            for row in 0..<Int(ceil(size.height / tile)) {
                for col in 0..<Int(ceil(size.width / tile)) where (row + col).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile,
                                             width: tile, height: tile)),
                                 with: .color(.gray.opacity(0.25)))
                }
            }
        }
        .background(.gray.opacity(0.1))
    }
}
