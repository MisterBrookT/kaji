import Foundation
import SQLite3

// MARK: - Accounts (shared with pix accountkit)
//
// Kaji is display only. quota.py emits one entry per account under "accounts"
// (numbers + the time each was really fetched). Which account is in use is
// pix's decision: Kaji reads pix's printout (pix.db kv "route", brook 11-20:
// code-written state is in ~/.pix/pix.db) and never derives it. The one thing
// Kaji writes is the pin, "route.claude" in the hand-edited ~/.pix/config.json.

struct AccountQuota: Codable, Equatable {
    let id: String
    let provider: String
    let label: String
    let ready: Bool?
    let limits: ProviderLimits?
    /// Epoch ms the reading was really fetched (quota.py `checked_at`: cache
    /// fetch time, never "now" for a cached number); nil = unknown.
    var checkedAt: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, provider, label, ready, limits
        case checkedAt = "checked_at"
    }
}

/// pix's printout of the route it is using (pix.db kv "route"). Read-only.
struct PixRoute: Equatable {
    var claude: String?
    var codex: String?
}

/// What a single account row can honestly claim.
enum AccountState: Equatable {
    case ok
    case signedOut      // profile has no login (ready == false)
    case unknown        // signed in, but no quota reading
    case stale          // last reading older than `staleAfterMs`
}

struct PixAccountsFiles {
    var home: URL

    static var standard: PixAccountsFiles {
        let env = ProcessInfo.processInfo.environment["PIX_HOME"]
        return PixAccountsFiles(home: env.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pix"))
    }

    private var configURL: URL { home.appendingPathComponent("config.json") }
    private var config: [String: Any]? {
        guard let data = try? Data(contentsOf: configURL) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// pix.db kv value (JSON) for `key`, read-only; nil when absent.
    func kv(_ key: String) -> Any? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let path = home.appendingPathComponent("pix.db").path
        guard FileManager.default.fileExists(atPath: path),
              sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 2000)
        var st: OpaquePointer?
        defer { sqlite3_finalize(st) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM kv WHERE key=?", -1, &st, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(st, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(st) == SQLITE_ROW, let t = sqlite3_column_text(st, 0) else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(String(cString: t).utf8), options: [.fragmentsAllowed])
    }

    /// Raw route: "auto" or an account id (validated by the caller). config.json `route.claude`.
    var route: String {
        let v = ((config?["route"] as? [String: Any])?["claude"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "auto" : v
    }

    /// Set `route.claude` in config.json, keeping every other key brook wrote. A config.json that
    /// does not parse is left alone (throws).
    func writeRoute(_ value: String) throws {
        guard var c = config else { throw CocoaError(.fileReadCorruptFile) }
        var r = c["route"] as? [String: Any] ?? [:]
        r["claude"] = value
        c["route"] = r
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: c, options: [.prettyPrinted, .sortedKeys])
        try (data + Data("\n".utf8)).write(to: configURL, options: .atomic)
    }

    /// Account pix is using per provider, from pix's printout (kv "route"):
    /// `accounts.claude ?? account`, `accounts.codex`. Empty when missing.
    var current: PixRoute {
        let d = kv("route") as? [String: Any] ?? [:]
        let per = d["accounts"] as? [String: Any]
        func id(_ v: Any?) -> String? { (v as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return PixRoute(claude: id(per?["claude"]) ?? id(d["account"]), codex: id(per?["codex"]))
    }
}

enum AccountRouting {
    static let staleAfterMs: Double = 15 * 60 * 1000

    /// % left of one window (100 - used); nil stays nil, never 100.
    static func left(_ used: Double?) -> Double? {
        used.map { min(100, max(0, 100 - $0)) }
    }

    static func state(ready: Bool?, hasReading: Bool, checkedAt: Double?, nowMs: Double) -> AccountState {
        if ready == false { return .signedOut }
        if !hasReading { return .unknown }
        if let checkedAt, nowMs - checkedAt > staleAfterMs { return .stale }
        return .ok
    }

    /// % left = 100 - the tighter window's used %.
    static func percentLeft(_ v: ProviderView) -> Double? {
        let used = [v.fiveHourPercent, v.weekPercent].compactMap { $0 }.max()
        return used.map { max(0, 100 - $0) }
    }

    /// The Claude account in use: a pin (config.json route.claude) naming a known account
    /// wins; otherwise whatever pix printed (pix.db kv route); nil when neither.
    static func currentClaudeID(accounts: [AccountQuota], route: String, current: PixRoute) -> String? {
        if route != "auto", accounts.contains(where: { $0.provider == "claude" && $0.id == route }) { return route }
        return current.claude
    }
}

/// Account copy, kept pure so tests can pin the wording.
enum AccountCopy {
    static func header(active: String?, pinned: Bool) -> String {
        "Using \(active ?? "—") · \(pinned ? "Pinned" : "Auto")"
    }

    static func summary(left: Double?, state: AccountState) -> String {
        switch state {
        case .signedOut: return "signed out"
        case .unknown: return "unknown"
        case .stale: return left.map { "\(Int($0.rounded()))% left · stale" } ?? "stale"
        case .ok: return left.map { "\(Int($0.rounded()))% left" } ?? "unknown"
        }
    }
}

/// Which account rows are open. Until the user toggles one, only the active
/// account is open; after that the user's choice survives refreshes.
struct AccountExpansion: Equatable {
    private(set) var userChoice: Set<String>?

    func isExpanded(_ id: String, active: Bool) -> Bool {
        userChoice?.contains(id) ?? active
    }

    mutating func toggle(_ id: String, accounts: [ProviderView]) {
        var set = userChoice ?? Set(accounts.filter(\.isActiveAccount).map(\.id))
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        userChoice = set
    }
}

/// Only a fresh, known zero is exhausted. Quota is not model availability.
enum AccountPinPolicy {
    static func requiresConfirmation(_ account: ProviderView) -> Bool {
        account.logo == "claude" && account.accountState == .ok && account.percentLeft == 0
    }
}
