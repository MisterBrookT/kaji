import XCTest
@testable import Kaji

@MainActor
final class SparkleBinaryUpdaterTests: XCTestCase {
    private let key = "1neydtMK0p/buAE35Fo7N2HQXwJ/g2FR03Fv8AG0gtE="
    private let feed = "https://github.com/example/kaji/releases/latest/download/appcast.xml"
    private let app = URL(fileURLWithPath: "/tmp/Kaji.app")

    func testValidConfigurationIsAccepted() {
        let c = SparkleBundleConfiguration.validated(bundleURL: app,
            info: ["SUPublicEDKey": key, "SUFeedURL": feed])
        XCTAssertEqual(c?.feedURL.absoluteString, feed)
    }

    func testRejectsNonAppBundle() {
        XCTAssertNil(SparkleBundleConfiguration.validated(bundleURL: URL(fileURLWithPath: "/tmp/KajiTests.xctest"),
            info: ["SUPublicEDKey": key, "SUFeedURL": feed]))
    }

    func testRejectsBadKeys() {
        for bad in ["", "abc", " " + key, Data(count: 31).base64EncodedString(), Data(count: 33).base64EncodedString()] {
            XCTAssertNil(SparkleBundleConfiguration.validated(bundleURL: app,
                info: ["SUPublicEDKey": bad, "SUFeedURL": feed]), bad)
        }
        XCTAssertNil(SparkleBundleConfiguration.validated(bundleURL: app, info: ["SUFeedURL": feed]))
    }

    func testRejectsNonCanonicalFeeds() {
        for bad in ["http://example.com/appcast.xml", "https:///x", "https://u:p@example.com/a",
                    "https://example.com/a#f", " https://example.com/a", "file:///tmp/a"] {
            XCTAssertNil(SparkleBundleConfiguration.validated(bundleURL: app,
                info: ["SUPublicEDKey": key, "SUFeedURL": bad]), bad)
        }
    }

    func testTestHostBundleIsInactiveAndCheckIsSafe() {
        let updater = SparkleBinaryUpdater()
        XCTAssertFalse(updater.isAvailable)
        updater.checkForUpdates()
    }
}
