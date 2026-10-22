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
                                   coolUntil: (d["coolUntil"] as? NSNumber)?.doubleValue)
        }
        return out
    }

    var storedActive: String? {
        (json("accounts-usage.json")["_active"] as? [String: Any])?["id"] as? String
    }
}

enum AccountRouting {
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
