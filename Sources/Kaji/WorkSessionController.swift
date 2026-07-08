import Foundation

enum WorkSessionPhase: String {
    case working
    case breakDue
    case breaking
}

@MainActor
final class WorkSessionController: ObservableObject {
    @Published private(set) var phase: WorkSessionPhase = .working
    @Published private(set) var workElapsed: TimeInterval = 0
    @Published private(set) var breakRemaining: TimeInterval = 0
    @Published private(set) var skipCountToday = 0
    @Published private(set) var completedBreaksToday = 0

    private let prefs: Prefs
    nonisolated(unsafe) private var timer: Timer?
    private var lastTickAt = Date()
    private var dayKey = WorkSessionController.todayKey()

    init(prefs: Prefs) {
        self.prefs = prefs
        self.breakRemaining = TimeInterval(max(1, prefs.breakMinutes) * 60)
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    var focusTarget: TimeInterval {
        TimeInterval(max(1, prefs.focusMinutes) * 60)
    }

    var breakTarget: TimeInterval {
        TimeInterval(max(1, prefs.breakMinutes) * 60)
    }

    var workProgress: Double {
        guard focusTarget > 0 else { return 0 }
        return min(max(workElapsed / focusTarget, 0), 1)
    }

    var breakProgress: Double {
        guard breakTarget > 0 else { return 0 }
        return min(max(1 - (breakRemaining / breakTarget), 0), 1)
    }

    var workClock: String {
        Self.clock(workElapsed)
    }

    var breakClock: String {
        Self.clock(max(0, breakRemaining))
    }

    func resetWork() {
        lastTickAt = Date()
        workElapsed = 0
        breakRemaining = breakTarget
        phase = .working
    }

    func startBreak() {
        lastTickAt = Date()
        breakRemaining = breakTarget
        phase = .breaking
    }

    func skipBreak() {
        guard prefs.allowBreakSkip else { return }
        skipCountToday += 1
        resetWork()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        rolloverDayIfNeeded()
        let now = Date()
        let delta = min(max(0, now.timeIntervalSince(lastTickAt)), 30)
        lastTickAt = now
        switch phase {
        case .working:
            workElapsed += delta
            if workElapsed >= focusTarget {
                phase = .breakDue
                breakRemaining = breakTarget
            }
        case .breakDue:
            break
        case .breaking:
            breakRemaining -= delta
            if breakRemaining <= 0 {
                completedBreaksToday += 1
                resetWork()
            }
        }
    }

    private func rolloverDayIfNeeded() {
        let now = Self.todayKey()
        guard now != dayKey else { return }
        dayKey = now
        skipCountToday = 0
        completedBreaksToday = 0
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func todayKey() -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }
}
