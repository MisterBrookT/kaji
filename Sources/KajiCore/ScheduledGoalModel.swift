import Foundation

public struct ScheduledGoal: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var tag: String
    public var note: String
    public var weekdays: Set<Int>

    public init(
        id: UUID = UUID(),
        title: String,
        tag: String,
        note: String = "",
        weekdays: Set<Int>
    ) {
        self.id = id
        self.title = title
        self.tag = tag
        self.note = note
        self.weekdays = weekdays
    }
}

public struct ScheduleCompletionState: Codable, Equatable, Sendable {
    public var dayKey: String
    public var completedIDs: Set<UUID>

    public init(dayKey: String, completedIDs: Set<UUID> = []) {
        self.dayKey = dayKey
        self.completedIDs = completedIDs
    }
}

public enum ScheduledGoalLogic {
    public static func normalizedWeekdays(_ weekdays: Set<Int>) -> Set<Int> {
        Set(weekdays.filter { (1...7).contains($0) })
    }

    public static func canSave(title: String, weekdays: Set<Int>) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !normalizedWeekdays(weekdays).isEmpty
    }

    public static func active(_ schedules: [ScheduledGoal], weekday: Int) -> [ScheduledGoal] {
        schedules.filter { $0.weekdays.contains(weekday) }
    }

    public static func refreshedCompletion(
        _ state: ScheduleCompletionState,
        dayKey: String
    ) -> ScheduleCompletionState {
        state.dayKey == dayKey ? state : ScheduleCompletionState(dayKey: dayKey)
    }
}

public enum ScheduleMigration {
    public struct Result: Equatable, Sendable {
        public let schedules: [ScheduledGoal]
        public let completedIDs: Set<UUID>
    }

    public static func migrate(
        plans: [FixedDayPlan],
        todayWeekday: Int,
        todayCompleted: Bool
    ) -> Result {
        let schedules = plans.map { plan in
            ScheduledGoal(
                title: plan.title,
                tag: plan.tag,
                note: plan.items.map {
                    $0.dose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? $0.title
                        : "\($0.title) · \($0.dose)"
                }.joined(separator: "\n"),
                weekdays: [plan.weekday]
            )
        }
        let completed = todayCompleted
            ? Set(schedules.filter { $0.weekdays.contains(todayWeekday) }.map(\.id))
            : []
        return Result(schedules: schedules, completedIDs: completed)
    }
}

public enum GoalMarkBase: String, Codable, Sendable {
    case circle
    case rectangle
}

public enum GoalMarkFill: String, Codable, Sendable {
    case outline
    case half
}

public struct GoalMarkStyle: Equatable, Sendable {
    public let base: GoalMarkBase
    public let fill: GoalMarkFill

    public var systemImage: String {
        switch (base, fill) {
        case (.circle, .outline): "circle"
        case (.circle, .half): "circle.lefthalf.filled"
        case (.rectangle, .outline): "rectangle"
        case (.rectangle, .half): "rectangle.lefthalf.filled"
        }
    }
}

public enum GoalMarkLogic {
    public static func style(for tag: GoalTag) -> GoalMarkStyle {
        switch tag {
        case .work, .learn: GoalMarkStyle(base: .rectangle, fill: .outline)
        case .home: GoalMarkStyle(base: .rectangle, fill: .half)
        case .health: GoalMarkStyle(base: .circle, fill: .outline)
        case .admin, .personal: GoalMarkStyle(base: .circle, fill: .half)
        }
    }
}

public enum DiskSizeFormatter {
    public static func string(bytes: Int64) -> String {
        let value = max(0, bytes)
        if value >= 1_000_000_000 {
            let gb = Double(value) / 1_000_000_000
            if abs(gb.rounded() - gb) < 0.05 {
                return "\(Int(gb.rounded())) GB"
            }
            let rounded = (gb * 10).rounded(.toNearestOrAwayFromZero) / 10
            return String(format: "%.1f GB", rounded)
        }
        if value == 0 { return "0 MB" }
        return "\(max(1, Int((Double(value) / 1_000_000).rounded()))) MB"
    }
}
