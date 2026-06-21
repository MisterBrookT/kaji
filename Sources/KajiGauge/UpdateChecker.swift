import Foundation
import Combine

// MARK: - UpdateChecker
//
// Lightweight, privacy-respecting update check for an UNSIGNED menubar app.
//
// On launch (and at most once per `minInterval`) it asks the GitHub Releases
// API for the latest published tag and compares it to this bundle's version.
// If a newer one exists it publishes `available`, which drives a passive cue:
// a dot on the menubar glyph + an "Update to vX" item in the right-click menu
// that opens the release page.
//
// Deliberately NOT a silent self-replace: the app ships unsigned, so a swapped
// binary would be quarantined and Gatekeeper-blocked on next launch. A one-tap
// "open the release" is the honest UX until the app is signed + notarized (then
// this can graduate to Sparkle with a real appcast). The check hits only the
// public GitHub API — no telemetry, no account, no payload sent.
@MainActor
final class UpdateChecker: ObservableObject {
    static let repo = "interesting-vibe-coding/kaji-gauge"

    struct Release: Equatable {
        let version: String   // normalized, e.g. "0.4.6"
        let tag: String       // raw tag, e.g. "v0.4.6"
        let url: URL          // release html_url
    }

    /// nil = up to date / unknown; non-nil = a strictly newer release exists.
    @Published private(set) var available: Release?

    private let session = URLSession(configuration: .ephemeral)
    private var lastCheck: Date?
    private var inFlight = false
    private let minInterval: TimeInterval = 6 * 3600

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Start a check unless one ran within `minInterval` (use force from a
    /// manual "Check for updates" action).
    func checkIfDue(force: Bool = false) {
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < minInterval { return }
        lastCheck = Date()
        Task { await check() }
    }

    func check() async {
        // Coalesce concurrent checks (e.g. rapid "Check for Updates" clicks) into
        // a single in-flight request. Safe to read/write unguarded: @MainActor.
        if inFlight { return }
        inFlight = true
        defer { inFlight = false }
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("KajiGauge", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["draft"] as? Bool) != true,
                  (obj["prerelease"] as? Bool) != true,
                  let tag = obj["tag_name"] as? String,
                  let htmlURL = (obj["html_url"] as? String).flatMap(URL.init(string:))
            else { return }
            let latest = Self.normalize(tag)
            if Self.isNewer(latest, than: Self.normalize(currentVersion)) {
                available = Release(version: latest, tag: tag, url: htmlURL)
            } else {
                available = nil
            }
        } catch {
            // Offline / rate-limited / transient — stay silent, retry next due.
        }
    }

    // "v0.4.6" -> "0.4.6", "v0.4.6-beta.1" -> "0.4.6". (Pre-releases are already
    // filtered out by the API query, so this only hardens the comparison.)
    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.first == "v" || t.first == "V" { t.removeFirst() }
        if let dash = t.firstIndex(of: "-") { t = String(t[..<dash]) }
        return t
    }

    /// Semver-ish compare on dot-separated integer components (missing = 0).
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
