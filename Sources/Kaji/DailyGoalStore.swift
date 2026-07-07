import Foundation

struct DailyGoal: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
}

struct DailyGoalHistoryDay: Identifiable, Codable, Equatable {
    let day: String
    var completed: Int
    var total: Int

    var id: String { day }
    var ratio: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

@MainActor
final class DailyGoalStore: ObservableObject {
    @Published private(set) var goals: [DailyGoal] {
        didSet {
            save()
            recordToday()
        }
    }
    @Published private(set) var history: [String: DailyGoalHistoryDay] {
        didSet { saveHistory() }
    }

    private var dayKey: String {
        didSet { UserDefaults.standard.set(dayKey, forKey: Key.dayKey) }
    }

    private enum Key {
        static let goals = "dailyGoals"
        static let dayKey = "dailyGoalsDayKey"
        static let history = "dailyGoalsHistory"
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Key.goals),
           let decoded = try? JSONDecoder().decode([DailyGoal].self, from: data),
           !decoded.isEmpty {
            goals = decoded
        } else {
            goals = Self.defaultGoals
        }
        if let data = defaults.data(forKey: Key.history),
           let decoded = try? JSONDecoder().decode([String: DailyGoalHistoryDay].self, from: data) {
            history = decoded
        } else {
            history = [:]
        }
        dayKey = defaults.string(forKey: Key.dayKey) ?? Self.todayKey()
        resetIfNeeded()
        recordToday()
    }

    var completedCount: Int {
        goals.filter(\.isDone).count
    }

    func toggle(_ goal: DailyGoal) {
        guard let idx = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[idx].isDone.toggle()
    }

    func updateTitle(_ goal: DailyGoal, title: String) {
        guard let idx = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[idx].title = title
    }

    func addGoal() {
        goals.append(DailyGoal(id: UUID(), title: "新的目标", isDone: false))
    }

    func delete(_ goal: DailyGoal) {
        guard goals.count > 1 else { return }
        goals.removeAll { $0.id == goal.id }
    }

    var pendingGoals: [DailyGoal] {
        goals.filter { !$0.isDone && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var heatmapDays: [DailyGoalHistoryDay] {
        (0..<35).reversed().map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let key = Self.key(for: date)
            return history[key] ?? DailyGoalHistoryDay(day: key, completed: 0, total: 0)
        }
    }

    func resetToday() {
        for idx in goals.indices {
            goals[idx].isDone = false
        }
        dayKey = Self.todayKey()
    }

    private func resetIfNeeded() {
        let now = Self.todayKey()
        guard now != dayKey else { return }
        record(day: dayKey)
        for idx in goals.indices {
            goals[idx].isDone = false
        }
        dayKey = now
        recordToday()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        UserDefaults.standard.set(data, forKey: Key.goals)
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: Key.history)
    }

    private func recordToday() {
        record(day: Self.todayKey())
    }

    private func record(day: String) {
        history[day] = DailyGoalHistoryDay(day: day,
                                           completed: completedCount,
                                           total: goals.count)
    }

    private static let defaultGoals: [DailyGoal] = [
        DailyGoal(id: UUID(), title: "完成一件重要事", isDone: false),
        DailyGoal(id: UUID(), title: "训练或恢复", isDone: false),
        DailyGoal(id: UUID(), title: "按时休息", isDone: false),
    ]

    private static func todayKey() -> String {
        key(for: Date())
    }

    private static func key(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }
}
