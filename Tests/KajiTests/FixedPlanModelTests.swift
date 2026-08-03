import XCTest
import KajiCore

final class FixedPlanModelTests: XCTestCase {
    func testDefaultPlansUseHealthTag() {
        XCTAssertTrue(FixedPlanModel.defaults.allSatisfy { $0.tag == GoalTag.health.rawValue })
    }

    func testOldPlanJSONDecodesWithEmptyTag() throws {
        let json = """
        {"weekday":2,"title":"Plan","items":[]}
        """
        let plan = try JSONDecoder().decode(FixedDayPlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.tag, "")
    }
    func testDefaults_coverEveryWeekday() {
        XCTAssertEqual(FixedPlanModel.defaults.map(\.weekday), Array(1...7))
    }

    func testTuesday_isExplicitRestPlan() {
        let plan = FixedPlanModel.plan(for: 3, in: FixedPlanModel.defaults)
        XCTAssertEqual(plan.title, "完全休息")
        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.items.first?.title, "休息")
    }

    func testTextRoundTrip_preservesTitlesAndDescriptions() {
        let original = FixedDayPlan(
            weekday: 2,
            title: "固定事项",
            items: [
                FixedPlanItem(title: "阅读", dose: "30 分钟"),
                FixedPlanItem(title: "复盘", dose: ""),
            ]
        )

        let decoded = FixedPlanModel.items(from: FixedPlanModel.text(for: original))

        XCTAssertEqual(decoded.map(\.title), ["阅读", "复盘"])
        XCTAssertEqual(decoded.map(\.dose), ["30 分钟", ""])
    }

    func testParser_ignoresBlankLinesAndTrimsFields() {
        let items = FixedPlanModel.items(from: "\n  喝水 | 500 ml  \n\n散步\n")

        XCTAssertEqual(items.map(\.title), ["喝水", "散步"])
        XCTAssertEqual(items.map(\.dose), ["500 ml", ""])
    }
}
