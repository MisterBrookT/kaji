import XCTest
import KajiCore

final class GoalHorizonModelTests: XCTestCase {
    func testOldGoalJSONDecodesWithEmptyTag() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","title":"Ship","isDone":false}
        """
        let goal = try JSONDecoder().decode(GoalItem.self, from: Data(json.utf8))
        XCTAssertEqual(goal.tag, "")
        XCTAssertEqual(goal.note, "")
    }

    func testRefreshPreservesTags() {
        let goal = GoalItem(id: UUID(), title: "Run", isDone: false, tag: "Health")
        let state = GoalHorizonState(
            today: [goal],
            week: [],
            longTerm: [],
            dayKey: "2026-8-1",
            weekKey: "2026-31",
            history: [:]
        )
        let refreshed = GoalHorizonLogic.refresh(
            state,
            dayKey: "2026-8-2",
            weekKey: "2026-31"
        )
        XCTAssertEqual(refreshed.today.first?.tag, "Health")
    }

    func testTagInferenceClassifiesCurrentTaskStyles() {
        XCTAssertEqual(GoalTagLogic.resolve("", title: "洗衣服 + 扔垃圾"), .home)
        XCTAssertEqual(GoalTagLogic.resolve("", title: "调研 RSI 研究方向"), .learn)
        XCTAssertEqual(GoalTagLogic.resolve("", title: "acl 报账"), .admin)
        XCTAssertEqual(GoalTagLogic.resolve("", title: "提交 dataset 和视频"), .learn)
        XCTAssertEqual(GoalTagLogic.resolve("", title: "完成公司项目"), .work)
        XCTAssertEqual(GoalTagLogic.resolve("", title: "戒烟"), .health)
    }

    func testTagResolutionPreservesExplicitChoice() {
        XCTAssertEqual(GoalTagLogic.resolve("Work", title: "洗衣服"), .work)
        XCTAssertEqual(GoalTagLogic.resolve("personal", title: "公司项目"), .personal)
    }
    private let todayID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let weekID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let longID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    func testDayChangeRecordsActivityAndKeepsGoals() {
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

        XCTAssertEqual(refreshed.today, state.today)
        XCTAssertTrue(refreshed.yesterdayPending.isEmpty)
        XCTAssertTrue(refreshed.week[0].isDone)
        XCTAssertTrue(refreshed.longTerm[0].isDone)
        XCTAssertEqual(refreshed.history["2026-8-1"], GoalHistoryDay(day: "2026-8-1", completed: 1, total: 2))
    }

    func testWeekChangeKeepsCompletionState() {
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
        XCTAssertTrue(refreshed.week[0].isDone)
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

    func testHeatmapReadoutFormatsEmptyDay() {
        XCTAssertEqual(
            GoalHeatmapFormatter.string(day: "2026-8-26", completed: 0, total: 0),
            "2026-8-26-0/0"
        )
    }

    func testHeatmapReadoutFormatsAllCompleteDay() {
        XCTAssertEqual(
            GoalHeatmapFormatter.string(day: "2026-8-26", completed: 4, total: 4),
            "2026-8-26-4/4"
        )
    }

}
