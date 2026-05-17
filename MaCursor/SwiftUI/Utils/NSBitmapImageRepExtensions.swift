import AppKit

extension NSBitmapImageRep {
    
    var retaggedSRGBSpace: NSBitmapImageRep {
        var targetSpace = NSColorSpace.sRGB
        if colorSpace.numberOfColorComponents == 1 {
            targetSpace = .genericGamma22Gray
        }
        return retagging(with: targetSpace) ?? self
    }
    
    var ensuredSRGBSpace: NSBitmapImageRep {
        var targetSpace = NSColorSpace.sRGB
        if colorSpace.numberOfColorComponents == 1 {
            targetSpace = .genericGamma22Gray
        }
        return converting(to: targetSpace, renderingIntent: .default) ?? self
    }
}
