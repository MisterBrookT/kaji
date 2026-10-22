import Foundation

// MARK: - Accounts (shared with pix accountkit)
//
// quota.py emits one entry per account under "accounts"; the route and usage
// cache live in ~/.pix (owned by pix accountkit.ts). Kaji mirrors pix's band
// rule to mark the active Claude account and can pin one via claude-route.
// Codex accounts are display-only.

struct AccountQuota: Codable, Equatable {
    let id: String
    let provider: String
    let label: String
    let ready: Bool?
    let limits: ProviderLimits?
}

struct AccountUsage: Equatable {
    var left: Double?
    var coolUntil: Double?   // epoch ms
    var checkedAt: Double? = nil   // epoch ms of the last quota.py reading
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

    private func json(_ name: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(name)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    /// Band width knob from accounts.json "band" (default 25).
    var bandWidth: Double {
        let v = (json("accounts.json")["band"] as? NSNumber)?.doubleValue ?? 25
        return v > 0 ? v : 25
    }

    /// Raw route: "auto" or an account id (validated by the caller).
    var route: String {
        let s = (try? String(contentsOf: home.appendingPathComponent("claude-route"), encoding: .utf8)) ?? ""
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "auto" : v
    }

    func writeRoute(_ value: String) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try (value + "\n").write(to: home.appendingPathComponent("claude-route"), atomically: true, encoding: .utf8)
    }

    var usage: [String: AccountUsage] {
        var out: [String: AccountUsage] = [:]
        for (id, v) in json("accounts-usage.json") {
            guard let d = v as? [String: Any] else { continue }
            out[id] = AccountUsage(left: (d["left"] as? NSNumber)?.doubleValue,
                                   coolUntil: (d["coolUntil"] as? NSNumber)?.doubleValue,
                                   checkedAt: (d["checkedAt"] as? NSNumber)?.doubleValue)
        }
        return out
    }

    var storedActive: String? {
        (json("accounts-usage.json")["_active"] as? [String: Any])?["id"] as? String
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

    /// Mirrors pix accountkit `plan()[0]`: a valid pinned route wins; otherwise
    /// keep the stored active account unless another ready, not-cooling account
    /// sits in a STRICTLY higher band of % left (ties stay; unknown = lowest).
    static func activeClaudeID(accounts: [AccountQuota], route: String,
                               usage: [String: AccountUsage], storedActive: String?,
                               bandWidth: Double, nowMs: Double) -> String? {
        let claude = accounts.filter { $0.provider == "claude" }
        if route != "auto", claude.contains(where: { $0.id == route }) { return route }
        func band(_ a: AccountQuota) -> Double {
            guard let left = usage[a.id]?.left else { return -1 }
            return (left / bandWidth).rounded(.down)
        }
        let awake = claude.filter { a in
            guard a.ready ?? true else { return false }
            if let cool = usage[a.id]?.coolUntil, nowMs < cool { return false }
            return true
        }
        var pick = awake.first { $0.id == storedActive } ?? awake.first
        for a in awake where pick.map({ band(a) > band($0) }) ?? false { pick = a }
        return pick?.id
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
