import UniformTypeIdentifiers

extension UTType {
    static let windowsCursor: UTType = UTType("com.microsoft.cur")
        ?? UTType(filenameExtension: "cur") ?? UTType.data
    
    static let windowsAnimatedCursor: UTType = UTType("com.microsoft.ani")
        ?? UTType(filenameExtension: "ani") ?? UTType.data
    
    static let allWindowsCursorTypes: [UTType] = [.windowsCursor, .windowsAnimatedCursor]
}
