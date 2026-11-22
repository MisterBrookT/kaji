import Foundation

// GPU monitor (opt-in module, brook 11-22): Kaji never ssh-es. mlkit's scheduler
// writes `~/.mlkit/gpus.json` (schema 1, mlkit docs/method/hosts.md); Kaji only
// reads it. Unknown fields are ignored; nullable numbers stay nil.

public struct GpuCard: Decodable, Equatable, Sendable, Identifiable {
    public let gpu: Int
    public let usedMB: Int?
    public let totalMB: Int?
    public let util: Int?
    public let who: String
    public var id: Int { gpu }

    public var freeMB: Int? {
        guard let usedMB, let totalMB else { return nil }
        return max(0, totalMB - usedMB)
    }

    enum CodingKeys: String, CodingKey {
        case gpu, util, who
        case usedMB = "used_mb"
        case totalMB = "total_mb"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gpu = try c.decode(Int.self, forKey: .gpu)
        usedMB = try c.decodeIfPresent(Int.self, forKey: .usedMB)
        totalMB = try c.decodeIfPresent(Int.self, forKey: .totalMB)
        util = try c.decodeIfPresent(Int.self, forKey: .util)
        who = (try c.decodeIfPresent(String.self, forKey: .who)) ?? ""
    }
}

public struct GpuHost: Decodable, Equatable, Sendable, Identifiable {
    public let name: String
    public let up: Bool
    public let cards: [GpuCard]
    public var id: String { name }
}

public struct GpuJob: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String?
    public let `where`: [String]
    public let owner: String?
    public let state: String?
    public let age: Int?
}

public struct GpuSnapshot: Decodable, Equatable, Sendable {
    public let schema: Int
    public let time: Double
    public let avgUtil: Double?
    public let hosts: [GpuHost]
    public let jobs: [GpuJob]

    /// The scheduler writes about once a minute while it runs and exits when idle.
    public static let staleAfter: TimeInterval = 15 * 60

    enum CodingKeys: String, CodingKey {
        case schema, time, hosts, jobs
        case avgUtil = "avg_util"
    }

    public static func decode(_ data: Data) throws -> GpuSnapshot {
        try JSONDecoder().decode(GpuSnapshot.self, from: data)
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mlkit/gpus.json")
    }

    public var date: Date { Date(timeIntervalSince1970: time) }
    public func isStale(now: Date = Date()) -> Bool { now.timeIntervalSince(date) > Self.staleAfter }
    public var totalCards: Int { hosts.reduce(0) { $0 + $1.cards.count } }
    public var busyCards: Int { hosts.reduce(0) { $0 + $1.cards.filter { !$0.who.isEmpty }.count } }
}

public enum GpuFormat {
    public static func memory(_ c: GpuCard) -> String {
        guard let u = c.usedMB, let t = c.totalMB, t > 0 else { return "mem n/a" }
        return "\(u / 1024)/\(t / 1024) GB"
    }

    public static func util(_ u: Int?) -> String {
        guard let u else { return "\u{2014}" }
        return "\(u)%"
    }

    /// "42m", "1h01m", "3d".
    public static func age(_ s: Int?) -> String {
        guard let s else { return "" }
        if s >= 86_400 { return "\(s / 86_400)d" }
        if s >= 3600 { return String(format: "%dh%02dm", s / 3600, s % 3600 / 60) }
        return "\(max(1, s / 60))m"
    }

    /// Menu-bar text: average util over reporting cards.
    public static func menuBarLabel(_ s: GpuSnapshot?) -> String {
        guard let a = s?.avgUtil else { return "\u{2014}" }
        return "\(Int(a.rounded()))%"
    }
}
