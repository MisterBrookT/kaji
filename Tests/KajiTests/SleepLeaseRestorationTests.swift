import XCTest
import KajiSleepSupport
@testable import Kaji

final class SleepLeaseRestorationTests: XCTestCase {
    func testRestoresOnlyChangeFromOriginalZero() {
        XCTAssertEqual(SleepLeaseRestoration.target(saved: false, current: true), false)
        XCTAssertNil(SleepLeaseRestoration.target(saved: false, current: false))
        XCTAssertNil(SleepLeaseRestoration.target(saved: true, current: true))
        XCTAssertNil(SleepLeaseRestoration.target(saved: true, current: false))
    }

    func testParsesSystemWidePmsetStateAndRejectsUnknownOutput() {
        XCTAssertEqual(SleepLeaseRestoration.parsePmsetState("System-wide power settings:\n SleepDisabled\t\t1\n"), true)
        XCTAssertEqual(SleepLeaseRestoration.parsePmsetState(" SleepDisabled 0\n"), false)
        XCTAssertNil(SleepLeaseRestoration.parsePmsetState(" sleep 1\n"))
        XCTAssertNil(SleepLeaseRestoration.parsePmsetState(" SleepDisabled 0\n SleepDisabled 1\n"))
    }

    func testMarkerAcceptsOnlyExactSavedBits() {
        XCTAssertEqual(SleepLeaseRestoration.parseMarker(Data("0".utf8)), false)
        XCTAssertEqual(SleepLeaseRestoration.parseMarker(Data("1".utf8)), true)
        for value in ["", "2", "1\n", " 0", "01", "invalid"] {
            XCTAssertNil(SleepLeaseRestoration.parseMarker(Data(value.utf8)))
        }
        XCTAssertNil(SleepLeaseRestoration.parseMarker(Data([0xff])))
    }

    func testInstallRequiresSuccessfulBootstrapWithoutPrintFallback() {
        let command = SleepHelperInstaller.installCommand(
            label: "dev.kaji.sleep-helper", bundledHelper: "/bundle/helper",
            installedHelper: "/Library/PrivilegedHelperTools/helper",
            temporaryPlist: "/tmp/helper.plist", installedPlist: "/Library/LaunchDaemons/helper.plist"
        )
        XCTAssertTrue(command.hasPrefix("set -e; "))
        XCTAssertTrue(command.hasSuffix("/bin/launchctl bootstrap system '/Library/LaunchDaemons/helper.plist'"))
        XCTAssertFalse(command.contains("launchctl print"))
    }

    func testCodeHashMustBeExactHexDigest() {
        XCTAssertTrue(SleepLeaseRestoration.acceptsCodeHash(String(repeating: "a", count: 40)))
        XCTAssertFalse(SleepLeaseRestoration.acceptsCodeHash(String(repeating: "a", count: 39)))
        XCTAssertFalse(SleepLeaseRestoration.acceptsCodeHash(String(repeating: "z", count: 40)))
        XCTAssertFalse(SleepLeaseRestoration.acceptsCodeHash("identifier dev.kaji"))
    }
}
