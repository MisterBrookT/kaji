import XCTest
import KajiCore

final class MoreMenuItemFormatterTests: XCTestCase {
    func testLabelComposesTitleAndDetail() {
        XCTAssertEqual(
            MoreMenuItemFormatter.label(title: "Background Tasks", detail: "2 failed"),
            "Background Tasks · 2 failed"
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

    func testLaunchdDetailFlagsFailures() {
        XCTAssertEqual(
            MoreMenuItemFormatter.launchdDetail(LaunchdMenuBarStatus(count: 2, hasFailures: true)),
            "2 failed"
        )
        XCTAssertEqual(
            MoreMenuItemFormatter.launchdDetail(LaunchdMenuBarStatus(count: 5, hasFailures: false)),
            "5"
        )
        XCTAssertNil(MoreMenuItemFormatter.launchdDetail(nil))
    }
}