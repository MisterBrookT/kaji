import XCTest
import KajiCore

final class GoalHorizonModelTests: XCTestCase {
    private let todayID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let weekID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let longID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    func testDayChangeArchivesPendingAndClearsToday() {
        let state = GoalHorizonState(
            today: [
                GoalItem(id: todayID, title: "Done", isDone: true),
                GoalItem(id: weekID, title: "Pending", isDone: false),
            ],
            week: [GoalItem(id: weekID, title: "Draft", isDone: true)],
            longTerm: [GoalItem(id: longID, title: "Learn", isDone: true)],
            dayKey: "2026-8-1",
            weekKey: "2026-31",
            history: [:]
        )

        let refreshed = GoalHorizonLogic.refresh(state, dayKey: "2026-8-2", weekKey: "2026-31")

        XCTAssertTrue(refreshed.today.isEmpty)
        XCTAssertEqual(refreshed.yesterdayPending, [
            GoalItem(id: weekID, title: "Pending", isDone: false)
        ])
        XCTAssertTrue(refreshed.week[0].isDone)
        XCTAssertTrue(refreshed.longTerm[0].isDone)
        XCTAssertEqual(refreshed.history["2026-8-1"], GoalHistoryDay(day: "2026-8-1", completed: 1, total: 2))
    }

    func testWeekChangeClearsOnlyWeekCompletion() {
        let state = GoalHorizonState(
            today: [GoalItem(id: todayID, title: "Ship", isDone: true)],
            week: [GoalItem(id: weekID, title: "Draft", isDone: true)],
            longTerm: [GoalItem(id: longID, title: "Learn", isDone: true)],
            dayKey: "2026-8-1",
            weekKey: "2026-31",
            history: [:]
        )

        let refreshed = GoalHorizonLogic.refresh(state, dayKey: "2026-8-1", weekKey: "2026-32")

        XCTAssertTrue(refreshed.today[0].isDone)
        XCTAssertFalse(refreshed.week[0].isDone)
        XCTAssertTrue(refreshed.longTerm[0].isDone)
    }

    func testSummaryIgnoresWhitespaceDrafts() {
        let goals = [
            GoalItem(id: todayID, title: "Done", isDone: true),
            GoalItem(id: weekID, title: "  ", isDone: true),
            GoalItem(id: longID, title: "Open", isDone: false),
        ]
        let summary = GoalHorizonLogic.summary(for: goals)
        XCTAssertEqual(summary.completed, 1)
        XCTAssertEqual(summary.total, 2)
    }

    func testStateCodableRoundTripPreservesIDsAndHistory() throws {
        let state = GoalHorizonState(
            today: [GoalItem(id: todayID, title: "Existing", isDone: true)],
            week: [],
            longTerm: [],
            dayKey: "2026-8-1",
            weekKey: "2026-31",
            history: ["2026-7-31": GoalHistoryDay(day: "2026-7-31", completed: 2, total: 3)]
        )
        let decoded = try JSONDecoder().decode(GoalHorizonState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }

    func testDecodeOldStateDefaultsYesterdayPendingToEmpty() throws {
        let json = """
        {"today":[],"week":[],"longTerm":[],"dayKey":"2026-8-1","weekKey":"2026-31","history":{}}
        """
        let decoded = try JSONDecoder().decode(GoalHorizonState.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.yesterdayPending.isEmpty)
    }

    func testLegacyMigrationPreservesGoalsIDsCompletionAndHistory() throws {
        let goals = [GoalItem(id: todayID, title: "Existing", isDone: true)]
        let history = ["2026-7-31": GoalHistoryDay(day: "2026-7-31", completed: 2, total: 3)]
        let migrated = GoalHorizonLogic.migrateLegacy(
            goalsData: try JSONEncoder().encode(goals),
            goalsKeyExists: true,
            dayKey: "2026-8-1",
            historyData: try JSONEncoder().encode(history),
            currentDayKey: "2026-8-1",
            currentWeekKey: "2026-31",
            freshDefaults: []
        )

        XCTAssertEqual(migrated.today, goals)
        XCTAssertEqual(migrated.history, history)
        XCTAssertTrue(migrated.week.isEmpty)
        XCTAssertTrue(migrated.longTerm.isEmpty)
    }

    func testCorruptLegacyDataDoesNotInsertDefaultsOverExistingKey() {
        let fallback = [GoalItem(id: todayID, title: "Sample", isDone: false)]
        let migrated = GoalHorizonLogic.migrateLegacy(
            goalsData: Data("bad".utf8),
            goalsKeyExists: true,
            dayKey: nil,
            historyData: Data("bad".utf8),
            currentDayKey: "2026-8-1",
            currentWeekKey: "2026-31",
            freshDefaults: fallback
        )

        XCTAssertTrue(migrated.today.isEmpty)
        XCTAssertTrue(migrated.history.isEmpty)
    }
}
