import Foundation
import AppKit
import Observation

@Observable
class CursorModel: Identifiable, Hashable {
    let id: String
    var identifier: String
    
    var name: String {
        let resolved = CursorIdentifier.displayName(for: identifier)
        if resolved == identifier || resolved.isEmpty {
            if identifier.contains(".") {
                return String(identifier.split(separator: ".").last ?? Substring(identifier))
            }
            return identifier.isEmpty ? "Unknown" : identifier
        }
        return resolved
    }
    
    var frameCount: Int
    var frameDuration: Double
    var hotSpot: CGPoint
    var size: CGSize
    
    var representationRevision: Int = 0
    
    let backingCursor: MCCursorSwift
    
    init(from cursor: MCCursorSwift, parentIdentifier: String? = nil) {
        self.backingCursor = cursor
        let rawId = (cursor.identifier?.isEmpty == false) ? cursor.identifier! : UUID().uuidString
        if let parentId = parentIdentifier, !parentId.isEmpty {
            self.id = "\(parentId)/\(rawId)"
        } else {
            self.id = rawId
        }
        self.identifier = cursor.identifier ?? ""
        
        self.frameCount = Int(cursor.frameCount)
        self.frameDuration = cursor.frameDuration
        self.hotSpot = CGPoint(x: cursor.hotSpot.x, y: cursor.hotSpot.y)
        self.size = CGSize(width: cursor.size.width, height: cursor.size.height)
    }
    
    func syncToBacking() {
        backingCursor.identifier = identifier
        backingCursor.frameCount = UInt(frameCount)
        backingCursor.frameDuration = frameDuration
        backingCursor.hotSpot = NSPoint(x: hotSpot.x, y: hotSpot.y)
        backingCursor.size = NSSize(width: size.width, height: size.height)
    }
    
    func image(forScale scale: Int) -> NSImage? {
        _ = representationRevision
        guard let scaleEnum = MCCursorScale(rawValue: UInt(scale)),
              let rep = backingCursor.representation(for: scaleEnum) else {
            return nil
        }
        let s = CGFloat(scale) / 100.0
        let image = NSImage(size: NSSize(
            width: CGFloat(rep.pixelsWide) / s,
            height: CGFloat(rep.pixelsHigh) / s
        ))
        image.addRepresentation(rep)
        return image
    }
    
    var primaryImage: NSImage? {
        _ = representationRevision
        return image(forScale: 100) ?? image(forScale: 200) ?? backingCursor.imageWithAllReps()
    }
    
    var cursorTypeName: String {
        guard !identifier.isEmpty else { return "Unassigned" }
        let parts = identifier.split(separator: ".")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: ".")
        }
        return identifier
    }
    
    func frame(at index: Int, scale: Int = 100) -> NSImage? {
        _ = representationRevision
        guard let scaleEnum = MCCursorScale(rawValue: UInt(scale)),
              let rep = backingCursor.representation(for: scaleEnum) else {
            return nil
        }
        
        let frameHeight = Int(size.height)
        guard frameHeight > 0, index < frameCount else { return nil }
        
        let s = CGFloat(scale) / 100.0
        let pixelFrameHeight = Int(CGFloat(frameHeight) * s)
        let yOffset = index * pixelFrameHeight
        
        let fullImage = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        fullImage.addRepresentation(rep)
        
        var proposedRect = CGRect(origin: .zero, size: CGSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        guard let fullCGImage = fullImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }
        let cropRect = CGRect(x: 0, y: yOffset, width: fullCGImage.width, height: pixelFrameHeight)
        guard let croppedCGImage = fullCGImage.cropping(to: cropRect) else { return nil }
        
        let frameImage = NSImage(size: NSSize(width: size.width, height: size.height))
        let frameRep = NSBitmapImageRep(cgImage: croppedCGImage)
        frameImage.addRepresentation(frameRep)
        return frameImage
    }
    
    
    func setRepresentation(_ rep: NSBitmapImageRep, forScale scale: Int) {
        guard let scaleEnum = MCCursorScale(rawValue: UInt(scale)) else { return }
        
        backingCursor.frameCount = UInt(frameCount)
        
        backingCursor.setRepresentation(rep, for: scaleEnum)
        representationRevision += 1
        
        let s = CGFloat(scale) / 100.0
        let calculatedSize = CGSize(
            width: CGFloat(rep.pixelsWide) / s,
            height: CGFloat(rep.pixelsHigh) / CGFloat(frameCount) / s
        )
        if calculatedSize != .zero {
            backingCursor.size = NSSize(width: calculatedSize.width, height: calculatedSize.height)
            size = calculatedSize
        }
    }
    
    func removeRepresentation(forScale scale: Int) {
        guard let scaleEnum = MCCursorScale(rawValue: UInt(scale)) else { return }
        backingCursor.removeRepresentation(for: scaleEnum)
        representationRevision += 1
    }
    
    
    static func == (lhs: CursorModel, rhs: CursorModel) -> Bool {
        lhs === rhs
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
