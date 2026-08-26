import XCTest
import AppKit
import SwiftUI
import KajiCore
@testable import Kaji

/// Regression guard for the recurring "blank strip above the header" bug.
///
/// `AppDelegate.resizePopoverContent` clamps `NSPopover.contentSize` to
/// `maxContentHeight`, but the hosting view keeps whatever height SwiftUI
/// laid out. Any page whose laid-out height exceeds `maxContentHeight`
/// therefore renders the overshoot as dead space at the top of the popover.
/// The overshoot only appears once a list is long enough to hit the scroll
/// cap, which is why short pages always looked fine.
@MainActor
final class PopoverHeightBudgetTests: XCTestCase {
    private static let width = PanelSize.medium.frameSize.width

    func testScrollBudgetSubtractsMeasuredChrome() {
        XCTAssertEqual(
            PopoverHeightBudget.scrollMaxHeight(maxContentHeight: 836, measuredChrome: 128),
            708
        )
    }

    func testScrollBudgetFallsBackToEstimateBeforeFirstMeasurement() {
        XCTAssertEqual(
            PopoverHeightBudget.scrollMaxHeight(maxContentHeight: 836, measuredChrome: 0),
            836 - PopoverHeightBudget.initialChromeEstimate
        )
    }

    func testScrollBudgetNeverCollapsesBelowMinimum() {
        XCTAssertEqual(
            PopoverHeightBudget.scrollMaxHeight(maxContentHeight: 200, measuredChrome: 128),
            PopoverHeightBudget.minimumScrollHeight
        )
    }

    func testChromeHeightIsTotalMinusScroll() {
        XCTAssertEqual(PopoverHeightBudget.chromeHeight(totalHeight: 860, scrollHeight: 732), 128)
        XCTAssertEqual(PopoverHeightBudget.chromeHeight(totalHeight: 100, scrollHeight: 200), 0)
    }

    /// The real layout check: a goals list long enough to hit the scroll cap
    /// must still lay out within `maxContentHeight`. Before the fix this
    /// measured 860 against a 836 limit — exactly the 24pt strip.
    func testLongGoalsListNeverOvershootsMaxContentHeight() throws {
        let fixture = PopoverRenderFixture()
        defer { fixture.tearDown() }
        for i in 2...40 {
            _ = try? fixture.dailyGoals.addGoal(
                title: "Stress goal \(i) with a title long enough to wrap onto a second line",
                tag: GoalTag.personal.rawValue,
                note: i % 3 == 0 ? "note \(i)" : "",
                in: .today
            )
        }

        for maxContentHeight in [CGFloat(320), 560, 836] {
            let laidOut = try layoutHeight(fixture: fixture, page: .goals, maxContentHeight: maxContentHeight)
            XCTAssertLessThanOrEqual(
                laidOut, maxContentHeight,
                "goals page laid out \(laidOut)pt against a \(maxContentHeight)pt limit — the overshoot renders as a blank strip above the header"
            )
        }
    }

    func testEveryPageStaysWithinMaxContentHeight() throws {
        let fixture = PopoverRenderFixture()
        defer { fixture.tearDown() }
        for i in 2...24 {
            _ = try? fixture.dailyGoals.addGoal(
                title: "Stress goal \(i)", tag: GoalTag.personal.rawValue, note: "", in: .today
            )
        }

        for page in KajiModuleID.allCases {
            let laidOut = try layoutHeight(fixture: fixture, page: page, maxContentHeight: 560)
            XCTAssertLessThanOrEqual(laidOut, 560, "\(page) overshoots the popover height limit")
        }
    }

    /// Lays the page out exactly the way `AppDelegate` does: fixed width,
    /// SwiftUI decides the height, and the measured height is what
    /// `resizePopoverContent` would clamp.
    private func layoutHeight(
        fixture: PopoverRenderFixture,
        page: KajiModuleID,
        maxContentHeight: CGFloat
    ) throws -> CGFloat {
        var reported: CGSize = .zero
        let view = KajiPopoverView(
            store: fixture.store,
            prefs: fixture.prefs,
            workSession: fixture.workSession,
            systemMonitor: fixture.systemMonitor,
            dailyGoals: fixture.dailyGoals,
            fixedPlanStore: fixture.fixedPlanStore,
            aiNewsStore: fixture.aiNewsStore,
            mailBriefStore: fixture.mailBriefStore,
            navigation: fixture.navigation,
            controls: KajiPopoverControls(
                onOpenSettings: {}, onQuit: {},
                onShowDetail: { _, _ in }, onDismissDetail: {}
            ),
            maxContentHeight: maxContentHeight,
            onContentSizeChange: { reported = $0 }
        )
        fixture.navigation.panel = page
        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: 1)
        host.layoutSubtreeIfNeeded()
        // Chrome is measured on the first pass and fed back into the scroll
        // budget on the next, so settle the layout before reading the height.
        for _ in 0..<3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let height = host.fittingSize.height
            host.frame = NSRect(x: 0, y: 0, width: Self.width, height: height)
            host.layoutSubtreeIfNeeded()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertGreaterThan(reported.height, 0, "\(page) never reported a content size")
        return max(host.fittingSize.height, reported.height)
    }
}
