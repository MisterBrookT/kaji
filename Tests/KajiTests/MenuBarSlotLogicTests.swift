import XCTest
import KajiCore

final class MenuBarSlotLogicTests: XCTestCase {
    func testGoalsDisabledHasNoLabel() {
        XCTAssertNil(MenuBarSlotLogic.goalsLabel(enabled: false, goals: []))
    }

    func testGoalsLabelShowsTodayCompletion() {
        let goals = [
            GoalItem(id: UUID(), title: "One", isDone: true),
            GoalItem(id: UUID(), title: "Two", isDone: false),
            GoalItem(id: UUID(), title: "Three", isDone: true),
            GoalItem(id: UUID(), title: "Four", isDone: false),
        ]
        XCTAssertEqual(MenuBarSlotLogic.goalsLabel(enabled: true, goals: goals), "2/4")
    }

    func testGoalsLabelIncludesFixedPlanAsOneGoal() {
        let goals = [
            GoalItem(id: UUID(), title: "One", isDone: true),
            GoalItem(id: UUID(), title: "Two", isDone: false),
        ]
        XCTAssertEqual(
            MenuBarSlotLogic.goalsLabel(
                enabled: true,
                goals: goals,
                fixedPlanCompleted: false
            ),
            "1/3"
        )
        XCTAssertEqual(
            MenuBarSlotLogic.goalsLabel(
                enabled: true,
                goals: goals,
                fixedPlanCompleted: true
            ),
            "2/3"
        )
    }

    func testEmptyGoalsStillShowsEntryPoint() {
        XCTAssertEqual(MenuBarSlotLogic.goalsLabel(enabled: true, goals: []), "0/0")
    }

    func testSlotDestinations() {
        XCTAssertEqual(MenuBarSlotLogic.destination(for: .quota), .quota)
        XCTAssertEqual(MenuBarSlotLogic.destination(for: .work), .work)
        XCTAssertEqual(MenuBarSlotLogic.destination(for: .goals), .goalsToday)
        XCTAssertEqual(MenuBarSlotLogic.destination(for: .system), .system)
        XCTAssertEqual(MenuBarSlotLogic.destination(for: .background), .quota)
    }

}
