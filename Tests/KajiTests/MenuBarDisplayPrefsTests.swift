import XCTest
import KajiCore
@testable import Kaji

@MainActor
final class MenuBarDisplayPrefsTests: XCTestCase {
    func testNewDefaultsUseMinutesAndIncompleteCount() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let prefs = Prefs(defaults: defaults)

        XCTAssertEqual(prefs.workTimeDisplayStyle, .minutesOnly)
        XCTAssertEqual(prefs.goalMenuBarDisplayStyle, .incompleteCount)
    }

    func testLegacyDisplayChoicesPersist() {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        var prefs: Prefs? = Prefs(defaults: defaults)
        prefs?.workTimeDisplayStyle = .exactSeconds
        prefs?.goalMenuBarDisplayStyle = .todayFraction
        prefs = nil

        let reloaded = Prefs(defaults: defaults)
        XCTAssertEqual(reloaded.workTimeDisplayStyle, .exactSeconds)
        XCTAssertEqual(reloaded.goalMenuBarDisplayStyle, .todayFraction)
    }

    private var defaultsSuiteName: String {
        "MenuBarDisplayPrefsTests"
    }

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        return defaults
    }
}
