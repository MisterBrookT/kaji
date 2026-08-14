import XCTest
import KajiCore

/// Unit tests for lean-modules-v1 pure logic.
/// Spec cases: `dev_docs/specs/2026-07-24-lean-modules-v1.md` §7.
final class ModulePrefsLogicTests: XCTestCase {

    // MARK: - normalizeEnabledModules

    func testNormalize_nil_yieldsSlimDefault() {
        let result = ModulePrefsLogic.normalizeEnabledModules(nil)
        XCTAssertEqual(result, ModulePrefsLogic.slimDefault)
    }

    func testNormalize_empty_yieldsSlimDefault() {
        let result = ModulePrefsLogic.normalizeEnabledModules([])
        XCTAssertEqual(result, ModulePrefsLogic.slimDefault)
    }

    func testNormalize_quotaOnly_unchanged() {
        let result = ModulePrefsLogic.normalizeEnabledModules(["quota"])
        XCTAssertEqual(result, [.quota])
    }

    func testNormalize_allFour_preservesAll() {
        let result = ModulePrefsLogic.normalizeEnabledModules(
            ["goals", "system", "work", "quota"]
        )
        XCTAssertEqual(result, [.quota, .work, .system, .goals])
    }

    func testNormalize_missingQuota_isForcedOn() {
        let result = ModulePrefsLogic.normalizeEnabledModules(["work", "system"])
        XCTAssertTrue(result.contains(.quota))
        XCTAssertTrue(result.contains(.work))
        XCTAssertTrue(result.contains(.system))
        XCTAssertFalse(result.contains(.goals))
    }

    func testNormalize_unknownIds_areDropped() {
        let result = ModulePrefsLogic.normalizeEnabledModules(["quota", "foo", "bar"])
        XCTAssertEqual(result, [.quota])
    }

    func testNormalize_onlyUnknown_fallsBackToSlimDefault() {
        // After dropping unknown, empty → slim default (still has quota).
        let result = ModulePrefsLogic.normalizeEnabledModules(["foo"])
        XCTAssertEqual(result, ModulePrefsLogic.slimDefault)
    }

    // MARK: - popoverPages

    func testPopoverPages_quotaOnly() {
        let pages = ModulePrefsLogic.popoverPages(enabled: [.quota])
        XCTAssertEqual(pages, [.quota])
    }

    func testPopoverPages_stableOrder_skipsDisabled() {
        let pages = ModulePrefsLogic.popoverPages(enabled: [.goals, .quota, .work])
        XCTAssertEqual(pages, [.quota, .work, .goals])
    }

    func testPopoverPages_allEnabled_fullOrder() {
        let pages = ModulePrefsLogic.popoverPages(
            enabled: [.quota, .work, .system, .goals, .aiNews, .mailBrief]
        )
        XCTAssertEqual(pages, KajiModuleID.stableOrder)
    }

    func testAIHotDefaultsOffAndAppearsAfterGoalsWhenEnabled() {
        XCTAssertFalse(ModulePrefsLogic.normalizeEnabledModules(nil).contains(.aiNews))
        XCTAssertEqual(ModulePrefsLogic.popoverPages(enabled: [.quota, .goals, .aiNews]), [.quota, .goals, .aiNews])
    }

    func testMailBriefDefaultsOffAndAppearsAfterAINewsWhenEnabled() {
        XCTAssertFalse(ModulePrefsLogic.normalizeEnabledModules(nil).contains(.mailBrief))
        XCTAssertEqual(
            ModulePrefsLogic.popoverPages(enabled: [.quota, .goals, .aiNews, .mailBrief]),
            [.quota, .goals, .aiNews, .mailBrief]
        )
    }

    func testPopoverPages_ignoresQuotaMissingInSet_byCallerContract() {
        // popoverPages assumes normalize already ran; if quota absent, pages
        // simply omit it (normalize is the gate). Documented contract.
        let pages = ModulePrefsLogic.popoverPages(enabled: [.work])
        XCTAssertEqual(pages, [.work])
    }
}
