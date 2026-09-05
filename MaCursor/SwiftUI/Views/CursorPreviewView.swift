import SwiftUI

struct CursorPreviewView: View {
    @ObservedObject var cursor: CursorModel
    var showHotSpot: Bool = true
    var scale: Int = 200
    var showCheckerboard: Bool = true

    @State private var currentFrame: Int = 0
    @State private var animationTimer: Timer?

    private var isAnimated: Bool {
        cursor.frameCount > 1
    }

    var body: some View {
        ZStack {
            if showCheckerboard {
                checkerboardBackground
            }

            if let frameImage = cursor.frame(at: currentFrame, scale: scale) {
                Image(nsImage: frameImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if scale != 100, let frameImage = cursor.frame(at: currentFrame, scale: 100) {
                Image(nsImage: frameImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let primaryImage = cursor.primaryImage {
                Image(nsImage: primaryImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "cursorarrow.square")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }

            if showHotSpot, cursor.size.width > 0, cursor.size.height > 0 {
                GeometryReader { geo in
                    let xRatio = cursor.hotSpot.x / cursor.size.width
                    let yRatio = cursor.hotSpot.y / cursor.size.height

                    Circle()
                        .fill(.red.opacity(0.7))
                        .frame(width: 6, height: 6)
                        .position(
                            x: geo.size.width * xRatio,
                            y: geo.size.height * yRatio
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear {
            if isAnimated {
                startAnimation()
            }
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        .onChangeCompat(of: cursor.frameCount) { newCount in
            currentFrame = 0
            if newCount > 1 {
                startAnimation()
            } else {
                animationTimer?.invalidate()
                animationTimer = nil
            }
        }
        .onChangeCompat(of: cursor.frameDuration) { _ in
            if isAnimated {
                startAnimation()
            }
        }
    }

    private var checkerboardBackground: some View {
        Canvas { context, size in
            let cellSize: CGFloat = 8
            let rows = Int(size.height / cellSize) + 1
            let cols = Int(size.width / cellSize) + 1

            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color(white: 0.9) : Color(white: 0.75))
                    )
                }
            }
        }
    }

    private func startAnimation() {
        guard cursor.frameDuration > 0, cursor.frameCount > 1 else { return }
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: cursor.frameDuration, repeats: true) { _ in
            DispatchQueue.main.async {
                let fc = cursor.frameCount
                guard fc > 1 else { return }
                currentFrame = (currentFrame + 1) % fc
            }
        }
    }
}

struct CursorThumbnailView: View {
    @ObservedObject var cursor: CursorModel
    var size: CGFloat = 24

    private var thumbnailImage: NSImage? {
        if cursor.frameCount > 1 {
            return cursor.frame(at: 0, scale: 200) ?? cursor.frame(at: 0, scale: 100)
        }
        return cursor.primaryImage
    }

    var body: some View {
        ZStack {
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "cursorarrow")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size, alignment: .center)
        .clipped()
    }
}
