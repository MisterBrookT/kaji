import Foundation
import Combine

// MARK: - Configuration constants
enum Config {
    /// Default path to the helm-quota script. Overridable at runtime via the
    /// UserDefaults key below (see `quotaScriptPath`).
    static let defaultQuotaScriptPath =
        "/Users/tangyinghao/workspace/helm-terminal/tools/helm-quota/quota.py"

    /// python3 interpreter. We rely on PATH resolution via /usr/bin/env.
    static let pythonInterpreter = "python3"

    /// Poll interval, seconds.
    static let refreshInterval: TimeInterval = 30

    /// Max sparkline history points kept per provider.
    static let sparklineHistoryMax = 48

    // UserDefaults keys.
    static let kQuotaScriptPath = "quotaScriptPath"
    static let kPanelVisible    = "panelVisible"
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
    let plan: String?
    let history: [Double]          // rolling 5h used% samples for the sparkline

    /// 0...1 fraction for the ring trim. Clamped. nil percent -> 0 (empty ring).
    var usedFraction: Double {
        guard let p = fiveHourPercent else { return 0 }
        return min(max(p / 100.0, 0), 1)
    }

    /// Near-limit alert state — the >=80% threshold deepens the ring to AMBER
    /// (same warm family, no glow) plus non-color emphasis (thicker cap / tick).
    var isNearLimit: Bool {
        (fiveHourPercent ?? 0) >= 80
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

    var scriptPath: String {
        UserDefaults.standard.string(forKey: Config.kQuotaScriptPath)
            ?? Config.defaultQuotaScriptPath
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

    nonisolated private static func runScript(path: String) -> ScriptResult {
        let proc = Process()
        // Use /usr/bin/env so python3 resolves via PATH.
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [Config.pythonInterpreter, path, "--json"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
        } catch {
            return .failure("launch failed: \(error.localizedDescription)")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

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
            // Still bump the timestamp so the user sees we tried.
            return
        case .success(let snap):
            lastError = nil
            lastUpdated = Date()
            ingest(snap)
        }
    }

    private func ingest(_ snap: QuotaSnapshot) {
        // Only show providers that have a `limits` block (a quota to gauge).
        // Providers like kiro/opencode with no limits are skipped from the
        // rings — there is nothing to ring-gauge.
        let keys = Providers.sorted(snap.keys.filter {
            snap[$0]?.limits != nil && Providers.isVisible($0)
        })

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
