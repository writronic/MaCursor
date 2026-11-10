import Foundation

enum CursorScreenshotNameToken: Character, CaseIterable, Sendable {
    case date = "x", year = "y", month = "m", day = "d", windowTitle = "t", appName = "a"
    case hour = "H", minutes = "M", seconds = "S", amPM = "p", number = "i"

    static let columns: [[CursorScreenshotNameToken]] = [[.date, .year, .month, .day, .windowTitle, .appName],
                                                         [.hour, .minutes, .seconds, .amPM, .number]]

    var code: String { "%\(rawValue)" }
}

struct CursorScreenshotNameContext: Equatable, Sendable {
    var date: Date
    var app: String?
    var title: String?
    var zone = TimeZone.current
    var locale = CursorScreenshotNameContext.macLocale()

    static func macLocale(_ global: [String: Any] = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]) -> Locale {
        let identifier = global["AppleLocale"] as? String ?? (global["AppleLanguages"] as? [String])?.first ?? "en_US_POSIX"
        let on = { (key: String) in (global[key] as? NSNumber)?.boolValue ?? (global[key] as? NSString)?.boolValue ?? false }
        let hours = on("AppleICUForce12HourTime") ? "h12" : on("AppleICUForce24HourTime") ? "h23" : nil
        return Locale(identifier: hours.map { identifier + (identifier.contains("@") ? ";" : "@") + "hours=" + $0 } ?? identifier)
    }
}

struct CursorScreenshotFileName: Codable, Equatable, Sendable {
    var stem: String
    var number: Int?
    var retina: Bool

    func file(as format: CursorScreenshotFormat, copy: Int = 1) -> String {
        "\(stem)\(copy > 1 ? " \(copy)" : "")\(retina ? "@2x" : "").\(format.fileExtension)"
    }

    func freeFile(as format: CursorScreenshotFormat, in folder: URL) -> String {
        var copy = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(file(as: format, copy: copy)).path) { copy += 1 }
        return file(as: format, copy: copy)
    }

    func renamed(_ typed: String) -> CursorScreenshotFileName {
        CursorScreenshotFileName(stem: typed, number: nil, retina: retina)
    }

    func answered(_ typed: String) -> CursorScreenshotFileName {
        typed == stem ? self : renamed(typed)
    }
}

struct CursorScreenshotNaming: Codable, Equatable, Sendable {
    static let defaultFormat = "MaCursor %x at %H.%M.%S %p"
    static let longest = 200
    private static let pictureExtensions: Set<String> = Set(CursorScreenshotFormat.allCases.map(\.fileExtension) + ["jpeg"])
    private static let illegal = CharacterSet(charactersIn: "\\:*?\"<>|")
    private static let banned = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/"))

    var asksForName = false
    var format = defaultFormat
    var removesIllegalCharacters = true
    var addsRetinaSuffix = false
    var nextNumber = 1

    var readsWindow: Bool {
        format.contains(CursorScreenshotNameToken.appName.code) || format.contains(CursorScreenshotNameToken.windowTitle.code)
    }

    var counts: Bool {
        format.contains(CursorScreenshotNameToken.number.code)
    }

    func name(_ context: CursorScreenshotNameContext, scale: CGFloat, output: CursorScreenshotOutput) -> CursorScreenshotFileName {
        CursorScreenshotFileName(stem: stem(context), number: counts ? nextNumber : nil, retina: addsRetinaSuffix && output.shownScale(scale) > 1)
    }

    func stem(_ context: CursorScreenshotNameContext) -> String {
        let made = cleaned(expanded(format, context))
        return made.isEmpty ? cleaned(expanded(Self.defaultFormat, context)) : made
    }

    func typed(_ text: String) -> String? {
        var kept = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.pictureExtensions.contains((kept as NSString).pathExtension.lowercased()) {
            kept = (kept as NSString).deletingPathExtension
        }
        let made = cleaned(kept)
        return made.isEmpty ? nil : made
    }

    mutating func spend(_ name: CursorScreenshotFileName) -> Bool {
        guard let number = name.number, number < Int.max, number >= nextNumber else { return false }
        nextNumber = number + 1
        return true
    }

    func restoringDefaults() -> CursorScreenshotNaming {
        let fresh = CursorScreenshotNaming()
        var reset = self
        reset.format = fresh.format
        reset.removesIllegalCharacters = fresh.removesIllegalCharacters
        return reset
    }

    func keepingSheet(_ draft: CursorScreenshotNaming, opened: CursorScreenshotNaming) -> CursorScreenshotNaming {
        var kept = self
        kept.format = draft.format
        kept.removesIllegalCharacters = draft.removesIllegalCharacters
        if draft.nextNumber != opened.nextNumber { kept.nextNumber = max(1, draft.nextNumber) }
        return kept
    }

    private static func unquoted(_ pattern: String?) -> String {
        (pattern ?? "").replacingOccurrences(of: "'[^']*'", with: "", options: .regularExpression)
    }

    private static func regionDate(_ fields: [Character: String], _ locale: Locale) -> String {
        let read = unquoted(DateFormatter.dateFormat(fromTemplate: "yMMdd", options: 0, locale: locale))
        let pattern = "yMd".allSatisfy(read.contains) ? read : "y-MM-dd"
        let order = "yMd".sorted { (pattern.firstIndex(of: $0) ?? pattern.endIndex) < (pattern.firstIndex(of: $1) ?? pattern.endIndex) }
        let between = pattern.drop { $0 != order[0] }.drop { $0 == order[0] }.prefix { $0 != order[1] }
        let separator = between.trimmingCharacters(in: CharacterSet.whitespaces.union(.controlCharacters)) == "." ? "." : "-"
        return order.compactMap { fields[$0] }.joined(separator: separator)
    }

    private func expanded(_ format: String, _ context: CursorScreenshotNameContext) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = context.locale
        calendar.timeZone = context.zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: context.date)
        let hour = parts.hour ?? 0
        let twelveHour = Self.unquoted(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: context.locale)).contains { "hKa".contains($0) }
        let twoDigits = { (value: Int?) in String(format: "%02d", value ?? 0) }
        let fields: [Character: String] = ["y": String(format: "%04d", parts.year ?? 0), "M": twoDigits(parts.month), "d": twoDigits(parts.day)]
        var made = ""
        var rest = Substring(format)
        while let first = rest.popFirst() {
            guard first == "%", let next = rest.first, let token = CursorScreenshotNameToken(rawValue: next) else {
                made.append(first)
                continue
            }
            rest.removeFirst()
            switch token {
            case .date: made += Self.regionDate(fields, context.locale)
            case .year: made += fields["y"] ?? ""
            case .month: made += fields["M"] ?? ""
            case .day: made += fields["d"] ?? ""
            case .windowTitle: made += context.title ?? ""
            case .appName: made += context.app ?? ""
            case .hour: made += twoDigits(twelveHour ? (hour % 12 == 0 ? 12 : hour % 12) : hour)
            case .minutes: made += twoDigits(parts.minute)
            case .seconds: made += twoDigits(parts.second)
            case .amPM where twelveHour: made += hour < 12 ? calendar.amSymbol : calendar.pmSymbol
            case .amPM: if made.last == " " { made.removeLast() }
            case .number: made += String(nextNumber)
            }
        }
        return made
    }

    private func cleaned(_ text: String) -> String {
        let banned = removesIllegalCharacters ? Self.banned.union(Self.illegal) : Self.banned
        var kept = String(String.UnicodeScalarView(text.unicodeScalars.filter { !banned.contains($0) })).trimmingCharacters(in: .whitespaces)
        while kept.hasPrefix(".") {
            kept = String(kept.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        var cut = ""
        for character in kept {
            guard cut.utf8.count + String(character).utf8.count <= Self.longest else { break }
            cut.append(character)
        }
        return cut
    }
}

extension CursorScreenshotNaming {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        asksForName = (try? container.decode(Bool.self, forKey: .asksForName)) ?? false
        if let format = try? container.decode(String.self, forKey: .format), !format.isEmpty {
            self.format = format
        }
        removesIllegalCharacters = (try? container.decode(Bool.self, forKey: .removesIllegalCharacters)) ?? true
        addsRetinaSuffix = (try? container.decode(Bool.self, forKey: .addsRetinaSuffix)) ?? false
        if let number = try? container.decode(Int.self, forKey: .nextNumber), number >= 1 {
            nextNumber = number
        }
    }
}
