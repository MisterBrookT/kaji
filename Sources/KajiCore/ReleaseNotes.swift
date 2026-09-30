import Foundation

/// Changelog shown before a manual update, parsed from a GitHub release body.
///
/// Recognised section headings (Markdown `#`, bold `**…**` or a trailing
/// colon) map to Fixed / Added / Removed; bullets under any other heading, or
/// under no heading, land in `other`. Items are plain text: Markdown emphasis
/// and link syntax are stripped so nothing in the body becomes clickable.
public struct ReleaseNotes: Equatable, Sendable {
    public enum Category: String, CaseIterable, Sendable {
        case fixed, added, removed, other
    }

    public var fixed: [String] = []
    public var added: [String] = []
    public var removed: [String] = []
    public var other: [String] = []

    public init(fixed: [String] = [], added: [String] = [], removed: [String] = [], other: [String] = []) {
        self.fixed = fixed
        self.added = added
        self.removed = removed
        self.other = other
    }

    public var isEmpty: Bool { fixed.isEmpty && added.isEmpty && removed.isEmpty && other.isEmpty }

    public func items(_ category: Category) -> [String] {
        switch category {
        case .fixed: fixed
        case .added: added
        case .removed: removed
        case .other: other
        }
    }

    /// Upper bounds so an oversized release body cannot bloat the sheet.
    static let maxBodyCharacters = 20_000
    static let maxItemsPerCategory = 30

    public static func parse(_ body: String?) -> ReleaseNotes {
        guard let body, !body.isEmpty else { return ReleaseNotes() }
        var notes = ReleaseNotes()
        var current: Category = .other
        for rawLine in String(body.prefix(maxBodyCharacters)).components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let heading = headingText(line) {
                current = category(forHeading: heading)
                continue
            }
            guard let item = bulletText(line) else { continue }
            let text = plainText(item)
            guard !text.isEmpty else { continue }
            notes.append(text, to: current)
        }
        return notes
    }

    private mutating func append(_ text: String, to category: Category) {
        switch category {
        case .fixed: if fixed.count < Self.maxItemsPerCategory { fixed.append(text) }
        case .added: if added.count < Self.maxItemsPerCategory { added.append(text) }
        case .removed: if removed.count < Self.maxItemsPerCategory { removed.append(text) }
        case .other: if other.count < Self.maxItemsPerCategory { other.append(text) }
        }
    }

    private static func headingText(_ line: String) -> String? {
        if line.hasPrefix("#") {
            return String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
        }
        if line.hasPrefix("**"), line.hasSuffix("**") || line.hasSuffix("**:"), line.count > 4 {
            return line.replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        }
        if line.hasSuffix(":"), !isBullet(line), line.count <= 40 {
            return String(line.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    public static func category(forHeading heading: String) -> Category {
        let h = heading.lowercased()
        if h.hasPrefix("fix") || h.contains("bug") { return .fixed }
        if h.hasPrefix("add") || h.hasPrefix("new") || h.contains("feature") { return .added }
        if h.hasPrefix("remov") || h.hasPrefix("delet") || h.hasPrefix("deprecat") { return .removed }
        return .other
    }

    private static func isBullet(_ line: String) -> Bool { bulletText(line) != nil }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        // "1. item"
        if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty {
            let rest = line[line.index(after: dot)...]
            if rest.first == " " { return String(rest.dropFirst()) }
        }
        return nil
    }

    /// `[label](url)` → `label`; drops `**`, `__`, backticks.
    static func plainText(_ s: String) -> String {
        var out = s
        if let regex = try? NSRegularExpression(pattern: #"!?\[([^\]]*)\]\([^)]*\)"#) {
            out = regex.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1")
        }
        for token in ["**", "__", "`"] { out = out.replacingOccurrences(of: token, with: "") }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
