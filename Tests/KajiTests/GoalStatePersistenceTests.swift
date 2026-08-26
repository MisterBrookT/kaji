import XCTest
import KajiCore
@testable import Kaji

final class GoalStatePersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "GoalStatePersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testValidCurrentStateLoadsWithoutRewrite() throws {
        let state = fixtureState()
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: GoalStatePersistence.stateKey)

        let result = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: "2026-8-3",
            currentWeekKey: "2026-31"
        )

        XCTAssertEqual(result.state, state)
        XCTAssertNil(result.issue)
        XCTAssertEqual(defaults.data(forKey: GoalStatePersistence.stateKey), data)
    }

    func testMissingStateInitializesEmptyAndRepeatedLoadIsStable() {
        let first = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: "2026-8-3",
            currentWeekKey: "2026-31"
        )
        let second = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: "2026-8-3",
            currentWeekKey: "2026-31"
        )

        XCTAssertEqual(first.issue, .missingStateInitializedEmpty)
        XCTAssertTrue(first.state.today.isEmpty)
        XCTAssertTrue(first.state.week.isEmpty)
        XCTAssertTrue(first.state.longTerm.isEmpty)
        XCTAssertEqual(second.state, first.state)
        XCTAssertNil(second.issue)
    }

    func testLegacyKeysAreDeletedAndNeverImported() throws {
        let legacyGoal = GoalItem(id: UUID(), title: "Do not resurrect", isDone: true)
        defaults.set(try JSONEncoder().encode([legacyGoal]), forKey: "dailyGoals")
        defaults.set("2026-8-2", forKey: "dailyGoalsDayKey")
        defaults.set(Data("history".utf8), forKey: "dailyGoalsHistory")
        defaults.set(1, forKey: "goalHorizonMigrationVersion")

        let result = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: "2026-8-3",
            currentWeekKey: "2026-31"
        )

        XCTAssertTrue(result.state.today.isEmpty)
        for key in GoalStatePersistence.legacyKeys {
            XCTAssertNil(defaults.object(forKey: key))
        }
    }

    func testCorruptStateIsBackedUpAndReplacedWithRecoverableEmptyState() {
        let corrupt = Data("{broken".utf8)
        defaults.set(corrupt, forKey: GoalStatePersistence.stateKey)
        defaults.set(Data("legacy".utf8), forKey: "dailyGoals")

        let first = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: "2026-8-3",
            currentWeekKey: "2026-31"
        )
        let second = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: "2026-8-3",
            currentWeekKey: "2026-31"
        )

        XCTAssertEqual(first.issue, .corruptStateInitializedEmpty)
        XCTAssertTrue(first.state.today.isEmpty)
        XCTAssertEqual(defaults.data(forKey: GoalStatePersistence.corruptBackupKey), corrupt)
        XCTAssertEqual(
            GoalStatePersistence.diagnostic(from: defaults)?.issue,
            .corruptStateInitializedEmpty
        )
        XCTAssertNil(defaults.object(forKey: "dailyGoals"))
        XCTAssertEqual(second.state, first.state)
        XCTAssertNil(second.issue)
    }

    func testInvalidStateTypeRecordsDiagnosticWithoutLegacyFallback() {
        defaults.set("not data", forKey: GoalStatePersistence.stateKey)
        defaults.set(Data("legacy".utf8), forKey: "dailyGoals")

        let result = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: "2026-8-3",
            currentWeekKey: "2026-31"
        )

        XCTAssertEqual(result.issue, .invalidStateTypeInitializedEmpty)
        XCTAssertTrue(result.state.today.isEmpty)
        XCTAssertEqual(
            GoalStatePersistence.diagnostic(from: defaults)?.issue,
            .invalidStateTypeInitializedEmpty
        )
        XCTAssertNil(defaults.object(forKey: "dailyGoals"))
    }

    func testCrossDayRefreshPersistsHistoryAndGoals() throws {
        let openID = UUID()
        let doneID = UUID()
        var state = GoalHorizonState(
            today: [
                GoalItem(id: openID, title: "Open", isDone: false, tag: "Work"),
                GoalItem(id: doneID, title: "Done", isDone: true, tag: "Home"),
            ],
            week: [],
            longTerm: [],
            dayKey: "2026-8-2",
            weekKey: "2026-31",
            history: [:]
        )
        try GoalStatePersistence.save(state, defaults: defaults)

        state = GoalHorizonLogic.refresh(
            state,
            dayKey: "2026-8-3",
            weekKey: "2026-31"
        )
        try GoalStatePersistence.save(state, defaults: defaults)
        let reloaded = GoalStatePersistence.load(
            defaults: defaults,
            currentDayKey: "2026-8-3",
            currentWeekKey: "2026-31"
        ).state

        XCTAssertEqual(reloaded.today.map(\.id), [openID, doneID])
        XCTAssertTrue(reloaded.yesterdayPending.isEmpty)
        XCTAssertEqual(
            reloaded.history["2026-8-2"],
            GoalHistoryDay(day: "2026-8-2", completed: 1, total: 2)
        )
    }

    @MainActor
    func testCompletedGoalCanBeUndoneBeforeDelayedRemoval() async throws {
        let store = DailyGoalStore(
            defaults: defaults,
            completionRemovalDelay: .milliseconds(30)
        )
        let goal = try store.addGoal(title: "Undo me", tag: "Work", note: "", in: .today)

        store.toggle(goal)
        XCTAssertTrue(store.goals.first?.isDone == true)
        try await Task.sleep(for: .milliseconds(10))
        let completed = try XCTUnwrap(store.goals.first)
        store.toggle(completed)
        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(store.goals.map(\.id), [goal.id])
        XCTAssertFalse(store.goals[0].isDone)
    }

    @MainActor
    func testCompletedGoalIsRemovedAfterDelay() async throws {
        let store = DailyGoalStore(
            defaults: defaults,
            completionRemovalDelay: .milliseconds(20)
        )
        let goal = try store.addGoal(title: "Finish me", tag: "Work", note: "", in: .today)

        store.toggle(goal)
        for _ in 0..<50 where !store.goals.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(store.goals.isEmpty)
    }

    private func fixtureState() -> GoalHorizonState {
        GoalHorizonState(
            today: [GoalItem(id: UUID(), title: "Today", isDone: true, tag: "Work")],
            week: [GoalItem(id: UUID(), title: "Week", isDone: false, tag: "Learn")],
            longTerm: [GoalItem(id: UUID(), title: "Vision", isDone: false, tag: "Health")],
            dayKey: "2026-8-3",
            weekKey: "2026-31",
            history: ["2026-8-2": GoalHistoryDay(day: "2026-8-2", completed: 1, total: 2)],
            yesterdayPending: [GoalItem(id: UUID(), title: "Pending", isDone: false, tag: "Home")]
        )
    }
}
