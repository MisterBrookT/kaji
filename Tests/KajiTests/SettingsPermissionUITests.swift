import AppKit
import SwiftUI
import XCTest
@testable import KajiCore
@testable import Kaji

@MainActor
final class SettingsPermissionUITests: XCTestCase {
    func testPreventSleepClickPresentsRepairDialogWhenRegisteredHelperCannotStart() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let suiteName = "dev.blackblue.Kaji.UITest.SleepPermission.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(AppLanguage.zh.rawValue, forKey: "language")
        let environment = SleepController.Environment(
            status: { .installed },
            install: {},
            request: { _ in false },
            readState: { false }
        )
        let controller = SleepController(previewEnabled: false, environment: environment)
        let window = NSWindow(
            contentRect: NSRect(x: -2_000, y: -2_000, width: 760, height: 590),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kaji Sleep Permission UI Test"
        window.contentView = NSHostingView(rootView: SettingsView(
            prefs: Prefs(defaults: defaults),
            sleepController: controller,
            fixedPlanStore: FixedPlanStore(defaults: defaults)
        ))
        window.contentView?.layoutSubtreeIfNeeded()
        defer {
            window.orderOut(nil)
            defaults.removePersistentDomain(forName: suiteName)
        }

        try await Task.sleep(for: .milliseconds(150))
        // SwiftPM has no XCUITest application target. Match KajiUIHarness:
        // invoke the same controller action wired to the visible segment, then
        // verify the real SettingsView presents and renders its AppKit sheet.
        controller.toggle()

        let deadline = Date().addingTimeInterval(2)
        while controller.approvalFlow.guidance != .repair, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(controller.approvalFlow.guidance, .repair)
        let sheet = try XCTUnwrap(
            window.attachedSheet,
            "Prevent Sleep failure must present a guided dialog"
        )
        let contentView = try XCTUnwrap(sheet.contentView)
        XCTAssertFalse(contentView.subviews.isEmpty, "Repair dialog must render visible AppKit content")
        sheet.orderOut(nil)
    }
}

