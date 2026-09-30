import XCTest
import AppKit
import SwiftUI
import KajiCore
@testable import Kaji

/// Footer Update entry: present only when `UpdateChecker.available` is set,
/// reacts live, and routes to review (never install). No network: the
/// checker is seeded through `UpdateChecker(available:)`.
@MainActor
final class PopoverUpdateEntryTests: XCTestCase {
    private static let size = CGSize(width: PanelSize.medium.frameSize.width, height: 640)
    private static let release = UpdateChecker.Release(
        version: "9.9.9", tag: "v9.9.9",
        url: URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v9.9.9")!,
        assetURL: nil
    )

    func testUpdateEntryAppearsOnlyWhenReleaseDetected() throws {
        let fixture = PopoverRenderFixture()
        defer { fixture.tearDown() }
        let checker = UpdateChecker()
        let none = try XCTUnwrap(renderImage(
            fixture.view(page: .quota, maxContentHeight: Self.size.height, updateChecker: checker), size: Self.size))
        writePNG(none, name: "popover-footer-no-update")
        let noneAgain = try XCTUnwrap(renderImage(
            fixture.view(page: .quota, maxContentHeight: Self.size.height, updateChecker: UpdateChecker()), size: Self.size))
        XCTAssertEqual(footerLeftPixels(none), footerLeftPixels(noneAgain), "footer must be stable without a release")

        let available = UpdateChecker(available: Self.release)
        let shown = try XCTUnwrap(renderImage(
            fixture.view(page: .quota, maxContentHeight: Self.size.height, updateChecker: available), size: Self.size))
        XCTAssertNotNil(writePNG(shown, name: "popover-footer-update-available"))
        XCTAssertNotEqual(footerLeftPixels(none), footerLeftPixels(shown), "Update entry must render beside gear/power")
    }

    /// Footer row left of the gear/power buttons, where the Update entry sits.
    private func footerLeftPixels(_ rep: NSBitmapImageRep) -> [UInt32] {
        var out: [UInt32] = []
        let h = rep.pixelsHigh, w = rep.pixelsWide
        let rows = Int(Double(h) * 0.12)
        var y = h - rows
        while y < h {
            var x = w / 4
            while x < w - Int(Double(w) * 0.25) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    out.append(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
                }
                x += 2
            }
            y += 2
        }
        return out
    }

    func testReviewReusesSettingsWindowAndPresentsConfirmation() async throws {
        let harness = KajiUIHarness()
        defer {
            for window in NSApp.windows where window.title == "Kaji Settings" {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
                window.close()
            }
            harness.tearDown()
        }
        harness.clickStatusItem()
        harness.appDelegate.reviewUpdate(Self.release)
        try await Task.sleep(for: .milliseconds(200))
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Kaji Settings" })
        XCTAssertFalse(harness.appDelegate.popover.isShown)
        XCTAssertNotNil(window.attachedSheet, "Footer review must show the changelog confirmation")
        harness.appDelegate.reviewUpdate(Self.release)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(NSApp.windows.first { $0.title == "Kaji Settings" } === window,
                      "Review must not close and recreate Settings, losing its state")
        XCTAssertNotNil(window.attachedSheet)
    }

    func testFooterReviewCallbackReceivesReleaseWithoutInstalling() throws {
        var reviewed: [UpdateChecker.Release] = []
        let controls = KajiPopoverControls(
            onOpenSettings: {}, onQuit: {},
            onReviewUpdate: { reviewed.append($0) }
        )
        controls.onReviewUpdate(Self.release)
        XCTAssertEqual(reviewed, [Self.release])
    }
}
