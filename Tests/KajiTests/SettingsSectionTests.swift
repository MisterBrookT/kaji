import XCTest
@testable import Kaji

final class SettingsSectionTests: XCTestCase {
    func testModulesAreMergedIntoGeneralWithoutOwnSidebarSection() {
        XCTAssertNil(SettingsSection(rawValue: "Modules"))
        XCTAssertEqual(SettingsSection.allCases.first, .general)
        XCTAssertFalse(SettingsSection.allCases.map(\.rawValue).contains("Modules"))
    }
}
