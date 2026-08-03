import Foundation

public enum GoalStateLoadIssue: String, Codable, Equatable, Sendable {
    case missingStateInitializedEmpty
    case invalidStateTypeInitializedEmpty
    case corruptStateInitializedEmpty
}

public struct GoalStateDiagnostic: Codable, Equatable, Sendable {
    public var issue: GoalStateLoadIssue
    public var detail: String

    public init(issue: GoalStateLoadIssue, detail: String) {
        self.issue = issue
        self.detail = detail
    }
}

public struct GoalStateLoadResult: Equatable, Sendable {
    public var state: GoalHorizonState
    public var issue: GoalStateLoadIssue?

    public init(state: GoalHorizonState, issue: GoalStateLoadIssue?) {
        self.state = state
        self.issue = issue
    }
}

public enum GoalStatePersistence {
    public static let stateKey = "goalHorizonStateV1"
    public static let corruptBackupKey = "goalHorizonStateV1CorruptBackup"
    public static let diagnosticKey = "goalHorizonStateV1Diagnostic"
    public static let legacyKeys = [
        "dailyGoals",
        "dailyGoalsDayKey",
        "dailyGoalsHistory",
        "goalHorizonMigrationVersion",
    ]

    public static func load(
        defaults: UserDefaults,
        currentDayKey: String,
        currentWeekKey: String
    ) -> GoalStateLoadResult {
        defer { removeLegacyKeys(from: defaults) }

        guard let stored = defaults.object(forKey: stateKey) else {
            let state = emptyState(dayKey: currentDayKey, weekKey: currentWeekKey)
            saveRecovery(
                state,
                issue: .missingStateInitializedEmpty,
                detail: "goalHorizonStateV1 was absent",
                defaults: defaults
            )
            return GoalStateLoadResult(state: state, issue: .missingStateInitializedEmpty)
        }

        guard let data = stored as? Data else {
            let state = emptyState(dayKey: currentDayKey, weekKey: currentWeekKey)
            saveRecovery(
                state,
                issue: .invalidStateTypeInitializedEmpty,
                detail: "goalHorizonStateV1 stored \(String(describing: type(of: stored))) instead of Data",
                defaults: defaults
            )
            return GoalStateLoadResult(state: state, issue: .invalidStateTypeInitializedEmpty)
        }

        do {
            let state = try JSONDecoder().decode(GoalHorizonState.self, from: data)
            return GoalStateLoadResult(state: state, issue: nil)
        } catch {
            defaults.set(data, forKey: corruptBackupKey)
            let state = emptyState(dayKey: currentDayKey, weekKey: currentWeekKey)
            saveRecovery(
                state,
                issue: .corruptStateInitializedEmpty,
                detail: String(describing: error),
                defaults: defaults
            )
            return GoalStateLoadResult(state: state, issue: .corruptStateInitializedEmpty)
        }
    }

    public static func save(_ state: GoalHorizonState, defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(state), forKey: stateKey)
    }

    public static func diagnostic(from defaults: UserDefaults) -> GoalStateDiagnostic? {
        guard let data = defaults.data(forKey: diagnosticKey) else { return nil }
        return try? JSONDecoder().decode(GoalStateDiagnostic.self, from: data)
    }

    private static func emptyState(dayKey: String, weekKey: String) -> GoalHorizonState {
        GoalHorizonState(
            today: [],
            week: [],
            longTerm: [],
            dayKey: dayKey,
            weekKey: weekKey,
            history: [:]
        )
    }

    private static func saveRecovery(
        _ state: GoalHorizonState,
        issue: GoalStateLoadIssue,
        detail: String,
        defaults: UserDefaults
    ) {
        try? save(state, defaults: defaults)
        let diagnostic = GoalStateDiagnostic(issue: issue, detail: detail)
        defaults.set(try? JSONEncoder().encode(diagnostic), forKey: diagnosticKey)
    }

    private static func removeLegacyKeys(from defaults: UserDefaults) {
        for key in legacyKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
