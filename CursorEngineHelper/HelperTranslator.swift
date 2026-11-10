import AppKit
import CoreMedia
import NaturalLanguage
@preconcurrency import ScreenCaptureKit
import SwiftUI
@preconcurrency import Translation
import VideoToolbox
@preconcurrency import Vision

@MainActor
final class CursorTranslatorController {
    private var config = CursorTranslatorConfig()
    private var trusted = false
    private var warmed = false
    private(set) var screenRecording = false
    private var screenProbe: Int32?
    private var frame: CursorTranslatorFrame?
    private var screens: [CGFloat] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init() {
        let centers: [(NotificationCenter, [Notification.Name])] = [
            (NSWorkspace.shared.notificationCenter, CursorShaker.workspacePauses.filter { $0.value.starts }.map(\.key)),
            (DistributedNotificationCenter.default(), CursorShaker.distributedPauses.filter { $0.value.starts }.map(\.key)),
        ]
        for (center, names) in centers {
            for name in names {
                observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.close() }
                }))
            }
        }
    }

    var wantsTrust: Bool { config.enabled }

    var trigger: CursorGestureTrigger? {
        trusted && screenRecording && CursorTranslatorConfig.isOn(enabled: config.enabled, usable: CursorTranslator.usable(config.trigger)) ? config.trigger : nil
    }

    func probeAhead() {
        guard wantsTrust, screenProbe == nil else { return }
        screenProbe = HelperTrustProbe.spawnScreenRecordingProbe()
    }

    func sync(trusted: Bool) {
        let ahead = screenProbe
        screenProbe = nil
        let latest = CursorTranslatorConfig.load()
        if !latest.readsTheSame(as: config) { close() }
        self.trusted = trusted
        config = latest
        if config.enabled, !warmed {
            warmed = true
            CursorTranslatorReader.warm()
        }
        frame?.restyle(latest.look)
        frame?.recolor(latest.color)
        frame?.retarget(latest.source, latest.resolvedTarget)
        if config.enabled { probe(ahead) } else if let ahead { _ = HelperTrustProbe.screenRecordingAllowed(ahead) }
        if trigger == nil { close() }
    }

    func configChanged() -> Bool {
        let latest = CursorTranslatorConfig.load()
        if latest != config && latest.readsTheSame(as: config) {
            config = latest
            frame?.restyle(latest.look)
            frame?.recolor(latest.color)
            frame?.retarget(latest.source, latest.resolvedTarget)
            return true
        }
        if !latest.enabled { probe() }
        frame?.retry()
        return false
    }

    func probe(_ ahead: Int32? = nil) {
        let allowed = HelperTrustProbe.screenRecordingAllowed(ahead ?? HelperTrustProbe.spawnScreenRecordingProbe())
        screenRecording = allowed
        CFPreferencesAppSynchronize(MACPreferences.domain)
        guard (MACPreferences.value(forKey: MACPreferences.cursorTranslatorScreenRecordingKey) as? NSNumber)?.boolValue != allowed else { return }
        MACPreferences.setFlag(allowed, forKey: MACPreferences.cursorTranslatorScreenRecordingKey)
        DistributedNotificationCenter.default().postNotificationName(.MACCursorTranslatorStatusDidChange, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    func received(_ note: CursorTranslatorNote) {
        guard trigger != nil else { return }
        let open = frame
        if config.mode == .follows {
            switch note {
            case .click(let point), .drawn(_, let point):
                if open != nil { return close() }
                show(CursorTranslator.clickFrame(at: point, size: CursorTranslator.followSize, in: Self.visible(at: point)), drawing: false)
            case .drawing:
                break
            }
            return
        }
        switch note {
        case .click(let point):
            if open != nil { return close() }
            show(CursorTranslator.clickFrame(at: point, in: Self.visible(at: point)), drawing: false)
        case .drawing(let start, let end):
            let rect = CursorTranslator.dragFrame(from: start, to: end, in: Self.visible(at: start))
            if let open, open.drawing { return open.draw(rect) }
            close()
            show(rect, drawing: true)
        case .drawn(let start, let end):
            let rect = CursorTranslator.dragFrame(from: start, to: end, in: Self.visible(at: start))
            guard let open, open.drawing else {
                close()
                return show(rect, drawing: false)
            }
            open.place(rect)
            open.start()
        }
    }

    func close() {
        guard let open = frame else { return }
        frame = nil
        open.close()
    }

    func stop() {
        close()
    }

    func displaysChanged() {
        guard Self.screenLayout == screens else { return close() }
        frame?.recapture()
    }

    static var screenLayout: [CGFloat] {
        NSScreen.screens.flatMap { [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height, $0.backingScaleFactor] }
    }

    private func show(_ rect: CGRect, drawing: Bool) {
        screens = Self.screenLayout
        let made = CursorTranslatorFrame(rect: rect, color: config.color, look: config.look, source: config.source, target: config.resolvedTarget, follows: config.mode == .follows,
                                         service: config.service, model: config.model(for: config.service), address: config.address(for: config.service),
                                         screenAllowed: { [weak self] in self?.screenRecording ?? false },
                                         onClose: { [weak self] in self?.close() })
        frame = made
        if !drawing { made.start() }
    }

    static func visible(at point: CGPoint) -> CGRect {
        CursorTranslator.visible(at: point, on: NSScreen.screens.map { ($0.frame, $0.visibleFrame) }) ?? CGRect(origin: .zero, size: CursorTranslator.clickSize)
    }
}

struct CursorTranslatorSpot: Sendable {
    let text: String
    let rect: CGRect
    let size: CGFloat
    let paper: UInt32
    let ink: UInt32
    let language: String?
}

struct CursorTranslatorBox: Identifiable {
    let id: String
    let text: String
    let rect: CGRect
    let cover: CGRect
    let size: CGFloat
    let spacing: CGFloat
    let paper: Color
    let ink: Color
    var delay: TimeInterval = 0
}

@MainActor
final class CursorTranslatorJob {
    let texts: [String]
    let arrived: @MainActor (Int, String, Bool) -> Void
    var reply: CheckedContinuation<[String]?, Never>?

    init(_ texts: [String], arrived: @escaping @MainActor (Int, String, Bool) -> Void) {
        self.texts = texts
        self.arrived = arrived
    }

    var waiting: Bool { reply != nil }

    func finish(_ value: [String]?) {
        reply?.resume(returning: value)
        reply = nil
    }
}

@available(macOS 15, *)
@MainActor
final class CursorTranslatorAppleSession: ObservableObject {
    @Published private(set) var configuration: TranslationSession.Configuration?
    private var stream: AsyncStream<CursorTranslatorJob>?
    private var jobs: AsyncStream<CursorTranslatorJob>.Continuation?
    private var pending: [CursorTranslatorJob] = []
    private var availability: [String: LanguageAvailability.Status] = [:]
    private var ended = false
    private var idle: (@MainActor () -> Void)?
    private(set) var serving = false
    private(set) var inFlight = false

    func check(_ page: String, _ target: String) async -> CursorTranslatorStatus? {
        let key = "\(page)>\(target)"
        let status: LanguageAvailability.Status
        if let known = availability[key] {
            status = known
        } else {
            status = await LanguageAvailability().status(from: Locale.Language(identifier: page), to: Locale.Language(identifier: target))
            availability[key] = status
        }
        switch status {
        case .installed:
            return nil
        case .supported:
            availability[key] = nil
            return .missingLanguage
        default:
            return .unavailable
        }
    }

    func use(_ source: String, _ target: String) async -> Bool {
        let wanted = TranslationSession.Configuration(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
        if configuration?.source == wanted.source, configuration?.target == wanted.target { return true }
        let until = ProcessInfo.processInfo.systemUptime + CursorTranslator.timeout
        while inFlight, !ended, ProcessInfo.processInfo.systemUptime < until { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard !inFlight, !ended else { return false }
        jobs?.finish()
        let (stream, jobs) = AsyncStream<CursorTranslatorJob>.makeStream()
        self.stream = stream
        self.jobs = jobs
        configuration = wanted
        return true
    }

    func serve(_ session: TranslationSession) async {
        guard let stream, !ended else { return }
        serving = true
        defer { serving = false }
        for await job in stream {
            guard !Task.isCancelled, !ended else { break }
            guard job.waiting else { continue }
            inFlight = true
            var texts = job.texts
            var failed = false
            do {
                for try await response in session.translate(batch: Self.requests(job.texts)) {
                    guard let id = response.clientIdentifier, let index = Int(id), texts.indices.contains(index) else { continue }
                    texts[index] = response.targetText
                    job.arrived(index, response.targetText, job.waiting)
                }
            } catch {
                failed = true
            }
            inFlight = false
            job.finish(failed ? nil : texts)
            if ended { break }
        }
        runIdle()
    }

    nonisolated static func requests(_ texts: [String]) -> sending [TranslationSession.Request] {
        texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: String($0)) }
    }

    func translate(_ texts: [String], arrived: @escaping @MainActor (Int, String, Bool) -> Void) async -> [String]? {
        guard let jobs, !ended else { return nil }
        let job = CursorTranslatorJob(texts, arrived: arrived)
        pending.append(job)
        let result = await withCheckedContinuation { reply in
            job.reply = reply
            jobs.yield(job)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                MainActor.assumeIsolated {
                    guard self?.serving != true else { return }
                    job.finish(nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + CursorTranslator.timeout) {
                MainActor.assumeIsolated { job.finish(nil) }
            }
        }
        pending.removeAll { $0 === job }
        return result
    }

    func end(then release: @escaping @MainActor () -> Void) {
        ended = true
        jobs?.finish()
        jobs = nil
        stream = nil
        pending.forEach { $0.finish(nil) }
        pending = []
        idle = release
        if !inFlight { runIdle() }
    }

    private func runIdle() {
        guard ended, !inFlight, let idle else { return }
        self.idle = nil
        idle()
    }
}

@available(macOS 15, *)
struct CursorTranslatorAppleHost: ViewModifier {
    @ObservedObject var session: CursorTranslatorAppleSession

    func body(content: Content) -> some View {
        content.translationTask(session.configuration) { translation in
            await session.serve(translation)
        }
    }
}

struct CursorTranslatorAppleTask: ViewModifier {
    let apple: AnyObject?

    func body(content: Content) -> some View {
        if #available(macOS 15, *), let session = apple as? CursorTranslatorAppleSession {
            return AnyView(content.modifier(CursorTranslatorAppleHost(session: session)))
        }
        return AnyView(content)
    }
}

@MainActor
final class CursorTranslatorFrameModel: ObservableObject {
    @Published var rect: CGRect
    @Published var boxes: [CursorTranslatorBox] = []
    @Published var direction: LayoutDirection
    let apple: AnyObject?
    private var next: TimeInterval = 0

    init(rect: CGRect, apple: AnyObject?, target: String) {
        self.rect = rect
        self.apple = apple
        direction = Self.direction(target)
    }

    func land(_ boxes: [CursorTranslatorBox]) {
        let shown = Dictionary(self.boxes.map { ($0.id, $0.delay) }, uniquingKeysWith: { first, _ in first })
        let now = ProcessInfo.processInfo.systemUptime
        var delays = CursorTranslator.reveal(boxes.filter { shown[$0.id] == nil }.count, after: next - now)[...]
        if let last = delays.last { next = now + last + CursorTranslator.revealStep }
        self.boxes = boxes.map { box in
            var box = box
            box.delay = shown[box.id] ?? delays.popFirst() ?? 0
            return box
        }
    }

    static func direction(_ target: String) -> LayoutDirection {
        Locale.Language(identifier: target).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }
}

struct CursorTranslatorFrameView: View {
    @ObservedObject var model: CursorTranslatorFrameModel

    private static func fade(_ box: CursorTranslatorBox, at rect: CGRect) -> AnyTransition {
        let grow: AnyTransition = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .opacity
            : .opacity.combined(with: .scale(scale: 0.98, anchor: UnitPoint(x: 0.5 + rect.minX / max(rect.width, 1), y: 0.5 + rect.minY / max(rect.height, 1))))
        return .asymmetric(insertion: grow.animation(.easeOut(duration: CursorTranslator.revealFade).delay(box.delay)),
                           removal: .opacity.animation(.linear(duration: 0.18)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.boxes) { box in
                let cover = CursorTranslator.local(box.cover, in: model.rect)
                box.paper
                    .frame(width: cover.width, height: cover.height)
                    .offset(x: cover.minX, y: cover.minY)
                    .transition(Self.fade(box, at: cover))
            }
            ForEach(model.boxes) { box in
                let spot = CursorTranslator.local(box.rect, in: model.rect)
                Text(verbatim: box.text)
                    .font(.system(size: box.size))
                    .lineSpacing(box.spacing)
                    .foregroundStyle(box.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: spot.width, height: spot.height, alignment: .topLeading)
                    .environment(\.layoutDirection, model.direction)
                    .clipped()
                    .offset(x: spot.minX, y: spot.minY)
                    .transition(Self.fade(box, at: spot))
            }
        }
        .frame(width: model.rect.width, height: model.rect.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: CursorTranslator.corner, style: .continuous))
        .modifier(CursorTranslatorAppleTask(apple: model.apple))
        .environment(\.layoutDirection, .leftToRight)
    }
}

final class CursorTranslatorBorder: NSView {
    private let ring = CALayer()
    private let holder = CALayer()
    private let turning = CAGradientLayer()

    init(color: CGColor, colors: [CGColor]) {
        super.init(frame: .zero)
        wantsLayer = true
        ring.borderWidth = CursorTranslator.border
        ring.borderColor = .black
        ring.cornerRadius = CursorTranslator.corner
        ring.cornerCurve = .continuous
        holder.mask = ring
        paint(color, colors)
        turning.type = .conic
        turning.startPoint = CGPoint(x: 0.5, y: 0.5)
        turning.endPoint = CGPoint(x: 0.5, y: 1)
        turning.opacity = 0
        holder.addSublayer(turning)
        layer?.addSublayer(holder)
    }

    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let side = hypot(newSize.width, newSize.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.frame = CGRect(origin: .zero, size: newSize)
        ring.frame = holder.bounds
        turning.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        turning.position = CGPoint(x: newSize.width / 2, y: newSize.height / 2)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 1
        for layer in [ring, holder, turning] { layer.contentsScale = scale }
    }

    func paint(_ color: CGColor, _ colors: [CGColor]) {
        holder.backgroundColor = color
        turning.colors = colors + colors.prefix(1)
    }

    func turn(_ on: Bool) {
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(!still)
        CATransaction.setAnimationDuration(0.2)
        turning.opacity = on ? 1 : 0
        CATransaction.commit()
        let turns = on && !still
        guard turns != (turning.animation(forKey: "turn") != nil) else { return }
        let angle = ((turning.presentation() ?? turning).value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        turning.setValue(angle, forKeyPath: "transform.rotation.z")
        turning.removeAnimation(forKey: "turn")
        CATransaction.commit()
        guard turns else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = angle
        spin.toValue = angle - 2 * Double.pi
        spin.duration = 4
        spin.repeatCount = .infinity
        spin.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
        turning.add(spin, forKey: "turn")
    }
}

final class CursorTranslatorHandle: NSView {
    var began: @MainActor () -> Void = {}
    var moved: @MainActor (CGSize) -> Void = { _ in }
    var ended: @MainActor () -> Void = {}
    var reach = CursorTranslator.dragReach
    private var start: CGPoint?
    private var pressed: NSPopUpButton?
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton && !(hit is NSPopUpButton) ? hit : self
    }

    override func mouseDown(with event: NSEvent) {
        start = event.cgEvent?.location
        pressed = super.hitTest(superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow) as? NSPopUpButton
        dragging = false
        began()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start, let now = event.cgEvent?.location else { return }
        let delta = CGSize(width: now.x - start.x, height: start.y - now.y)
        dragging = dragging || hypot(delta.width, delta.height) >= reach
        if dragging { moved(delta) }
    }

    override func mouseUp(with event: NSEvent) {
        start = nil
        if dragging { ended() } else { pressed?.performClick(nil) }
        pressed = nil
        dragging = false
    }
}

final class CursorTranslatorButton: NSButton {
    var pressed: @MainActor () -> Void = {}

    @objc func press() {
        pressed()
    }
}

final class CursorTranslatorMenuButton: NSPopUpButton {
    var picked: @MainActor () -> Void = {}
    private lazy var hovering = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if !trackingAreas.contains(hovering) { addTrackingArea(hovering) }
    }

    override func mouseEntered(with event: NSEvent) { hover(true) }

    override func mouseExited(with event: NSEvent) { hover(false) }

    override func performClick(_ sender: Any?) {
        super.performClick(sender)
        hover(window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false)
    }

    private func hover(_ on: Bool) {
        contentTintColor = on ? .white : .clear
        layer?.backgroundColor = on ? NSColor.white.withAlphaComponent(0.15).cgColor : nil
    }

    @objc func pick() {
        picked()
    }

    func show(_ title: String) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: font ?? .systemFont(ofSize: 12, weight: .medium),
                                                                              .foregroundColor: NSColor.white, .paragraphStyle: style])
        (cell as? NSPopUpButtonCell)?.menuItem = item
        toolTip = title
        invalidateIntrinsicContentSize()
    }
}

final class CursorTranslatorOutlines: NSView {
    private let holder = CALayer()
    private var lines: [String: CAShapeLayer] = [:]
    private var color: CGColor

    init(color: CGColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        holder.isGeometryFlipped = true
        layer?.addSublayer(holder)
    }

    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        holder.frame = CGRect(origin: .zero, size: newSize)
        CATransaction.commit()
    }

    func paint(_ color: CGColor) {
        self.color = color
        for line in lines.values { line.strokeColor = color }
    }

    func show(_ waiting: [(name: String, rect: CGRect)], fade: Bool, after starts: [String: TimeInterval]) {
        let names = Set(waiting.map(\.name))
        for (name, line) in lines where !names.contains(name) {
            lines[name] = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { line.removeFromSuperlayer() }
            if fade {
                let out = CABasicAnimation(keyPath: "opacity")
                out.fromValue = line.opacity
                out.duration = 0.3
                out.beginTime = CACurrentMediaTime() + (starts[name] ?? 0)
                out.fillMode = .backwards
                line.add(out, forKey: "out")
            }
            line.opacity = 0
            CATransaction.commit()
        }
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let new = waiting.filter { lines[$0.name] == nil }
        for (index, item) in new.enumerated() {
            let outer = item.rect.insetBy(dx: -5, dy: -5)
            let corner = min(8, outer.width / 2, outer.height / 2)
            let line = CAShapeLayer()
            line.contentsScale = window?.backingScaleFactor ?? 2
            line.path = CGPath(roundedRect: outer, cornerWidth: corner, cornerHeight: corner, transform: nil)
            line.fillColor = nil
            line.strokeColor = color
            line.lineWidth = 2
            let draw = CABasicAnimation(keyPath: still ? "opacity" : "strokeEnd")
            draw.fromValue = 0
            draw.duration = still ? 0.2 : 0.35
            draw.timingFunction = CAMediaTimingFunction(name: still ? .linear : .easeOut)
            draw.beginTime = CACurrentMediaTime() + (still ? 0 : CursorTranslator.outlineDelay(index, of: new.count))
            draw.fillMode = .backwards
            line.add(draw, forKey: "draw")
            holder.addSublayer(line)
            lines[item.name] = line
        }
    }
}

final class CursorTranslatorStreamShot: NSObject, SCStreamOutput, @unchecked Sendable {
    private let once = CursorTranslatorOnce<CGImage>()

    static func capture(_ filter: SCContentFilter, _ configuration: SCStreamConfiguration, limit: TimeInterval = 2) async throws -> CGImage {
        let shot = CursorTranslatorStreamShot()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(shot, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
        defer { stream.stopCapture { _ in } }
        return try await shot.once.wait(limit, else: CocoaError(.featureUnsupported)) {
            stream.startCapture { error in
                if let error { shot.once.finish(.failure(error)) }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[SCStreamFrameInfo.status] as? Int, SCFrameStatus(rawValue: raw) == SCFrameStatus.complete,
              let pixels = sampleBuffer.imageBuffer else { return }
        var image: CGImage?
        _ = VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
        if let image { once.finish(.success(image)) }
    }
}

struct CursorTranslatorSeen: Codable, Sendable {
    let text: String
    let box: CGRect
}

struct CursorTranslatorRead: Codable, Sendable {
    let lines: [CursorTranslatorSeen]
    let readable: [String]
}

struct CursorTranslatorPage: Codable, Sendable {
    let image: Data
    let source: String?
}

final class CursorTranslatorReader: Sendable {
    private let child: CursorTranslatorChild?

    @MainActor private static var warming = false

    init(deadline: TimeInterval = CursorTranslatorChild.deadline, first: TimeInterval = CursorTranslatorChild.first) {
        child = Bundle.main.executableURL.map { CursorTranslatorChild(executable: $0, arguments: [MACTranslatorReaderArgument], deadline: deadline, first: first) }
    }

    var fresh: Bool {
        child?.fresh ?? false
    }

    static func childMain() -> Int32 {
        while true {
            let status: Int32? = autoreleasepool {
                guard let picture = CursorTranslatorChild.receive(FileHandle.standardInput) else { return EXIT_SUCCESS }
                guard let answer = lines(picture),
                      (try? FileHandle.standardOutput.write(contentsOf: CursorTranslatorChild.framed(answer))) != nil else { return EXIT_FAILURE }
                return nil
            }
            if let status { return status }
        }
    }

    static func lines(_ data: Data) -> Data? {
        guard let page = try? PropertyListDecoder().decode(CursorTranslatorPage.self, from: data),
              let picture = CGImageSourceCreateWithData(page.image as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(picture, 0, nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let readable = (try? request.supportedRecognitionLanguages()) ?? []
        let languages = page.source.map { CursorTranslator.recognition($0, in: readable) } ?? []
        request.automaticallyDetectsLanguage = languages.isEmpty
        if !languages.isEmpty { request.recognitionLanguages = languages }
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return nil }
        let seen = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { CursorTranslatorSeen(text: $0.string, box: observation.boundingBox) }
        }
        return try? JSONEncoder().encode(CursorTranslatorRead(lines: seen, readable: readable))
    }

    @MainActor
    static func warm() {
        guard !warming else { return }
        func sample(_ line: String, width: CGFloat) -> NSImage {
            NSImage(size: NSSize(width: width, height: 90), flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                (line as NSString).draw(at: NSPoint(x: 16, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black])
                return true
            }
        }
        var wide = NSRect(x: 0, y: 0, width: 1140, height: 90)
        let pictures = [sample("Cursor Translator reads this line", width: 420).cgImage(forProposedRect: nil, context: nil, hints: nil),
                        sample("يقرأ مترجم المؤشر هذا السطر", width: wide.width).cgImage(forProposedRect: &wide, context: nil, hints: [.ctm: NSAffineTransform()])]
            .compactMap { $0 }
        warming = true
        let reader = CursorTranslatorReader(deadline: 180, first: 180)
        Task.detached(priority: .utility) {
            for picture in pictures { _ = await reader.read(picture) }
            reader.stop()
            await MainActor.run { CursorTranslatorReader.warming = false }
        }
    }

    func prepare() {
        child?.start()
    }

    func read(_ image: CGImage, source: String? = nil) async -> CursorTranslatorRead? {
        guard let child, let png = await Task.detached(operation: { Self.png(image) }).value,
              let page = try? PropertyListEncoder().encode(CursorTranslatorPage(image: png, source: source)),
              let answer = await child.ask(page) else { return nil }
        return try? JSONDecoder().decode(CursorTranslatorRead.self, from: answer)
    }

    func stop() {
        child?.stop()
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

@MainActor
final class CursorTranslatorFrame {
    private static let tagLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    private static let grip: CGFloat = 20
    private static let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = CursorTranslator.timeLimit(for: CursorTranslator.group)
        configuration.timeoutIntervalForResource = CursorTranslator.timeLimit(for: CursorTranslator.group)
        return URLSession(configuration: configuration)
    }()

    private let model: CursorTranslatorFrameModel
    private let hosting: NSView
    private let border: CursorTranslatorBorder
    private let outlines: CursorTranslatorOutlines
    private var look: CursorTranslatorLook
    private var pieces: [(source: String, piece: CursorTranslatorPiece, paper: Color, ink: Color)] = [] {
        didSet { arrange() }
    }
    private let follows: Bool
    private let service: CursorTranslatorService
    private let modelName: String
    private let address: String
    private let apple: AnyObject?
    private var monitors: [Any] = []
    private var moved: TimeInterval?
    private var still: DispatchWorkItem?
    private var following = false
    private var stroke: CGRect?
    private let content: NSWindow
    private let tag: NSPanel
    private let grip: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let fromButton = CursorTranslatorMenuButton()
    private let toButton = CursorTranslatorMenuButton()
    private let dot = NSView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
    private let lines = CAShapeLayer()
    private var palette: CursorTrailsPalette
    private let stack: NSStackView
    private let locale: Locale
    private var source: String?
    private var target: String
    private let screenAllowed: @MainActor () -> Bool
    private var timer: DispatchSourceTimer?
    private var watch = CursorTranslatorWatch()
    private var cache = CursorTranslatorCache()
    private let reader = CursorTranslatorReader()
    private var capture: (display: CGDirectDisplayID, filter: SCContentFilter)?
    private var anchor = CGRect.zero
    private var drawn: CGRect
    private var area: CGRect
    private var motion: NSObjectProtocol?
    private var spin = CursorTranslatorSpin()
    private var spinCheck: DispatchWorkItem?
    private var latest: (spots: [CursorTranslatorSpot], page: String, rect: CGRect)? {
        didSet { outline() }
    }
    private var busy = false
    private var held = false
    private var again = false
    private var parked: CursorTranslatorStatus?
    private var reading = false
    private var translating = false
    private var closed = false
    private(set) var drawing = true

    init(rect: CGRect, color palette: CursorTrailsPalette, look: CursorTranslatorLook, source: String?, target: String, follows: Bool, service: CursorTranslatorService,
         model modelName: String, address: String, screenAllowed: @escaping @MainActor () -> Bool, onClose: @escaping @MainActor () -> Void) {
        let color = CursorTrailsPalette.color(at: 0, stops: [palette.frameColor], alpha: 1)
        var apple: AnyObject?
        if #available(macOS 15, *), service == .apple { apple = CursorTranslatorAppleSession() }
        self.apple = apple
        self.palette = palette
        model = CursorTranslatorFrameModel(rect: rect, apple: apple, target: target)
        drawn = rect
        area = rect
        let border = CursorTranslatorBorder(color: color, colors: palette.colors)
        self.border = border
        let outlines = CursorTranslatorOutlines(color: color)
        self.outlines = outlines
        self.look = look
        self.source = source
        self.target = target
        locale = MenuBarService.language().map { Locale(identifier: $0) } ?? .current
        self.follows = follows
        self.service = service
        self.modelName = modelName
        self.address = address
        self.screenAllowed = screenAllowed
        content = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: CursorTranslatorFrameView(model: model))
        hosting.sizingOptions = []
        self.hosting = hosting
        let host = NSView(frame: CGRect(origin: .zero, size: rect.size))
        for view in [hosting, outlines, border] as [NSView] {
            view.frame = host.bounds
            host.addSubview(view)
        }
        border.autoresizingMask = [.width, .height]
        content.contentView = host
        content.ignoresMouseEvents = true
        Self.prepare(content, level: .floating)

        dot.wantsLayer = true
        dot.layer?.backgroundColor = color
        dot.layer?.cornerRadius = 4
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let close = CursorTranslatorButton(frame: .zero)
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: MenuBarL("Close"))
        close.isBordered = false
        close.contentTintColor = .white
        close.target = close
        close.action = #selector(CursorTranslatorButton.press)
        close.pressed = onClose
        close.setAccessibilityLabel(MenuBarL("Close"))
        close.isHidden = follows
        close.widthAnchor.constraint(equalToConstant: Self.grip).isActive = true
        close.heightAnchor.constraint(equalToConstant: Self.grip).isActive = true
        fromButton.addItem(withTitle: MenuBarL("Detect Language"))
        fromButton.menu?.addItem(.separator())
        for button in [fromButton, toButton] {
            for code in CursorTranslatorConfig.sortedLanguages(in: locale) {
                button.addItem(withTitle: CursorTranslatorConfig.name(code, in: locale))
                button.lastItem?.representedObject = code
            }
            button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.menu?.font = .menuFont(ofSize: 0)
            button.contentTintColor = .clear
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            (button.cell as? NSPopUpButtonCell)?.usesItemFromMenu = false
            button.target = button
            button.action = #selector(CursorTranslatorMenuButton.pick)
            button.heightAnchor.constraint(equalToConstant: Self.grip).isActive = true
            button.isHidden = follows
        }
        fromButton.setAccessibilityLabel(MenuBarL("Translate from"))
        toButton.setAccessibilityLabel(MenuBarL("Translate to"))
        let arrow = NSTextField(labelWithString: locale.language.characterDirection == .rightToLeft ? "←" : "→")
        arrow.font = .systemFont(ofSize: 12, weight: .medium)
        arrow.textColor = .white
        arrow.isHidden = follows
        stack = NSStackView(views: [dot, fromButton, arrow, toButton, label, close])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.setCustomSpacing(12, after: toButton)
        stack.userInterfaceLayoutDirection = locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 2, right: 8)
        let face = CursorTranslatorHandle()
        face.wantsLayer = true
        face.layer?.backgroundColor = CGColor(gray: 0.1, alpha: 0.85)
        face.layer?.cornerRadius = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        face.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: face.leadingAnchor), stack.trailingAnchor.constraint(equalTo: face.trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: face.topAnchor), stack.bottomAnchor.constraint(equalTo: face.bottomAnchor)])
        tag = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        tag.contentView = face
        tag.ignoresMouseEvents = follows
        Self.prepare(tag, level: Self.tagLevel)

        let corner = CursorTranslatorHandle(frame: CGRect(x: 0, y: 0, width: Self.grip, height: Self.grip))
        let path = CGMutablePath()
        for step in [CGFloat(4), 8, 12] {
            path.move(to: CGPoint(x: Self.grip - 2, y: Self.grip - step))
            path.addLine(to: CGPoint(x: Self.grip - step, y: 2))
        }
        lines.path = path
        lines.strokeColor = color
        lines.lineWidth = 1.5
        lines.lineCap = .round
        corner.wantsLayer = true
        corner.layer?.addSublayer(lines)
        corner.setAccessibilityElement(false)
        corner.reach = 0
        grip = NSPanel(contentRect: corner.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        grip.contentView = corner
        Self.prepare(grip, level: Self.tagLevel)

        face.began = { [weak self] in self.map { $0.anchor = $0.drawn } }
        face.moved = { [weak self] delta in
            guard let self else { return }
            let moved = self.anchor.offsetBy(dx: delta.width, dy: delta.height)
            self.slide(CursorTranslator.fit(moved, in: CursorTranslatorController.visible(at: NSEvent.mouseLocation)), height: self.content.frame.height)
        }
        corner.began = { [weak self] in self.map { $0.anchor = $0.drawn } }
        corner.moved = { [weak self] delta in
            guard let self else { return }
            let rect = CursorTranslator.resized(self.anchor, by: delta, in: CursorTranslatorController.visible(at: CGPoint(x: self.anchor.minX, y: self.anchor.maxY)))
            self.slide(rect, height: rect.height)
        }
        face.ended = { [weak self] in self?.settle() }
        corner.ended = { [weak self] in self?.settle() }
        fromButton.picked = { [weak self] in self.map { $0.pick($0.fromButton) } }
        toButton.picked = { [weak self] in self.map { $0.pick($0.toButton) } }
        place(rect)
        content.orderFrontRegardless()
    }

    func place(_ rect: CGRect) {
        guard !closed else { return }
        if rect != drawn { watch.lookAfresh() }
        drawn = rect
        arrange()
    }

    private func slide(_ rect: CGRect, height: CGFloat) {
        held = true
        guard !closed, rect != drawn else { return }
        drawn = rect
        let pinned = CGPoint(x: content.frame.minX + hosting.frame.minX, y: content.frame.minY + hosting.frame.minY)
        content.setFrame(CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height), display: true)
        for view in [hosting, outlines] { view.setFrameOrigin(CGPoint(x: pinned.x - content.frame.minX, y: pinned.y - content.frame.minY)) }
        layoutHandles()
    }

    private func settle() {
        held = false
        guard !closed else { return }
        watch.lookAfresh()
        watch.endRest()
        if let parked {
            self.parked = nil
            show(parked)
        }
        arrange()
        kick()
    }

    private func kick() {
        guard !closed, !drawing, !held else { return }
        guard !busy else {
            again = true
            return
        }
        busy = true
        again = false
        Task { await look() }
    }

    func draw(_ rect: CGRect) {
        let pending = stroke != nil
        stroke = rect
        guard !pending else { return }
        let fps = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 / Double(fps > 0 ? fps : 60)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let rect = self.stroke else { return }
                self.stroke = nil
                if self.drawing, !self.closed { self.place(rect) }
            }
        }
    }

    func recapture() {
        capture = nil
    }

    func retry() {
        watch.forget()
        watch.endRest()
        kick()
    }

    func restyle(_ look: CursorTranslatorLook) {
        guard self.look != look else { return }
        self.look = look
        arrange()
    }

    func recolor(_ palette: CursorTrailsPalette) {
        guard self.palette != palette else { return }
        self.palette = palette
        let color = CursorTrailsPalette.color(at: 0, stops: [palette.frameColor], alpha: 1)
        border.paint(color, palette.colors)
        dot.layer?.backgroundColor = color
        lines.strokeColor = color
        outlines.paint(color)
    }

    func retarget(_ source: String?, _ target: String) {
        guard source != self.source || target != self.target else { return }
        if held || source != self.source || latest?.rect != drawn {
            latest = nil
            watch.forget()
        }
        self.source = source
        self.target = target
        model.direction = CursorTranslatorFrameModel.direction(target)
        pieces = []
        watch.endRest()
        show(.reading)
        guard latest == nil else { return answer() }
        kick()
    }

    func start() {
        guard !closed, drawing else { return }
        drawing = false
        reader.prepare()
        show(.reading)
        tag.orderFrontRegardless()
        motion = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.turnBorder() }
        }
        if follows {
            monitors = [NSEvent.addGlobalMonitorForEvents(matching: Self.moves) { [weak self] _ in
                            MainActor.assumeIsolated { self?.follow() }
                        },
                        NSEvent.addLocalMonitorForEvents(matching: Self.moves) { [weak self] event in
                            MainActor.assumeIsolated { self?.follow() }
                            return event
                        }].compactMap { $0 }
        } else {
            grip.orderFrontRegardless()
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: CursorTranslator.interval, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.kick() }
        }
        self.timer = timer
        timer.resume()
    }

    func close() {
        guard !closed else { return }
        closed = true
        cache = CursorTranslatorCache()
        latest = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        timer?.cancel()
        timer = nil
        spinCheck?.cancel()
        spinCheck = nil
        still?.cancel()
        still = nil
        border.turn(false)
        if let motion { NSWorkspace.shared.notificationCenter.removeObserver(motion) }
        motion = nil
        reader.stop()
        for window in [tag, grip, content] { window.orderOut(nil) }
        tag.close()
        grip.close()
        let content = self.content
        let release: @MainActor () -> Void = {
            content.contentView = nil
            content.close()
        }
        if #available(macOS 15, *), let session = apple as? CursorTranslatorAppleSession {
            session.end(then: release)
        } else {
            release()
        }
    }

    private func follow() {
        moved = ProcessInfo.processInfo.systemUptime
        still?.cancel()
        let still = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.kick() }
        }
        self.still = still
        DispatchQueue.main.asyncAfter(deadline: .now() + CursorTranslator.rest, execute: still)
        guard !following else { return }
        following = true
        let fps = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 / Double(fps > 0 ? fps : 60)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.following = false
                let point = NSEvent.mouseLocation
                self.place(CursorTranslator.clickFrame(at: point, size: CursorTranslator.followSize, in: CursorTranslatorController.visible(at: point)))
            }
        }
    }

    private func layoutHandles() {
        let rect = content.frame
        let fitting = stack.fittingSize
        tag.setFrame(CursorTranslator.tagFrame(above: rect, fitting: fitting, least: fitting.width - (label.isHidden ? 0 : label.intrinsicContentSize.width),
                                               in: CursorTranslatorController.visible(at: CGPoint(x: rect.midX, y: rect.midY))), display: true)
        grip.setFrame(CGRect(x: rect.maxX - CursorTranslator.border - Self.grip - 2, y: rect.minY + CursorTranslator.border + 2,
                             width: Self.grip, height: Self.grip), display: true)
    }

    private func show(_ status: CursorTranslatorStatus) {
        guard !held else {
            parked = status
            return
        }
        var shown = status.text(MenuBarL, in: locale)
        if !follows {
            fromButton.selectItem(at: source.map { fromButton.indexOfItem(withRepresentedObject: $0) } ?? 0)
            toButton.selectItem(at: toButton.indexOfItem(withRepresentedObject: target))
            fromButton.show(CursorTranslatorConfig.sourceTitle(source, detected: latest?.page, MenuBarL, in: locale))
            toButton.show(CursorTranslatorConfig.name(target, in: locale))
            if case .pair = status { shown = "" }
        }
        label.stringValue = shown
        label.isHidden = shown.isEmpty
        label.toolTip = shown
        layoutHandles()
    }

    private func pick(_ button: CursorTranslatorMenuButton) {
        let saved = CursorTranslatorConfig.load()
        var config = saved
        let code = button.selectedItem?.representedObject as? String
        if button === fromButton {
            config.source = code
        } else if code != target {
            config.target = code ?? saved.target
        }
        guard config != saved else { return }
        config.save()
    }

    private func working() {
        spin.set(working: reading || translating, at: ProcessInfo.processInfo.systemUptime)
        turnBorder()
        outline()
    }

    private func outline() {
        let starts = Dictionary(model.boxes.map { ($0.id, $0.delay) }, uniquingKeysWith: { first, _ in first })
        guard let latest, latest.rect == drawn, translating else { return outlines.show([], fade: latest?.rect == drawn, after: starts) }
        let waiting = Set(misses())
        outlines.show(zip(CursorTranslator.names(latest.spots.map(\.text)), latest.spots).filter { waiting.contains($1.text) }
            .map { (name: $0, rect: CursorTranslator.local($1.rect, in: drawn)) }, fade: true, after: starts)
    }

    private func turnBorder() {
        guard !closed else { return }
        let state = spin.update(at: ProcessInfo.processInfo.systemUptime)
        border.turn(state.turns)
        spinCheck?.cancel()
        spinCheck = state.next.map { next in
            let check = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.turnBorder() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(next - ProcessInfo.processInfo.systemUptime, 0), execute: check)
            return check
        }
    }

    private func look() async {
        defer {
            busy = false
            reading = false
            working()
            if again { kick() }
        }
        watch.wake(at: ProcessInfo.processInfo.systemUptime)
        guard watch.resting == nil, CursorTranslator.rested(since: moved, now: ProcessInfo.processInfo.systemUptime) else { return }
        let rect = drawn, from = source
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard !closed, let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return }
        let image: CGImage
        do {
            image = try await grab(rect, on: screen)
        } catch {
            capture = nil
            if (error as? POSIXError)?.code == .ETIMEDOUT { watch.failed(at: ProcessInfo.processInfo.systemUptime) }
            return show(screenAllowed() ? .unreadable : .needsScreenRecording)
        }
        guard !closed, rect == drawn,
              let picture = await Task.detached(operation: { CursorTranslatorPicture(image) }).value, watch.look(picture) else { return }
        if model.boxes.isEmpty { show(.reading) }
        reading = true
        working()
        guard let seen = await readText(image, source: from) else {
            guard !closed else { return }
            watch.misread(at: ProcessInfo.processInfo.systemUptime)
            return show(.notRead)
        }
        watch.readWell()
        let read = await Task.detached(operation: { Self.read(seen, from: image, in: rect, source: from) }).value
        guard !closed else { return }
        guard rect == drawn, from == source else { return watch.forget() }
        guard let page = read.page, !read.spots.isEmpty else {
            latest = nil
            pieces = []
            let unreadable = picture.blank ? [] : CursorTranslator.unreadable(seen.readable)
            return show(unreadable.isEmpty ? .noText : .cannotRead(unreadable))
        }
        latest = (read.spots, page, rect)
        answer()
    }

    private func answer() {
        guard let latest else { return }
        let wanted = Set(latest.spots.filter { !CursorTranslator.skips($0.text, language: $0.language, page: latest.page, target: target) }.map(\.text))
        guard !wanted.isEmpty else {
            pieces = []
            return show(.pair(latest.page, target))
        }
        let misses = misses()
        if misses.count < wanted.count { draw() }
        guard misses.isEmpty else { return translate() }
        show(.pair(latest.page, target))
    }

    private func misses() -> [String] {
        guard let latest else { return [] }
        var asked = Set<String>()
        return latest.spots.filter { !CursorTranslator.skips($0.text, language: $0.language, page: latest.page, target: target) }
            .map(\.text).filter { cache.value($0, from: source, to: target) == nil && asked.insert($0).inserted }
    }

    private func draw() {
        guard let latest, latest.rect == drawn else { return }
        guard watch.unchanged else { return watch.forget() }
        area = latest.rect
        pieces = latest.spots.compactMap { spot in
            let skipped = CursorTranslator.skips(spot.text, language: spot.language, page: latest.page, target: target)
            let translation = skipped ? nil : cache.value(spot.text, from: source, to: target)
            guard skipped || translation != nil else { return nil }
            return (spot.text, CursorTranslatorPiece(text: translation ?? spot.text, rect: spot.rect, size: spot.size, translated: translation != nil),
                    Color(cgColor: CursorTrailsPalette.color(at: 0, stops: [spot.paper], alpha: 1)),
                    Color(cgColor: CursorTrailsPalette.color(at: 0, stops: [spot.ink], alpha: 1)))
        }
    }

    private func translate() {
        guard !translating else { return }
        translating = true
        working()
        Task {
            defer {
                translating = false
                working()
            }
            var asked = Set<String>()
            var languages = (source, target)
            while !closed, watch.resting == nil, let latest, latest.rect == drawn {
                if languages != (source, target) {
                    asked = []
                    languages = (source, target)
                }
                let misses = misses().filter { asked.insert($0).inserted }
                guard !misses.isEmpty else {
                    draw()
                    return show(.pair(latest.page, target))
                }
                let problem = await translated(misses, page: latest.page)
                guard !closed else { return }
                draw()
                if let problem, languages == (source, target) {
                    if CursorTranslator.retries(problem) { watch.failed(at: ProcessInfo.processInfo.systemUptime) }
                    return show(problem)
                }
            }
        }
    }

    private func translated(_ misses: [String], page: String) async -> CursorTranslatorStatus? {
        let source = source, target = target
        guard let apple else { return await online(misses, from: source, to: target) }
        guard #available(macOS 15, *), let session = apple as? CursorTranslatorAppleSession else { return nil }
        if let problem = await session.check(page, target) { return problem }
        guard await session.use(page, target) else { return .unavailable }
        guard let done = await session.translate(misses, arrived: { index, text, live in
            guard !self.closed else { return }
            self.cache.store(text, for: misses[index], from: source, to: target)
            if live { self.draw() }
        }) else { return .unavailable }
        store(done, for: misses, from: source, to: target)
        return nil
    }

    private func readText(_ image: CGImage, source: String?) async -> CursorTranslatorRead? {
        let preparing: Task<Bool, Never>? = reader.fresh ? Task { [weak self] in
            guard (try? await Task.sleep(nanoseconds: UInt64(CursorTranslatorChild.patience * 1_000_000_000))) != nil, let self, !self.closed else { return false }
            self.show(.preparing)
            return true
        } : nil
        let seen = await reader.read(image, source: source)
        preparing?.cancel()
        if await preparing?.value == true, !closed { show(.reading) }
        if seen == nil, !closed { CursorTranslatorReader.warm() }
        return seen
    }

    private func arrange() {
        guard !held else { return }
        if area == drawn || pieces.isEmpty {
            let sources = pieces.map(\.piece)
            let placed = CursorTranslator.layout(sources, in: drawn, bottom: CursorTranslatorController.visible(at: CGPoint(x: drawn.midX, y: drawn.midY)).minY, look: look)
            model.rect = CursorTranslator.grown(drawn, around: placed, from: sources)
            let names = CursorTranslator.names(pieces.map(\.source))
            model.land(pieces.indices.filter { pieces[$0].piece.translated }.map { index in
                let place = placed[index]
                return CursorTranslatorBox(id: names[index], text: place.text, rect: place.rect, cover: place.rect.union(pieces[index].piece.rect), size: place.size,
                                           spacing: CursorTranslator.spacing(place.size, look), paper: pieces[index].paper, ink: pieces[index].ink)
            })
        } else {
            model.rect = drawn
        }
        content.setFrame(model.rect, display: true)
        for view in [hosting, outlines] { view.frame = CGRect(origin: .zero, size: content.frame.size) }
        layoutHandles()
        outline()
    }

    private func store(_ translations: [String], for texts: [String], from source: String?, to target: String) {
        guard !closed else { return }
        for (text, translation) in zip(texts, translations) { cache.store(translation, for: text, from: source, to: target) }
    }

    private func online(_ texts: [String], from source: String?, to target: String) async -> CursorTranslatorStatus? {
        let name = service.title(MenuBarL)
        let key = CursorTranslatorKeychain.key(for: service) ?? ""
        if service.needsKey, key.isEmpty { return .missingKey(name) }
        let batches = CursorTranslator.batches(texts, for: service)
        let service = service, model = modelName, address = address
        return await withTaskGroup(of: [CursorTranslator.Landing].self) { group in
            var problem: CursorTranslatorStatus?
            @MainActor func landed(_ landings: [CursorTranslator.Landing]) {
                for landing in landings {
                    switch landing.result {
                    case .success(let translated):
                        store(translated, for: landing.texts, from: source, to: target)
                        draw()
                    case .failure(let failure):
                        problem = problem ?? failure
                    }
                }
            }
            for (index, batch) in batches.enumerated() {
                if index >= CursorTranslator.flights, let landing = await group.next() { landed(landing) }
                guard problem == nil, !closed, !held, self.source == source, self.target == target else { break }
                group.addTask {
                    await CursorTranslator.asked(batch, again: { @MainActor in !self.closed && !self.held }) { part in
                        guard let request = CursorTranslator.request(part, from: source, to: target, service: service, key: key, model: model, address: address)
                        else { return .failure(.badAddress) }
                        return await Self.ask(request, service: service, name: name, count: part.count)
                    }
                }
            }
            for await landing in group { landed(landing) }
            return problem
        }
    }

    nonisolated private static func ask(_ request: URLRequest, service: CursorTranslatorService, name: String, count: Int) async -> Result<[String], CursorTranslatorStatus> {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return .failure(CursorTranslator.failure(status: status, error: nil, service: name, reply: data)) }
            guard let translated = CursorTranslator.translations(data, from: service, count: count) else { return .failure(.notUnderstood(name)) }
            return .success(translated)
        } catch {
            return .failure(CursorTranslator.failure(status: nil, error: error, service: name))
        }
    }

    private func grab(_ rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        if capture?.display != display {
            let content = try await CursorTranslatorOnce.within(2) { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
            guard let shown = content.displays.first(where: { $0.displayID == display }) else { throw CocoaError(.featureUnsupported) }
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            capture = (display, SCContentFilter(display: shown, excludingApplications: own, exceptingWindows: []))
        }
        guard let filter = capture?.filter else { throw CocoaError(.featureUnsupported) }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CursorTranslator.displayRect(rect, on: screen.frame)
        configuration.showsCursor = false
        if #available(macOS 14, *) {
            let size = CursorTranslator.pixels(rect, scale: CGFloat(filter.pointPixelScale))
            configuration.width = size.width
            configuration.height = size.height
            return try await CursorTranslatorOnce.within(2) { try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) }
        }
        let size = CursorTranslator.pixels(rect, scale: screen.backingScaleFactor)
        configuration.width = size.width
        configuration.height = size.height
        return try await CursorTranslatorStreamShot.capture(filter, configuration)
    }

    nonisolated static func read(_ seen: CursorTranslatorRead, from image: CGImage, in rect: CGRect, source: String?) -> (spots: [CursorTranslatorSpot], page: String?) {
        let lines = seen.lines.map { CursorTranslatorLine(text: $0.text, rect: CursorTranslator.screenRect($0.box, in: rect)) }
        let paragraphs = CursorTranslator.paragraphs(lines)
        let page = source ?? NLLanguageRecognizer.dominantLanguage(for: paragraphs.map(\.text).joined(separator: "\n"))?.rawValue
        let spots = paragraphs.map { paragraph -> CursorTranslatorSpot in
            let box = CGRect(x: (paragraph.rect.minX - rect.minX) / rect.width, y: (paragraph.rect.minY - rect.minY) / rect.height,
                             width: paragraph.rect.width / rect.width, height: paragraph.rect.height / rect.height)
            let colors = CursorTranslator.colors(image, in: CursorTranslator.imageRect(box, width: image.width, height: image.height).insetBy(dx: -2, dy: -2))
            let text = paragraph.text
            let language = source ?? (text.count < 12 ? page : NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue)
            return CursorTranslatorSpot(text: text, rect: paragraph.rect, size: max(paragraph.lineHeight * 0.8, 8),
                                        paper: colors?.paper ?? 0xFFFFFF, ink: colors?.ink ?? 0, language: language)
        }
        return (spots, page)
    }

    private static func prepare(_ window: NSWindow, level: NSWindow.Level) {
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = level
        window.canHide = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        if let panel = window as? NSPanel {
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
        }
    }
}
