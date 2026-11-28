import Foundation

public struct RoleMapping: Sendable, Equatable {
    public let primary: String
    public let secondaries: [String]

    public init(primary: String, secondaries: [String] = []) {
        self.primary = primary
        self.secondaries = secondaries
    }
}

public enum MappingTier: Int, Sendable, Comparable {
    case infDeclaration = 0
    case exactName = 1
    case heuristic = 2

    public static func < (lhs: MappingTier, rhs: MappingTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum NameMatch: Sendable, Equatable {
    case slot(RoleMapping, MappingTier)
    case ignored
}

public enum RoleMapper {

    public static func normalize(_ raw: String) -> String {
        (raw as NSString).deletingPathExtension.lowercased()
            .replacingOccurrences(of: "(\\p{L})(\\p{N})", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "(\\p{N})(\\p{L})", with: "$1 $2", options: .regularExpression)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    static func folded(_ table: [String: RoleMapping]) -> [String: RoleMapping] {
        Dictionary(table.map { (normalize($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    static let windowsNames = folded(CursorNameList.windows)
    static let cssNames = folded(CursorNameList.css)
    static let linuxNames = folded(
        CursorNameList.linux.merging(CursorNameList.linuxAliases.compactMapValues { mapX11Name($0) }) { name, _ in name }
            .filter { !$0.key.contains(where: \.isNumber) })
    static let ignoredWindowsNames = Set(CursorNameList.ignoredWindows.map(normalize))
    static let ignoredNames = ignoredWindowsNames.union(CursorNameList.ignoredLinux.map(normalize))
    static let ignoredWindowsJoined = Set(ignoredWindowsNames.map { $0.filter { $0 != " " } })

    static let wholeWordNames: [String: NameMatch] = {
        var table = cssNames.mapValues { NameMatch.slot($0, .heuristic) }
        for (name, mapping) in windowsNames { table[name] = .slot(mapping, .heuristic) }
        for name in ignoredWindowsNames { table[name] = .ignored }
        return table
    }()
    static let weakWholeWordNames = Set(wholeWordNames.keys.filter { !$0.contains(" ") && $0.count <= 3 })
    static let longestWholeWordName = wholeWordNames.keys.map { $0.split(separator: " ").count }.max() ?? 1

    public static func mapX11Name(_ name: String) -> RoleMapping? {
        let key = name.lowercased()
        if let mapping = CursorNameList.linux[key] ?? CursorNameList.css[key] { return mapping }
        guard let canonical = CursorNameList.linuxAliases[key] else { return nil }
        return CursorNameList.linux[canonical] ?? CursorNameList.css[canonical]
    }

    public static func mapINFRole(_ role: String) -> RoleMapping? {
        CursorNameList.infRoles[role.lowercased()]
    }

    public static func mapFilenameHeuristic(_ stem: String) -> RoleMapping? {
        let lower = stem.lowercased()
        for row in CursorNameList.wordGuesses where row.words.contains(where: { lower.contains($0) }) {
            return RoleMapping(primary: row.identifier)
        }
        return nil
    }

    public static func matchWindowsFileName(_ fileName: String) -> NameMatch? {
        let key = normalize(fileName)
        if ignoredNames.contains(key) || ignoredWindowsJoined.contains(key.filter { $0 != " " }) { return .ignored }
        if let mapping = windowsNames[key] ?? cssNames[key] ?? linuxNames[key] {
            return .slot(mapping, .exactName)
        }
        var words = key.split(separator: " ")
        if words.starts(with: ["copy", "of"]) { words.removeFirst(2) }
        for skipWeak in [true, false] {
            for start in words.indices {
                for end in stride(from: min(words.count, start + longestWholeWordName), to: start, by: -1) {
                    let name = words[start ..< end].joined(separator: " ")
                    if skipWeak && weakWholeWordNames.contains(name) { continue }
                    if let match = wholeWordNames[name] { return match }
                    if ignoredWindowsJoined.contains(words[start ..< end].joined()) { return .ignored }
                }
            }
        }
        return mapFilenameHeuristic((fileName as NSString).deletingPathExtension).map { .slot($0, .heuristic) }
    }

    public static func isDeliberatelyUnmapped(_ rawName: String) -> Bool {
        ignoredNames.contains(normalize(rawName))
    }
}
