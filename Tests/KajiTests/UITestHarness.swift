import XCTest
import AppKit
import ApplicationServices
import SwiftUI
@testable import Kaji
@testable import KajiCore

private func removeResidualTestDefaultsFiles() {
    guard let preferences = FileManager.default.urls(
        for: .libraryDirectory, in: .userDomainMask
    ).first?.appendingPathComponent("Preferences", isDirectory: true),
          let files = try? FileManager.default.contentsOfDirectory(
              at: preferences, includingPropertiesForKeys: nil
          ) else {
        return
    }
    for file in files {
        let name = file.lastPathComponent
        if name.hasPrefix("dev.blackblue.Kaji.PopoverRender.")
            || name.hasPrefix("dev.blackblue.Kaji.UITest.") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // cfprefsd can recreate an empty suite plist while the xctest process is
    // exiting. Remove that filesystem shell after the process has detached.
    let cleanup = Process()
    cleanup.executableURL = URL(fileURLWithPath: "/bin/sh")
    cleanup.arguments = [
        "-c",
        "sleep 0.2; rm -f \"$HOME\"/Library/Preferences/dev.blackblue.Kaji.PopoverRender.*.plist \"$HOME\"/Library/Preferences/dev.blackblue.Kaji.UITest.*.plist",
    ]
    try? cleanup.run()
}

private let registerTestDefaultsCleanup: Void = {
    atexit(removeResidualTestDefaultsFiles)
}()

private func removeDefaultsSuite(_ defaults: UserDefaults, named suiteName: String) {
    _ = registerTestDefaultsCleanup
    defaults.removePersistentDomain(forName: suiteName)
    defaults.synchronize()
    guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
        return
    }
    try? FileManager.default.removeItem(
        at: library.appendingPathComponent("Preferences/\(suiteName).plist")
    )
}

/// In-process AppKit/SwiftUI driver for `swift test`. There is no XCUITest
/// target in this package (SwiftPM can't host one), so this harness boots
/// the real `AppDelegate` object graph inside the test process: a real
/// `NSStatusItem`, a real `NSPopover`, and the real `StatusItemView` hosted
/// on the status item's button.
///
/// `clickStatusItem()` does not synthesize an OS-level click. A synthetic
/// `NSEvent`/`CGEvent` reliably fails to reach a SwiftUI `Button`'s gesture
/// recognizer from inside a bare `xctest` process outside a real, launched
/// `.app` bundle (confirmed by direct investigation — AppKit's own
/// hit-testing resolves correctly, but the gesture never fires). Real
/// OS-level click coverage against the actual signed `.app` lives in
/// `scripts/ui-smoke.sh`, not here. Instead, this harness reaches into the
/// live `StatusItemView` AppKit hosts and invokes its `onQuotaClick`
/// closure directly — the exact closure `setupStatusItem()` wires to
/// `showPopover(.quota)` (`AppDelegate.swift`). This still exercises the
/// real `showPopover` implementation end-to-end; it only skips the
/// SwiftUI-gesture-recognition step that `ui-smoke.sh` covers separately.
/// If `setupStatusItem()` ever stops wiring that closure, this reaches a
/// stale default (`{}`) and every assertion after it fails for real.
///
/// The harness gives the real `AppDelegate` a unique `UserDefaults` suite and
/// temporary cache directory. Production still uses `.standard`; tests never
/// read or write the app's real defaults domain.

@MainActor
final class KajiUIHarness {
    let appDelegate: AppDelegate

    private let suiteName: String
    private let defaults: UserDefaults
    private let cacheDirectory: URL

    init() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        suiteName = "dev.blackblue.Kaji.UITest.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("failed to create isolated defaults suite")
        }
        defaults = isolatedDefaults
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaji-ui-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        appDelegate = AppDelegate(
            defaults: defaults,
            cacheDirectory: cacheDirectory,
            store: QuotaStore(previewProviders: [
                ProviderView(
                    id: "claude", mark: "C", displayName: "Fixture Claude",
                    fiveHourPercent: 24, weekPercent: 42,
                    resetDate: nil, weekResetDate: nil
                ),
            ])
        )
        _ = try? appDelegate.dailyGoals.addGoal(
            title: "Fixture goal",
            tag: GoalTag.personal.rawValue,
            note: "Fixture note",
            in: .today
        )
        _ = appDelegate.fixedPlanStore.add(
            title: "Fixture scheduled goal",
            tag: GoalTag.personal.rawValue,
            note: "Fixture schedule note",
            weekdays: Set(1...7)
        )
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        // `NSPopover.isShown` only flips to `false` once the close animation
        // completes (`popover.animates = true` in `AppDelegate.setupPopover()`),
        // and that completion callback is driven by real screen composition
        // that a bare `xctest` process off-screen never receives — leaving
        // `isShown` stuck `true` indefinitely after a real `close()`/
        // `performClose()` call. Disabling animation makes the state change
        // synchronous, which is what these tests assert on; it does not
        // change which code path handles the close.
        appDelegate.popover.animates = false
    }

    /// Must be called at the end of every test that constructs a harness:
    /// closes the popover, stops timers/network stores, removes the real
    /// `NSStatusItem`, and deletes the isolated defaults/cache world.
    func tearDown() {
        if appDelegate.popover?.isShown == true {
            appDelegate.popover.performClose(nil)
        }
        appDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
        if let statusItem = appDelegate.statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        removeDefaultsSuite(defaults, named: suiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    /// Invokes the real click handler the status item's hosted
    /// `StatusItemView` (`StatusItemView.swift:40`) wires its quota
    /// `Button` to — the same closure `setupStatusItem()` passes as
    /// `onQuotaClick` (`AppDelegate.swift`), which calls
    /// `showPopover(.quota)`. This exercises the real popover-construction
    /// path end to end; it does not call `showPopover` from the test and
    /// does not add any test-only hook to `AppDelegate` — it reads the
    /// closure straight out of the live, currently-hosted SwiftUI view.
    /// (Real OS-level click delivery is covered separately by
    /// `scripts/ui-smoke.sh` against the launched `.app` — see the class
    /// doc comment.)
    func clickStatusItem() {
        guard let hostingView = appDelegate.hostingView else {
            XCTFail("status item hosting view is nil — setupStatusItem() did not run")
            return
        }
        // The private `NSStatusBarWindow` only resolves a real on-screen
        // frame after a run-loop turn; `showPopover` positions relative to
        // it, so give AppKit that turn before invoking the handler.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hostingView.rootView.onQuotaClick()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func clickDetailAffordance(prefix: String) {
        guard let root = appDelegate.popover.contentViewController?.view,
              let button = findButton(prefix: prefix, in: root) else {
            XCTFail("detail affordance starting with \(prefix) not found in popover")
            return
        }
        button.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func findButton(prefix: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.identifier?.rawValue.hasPrefix(prefix) == true {
            return button
        }
        for subview in view.subviews {
            if let button = findButton(prefix: prefix, in: subview) {
                return button
            }
        }
        return nil
    }

}

/// Renders any SwiftUI `View` to a bitmap via a real `NSHostingView` — the
/// same mechanism `AppDelegate.makePopoverContentController` uses for the
/// live popover.
@MainActor
func renderImage<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep? {
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(origin: .zero, size: size)
    // SwiftUI only fully realizes a hosted view's content (text layout,
    // @ObservedObject-driven page switching, environment values) once it is
    // part of a real window — an unparented `NSHostingView` can render a
    // stale/placeholder frame. Host it in an offscreen, never-ordered-front
    // window (never shown on screen, so this is safe to run in any
    // `swift test` session).
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hosting
    window.isReleasedWhenClosed = false
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        window.close()
        return nil
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    window.close()
    return rep
}

/// Writes a PNG artifact to `.build/ui-snapshots/<name>.png` for human/agent
/// inspection. Returns the path written, or nil on failure.
@discardableResult
func writePNG(_ rep: NSBitmapImageRep, name: String) -> URL? {
    guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
    let dir = URL(fileURLWithPath: ".build/ui-snapshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(name).png")
    do {
        try data.write(to: url)
        return url
    } catch {
        XCTFail("failed to write PNG \(url.path): \(error)")
        return nil
    }
}

/// Independent, fresh object graph for rendering `KajiPopoverView` pages.
/// Deliberately decoupled from `AppDelegate`'s (still-private) stores —
/// `AppDelegate`'s visibility was only widened for the status-item/popover
/// surface the click tests need, not for every store it owns. Rendering a
/// page only needs *some* real, correctly-typed store graph, not the live
/// app's specific instances.
@MainActor
final class PopoverRenderFixture {
    let store: QuotaStore
    let prefs: Prefs
    let workSession: WorkSessionController
    let systemMonitor = SystemMonitor()
    let dailyGoals: DailyGoalStore
    let fixedPlanStore: FixedPlanStore
    let aiNewsStore: AIHotNewsStore
    let mailBriefStore: MailBriefStore
    let navigation = PopoverNavigation()

    private let suiteName: String
    private let defaults: UserDefaults
    private let cacheDirectory: URL

    init() {
        suiteName = "dev.blackblue.Kaji.PopoverRender.\(UUID().uuidString)"
        guard let isolatedDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("failed to create isolated defaults suite")
        }
        defaults = isolatedDefaults
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaji-popover-render-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        prefs = Prefs(defaults: defaults)
        dailyGoals = DailyGoalStore(defaults: defaults)
        defaults.set(
            try? JSONEncoder().encode([ScheduledGoal]()),
            forKey: FixedPlanStore.schedulesPersistenceKey
        )
        fixedPlanStore = FixedPlanStore(defaults: defaults)
        store = QuotaStore(
            previewProviders: [
                ProviderView(
                    id: "claude", mark: "C", displayName: "Fixture Claude",
                    fiveHourPercent: 24, weekPercent: 42,
                    resetDate: Date(timeIntervalSince1970: 1_900_000_000),
                    weekResetDate: Date(timeIntervalSince1970: 1_900_086_400)
                ),
            ],
            updated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        aiNewsStore = AIHotNewsStore(
            previewTopics: [
                AIHotTopic(
                    rank: 1, id: "fixture-ai-topic", title: "Fixture AI headline",
                    sourceName: "Fixture Source", sourceCount: 1, signalCount: 1,
                    sourceNames: ["Fixture Source"],
                    latestAt: Date(timeIntervalSince1970: 1_700_000_000),
                    aiHotURL: URL(string: "https://example.invalid/fixture-ai")!,
                    originalURL: URL(string: "https://example.invalid/fixture-source")!,
                    storyPublicID: nil
                ),
            ],
            cacheURL: cacheDirectory.appendingPathComponent("ai-news-cache-v1.json")
        )
        mailBriefStore = MailBriefStore(
            previewGeneration: MailBriefGeneration(
                generationID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                briefDay: "2026-01-01",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                entries: [
                    MailBriefEntry(
                        threadID: "fixture-mail", subject: "Fixture mail subject",
                        sender: "Fixture Sender", gmailURL: nil, level: 2, bucket: .act,
                        summaryZH: "Fixture mail summary", reasonZH: "Fixture mail reason",
                        suggestedAction: .reply, deadline: nil, confidence: .high,
                        goalTitleZH: nil
                    ),
                ],
                snapshotInboxThreadCount: 1
            ),
            cacheDirectory: cacheDirectory
        )
        workSession = WorkSessionController(prefs: prefs)
        prefs.enabledModules = Set(KajiModuleID.allCases)
        _ = try? dailyGoals.addGoal(
            title: "Fixture goal", tag: GoalTag.personal.rawValue, note: "Fixture note",
            in: .today
        )
        _ = fixedPlanStore.add(
            title: "Fixture scheduled goal", tag: GoalTag.personal.rawValue,
            note: "Fixture schedule note", weekdays: Set(1...7)
        )
    }

    func tearDown() {
        aiNewsStore.stop()
        mailBriefStore.stop()
        removeDefaultsSuite(defaults, named: suiteName)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    func view(
        page: KajiModuleID,
        maxContentHeight: CGFloat = 640,
        onShowDetail: @escaping (NSView, AnyView) -> Void = { _, _ in }
    ) -> KajiPopoverView {
        navigation.panel = page
        if page == .goals {
            navigation.goalHorizon = .today
        }
        return KajiPopoverView(
            store: store,
            prefs: prefs,
            workSession: workSession,
            systemMonitor: systemMonitor,
            dailyGoals: dailyGoals,
            fixedPlanStore: fixedPlanStore,
            aiNewsStore: aiNewsStore,
            mailBriefStore: mailBriefStore,
            navigation: navigation,
            controls: KajiPopoverControls(
                onOpenSettings: {},
                onQuit: {},
                onShowDetail: onShowDetail
            ),
            maxContentHeight: maxContentHeight,
            onContentSizeChange: { _ in }
        )
    }
}
