import Foundation

enum CursorIdentifier {
    static func displayName(for identifier: String) -> String {
        return MCConstants.nameForIdentifier(identifier)
    }
    
    static func identifier(for name: String) -> String? {
        return MCConstants.identifierForName(name)
    }
    
    static var allIdentifiers: [(identifier: String, name: String)] {
        return MCConstants.cursorMap
            .map { (identifier: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    static var allNames: [String] {
        return MCConstants.cursorMap.values
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
