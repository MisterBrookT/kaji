import XCTest
import AppKit
import SwiftUI
import KajiCore
@testable import Kaji

/// Renders every popover page to a real bitmap (no XCUITest — see
/// `Tests/KajiTests/UITestHarness.swift`) and asserts it isn't blank, so a
/// page that silently renders empty/black doesn't slip through
/// `swift build` (which only proves the view compiles, not that it draws
/// anything). PNGs land in `.build/ui-snapshots/<page>.png` for a human/agent
/// to eyeball.
@MainActor
final class PopoverRenderTests: XCTestCase {
    private static let renderSize = CGSize(width: PanelSize.medium.frameSize.width, height: 640)

    func testEveryModulePageRendersNonBlank() throws {
        let fixture = PopoverRenderFixture()
        defer { fixture.tearDown() }
        for page in KajiModuleID.allCases {
            let view = fixture.view(page: page, maxContentHeight: Self.renderSize.height)
            guard let rep = renderImage(view, size: Self.renderSize) else {
                XCTFail("\(page): failed to render bitmap")
                continue
            }
            writePNG(rep, name: "popover-\(page.rawValue)")
            assertNonBlank(rep, page: page)
        }
    }
    func testGroupedGoalsPageRendersNonBlank() throws {
        let fixture = PopoverRenderFixture()
        defer { fixture.tearDown() }
        fixture.prefs.goalGrouping = .byTag
        _ = try fixture.dailyGoals.addGoal(
            title: "Fixture work goal",
            tag: GoalTag.work.rawValue,
            note: "",
            in: .today
        )
        let view = fixture.view(page: .goals, maxContentHeight: Self.renderSize.height)
        guard let rep = renderImage(view, size: Self.renderSize) else {
            return XCTFail("grouped goals: failed to render bitmap")
        }
        XCTAssertNotNil(writePNG(rep, name: "popover-goals-grouped-by-tag"))
        assertNonBlank(rep, page: .goals)
    }

    func testSecondaryDetailPopoverRendersNonBlank() throws {
        let fixture = PopoverRenderFixture()
        defer { fixture.tearDown() }
        let page = fixture.view(page: .goals, maxContentHeight: Self.renderSize.height)
        let goal = try XCTUnwrap(fixture.dailyGoals.goals(for: .today).first)
        let detail = page.goalDetailContent(goal, horizon: .today)
        let rep = try XCTUnwrap(renderImage(detail, size: CGSize(width: 260, height: 180)))
        let path = try XCTUnwrap(writePNG(rep, name: "popover-secondary-goal-detail"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        assertNonBlank(rep, page: .goals)
    }


    /// Samples a grid of pixels and requires more than one distinct color —
    /// a single solid color (all-black, all-white, all-clear) means the view
    /// drew nothing.
    private func assertNonBlank(_ rep: NSBitmapImageRep, page: KajiModuleID) {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else {
            XCTFail("\(page): zero-sized bitmap")
            return
        }
        var seenColors = Set<UInt32>()
        let stepX = max(1, width / 24)
        let stepY = max(1, height / 24)
        var x = 0
        while x < width {
            var y = 0
            while y < height {
                if let color = rep.colorAt(x: x, y: y) {
                    let packed = pack(color)
                    seenColors.insert(packed)
                }
                y += stepY
            }
            x += stepX
        }
        XCTAssertGreaterThan(
            seenColors.count, 1,
            "\(page): sampled pixels are all one color (\(seenColors.first.map { String(format: "0x%08X", $0) } ?? "?")) — page rendered blank"
        )
    }

    private func pack(_ color: NSColor) -> UInt32 {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0 }
        let r = UInt32(rgb.redComponent * 255)
        let g = UInt32(rgb.greenComponent * 255)
        let b = UInt32(rgb.blueComponent * 255)
        let a = UInt32(rgb.alphaComponent * 255)
        return (r << 24) | (g << 16) | (b << 8) | a
    }
}
