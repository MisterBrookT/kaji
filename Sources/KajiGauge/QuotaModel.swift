import Foundation

// MARK: - Quota data model
//
// Mirrors the JSON emitted by:
//   python3 helm-terminal/tools/helm-quota/quota.py --json
//
// Observed schema (2026-06):
//   {
//     "claude": {
//       "tokens_today": 618003,
//       "sessions_today": 2,
//       "limits": {
//         "five_hour_used_percent": 44.0,
//         "five_hour_resets_at": "2026-06-13T06:30:00.722666+00:00",  // ISO 8601
//         "seven_day_used_percent": 5.0,
//         "seven_day_resets_at": "2026-06-15T12:00:00.722690+00:00",
//         "plan": "..."          // optional
//       },
//       "by_project": {...},     // ignored here
//       "context": {...}         // ignored here
//     },
//     "codex": {
//       "tokens_today": 0,
//       "sessions_today": 0,
//       "limits": {
//         "five_hour_used_percent": 1,
//         "five_hour_resets_at": 1781341233,   // NOTE: unix epoch INT here, not ISO
//         "seven_day_used_percent": 3,
//         "seven_day_resets_at": 1781774199,
//         "plan": "plus"
//       }
//     },
//     "kiro":     { "tokens_today": 0, "sessions_today": 0 },   // no limits
//     "opencode": { "tokens_today": 0, "sessions_today": 0 }
//   }
//
// Graceful fallback is a hard requirement: any missing field decodes to nil,
// and the UI renders "—" rather than crashing.

// A reset timestamp can arrive as an ISO-8601 string (claude) OR a unix epoch
// number (codex). This wrapper accepts either and normalizes to a Date.
struct ResetTimestamp: Codable, Equatable {
    let date: Date?

    init(date: Date?) { self.date = date }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let epoch = try? c.decode(Double.self) {
            self.date = Date(timeIntervalSince1970: epoch)
        } else if let s = try? c.decode(String.self) {
            self.date = ResetTimestamp.parseISO(s)
        } else {
            self.date = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(date?.timeIntervalSince1970)
    }

    // ISO8601DateFormatter is thread-safe for read-only use; mark unsafe to
    // satisfy Swift 6 strict concurrency (the class isn't Sendable).
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        return isoNoFrac.date(from: s)
    }
}

struct ProviderLimits: Codable, Equatable {
    let fiveHourUsedPercent: Double?
    let fiveHourResetsAt: ResetTimestamp?
    let sevenDayUsedPercent: Double?
    let sevenDayResetsAt: ResetTimestamp?
    let plan: String?

    enum CodingKeys: String, CodingKey {
        case fiveHourUsedPercent = "five_hour_used_percent"
        case fiveHourResetsAt    = "five_hour_resets_at"
        case sevenDayUsedPercent = "seven_day_used_percent"
        case sevenDayResetsAt    = "seven_day_resets_at"
        case plan
    }
}

struct ProviderQuota: Codable, Equatable {
    let tokensToday: Int?
    let sessionsToday: Int?
    let limits: ProviderLimits?

    enum CodingKeys: String, CodingKey {
        case tokensToday   = "tokens_today"
        case sessionsToday = "sessions_today"
        case limits
        // by_project / context intentionally omitted — not needed by the UI.
    }
}

// The top-level object is a free-form map of provider-name -> ProviderQuota.
typealias QuotaSnapshot = [String: ProviderQuota]
