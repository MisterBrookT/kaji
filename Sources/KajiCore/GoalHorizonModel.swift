import Foundation

public enum GoalHorizon: String, CaseIterable, Codable, Sendable {
    case today
    case week
    case longTerm
}

public struct GoalItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID, title: String, isDone: Bool) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

public struct GoalHistoryDay: Identifiable, Codable, Equatable, Sendable {
    public let day: String
    public var completed: Int
    public var total: Int

    public init(day: String, completed: Int, total: Int) {
        self.day = day
        self.completed = completed
        self.total = total
    }

    public var id: String { day }
    public var ratio: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

public struct GoalHorizonState: Codable, Equatable, Sendable {
    public var today: [GoalItem]
    public var week: [GoalItem]
    public var longTerm: [GoalItem]
    public var dayKey: String
    public var weekKey: String
    public var history: [String: GoalHistoryDay]
    public var yesterdayPending: [GoalItem]

    public init(
        today: [GoalItem],
        week: [GoalItem],
        longTerm: [GoalItem],
        dayKey: String,
        weekKey: String,
        history: [String: GoalHistoryDay],
        yesterdayPending: [GoalItem] = []
    ) {
        self.today = today
        self.week = week
        self.longTerm = longTerm
        self.dayKey = dayKey
        self.weekKey = weekKey
        self.history = history
        self.yesterdayPending = yesterdayPending
    }

    private enum CodingKeys: String, CodingKey {
        case today, week, longTerm, dayKey, weekKey, history, yesterdayPending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        today = try container.decode([GoalItem].self, forKey: .today)
        week = try container.decode([GoalItem].self, forKey: .week)
        longTerm = try container.decode([GoalItem].self, forKey: .longTerm)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        weekKey = try container.decode(String.self, forKey: .weekKey)
        history = try container.decode([String: GoalHistoryDay].self, forKey: .history)
        yesterdayPending = try container.decodeIfPresent([GoalItem].self, forKey: .yesterdayPending) ?? []
    }

    public subscript(_ horizon: GoalHorizon) -> [GoalItem] {
        get {
            switch horizon {
            case .today: today
            case .week: week
            case .longTerm: longTerm
            }
        }
        set {
            switch horizon {
            case .today: today = newValue
            case .week: week = newValue
            case .longTerm: longTerm = newValue
            }
        }
    }
}

public enum GoalHorizonLogic {
    public static func migrateLegacy(
        goalsData: Data?,
        goalsKeyExists: Bool,
        dayKey: String?,
        historyData: Data?,
        currentDayKey: String,
        currentWeekKey: String,
        freshDefaults: [GoalItem]
    ) -> GoalHorizonState {
        let goals: [GoalItem]
        if let goalsData,
           let decoded = try? JSONDecoder().decode([GoalItem].self, from: goalsData) {
            goals = decoded
        } else {
            goals = goalsKeyExists ? [] : freshDefaults
        }

        let history: [String: GoalHistoryDay]
        if let historyData,
           let decoded = try? JSONDecoder().decode([String: GoalHistoryDay].self, from: historyData) {
            history = decoded
        } else {
            history = [:]
        }

        return GoalHorizonState(
            today: goals,
            week: [],
            longTerm: [],
            dayKey: dayKey ?? currentDayKey,
            weekKey: currentWeekKey,
            history: history
        )
    }

    public static func refresh(
        _ state: GoalHorizonState,
        dayKey: String,
        weekKey: String
    ) -> GoalHorizonState {
        var result = state
        if result.dayKey != dayKey {
            let valid = result.today.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            result.history[result.dayKey] = GoalHistoryDay(
                day: result.dayKey,
                completed: valid.filter(\.isDone).count,
                total: valid.count
            )
            result.yesterdayPending = valid.compactMap {
                guard !$0.isDone else { return nil }
                return GoalItem(id: $0.id, title: $0.title, isDone: false)
            }
            result.today = []
            result.dayKey = dayKey
        }
        if result.weekKey != weekKey {
            result.week = result.week.map {
                GoalItem(id: $0.id, title: $0.title, isDone: false)
            }
            result.weekKey = weekKey
        }
        return result
    }

    public static func summary(for goals: [GoalItem]) -> (completed: Int, total: Int) {
        let valid = goals.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return (valid.filter(\.isDone).count, valid.count)
    }
}

public enum MenuBarDestination: Equatable, Sendable {
    case quota
    case work
    case goalsToday
}

public enum MenuBarSlotLogic {
    public static func goalsLabel(enabled: Bool, goals: [GoalItem]) -> String? {
        guard enabled else { return nil }
        let summary = GoalHorizonLogic.summary(for: goals)
        return "\(summary.completed)/\(summary.total)"
    }

    public static func destination(for slot: MenuBarSlot) -> MenuBarDestination {
        switch slot {
        case .quota, .background: .quota
        case .work: .work
        case .goals: .goalsToday
        }
    }
}

public enum MenuBarSlot: Equatable, Sendable {
    case quota
    case work
    case goals
    case background
}
