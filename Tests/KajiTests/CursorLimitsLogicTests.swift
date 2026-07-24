import XCTest
@testable import KajiCore

final class CursorLimitsLogicTests: XCTestCase {
    func testWindowLabels() {
        XCTAssertEqual(
            CursorLimitsLogic.windowLabels(for: "cursor"),
            CursorLimitsLogic.cursorLabels
        )
        XCTAssertEqual(
            CursorLimitsLogic.windowLabels(for: "claude"),
            CursorLimitsLogic.standardLabels
        )
        XCTAssertEqual(CursorLimitsLogic.cursorLabels.primary, "API")
        XCTAssertEqual(CursorLimitsLogic.cursorLabels.secondary, "Auto")
    }

    func testClampPercent() {
        XCTAssertEqual(CursorLimitsLogic.clampPercent(38.39), 38.39)
        XCTAssertEqual(CursorLimitsLogic.clampPercent(-1), 0)
        XCTAssertEqual(CursorLimitsLogic.clampPercent(150), 100)
        XCTAssertNil(CursorLimitsLogic.clampPercent(nil))
        XCTAssertNil(CursorLimitsLogic.clampPercent(.nan))
    }

    func testResetsAtFromMs() {
        // 2025-08-24T00:00:00Z
        let iso = CursorLimitsLogic.resetsAtISO(fromBillingCycleEndMs: 1_755_993_600_000)
        XCTAssertNotNil(iso)
        XCTAssertTrue(iso?.hasPrefix("2025-08-24T00:00:00") == true)
        XCTAssertTrue(iso?.hasSuffix("Z") == true)
        XCTAssertNil(CursorLimitsLogic.resetsAtISO(fromBillingCycleEndMs: nil))
        XCTAssertNil(CursorLimitsLogic.resetsAtISO(fromBillingCycleEndMs: -1))
    }

    func testLimitsMapsOuterAPIInnerAuto() {
        let limits = CursorLimitsLogic.limits(
            apiPercentUsed: 100,
            autoPercentUsed: 38.39,
            billingCycleEndMs: 1_755_993_600_000
        )
        XCTAssertEqual(limits["five_hour_used_percent"] as? Double, 100)
        XCTAssertEqual(limits["seven_day_used_percent"] as? Double, 38.39)
        let fiveReset = limits["five_hour_resets_at"] as? String
        let sevenReset = limits["seven_day_resets_at"] as? String
        XCTAssertEqual(fiveReset, sevenReset)
        XCTAssertTrue(fiveReset?.hasPrefix("2025-08-24T00:00:00") == true)
    }

    func testLimitsOmitsMissingWindows() {
        let onlyAPI = CursorLimitsLogic.limits(
            apiPercentUsed: 50,
            autoPercentUsed: nil,
            billingCycleEndMs: 1_755_993_600_000
        )
        XCTAssertEqual(onlyAPI["five_hour_used_percent"] as? Double, 50)
        XCTAssertNil(onlyAPI["seven_day_used_percent"])
        XCTAssertTrue(onlyAPI.keys.contains("five_hour_resets_at"))
        XCTAssertFalse(onlyAPI.keys.contains("seven_day_resets_at"))
    }
}
