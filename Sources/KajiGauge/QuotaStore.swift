import Foundation
import Combine

// MARK: - Configuration constants
enum Config {
    /// Dev fallback ONLY (used by `swift run`, which has no app bundle). The
    /// shipped .app uses the self-contained copy bundled in Contents/Resources
    /// (see `QuotaStore.scriptPath`); end users never need this path.
    static let defaultQuotaScriptPath =
        "/Users/tangyinghao/workspace/kaji/tools/helm-quota/quota.py"

    /// Candidate python3 interpreters, probed in order. A .app launched from
    /// Finder inherits a MINIMAL PATH (/usr/bin:/bin:/usr/sbin:/sbin) — not the
    /// user's shell PATH — so `/usr/bin/env python3` can't see Homebrew's
    /// python, and `/usr/bin/python3` is only the Command Line Tools STUB on a
    /// machine without dev tools (it prompts to install Xcode and exits non-
    /// zero). We probe each candidate with `--version` and use the first that
    /// actually runs, so non-developer users aren't left with a dead panel.
    static let pythonCandidates = [
        "/opt/homebrew/bin/python3",   // Apple Silicon Homebrew
        "/usr/local/bin/python3",      // Intel Homebrew
        "/usr/bin/python3",            // system / Command Line Tools (may be a stub)
    ]

    /// Sentinel surfaced when NO working python3 was found — the UI maps this to
    /// an actionable onboarding message instead of a raw subprocess error.
    static let noPythonSentinel = "__no_python__"

    /// Poll interval, seconds.
    static let refreshInterval: TimeInterval = 30

    /// Max sparkline history points kept per provider.
    static let sparklineHistoryMax = 48

    // UserDefaults keys.
    static let kQuotaScriptPath = "quotaScriptPath"
    static let kPythonInterpreter = "pythonInterpreter" // user override (optional)
    static let kPanelVisible    = "panelVisible"
    static let kPanelDockEdge   = "panelDockEdge"  // "left" | "right" | "top" | "bottom"
    static let kSparkHistory    = "sparklineHistory" // [providerKey: [Double]]
}

// A single provider's view-ready data, decoupled from the raw Codable model.
struct ProviderView: Identifiable, Equatable {
    let id: String            // provider key, e.g. "claude"
    let mark: String
    let displayName: String
    let fiveHourPercent: Double?   // nil -> render "—"
    let weekPercent: Double?
    let tokensToday: Int?
    let resetDate: Date?           // five-hour reset
    let weekResetDate: Date?       // seven-day reset
    let plan: String?
    let history: [Double]          // rolling 5h used% samples for the sparkline

    /// 0...1 fraction for the 5h ring trim. Clamped. nil percent -> 0 (empty).
    var usedFraction: Double {
        guard let p = fiveHourPercent else { return 0 }
        return min(max(p / 100.0, 0), 1)
    }

    /// 0...1 fraction for the inner 7-day ring trim.
    var weekFraction: Double {
        guard let p = weekPercent else { return 0 }
        return min(max(p / 100.0, 0), 1)
    }

    /// Near-limit alert state — the >=80% threshold deepens the ring to AMBER
    /// (same warm family, no glow) plus non-color emphasis (thicker cap / tick).
    var isNearLimit: Bool {
        (fiveHourPercent ?? 0) >= 80
    }

    /// 7-day near-limit — deepens the inner ring to amber the same way.
    var weekNearLimit: Bool {
        (weekPercent ?? 0) >= 80
    }

    var hasData: Bool { fiveHourPercent != nil }
}

// MARK: - QuotaStore
//
// Runs quota.py on a timer, decodes the JSON, maintains a rolling per-provider
// history of 5h used% for the sparkline, and publishes view-ready providers.
//
// SPARKLINE NOTE: quota.py does not expose 24h history. We approximate it by
// appending each polled 5h used% sample to a rolling buffer (persisted in
// UserDefaults so it survives restarts). It seeds empty and fills over time;
// early on the sparkline will be short or flat. This is intentional — there is
// no real historical series to draw from.
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var providers: [ProviderView] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?
    private var history: [String: [Double]] = [:]

    init() {
        loadHistory()
    }

    /// Seed a store with fixed data for previews / offscreen snapshots. Does not
    /// start the poll timer or touch UserDefaults.
    init(previewProviders: [ProviderView], updated: Date? = nil) {
        self.providers = previewProviders
        self.lastUpdated = updated
    }

    /// Resolve the quota reader, in priority order:
    ///   1. a user override in UserDefaults (`quotaScriptPath`)
    ///   2. the copy bundled inside the .app (Contents/Resources/quota.py) —
    ///      this is what makes the shipped app self-contained (no helm-terminal)
    ///   3. a dev fallback for `swift run` (no bundle present)
    var scriptPath: String {
        if let override = UserDefaults.standard.string(forKey: Config.kQuotaScriptPath),
           !override.isEmpty {
            return override
        }
        if let bundled = Bundle.main.url(forResource: "quota", withExtension: "py") {
            return bundled.path
        }
        return Config.defaultQuotaScriptPath
    }

    func start() {
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: Config.refreshInterval,
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 5
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Run quota.py off the main thread, then fold results back on main.
    func refresh() {
        let path = scriptPath
        Task.detached(priority: .utility) {
            let result = Self.runScript(path: path)
            await MainActor.run { self.apply(result) }
        }
    }

    // MARK: - Script execution

    private enum ScriptResult {
        case success(QuotaSnapshot)
        case failure(String)
    }

    // Resolved python3 path, cached after the first successful probe so we don't
    // spawn `--version` checks every 30s poll. Guarded by a lock (runScript runs
    // on a detached task).
    nonisolated(unsafe) private static var cachedInterpreter: String?
    nonisolated private static let interpreterLock = NSLock()

    /// First python3 candidate that actually runs. Rejects the Command Line
    /// Tools stub (which exits non-zero) by requiring `--version` to succeed.
    nonisolated private static func resolveInterpreter() -> String? {
        interpreterLock.lock()
        defer { interpreterLock.unlock() }
        if let cached = cachedInterpreter { return cached }
        var candidates: [String] = []
        if let override = UserDefaults.standard.string(forKey: Config.kPythonInterpreter),
           !override.isEmpty {
            candidates.append(override)
        }
        candidates += Config.pythonCandidates
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if probeInterpreter(path) {
                cachedInterpreter = path
                return path
            }
        }
        return nil
    }

    /// True if `<path> --version` exits 0 within a few seconds. The CLT stub at
    /// /usr/bin/python3 exits non-zero (and prints an install prompt), so this
    /// naturally rejects it.
    nonisolated private static func probeInterpreter(_ path: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["--version"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { return false }
        // Watchdog: a hung candidate would otherwise hold `interpreterLock`
        // forever and freeze every future refresh. `--version` is instant; kill
        // after 5s.
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: killer)
        p.waitUntilExit()
        killer.cancel()
        return p.terminationStatus == 0
    }

    nonisolated private static func runScript(path: String) -> ScriptResult {
        guard let interpreter = resolveInterpreter() else {
            return .failure(Config.noPythonSentinel)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: interpreter)
        proc.arguments = [path, "--json"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return .failure("launch failed: \(error.localizedDescription)")
        }

        // Watchdog: quota.py's network/subprocess calls are individually bounded
        // (~10s each, cached 180s), so a healthy run finishes well under this.
        // A genuine hang (wedged interpreter / stuck child) would otherwise pin
        // a detached worker forever — terminate, then hard-kill.
        let killer = DispatchWorkItem {
            if proc.isRunning { proc.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: killer)

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        killer.cancel()

        if proc.terminationStatus != 0 {
            let err = String(data: errData, encoding: .utf8) ?? ""
            return .failure("exit \(proc.terminationStatus): \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        guard !outData.isEmpty else {
            return .failure("empty output")
        }

        do {
            let snap = try JSONDecoder().decode(QuotaSnapshot.self, from: outData)
            return .success(snap)
        } catch {
            return .failure("decode failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Apply results

    private func apply(_ result: ScriptResult) {
        switch result {
        case .failure(let msg):
            // Keep the last good data on screen; just surface the error.
            lastError = msg
            // Raw error stays in the log for debugging even though the empty
            // state shows a friendlier message.
            NSLog("[KajiGauge] quota refresh failed: %@", msg)
            // Still bump the timestamp so the user sees we tried.
            return
        case .success(let snap):
            lastError = nil
            lastUpdated = Date()
            ingest(snap)
        }
    }

    private func ingest(_ snap: QuotaSnapshot) {
        // Keep every display-ready provider emitted by quota.py in the store.
        // Visibility is a user preference applied by the views; filtering only
        // to default-visible providers here would hide Ark from the toggles.
        let keys = Providers.sorted(snap.keys.filter { Providers.isAvailable($0) })

        var views: [ProviderView] = []
        for key in keys {
            guard let q = snap[key] else { continue }
            let limits = q.limits
            let five = limits?.fiveHourUsedPercent

            // Append to rolling history only when we have a real sample.
            if let five = five {
                var arr = history[key] ?? []
                arr.append(five)
                if arr.count > Config.sparklineHistoryMax {
                    arr.removeFirst(arr.count - Config.sparklineHistoryMax)
                }
                history[key] = arr
            }

            views.append(ProviderView(
                id: key,
                mark: Providers.mark(for: key),
                displayName: Providers.displayName(for: key),
                fiveHourPercent: five,
                weekPercent: limits?.sevenDayUsedPercent,
                tokensToday: q.tokensToday,
                resetDate: limits?.fiveHourResetsAt?.date,
                weekResetDate: limits?.sevenDayResetsAt?.date,
                plan: limits?.plan,
                history: history[key] ?? []
            ))
        }

        providers = views
        saveHistory()
    }

    /// The provider closest to its limit — drives the menubar indicator.
    var mostConstrained: ProviderView? {
        providers
            .filter { $0.fiveHourPercent != nil }
            .max { ($0.fiveHourPercent ?? 0) < ($1.fiveHourPercent ?? 0) }
    }

    // MARK: - History persistence

    private func loadHistory() {
        if let dict = UserDefaults.standard.dictionary(forKey: Config.kSparkHistory)
            as? [String: [Double]] {
            history = dict
        }
    }

    private func saveHistory() {
        UserDefaults.standard.set(history, forKey: Config.kSparkHistory)
    }
}
