import Foundation
import Combine
import Darwin

// MARK: - Configuration constants
enum Config {
    /// Dev fallback ONLY (used by `swift run`, which has no app bundle). The
    /// shipped .app uses the self-contained copy bundled in Contents/Resources
    /// (see `QuotaStore.scriptPath`); end users never need this path.
    static let defaultQuotaScriptPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/quota.py")
        .path

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


    // UserDefaults keys.
    static let kQuotaScriptPath = "quotaScriptPath"
    static let kPythonInterpreter = "pythonInterpreter" // user override (optional)
}

// A single provider's view-ready data, decoupled from the raw Codable model.
struct ProviderView: Identifiable, Equatable {
    let id: String            // provider key, e.g. "claude"
    let mark: String
    let displayName: String
    let fiveHourPercent: Double?   // nil -> render "—"
    let weekPercent: Double?
    let resetDate: Date?           // five-hour reset
    let weekResetDate: Date?       // seven-day reset

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
// Runs quota.py on a timer, decodes the JSON, and publishes view-ready providers.
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var providers: [ProviderView] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?

    private var timer: Timer?
    private let isPreview: Bool
    private let runner: @Sendable (String) -> ScriptResult
    private var inFlight: Task<Void, Never>?
    private var pendingRefresh = false
    private var generation = 0

    init() {
        isPreview = false
        runner = { Self.runScript(path: $0) }
        UserDefaults.standard.removeObject(forKey: "sparklineHistory")
        UserDefaults.standard.removeObject(forKey: "tokenHistory")
        UserDefaults.standard.removeObject(forKey: "tokenHistoryV2")
    }

    /// Seed a store with fixed data for previews / offscreen snapshots. Does not
    /// start the poll timer or touch UserDefaults.
    init(previewProviders: [ProviderView], updated: Date? = nil) {
        isPreview = true
        runner = { _ in .failure("preview") }
        self.providers = previewProviders
        self.lastUpdated = updated
    }

    init(runner: @escaping @Sendable (String) -> ScriptResult) {
        isPreview = false
        self.runner = runner
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
        guard !isPreview, timer == nil else { return }
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
        generation &+= 1
        pendingRefresh = false
    }

    /// Run quota.py off the main thread, then fold results back on main.
    func refresh() {
        guard !isPreview else { return }
        if inFlight != nil {
            pendingRefresh = true
            return
        }
        let path = scriptPath
        let currentGeneration = generation
        let runner = runner
        inFlight = Task.detached(priority: .utility) { [weak self] in
            let result = runner(path)
            await MainActor.run {
                guard let self else { return }
                self.inFlight = nil
                if self.generation == currentGeneration { self.apply(result) }
                if self.pendingRefresh {
                    self.pendingRefresh = false
                    self.refresh()
                }
            }
        }
    }

    // MARK: - Script execution

    enum ScriptResult {
        case success(QuotaSnapshot)
        case failure(String)
    }

    // Resolved python3 path, cached after the first successful probe so we don't
    // spawn `--version` checks every 30s poll. Guarded by a lock (runScript runs
    // on a detached task).
    nonisolated(unsafe) private static var cachedInterpreter: String?
    nonisolated(unsafe) private static var cachedOverride: String?
    nonisolated private static let interpreterLock = NSLock()

    /// First python3 candidate that actually runs. Rejects the Command Line
    /// Tools stub (which exits non-zero) by requiring `--version` to succeed.
    nonisolated private static func resolveInterpreter() -> String? {
        interpreterLock.lock()
        defer { interpreterLock.unlock() }
        let override = UserDefaults.standard.string(forKey: Config.kPythonInterpreter).flatMap { $0.isEmpty ? nil : $0 }
        if cachedOverride != override {
            cachedInterpreter = nil
            cachedOverride = override
        }
        if let cached = cachedInterpreter { return cached }
        var candidates: [String] = []
        if let override { candidates.append(override) }
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
        return (try? execute(p, timeout: 5).status) == 0
    }

    nonisolated private static func runScript(path: String) -> ScriptResult {
        guard let interpreter = resolveInterpreter() else {
            return .failure(Config.noPythonSentinel)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: interpreter)
        proc.arguments = [path, "--json"]

        let output: (status: Int32, stdout: Data, stderr: Data)
        do {
            output = try execute(proc, timeout: 90)
        } catch {
            interpreterLock.lock()
            if cachedInterpreter == interpreter { cachedInterpreter = nil }
            interpreterLock.unlock()
            return .failure("launch failed: \(error.localizedDescription)")
        }
        let outData = output.stdout
        let errData = output.stderr
        if output.status != 0 {
            let err = String(data: errData, encoding: .utf8) ?? ""
            return .failure("exit \(output.status): \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
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

    /// Drain both pipes without waiting for EOF from descendants that inherited them.
    nonisolated static func execute(_ process: Process, timeout: TimeInterval) throws -> (status: Int32, stdout: Data, stderr: Data) {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        stdout.fileHandleForWriting.closeFile()
        stderr.fileHandleForWriting.closeFile()
        let descriptors = [stdout.fileHandleForReading.fileDescriptor, stderr.fileHandleForReading.fileDescriptor]
        for fd in descriptors { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
        var buffers = [Data(), Data()]
        var open = [true, true]
        let deadline = Date().addingTimeInterval(max(0, timeout))
        var killDeadline: Date?
        while true {
            let now = Date()
            if now >= deadline && killDeadline == nil {
                if process.isRunning { process.terminate() }
                killDeadline = now.addingTimeInterval(3)
            }
            if let killDeadline, now >= killDeadline, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }
            var polls = descriptors.enumerated().map { index, fd in
                pollfd(fd: open[index] ? fd : -1, events: Int16(POLLIN | POLLHUP), revents: 0)
            }
            _ = polls.withUnsafeMutableBufferPointer { poll($0.baseAddress, nfds_t($0.count), 20) }
            for index in descriptors.indices where open[index] {
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = read(descriptors[index], &bytes, bytes.count)
                if count > 0 { buffers[index].append(contentsOf: bytes.prefix(count)) }
                else if count == 0 { open[index] = false }
            }
            // Once the direct child exits, allow a brief final drain but never
            // wait for a grandchild's inherited write descriptors to close.
            if !process.isRunning && (now >= deadline || !open.contains(true)) { break }
            if !process.isRunning && killDeadline == nil { killDeadline = now.addingTimeInterval(0.1) }
            if !process.isRunning, let killDeadline, now >= killDeadline { break }
        }
        process.waitUntilExit()
        return (process.terminationStatus, buffers[0], buffers[1])
    }

    // MARK: - Apply results

    private func apply(_ result: ScriptResult) {
        switch result {
        case .failure(let msg):
            // Keep the last good data on screen; just surface the error.
            lastError = msg
            // Raw error stays in the log for debugging even though the empty
            // state shows a friendlier message.
            NSLog("[Kaji] quota refresh failed: %@", msg)
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

            views.append(ProviderView(
                id: key,
                mark: Providers.mark(for: key),
                displayName: Providers.displayName(for: key),
                fiveHourPercent: five,
                weekPercent: limits?.sevenDayUsedPercent,
                resetDate: limits?.fiveHourResetsAt?.date,
                weekResetDate: limits?.sevenDayResetsAt?.date
            ))
        }

        providers = views
    }

    /// Ranking signal: how constrained a provider looks right now — the worse
    /// of the two windows. `nil` only when the provider reports no quota at
    /// all; such a provider still gets a ring (empty track), it just sorts last.
    private static func constraintScore(_ p: ProviderView) -> Double? {
        switch (p.fiveHourPercent, p.weekPercent) {
        case let (five?, week?): return max(five, week)
        case let (five?, nil): return five
        case let (nil, week?): return week
        case (nil, nil): return nil
        }
    }

    /// What the menubar draws: the user's visible providers, most-constrained
    /// first, capped at `count`. Enabling a provider is an explicit request to
    /// see it, so a missing percentage NEVER removes its ring — no-data
    /// providers sort last and render an empty track. Ties and no-data
    /// providers keep their input order.
    static func menuBarOrder(in providers: [ProviderView], count: Int) -> [ProviderView] {
        let ranked = providers.enumerated()
            .sorted { a, b in
                switch (constraintScore(a.element), constraintScore(b.element)) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                // Explicit index tiebreak: Swift's sort is not guaranteed stable.
                default: return a.offset < b.offset
                }
            }
            .map(\.element)
        return Array(ranked.prefix(max(0, count)))
    }
}
