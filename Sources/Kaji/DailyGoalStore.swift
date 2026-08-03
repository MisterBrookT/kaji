import Foundation
import KajiCore

typealias DailyGoal = GoalItem
typealias DailyGoalHistoryDay = GoalHistoryDay

@MainActor
final class DailyGoalStore: ObservableObject {
    @Published private(set) var state: GoalHorizonState {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private var now: () -> Date
    private var calendar: Calendar
    private(set) var loadIssue: GoalStateLoadIssue?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar

        let date = now()
        let dayKey = Self.dayKey(for: date, calendar: calendar)
        let weekKey = Self.weekKey(for: date, calendar: calendar)
        let loaded = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: dayKey,
            currentWeekKey: weekKey
        )
        let refreshed = GoalHorizonLogic.refresh(
            loaded.state,
            dayKey: dayKey,
            weekKey: weekKey
        )
        state = refreshed
        loadIssue = loaded.issue
        if refreshed != loaded.state {
            save()
        }
    }

    var goals: [DailyGoal] { state.today }
    var completedCount: Int { summary(for: .today).completed }
    var history: [String: DailyGoalHistoryDay] { state.history }
    var pendingGoals: [DailyGoal] {
        state.today.filter {
            !$0.isDone && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    var yesterdayPending: [DailyGoal] { state.yesterdayPending }

    func goals(for horizon: GoalHorizon) -> [DailyGoal] {
        state[horizon]
    }

    func summary(for horizon: GoalHorizon) -> (completed: Int, total: Int) {
        GoalHorizonLogic.summary(for: state[horizon])
    }

    func toggle(_ goal: DailyGoal, in horizon: GoalHorizon = .today) {
        mutate(horizon) { goals in
            guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
            goals[index].isDone.toggle()
        }
    }

    func updateTitle(_ goal: DailyGoal, title: String, in horizon: GoalHorizon = .today) {
        mutate(horizon) { goals in
            guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
            goals[index].title = title
        }
    }

    func updateTag(_ goal: DailyGoal, tag: String, in horizon: GoalHorizon = .today) {
        mutate(horizon) { goals in
            guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
            goals[index].tag = tag
        }
    }

    @discardableResult
    func addGoal(in horizon: GoalHorizon = .today) -> UUID {
        let id = UUID()
        mutate(horizon) { goals in
            goals.append(DailyGoal(id: id, title: "", isDone: false, tag: GoalTag.personal.rawValue))
        }
        return id
    }

    func delete(_ goal: DailyGoal, in horizon: GoalHorizon = .today) {
        mutate(horizon) { goals in
            goals.removeAll { $0.id == goal.id }
        }
    }

    func move(_ goal: DailyGoal, in horizon: GoalHorizon, offset: Int) {
        mutate(horizon) { goals in
            guard let source = goals.firstIndex(where: { $0.id == goal.id }) else { return }
            let destination = min(max(0, source + offset), goals.count - 1)
            guard source != destination else { return }
            let moved = goals.remove(at: source)
            goals.insert(moved, at: destination)
        }
    }

    func removeIfBlank(_ goal: DailyGoal, in horizon: GoalHorizon) {
        guard goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        delete(goal, in: horizon)
    }

    func moveYesterdayGoalToToday(_ goal: DailyGoal) {
        var next = state
        guard let index = next.yesterdayPending.firstIndex(where: { $0.id == goal.id }) else { return }
        let moved = next.yesterdayPending.remove(at: index)
        next.today.append(DailyGoal(id: moved.id, title: moved.title, isDone: false, tag: moved.tag))
        state = next
        recordToday()
    }

    func dismissYesterdayGoal(_ goal: DailyGoal) {
        var next = state
        next.yesterdayPending.removeAll { $0.id == goal.id }
        state = next
    }

    func reset(_ horizon: GoalHorizon) {
        mutate(horizon) { goals in
            for index in goals.indices {
                goals[index].isDone = false
            }
        }
    }

    func resetToday() {
        reset(.today)
    }

    func refreshPeriodBoundaries() {
        let date = now()
        state = GoalHorizonLogic.refresh(
            state,
            dayKey: Self.dayKey(for: date, calendar: calendar),
            weekKey: Self.weekKey(for: date, calendar: calendar)
        )
        recordToday()
    }

    var heatmapDays: [DailyGoalHistoryDay] {
        let date = now()
        return (0..<35).reversed().map { offset in
            let value = calendar.date(byAdding: .day, value: -offset, to: date) ?? date
            let key = Self.dayKey(for: value, calendar: calendar)
            return state.history[key] ?? DailyGoalHistoryDay(day: key, completed: 0, total: 0)
        }
    }

    private func mutate(_ horizon: GoalHorizon, _ body: (inout [DailyGoal]) -> Void) {
        var next = state
        body(&next[horizon])
        state = next
        if horizon == .today {
            recordToday()
        }
    }

    private func recordToday() {
        var next = state
        let summary = GoalHorizonLogic.summary(for: next.today)
        next.history[next.dayKey] = DailyGoalHistoryDay(
            day: next.dayKey,
            completed: summary.completed,
            total: summary.total
        )
        if next != state {
            state = next
        }
    }

    private func save() {
        try? GoalStatePersistence.save(state, defaults: defaults)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private static func weekKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
    }

}
