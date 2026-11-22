// brook 11-22: "only quota tracking may be on by default; every other feature (to-do list,
// focus tools, etc.) must be OFF by default, opt-in in Settings ... existing users keep their
// current choices (migrate only unset prefs). Add a test that asserts the default set = {quota}."
import XCTest
import KajiCore
@testable import Kaji

@MainActor
final class DefaultModulesTests: XCTestCase {
    private func fresh(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaultSetIsQuotaOnly() {
        XCTAssertEqual(ModulePrefsLogic.slimDefault, [.quota])
        let d = fresh("kaji.defaults.fresh")
        defer { d.removePersistentDomain(forName: "kaji.defaults.fresh") }
        let prefs = Prefs(defaults: d)
        XCTAssertEqual(prefs.enabledModules, [.quota])
        for m in KajiModuleID.allCases where m != .quota {
            XCTAssertFalse(prefs.isModuleEnabled(m), "\(m) must be off by default")
        }
        XCTAssertFalse(prefs.preventSleep)
    }

    func testExistingChoicesAreKept() {
        let d = fresh("kaji.defaults.existing")
        defer { d.removePersistentDomain(forName: "kaji.defaults.existing") }
        d.set(["quota", "goals", "work"], forKey: Prefs.Key.enabledModules)
        XCTAssertEqual(Prefs(defaults: d).enabledModules, [.quota, .goals, .work])
    }

    func testGpuModuleIsOptIn() {
        let d = fresh("kaji.defaults.gpu")
        defer { d.removePersistentDomain(forName: "kaji.defaults.gpu") }
        let prefs = Prefs(defaults: d)
        XCTAssertFalse(prefs.isModuleEnabled(.gpu))
        prefs.setModule(.gpu, enabled: true)
        XCTAssertTrue(Prefs(defaults: d).isModuleEnabled(.gpu))
    }
}
