import Foundation

public enum GoalHorizon: String, CaseIterable, Codable, Sendable {
    case today
    case week
    case longTerm
}

public enum GoalTag: String, CaseIterable, Codable, Sendable {
    case work
    case health
    case home
    case learn
    case admin
    case personal

    public static let selectableCases: [GoalTag] = [.work, .home, .health, .personal]

    public var selectableEquivalent: GoalTag {
        switch self {
        case .learn: .work
        case .admin: .personal
        default: self
        }
    }

    public var label: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    public var systemImage: String {
        switch self {
        case .work, .learn: "briefcase"
        case .health: "heart"
        case .home: "house"
        case .admin, .personal: "person"
        }
    }
}

public enum GoalTagLogic {
    public static func resolve(_ rawValue: String, title: String) -> GoalTag {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let explicit = GoalTag(rawValue: normalized) {
            return explicit
        }

        let value = title.lowercased()
        if contains(value, ["训练", "拉伸", "运动", "健身", "跑步", "恢复", "休息", "戒烟", "睡眠", "health"]) {
            return .health
        }
        if contains(value, ["洗衣", "垃圾", "寝室", "打扫", "清洁", "收拾", "家里", "clean", "home"]) {
            return .home
        }
        if contains(value, ["视频", "调研", "研究", "学习", "课程", "读书", "kdd", "rsi", "saas", "learn"]) {
            return .learn
        }
        if contains(value, ["注册", "报账", "申诉", "离职", "手续", "办理", "账单", "admin"]) {
            return .admin
        }
        if contains(value, ["公司", "提交", "dataset", "产品", "项目", "orivue", "claude", "acl", "工作", "work"]) {
            return .work
        }
        return .personal
    }

    private static func contains(_ value: String, _ keywords: [String]) -> Bool {
        keywords.contains { value.contains($0) }
    }
}

public struct GoalItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var isDone: Bool
    public var tag: String
    public var note: String
    /// Persisted creation time. `nil` identifies goals decoded from data written
    /// before creation timestamps existed; grouping keeps those in source order.
    public let createdAt: Date?

    public init(
        id: UUID,
        title: String,
        isDone: Bool,
        tag: String = "",
        note: String = "",
        createdAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.tag = tag
        self.note = note
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, isDone, tag, note, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
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

public enum GoalHeatmapFormatter {
    public static func string(day: String, completed: Int, total: Int) -> String {
        "\(day)-\(completed)/\(total)"
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
            result.yesterdayPending = []
            result.dayKey = dayKey
        }
        if result.weekKey != weekKey {
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
    public static func goalsLabel(
        enabled: Bool,
        goals: [GoalItem],
        fixedPlanCompleted: Bool? = nil,
        scheduledCompleted: Int = 0,
        scheduledTotal: Int = 0
    ) -> String? {
        guard enabled else { return nil }
        let summary = GoalHorizonLogic.summary(for: goals)
        let fixedTotal = fixedPlanCompleted == nil ? 0 : 1
        let fixedDone = fixedPlanCompleted == true ? 1 : 0
        return "\(summary.completed + fixedDone + scheduledCompleted)/\(summary.total + fixedTotal + scheduledTotal)"
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
