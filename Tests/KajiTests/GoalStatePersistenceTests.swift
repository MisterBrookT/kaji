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
        let gate = SleepGate()
        let store = DailyGoalStore(
            defaults: defaults,
            completionRemovalDelay: .milliseconds(30),
            completionRemovalSleep: { await gate.sleep($0) }
        )
        let goal = try store.addGoal(title: "Undo me", tag: "Work", note: "", in: .today)

        store.toggle(goal)
        XCTAssertTrue(store.goals.first?.isDone == true)
        let removalTask = try XCTUnwrap(store.completionRemovalTasks[goal.id])
        // Wait until the removal task has actually reached its delay, proving
        // there is a pending removal in flight to cancel below.
        await gate.waitUntilReached()

        let completed = try XCTUnwrap(store.goals.first)
        store.toggle(completed)

        // The cancellation above happens synchronously inside `toggle`, so
        // this assertion does not race any clock.
        XCTAssertEqual(store.goals.map(\.id), [goal.id])
        XCTAssertFalse(store.goals[0].isDone)

        // Release the (already cancelled) task so it observes cancellation
        // and exits cleanly instead of leaking a suspended continuation.
        await gate.release()
        _ = await removalTask.value
    }

    @MainActor
    func testCompletedGoalRetiresAfterDelayWithoutErasingCountsOrHistory() async throws {
        let gate = SleepGate()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let currentDate = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 26, hour: 12)
        ))
        let store = DailyGoalStore(
            defaults: defaults,
            now: { currentDate },
            calendar: calendar,
            completionRemovalDelay: .milliseconds(20),
            completionRemovalSleep: { await gate.sleep($0) }
        )
        let goal = try store.addGoal(title: "Finish me", tag: "Work", note: "", in: .today)

        store.toggle(goal)
        let removalTask = try XCTUnwrap(store.completionRemovalTasks[goal.id])
        await gate.waitUntilReached()
        XCTAssertEqual(store.goals.map(\.id), [goal.id])

        await gate.release()
        await removalTask.value

        XCTAssertTrue(store.goals.isEmpty)
        XCTAssertEqual(store.summary(for: .today).completed, 1)
        XCTAssertEqual(store.summary(for: .today).total, 1)
        XCTAssertEqual(
            store.history["2026-8-26"],
            GoalHistoryDay(day: "2026-8-26", completed: 1, total: 1)
        )
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

/// Deterministic stand-in for `Task.sleep` used by `DailyGoalStore`'s
/// delayed-removal task. Lets a test observe exactly when the production
/// code has entered its delay (`waitUntilReached`) and control exactly when
/// it resumes (`release`), replacing wall-clock races with explicit
/// state-machine signaling.
private actor SleepGate {
    private var hasReached = false
    private var reachedContinuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    /// Called by the code under test in place of `Task.sleep`.
    func sleep(_ duration: Duration) async {
        hasReached = true
        reachedContinuation?.resume()
        reachedContinuation = nil
        if isReleased { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    /// Suspends the caller until `sleep(_:)` has been entered.
    func waitUntilReached() async {
        if hasReached { return }
        await withCheckedContinuation { continuation in
            reachedContinuation = continuation
        }
    }

    /// Lets a suspended (or future) `sleep(_:)` call resume.
    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
