import Foundation

public enum GoalGrouping: String, CaseIterable, Codable, Sendable {
    case none
    case byTag
    case byCreatedTime
}

public struct GoalGroup: Equatable, Sendable {
    public let title: String
    public let goals: [GoalItem]

    public init(title: String, goals: [GoalItem]) {
        self.title = title
        self.goals = goals
    }
}

public enum GoalGroupingLogic {
    /// Groups goals without changing their order within a group.
    ///
    /// Tag groups follow `tagOrder`; unknown tags follow in first-seen order and
    /// untagged goals are last. Date groups are newest-first. Legacy goals with
    /// no persisted creation date form the final Earlier group in source order.
    public static func group(
        _ goals: [GoalItem],
        by grouping: GoalGrouping,
        tagOrder: [String] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        language: AppLanguage = .en
    ) -> [GoalGroup] {
        guard !goals.isEmpty else { return [] }
        switch grouping {
        case .none:
            return [GoalGroup(title: "", goals: goals)]
        case .byTag:
            return groupByTag(goals, tagOrder: tagOrder, language: language)
        case .byCreatedTime:
            return groupByDate(goals, now: now, calendar: calendar, language: language)
        }
    }

    private static func groupByTag(
        _ goals: [GoalItem],
        tagOrder: [String],
        language: AppLanguage
    ) -> [GoalGroup] {
        func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var ordered = tagOrder.map(normalized).filter { !$0.isEmpty }
        for goal in goals {
            let tag = normalized(goal.tag)
            if !tag.isEmpty && !ordered.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                ordered.append(tag)
            }
        }
        var groups = ordered.compactMap { tag -> GoalGroup? in
            let matches = goals.filter { normalized($0.tag).caseInsensitiveCompare(tag) == .orderedSame }
            return matches.isEmpty ? nil : GoalGroup(title: tag, goals: matches)
        }
        let untagged = goals.filter { normalized($0.tag).isEmpty }
        if !untagged.isEmpty {
            groups.append(GoalGroup(title: L10n.t(.goalGroupUntagged, language), goals: untagged))
        }
        return groups
    }

    private static func groupByDate(
        _ goals: [GoalItem],
        now: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> [GoalGroup] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let buckets: [(L10n.K, (Date?) -> Bool)] = [
            (.goalGroupToday, { $0.map { $0 >= today } ?? false }),
            (.goalGroupYesterday, { $0.map { $0 >= yesterday && $0 < today } ?? false }),
            (.goalGroupThisWeek, { $0.map { $0 >= weekStart && $0 < yesterday } ?? false }),
            (.goalGroupEarlier, { date in date == nil || date! < weekStart }),
        ]
        return buckets.compactMap { key, includes in
            let matches = goals.filter { includes($0.createdAt) }
            return matches.isEmpty ? nil : GoalGroup(title: L10n.t(key, language), goals: matches)
        }
    }
}
