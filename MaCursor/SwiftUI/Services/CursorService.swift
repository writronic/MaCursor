import Foundation

enum CursorService {
    static func applyTheme(atPath path: String) -> Bool {
        return applyThemeAtPath(path)
    }
    
    static func applyTheme(from library: CursorLibrary) -> Bool {
        guard let path = library.fileURL?.path else {
            return false
        }
        return applyTheme(atPath: path)
    }
    
    @discardableResult
    static func restoreAll() -> Bool {
        return resetAllCursors(nil)
    }
    
    static func currentScale() -> Float {
        return cursorScale()
    }
    
    static func defaultScale() -> Float {
        return defaultCursorScale()
    }
    
    @discardableResult
    static func setScale(_ scale: Float) -> Bool {
        return setCursorScale(scale)
    }
}
