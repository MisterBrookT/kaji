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

    func testNormalizeLegacySystemIsDropped() {
        let result = ModulePrefsLogic.normalizeEnabledModules(
            ["goals", "system", "work", "quota"]
        )
        XCTAssertEqual(result, [.quota, .work, .goals])
    }

    func testNormalize_missingQuota_isForcedOn() {
        let result = ModulePrefsLogic.normalizeEnabledModules(["work"])
        XCTAssertTrue(result.contains(.quota))
        XCTAssertTrue(result.contains(.work))
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

    // MARK: - Primary and More modules

    func testNormalizedFavoritesDropsQuotaDisabledAndDuplicatesAndCapsAtTwo() {
        let enabled: Set<KajiModuleID> = [.quota, .work, .goals]
        XCTAssertEqual(
            ModulePrefsLogic.normalizedFavorites(
                [.quota, .goals, .work, .goals],
                enabled: enabled
            ),
            [.goals, .work]
        )
        XCTAssertEqual(
            ModulePrefsLogic.normalizedFavorites([.work, .goals], enabled: [.quota, .goals]),
            [.goals]
        )
    }

    func testPrimaryModulesAreQuotaFirstAndFavoriteOrdered() {
        XCTAssertEqual(
            ModulePrefsLogic.primaryModules(
                enabled: [.quota, .work, .goals],
                favorites: [.goals, .work]
            ),
            [.quota, .goals, .work]
        )
    }

    func testMoreModulesUseStableOrderAndExcludePrimaryModules() {
        XCTAssertEqual(
            ModulePrefsLogic.moreModules(
                enabled: [.quota, .work, .goals],
                favorites: [.goals]
            ),
            [.work]
        )
    }
}
