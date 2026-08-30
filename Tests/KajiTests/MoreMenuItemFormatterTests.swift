import XCTest
import KajiCore

final class MoreMenuItemFormatterTests: XCTestCase {
    func testLabelComposesTitleAndDetail() {
        XCTAssertEqual(
            MoreMenuItemFormatter.label(title: "Goals", detail: "2/4"),
            "Goals · 2/4"
        )
        XCTAssertEqual(
            MoreMenuItemFormatter.label(title: "System", detail: "34%"),
            "System · 34%"
        )
    }

    func testLabelFallsBackToTitleWithoutDetail() {
        XCTAssertEqual(MoreMenuItemFormatter.label(title: "System", detail: nil), "System")
        XCTAssertEqual(MoreMenuItemFormatter.label(title: "System", detail: ""), "System")
    }
}