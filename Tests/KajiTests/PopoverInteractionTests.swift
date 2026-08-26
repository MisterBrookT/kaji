import XCTest
import AppKit
import KajiCore
@testable import Kaji

/// Drives the real `AppDelegate` object graph in-process (no XCUITest — see
/// `Tests/KajiTests/UITestHarness.swift`). `clickStatusItem()` invokes the
/// real `onQuotaClick` closure `setupStatusItem()` wires on the hosted
/// `StatusItemView` — the same closure a real click calls — so a regression
/// like an unwired closure, or a broken `showPopover` implementation (e.g.
/// the NSPanel + `hidesOnDeactivate` regression in 5d6928b, where the panel
/// hid itself instantly because clicking the status item never activates
/// an `LSUIElement` app), fails these tests for real.
///
/// Real OS-level click delivery (can a genuine mouse click actually reach
/// the SwiftUI `Button`'s gesture recognizer?) is out of scope here — that
/// reliably does not work from inside a bare `xctest` process outside a
/// real, launched `.app` bundle, and is covered separately by
/// `scripts/ui-smoke.sh` against the actual signed `.app`.
@MainActor
final class PopoverInteractionTests: XCTestCase {
    private var harness: KajiUIHarness!

    override func setUp() async throws {
        try await super.setUp()
        harness = KajiUIHarness()
    }

    override func tearDown() async throws {
        harness.tearDown()
        harness = nil
        try await super.tearDown()
    }

    func testStatusItemHasWiredClickSurface() throws {
        let hostingView = try XCTUnwrap(harness.appDelegate.hostingView, "setupStatusItem() must create the hosted click surface")
        let statusItem = try XCTUnwrap(harness.appDelegate.statusItem, "status item must exist after launch")
        let button = try XCTUnwrap(statusItem.button, "status item must have a button")
        XCTAssertTrue(button.subviews.contains(hostingView), "hosting view must be attached as a subview of the status item button — this is the actual click surface AppKit delivers events to")
        XCTAssertGreaterThan(statusItem.length, 0, "status item must have non-zero width to be clickable")
    }

    func testClickOpensPopover() throws {
        XCTAssertFalse(harness.appDelegate.popover.isShown)
        harness.clickStatusItem()
        XCTAssertTrue(harness.appDelegate.popover.isShown, "clicking the status item must open the popover")
    }

    func testClickTwiceClosesPopover() throws {
        harness.clickStatusItem()
        XCTAssertTrue(harness.appDelegate.popover.isShown)
        harness.clickStatusItem()
        XCTAssertFalse(harness.appDelegate.popover.isShown, "clicking the same slot again must close the popover")
    }

    func testPopoverHasNonZeroContentSize() throws {
        harness.clickStatusItem()
        XCTAssertTrue(harness.appDelegate.popover.isShown)
        let size = harness.appDelegate.popover.contentSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        let contentView = try XCTUnwrap(harness.appDelegate.popover.contentViewController?.view)
        XCTAssertFalse(contentView.subviews.isEmpty, "popover content view must not be an empty subtree")
    }

    func testEveryModulePageNavigatesWithoutCrashing() throws {
        harness.clickStatusItem()
        XCTAssertTrue(harness.appDelegate.popover.isShown)
        for page in KajiModuleID.allCases {
            harness.appDelegate.popoverNavigation.panel = page
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            XCTAssertEqual(harness.appDelegate.popoverNavigation.panel, page)
            XCTAssertTrue(harness.appDelegate.popover.isShown, "popover must stay shown while paging through \(page)")
            let contentView = try XCTUnwrap(harness.appDelegate.popover.contentViewController?.view)
            XCTAssertFalse(contentView.subviews.isEmpty, "\(page) must render a non-empty content subtree")
        }
    }

    /// The goal note is no longer an AppKit affordance: nesting a second
    /// `NSPopover` inside the status-item popover threw
    /// `NSInternalInconsistencyException` from
    /// `-[NSWindow _newFirstResponderAfterResigning]` when the note text view
    /// resigned first responder, hanging/killing the app. The note card must
    /// therefore render inside the popover's own window.
    func testGoalNoteHasNoNestedAppKitPopoverAffordance() throws {
        harness.clickStatusItem()
        harness.appDelegate.popoverNavigation.panel = .goals
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(harness.detailAffordances(prefix: "goal-detail-").isEmpty,
                      "goal notes must not be backed by an AppKit button that opens a child NSPopover")
        XCTAssertNil(harness.appDelegate.detailPopover,
                     "paging to goals must not create a child popover")
        XCTAssertTrue(harness.appDelegate.popover.isShown)
    }

    func testDetailAffordanceOpensChildWhileParentStaysShown() throws {
        harness.clickStatusItem()
        harness.appDelegate.popoverNavigation.panel = .goals
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        harness.clickDetailAffordance(prefix: "schedule-detail-")

        XCTAssertTrue(harness.appDelegate.popover.isShown, "opening a detail must not dismiss the main popover")
        XCTAssertTrue(try XCTUnwrap(harness.appDelegate.detailPopover).isShown)
    }

    func testClosingParentClosesChildPopover() throws {
        harness.clickStatusItem()
        harness.appDelegate.popoverNavigation.panel = .goals
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        harness.clickDetailAffordance(prefix: "schedule-detail-")
        let child = try XCTUnwrap(harness.appDelegate.detailPopover)
        child.animates = false

        harness.appDelegate.showPopover(.goalsToday)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(harness.appDelegate.popover.isShown)
        XCTAssertFalse(child.isShown, "closing the main popover must close its child")
        XCTAssertNil(harness.appDelegate.detailPopover)
    }

    func testDifferentDetailAffordanceReanchorsSingleChildPopover() throws {
        harness.clickStatusItem()
        harness.appDelegate.popoverNavigation.panel = .goals
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let affordances = harness.detailAffordances(prefix: "schedule-detail-")
        XCTAssertGreaterThan(affordances.count, 1,
                             "harness seeds two scheduled goals with notes; both must render a detail affordance")

        harness.click(affordances[0])
        let first = try XCTUnwrap(harness.appDelegate.detailPopover)
        first.animates = false

        harness.click(affordances[1])
        let second = try XCTUnwrap(harness.appDelegate.detailPopover)

        XCTAssertFalse(first === second)
        XCTAssertFalse(first.isShown, "re-anchoring must close the previous child")
        XCTAssertTrue(second.isShown)
        XCTAssertTrue(harness.appDelegate.popover.isShown)
    }
}
