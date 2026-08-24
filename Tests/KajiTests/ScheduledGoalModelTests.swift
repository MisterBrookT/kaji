import XCTest
@testable import KajiCore

final class ScheduledGoalModelTests: XCTestCase {
    func testScheduleRequiresTitleAndAtLeastOneWeekday() {
        XCTAssertFalse(ScheduledGoalLogic.canSave(title: "", weekdays: [2]))
        XCTAssertFalse(ScheduledGoalLogic.canSave(title: "Read", weekdays: []))
        XCTAssertTrue(ScheduledGoalLogic.canSave(title: "Read", weekdays: [2, 4, 6]))
        XCTAssertEqual(ScheduledGoalLogic.normalizedWeekdays([0, 1, 7, 8]), [1, 7])
    }

    func testActiveSchedulesSupportsMultipleEntriesOnSameDay() {
        let first = ScheduledGoal(title: "Read", tag: "learn", weekdays: [2, 3])
        let second = ScheduledGoal(title: "Walk", tag: "health", weekdays: [2])
        XCTAssertEqual(ScheduledGoalLogic.active([first, second], weekday: 2).map(\.id), [first.id, second.id])
        XCTAssertEqual(ScheduledGoalLogic.active([first, second], weekday: 3).map(\.id), [first.id])
    }

    func testCompletionRefreshesAcrossDay() {
        let id = UUID()
        let state = ScheduleCompletionState(dayKey: "2026-8-4", completedIDs: [id])
        XCTAssertEqual(ScheduledGoalLogic.refreshedCompletion(state, dayKey: "2026-8-4"), state)
        XCTAssertEqual(
            ScheduledGoalLogic.refreshedCompletion(state, dayKey: "2026-8-5"),
            ScheduleCompletionState(dayKey: "2026-8-5")
        )
    }

    func testMigrationPreservesPlanContentAndTodayCompletion() {
        let plans = [
            FixedDayPlan(
                weekday: 2,
                title: "训练",
                tag: GoalTag.health.rawValue,
                items: [
                    FixedPlanItem(title: "深蹲", dose: "3 × 10"),
                    FixedPlanItem(title: "散步", dose: ""),
                ]
            ),
            FixedDayPlan(weekday: 3, title: "阅读", tag: GoalTag.learn.rawValue, items: []),
        ]
        let result = ScheduleMigration.migrate(plans: plans, todayWeekday: 2, todayCompleted: true)
        XCTAssertEqual(result.schedules.count, 2)
        XCTAssertEqual(result.schedules[0].weekdays, [2])
        XCTAssertEqual(result.schedules[0].note, "深蹲 · 3 × 10\n散步")
        XCTAssertEqual(result.completedIDs, [result.schedules[0].id])
    }

    func testSelectableGoalTagsUseDistinctSemanticSFSymbols() {
        XCTAssertEqual(GoalTag.selectableCases, [.work, .home, .health, .personal])
        XCTAssertEqual(GoalTag.work.systemImage, "briefcase")
        XCTAssertEqual(GoalTag.home.systemImage, "house")
        XCTAssertEqual(GoalTag.health.systemImage, "heart")
        XCTAssertEqual(GoalTag.personal.systemImage, "person")
        XCTAssertEqual(GoalTag.learn.systemImage, GoalTag.work.systemImage)
        XCTAssertEqual(GoalTag.admin.systemImage, GoalTag.personal.systemImage)
        XCTAssertEqual(Set(GoalTag.selectableCases.map(\.systemImage)).count, GoalTag.selectableCases.count)
    }

    func testDiskSizeFormatterUsesGBThenMB() {
        XCTAssertEqual(DiskSizeFormatter.string(bytes: 16_980_000_000), "17 GB")
        XCTAssertEqual(DiskSizeFormatter.string(bytes: 1_250_000_000), "1.3 GB")
        XCTAssertEqual(DiskSizeFormatter.string(bytes: 980_000_000), "980 MB")
        XCTAssertEqual(DiskSizeFormatter.string(bytes: 500_000), "1 MB")
    }
}
