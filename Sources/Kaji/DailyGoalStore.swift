import Foundation
import KajiCore

typealias DailyGoal = GoalItem
typealias DailyGoalHistoryDay = GoalHistoryDay

struct GoalTagDefinition: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var colorHex: UInt32

    static let defaults: [GoalTagDefinition] = [
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, name: "Work", colorHex: 0x5B7CFA),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, name: "Personal", colorHex: 0x8E6AD8),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, name: "Health", colorHex: 0xE05D6F),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, name: "Home", colorHex: 0xD18A3C),
    ]
}

@MainActor
final class DailyGoalStore: ObservableObject {
    @Published private(set) var state: GoalHorizonState {
        didSet { save() }
    }
    @Published private(set) var tagDefinitions: [GoalTagDefinition] {
        didSet { saveTagDefinitions() }
    }

    private let defaults: UserDefaults
    private var now: () -> Date
    private var calendar: Calendar
    private let completionRemovalDelay: Duration
    private var completionRemovalTasks: [UUID: Task<Void, Never>] = [:]
    private(set) var loadIssue: GoalStateLoadIssue?
    private static let tagDefinitionsKey = "goalTagDefinitionsV1"

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        completionRemovalDelay: Duration = .seconds(5)
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.completionRemovalDelay = completionRemovalDelay
        if let data = defaults.data(forKey: Self.tagDefinitionsKey),
           let saved = try? JSONDecoder().decode([GoalTagDefinition].self, from: data),
           !saved.isEmpty {
            tagDefinitions = saved
        } else {
            tagDefinitions = GoalTagDefinition.defaults
        }

        let date = now()
        let dayKey = Self.dayKey(for: date, calendar: calendar)
        let weekKey = Self.weekKey(for: date, calendar: calendar)
        let loaded = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: dayKey,
            currentWeekKey: weekKey
        )
        var refreshed = GoalHorizonLogic.refresh(
            loaded.state,
            dayKey: dayKey,
            weekKey: weekKey
        )
        let merged = refreshed.today + refreshed.week + refreshed.longTerm + refreshed.yesterdayPending
        var seen = Set<UUID>()
        refreshed.today = merged.filter { seen.insert($0.id).inserted }
        refreshed.week = []
        refreshed.longTerm = []
        refreshed.yesterdayPending = []
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
        var isNowDone = false
        mutate(horizon) { goals in
            guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
            goals[index].isDone.toggle()
            isNowDone = goals[index].isDone
        }
        updateCompletionRemoval(for: goal.id, in: horizon, isDone: isNowDone)
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

    func updateNote(_ goal: DailyGoal, note: String, in horizon: GoalHorizon = .today) {
        mutate(horizon) { goals in
            guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
            goals[index].note = note
        }
    }

    @discardableResult
    func addGoal(in horizon: GoalHorizon = .today) -> UUID {
        let id = UUID()
        mutate(horizon) { goals in
            goals.append(DailyGoal(
                id: id,
                title: "",
                isDone: false,
                tag: GoalTag.personal.rawValue,
                createdAt: now()
            ))
        }
        return id
    }

    func delete(_ goal: DailyGoal, in horizon: GoalHorizon = .today) {
        completionRemovalTasks.removeValue(forKey: goal.id)?.cancel()
        mutate(horizon) { goals in
            goals.removeAll { $0.id == goal.id }
        }
    }

    @discardableResult
    func addGoal(
        title: String,
        tag: String,
        note: String,
        in horizon: GoalHorizon
    ) throws -> DailyGoal {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw GoalStoreMutationError.emptyTitle
        }
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = DailyGoal(
            id: UUID(),
            title: normalizedTitle,
            isDone: false,
            tag: normalizedTag.isEmpty ? GoalTag.personal.rawValue : normalizedTag,
            note: note,
            createdAt: now()
        )
        mutate(horizon) { $0.append(goal) }
        return goal
    }

    func updateGoal(
        id: UUID,
        title: String?,
        tag: String?,
        note: String?,
        in horizon: GoalHorizon
    ) throws {
        var next = state
        guard let index = next[horizon].firstIndex(where: { $0.id == id }) else {
            throw GoalStoreMutationError.goalNotFound
        }
        if let title {
            let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedTitle.isEmpty else {
                throw GoalStoreMutationError.emptyTitle
            }
            next[horizon][index].title = normalizedTitle
        }
        if let tag {
            let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            next[horizon][index].tag = normalizedTag.isEmpty ? GoalTag.personal.rawValue : normalizedTag
        }
        if let note {
            next[horizon][index].note = note
        }
        state = next
        if horizon == .today { recordToday() }
    }

    func setGoalCompleted(id: UUID, isDone: Bool, in horizon: GoalHorizon) throws {
        var next = state
        guard let index = next[horizon].firstIndex(where: { $0.id == id }) else {
            throw GoalStoreMutationError.goalNotFound
        }
        next[horizon][index].isDone = isDone
        state = next
        if horizon == .today { recordToday() }
        updateCompletionRemoval(for: id, in: horizon, isDone: isDone)
    }

    func deleteGoal(id: UUID, in horizon: GoalHorizon) throws {
        var next = state
        guard next[horizon].contains(where: { $0.id == id }) else {
            throw GoalStoreMutationError.goalNotFound
        }
        next[horizon].removeAll { $0.id == id }
        state = next
        if horizon == .today { recordToday() }
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
        next.today.append(DailyGoal(
            id: moved.id,
            title: moved.title,
            isDone: false,
            tag: moved.tag,
            note: moved.note,
            createdAt: moved.createdAt
        ))
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
        return (0..<30).reversed().map { offset in
            let value = calendar.date(byAdding: .day, value: -offset, to: date) ?? date
            let key = Self.dayKey(for: value, calendar: calendar)
            return state.history[key] ?? DailyGoalHistoryDay(day: key, completed: 0, total: 0)
        }
    }

    @discardableResult
    func ensureTag(name: String, colorHex: UInt32) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return GoalTag.personal.rawValue }
        if let existing = tagDefinitions.first(where: {
            $0.name.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            return existing.name
        }
        tagDefinitions.append(.init(id: UUID(), name: normalized, colorHex: colorHex))
        return normalized
    }

    func tagDefinition(for rawValue: String) -> GoalTagDefinition {
        if let existing = tagDefinitions.first(where: {
            $0.name.caseInsensitiveCompare(rawValue) == .orderedSame
        }) {
            return existing
        }
        let legacy = GoalTagLogic.resolve(rawValue, title: "").selectableEquivalent.label
        return tagDefinitions.first(where: { $0.name == legacy }) ?? GoalTagDefinition.defaults[1]
    }

    private func updateCompletionRemoval(for id: UUID, in horizon: GoalHorizon, isDone: Bool) {
        completionRemovalTasks.removeValue(forKey: id)?.cancel()
        guard isDone else { return }
        completionRemovalTasks[id] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.completionRemovalDelay)
            guard !Task.isCancelled else { return }
            self.completionRemovalTasks[id] = nil
            self.mutate(horizon) { goals in
                goals.removeAll { $0.id == id && $0.isDone }
            }
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

    private func saveTagDefinitions() {
        guard let data = try? JSONEncoder().encode(tagDefinitions) else { return }
        defaults.set(data, forKey: Self.tagDefinitionsKey)
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

enum GoalStoreMutationError: Error {
    case goalNotFound
    case emptyTitle
}
