import XCTest
import AppKit
import SwiftUI
import KajiCore
@testable import Kaji

final class UpdateReleaseNotesTests: XCTestCase {
    func testParseGroupsMarkdownHeadingsIntoCategories() {
        let body = """
        ## What's changed
        Intro paragraph that is not a bullet.

        ### Fixed
        - Claude token renewal no longer **stalls**
        * Codex reads quota under minimal `PATH`

        ### Added
        - Update changelog in [Settings](https://example.com/x)

        **Removed**
        - System module
        """
        let notes = ReleaseNotes.parse(body)
        XCTAssertEqual(notes.fixed, ["Claude token renewal no longer stalls", "Codex reads quota under minimal PATH"])
        XCTAssertEqual(notes.added, ["Update changelog in Settings"])
        XCTAssertEqual(notes.removed, ["System module"])
        XCTAssertEqual(notes.other, [])
    }

    func testParseDefaultsEmptyAndUncategorizedBody() {
        XCTAssertTrue(ReleaseNotes.parse(nil).isEmpty)
        XCTAssertTrue(ReleaseNotes.parse("").isEmpty)
        XCTAssertTrue(ReleaseNotes.parse("Just prose, no bullets.").isEmpty)
        let notes = ReleaseNotes.parse("- one\n1. two\nChanges:\n- three")
        XCTAssertEqual(notes.other, ["one", "two", "three"])
    }

    func testHeadingSynonyms() {
        XCTAssertEqual(ReleaseNotes.category(forHeading: "Bug fixes"), .fixed)
        XCTAssertEqual(ReleaseNotes.category(forHeading: "New features"), .added)
        XCTAssertEqual(ReleaseNotes.category(forHeading: "Deprecated"), .removed)
        XCTAssertEqual(ReleaseNotes.category(forHeading: "Chores"), .other)
    }

    func testParseCapsItemsPerCategory() {
        let body = "### Fixed\n" + (0..<100).map { "- item \($0)" }.joined(separator: "\n")
        XCTAssertEqual(ReleaseNotes.parse(body).fixed.count, 30)
    }

    @MainActor
    func testSourceOnlyReleaseCannotInstallDifferentLatestVersion() async {
        let release = UpdateChecker.Release(
            version: "1.0.0", tag: "v2.0.0",
            url: URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v1.0.0")!,
            assetURL: nil
        )
        do {
            try await UpdateChecker(binaryUpdater: nil).install(release)
            XCTFail("must reject mismatched approved version/tag before building")
        } catch {
            XCTAssertEqual(error as? UpdateChecker.InstallError, .invalidRelease)
        }
    }

    @MainActor
    func testUpdateNotesSheetRendersAndOnlyInstallsFromExplicitAction() {
        var installs = 0
        let release = UpdateChecker.Release(
            version: "1.0.0", tag: "v1.0.0",
            url: URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v1.0.0")!,
            assetURL: nil,
            notes: ReleaseNotes(fixed: ["a"], added: ["b"], removed: ["c"])
        )
        let sheet = UpdateNotesSheet(release: release, currentVersion: "0.9.6", language: .en,
                                     onInstall: { installs += 1 }, onViewRelease: {}, onCancel: {})
        let host = NSHostingView(rootView: sheet)
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 100)
        XCTAssertEqual(installs, 0)
        sheet.onInstall()
        XCTAssertEqual(installs, 1)
    }
}
