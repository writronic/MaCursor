import AppKit
import SwiftUI

@MainActor
final class TryAreaCursorLoop {
    private static let staticReassertInterval = 0.1

    private var timer: Timer?
    private var startDate = Date()
    private var cursor: CursorModel?

    func start(cursor: CursorModel) {
        stopTimerOnly()
        self.cursor = cursor
        startDate = Date()
        advance()
    }

    func stop() {
        stopTimerOnly()
        guard cursor != nil else { return }
        cursor = nil
        NSCursor.arrow.set()
    }

    private func stopTimerOnly() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        guard let cursor else { return }
        let count = max(cursor.frameCount, 1)
        let interval = CursorTryAreaView.playbackInterval(frameDuration: cursor.frameDuration)
        let elapsed = Date().timeIntervalSince(startDate)
        let index = CursorTryAreaView.frameIndex(elapsed: elapsed, interval: interval,
                                                frameCount: count)
        if let image = cursor.previewFrame(at: index) {
            let hot = NSPoint(x: min(max(cursor.hotSpot.x, 0), cursor.size.width),
                              y: min(max(cursor.hotSpot.y, 0), cursor.size.height))
            NSCursor(image: image, hotSpot: hot).set()
        }
        let delay = count > 1 ? interval : Self.staticReassertInterval
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }
}

struct CursorTryAreaView: View {
    @ObservedObject var cursor: CursorModel

    @State private var loop = TryAreaCursorLoop()
    @State private var loopIdle = true
    @State private var clickPoint: CGPoint?
    @State private var clickFadeTask: Task<Void, Never>?

    private static let hoverLoopHandlesStaticCursors: Bool = {
        if #available(macOS 15, *) { return false }
        return true
    }()

    private var isAnimated: Bool { cursor.frameCount > 1 }

    private var loopShouldRun: Bool { isAnimated || Self.hoverLoopHandlesStaticCursors }

    @available(macOS 15, *)
    private var staticPointerStyle: PointerStyle? {
        guard !isAnimated,
              let image = cursor.previewFrame(at: 0) ?? cursor.primaryImage,
              cursor.size.width > 0, cursor.size.height > 0 else { return nil }
        return .image(Image(nsImage: image),
                      hotSpot: UnitPoint(x: min(max(cursor.hotSpot.x / cursor.size.width, 0), 1),
                                         y: min(max(cursor.hotSpot.y / cursor.size.height, 0), 1)))
    }

    private var tryArea: some View {
        ZStack {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(.white)
                    Rectangle().fill(.black)
                }
                if let clickPoint {
                    Bullseye().position(clickPoint)
                }
                Text(NSLocalizedString("Hover to try the cursor — click to check the hotspot",
                                       comment: "Try area hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .position(x: geo.size.width / 2, y: geo.size.height - 14)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    var body: some View {
        Group {
            if #available(macOS 15, *) {
                tryArea.pointerStyle(staticPointerStyle)
            } else {
                tryArea
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if loopShouldRun, loopIdle {
                    loopIdle = false
                    loop.start(cursor: cursor)
                }
            case .ended:
                loopIdle = true
                loop.stop()
            }
        }
        .onChangeCompat(of: cursor.frameCount) { _ in
            if !loopShouldRun, !loopIdle {
                loopIdle = true
                loop.stop()
            }
        }
        .gesture(
            SpatialTapGesture().onEnded { value in
                clickPoint = value.location
                clickFadeTask?.cancel()
                clickFadeTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { clickPoint = nil }
                }
            })
        .onDisappear {
            loopIdle = true
            loop.stop()
            clickFadeTask?.cancel()
        }
    }

    static func playbackInterval(frameDuration: Double) -> Double {
        max(frameDuration, 0.01)
    }

    static func frameIndex(elapsed: Double, interval: Double, frameCount: Int) -> Int {
        guard frameCount > 1, interval > 0, elapsed >= 0 else { return 0 }
        return Int(elapsed / interval) % frameCount
    }
}

private struct Bullseye: View {
    var body: some View {
        ZStack {
            Circle().fill(.blue.opacity(0.4)).frame(width: 40, height: 40)
            Circle().fill(.green.opacity(0.8)).frame(width: 16, height: 16)
            Circle().fill(.red).frame(width: 6, height: 6)
        }
    }
}
