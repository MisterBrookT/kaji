import AppKit
import Foundation
import XCTest
@testable import Kaji

@MainActor
final class BinaryUpdateRoutingTests: XCTestCase {
    final class FakeBinaryUpdater: BinaryUpdatePresenting {
        var isAvailable: Bool
        var checks = 0
        init(isAvailable: Bool) { self.isAvailable = isAvailable }
        func checkForUpdates() { checks += 1 }
    }

    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "Kaji.BinaryUpdateRoutingTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: directory.appendingPathComponent("source-update.sh"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private let release = UpdateChecker.Release(
        version: "1.0.0", tag: "v1.0.0",
        url: URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v1.0.0")!,
        assetURL: nil, sourceRevision: String(repeating: "a", count: 40))

    private func checker(binary: BinaryUpdatePresenting?, runner: SourceUpdateInstallerTests.FakeRunner) -> UpdateChecker {
        let installer = SourceUpdateInstaller(scriptURL: directory.appendingPathComponent("source-update.sh"),
                                              destinationAppURL: URL(fileURLWithPath: "/Apps/Kaji.app"),
                                              logURL: directory.appendingPathComponent("install.log"),
                                              hostPID: 4242, runner: runner)
        return UpdateChecker(available: release, installer: installer, installationDefaults: defaults,
                             binaryUpdater: binary)
    }

    func testDefaultSparkleUpdaterIsInactiveUnderTests() {
        XCTAssertFalse(SparkleBinaryUpdater().isAvailable)
        XCTAssertFalse(UpdateChecker().usesBinaryUpdater)
    }

    func testConfiguredBinaryUpdaterHandlesExplicitCheck() {
        let fake = FakeBinaryUpdater(isAvailable: true)
        let runner = SourceUpdateInstallerTests.FakeRunner()
        let checker = checker(binary: fake, runner: runner)
        XCTAssertTrue(checker.usesBinaryUpdater)
        XCTAssertTrue(checker.presentBinaryUpdateCheck())
        XCTAssertEqual(fake.checks, 1)
        XCTAssertTrue(runner.runArgs.isEmpty)
        XCTAssertTrue(runner.detachedArgs.isEmpty)
        XCTAssertNil(defaults.string(forKey: "pendingSourceUpdateLog"))
    }

    func testInactiveBinaryUpdaterFallsBackToSourceInstall() async throws {
        let fake = FakeBinaryUpdater(isAvailable: false)
        let runner = SourceUpdateInstallerTests.FakeRunner()
        runner.output = "STAGED=/Apps/.kaji-update.X/Kaji.app\n"
        let checker = checker(binary: fake, runner: runner)
        XCTAssertFalse(checker.usesBinaryUpdater)
        XCTAssertFalse(checker.presentBinaryUpdateCheck())
        XCTAssertEqual(fake.checks, 0)
        try await checker.install(release)
        XCTAssertEqual(runner.detachedArgs.count, 1)
    }

    func testAppDelegateReviewRoutesToNativeWithoutSourceSheet() {
        let fake = FakeBinaryUpdater(isAvailable: true)
        let runner = SourceUpdateInstallerTests.FakeRunner()
        let checker = checker(binary: fake, runner: runner)
        let app = AppDelegate(defaults: defaults, updateChecker: checker)
        _ = NSApplication.shared
        app.reviewUpdate(release)
        XCTAssertEqual(fake.checks, 1)
        XCTAssertNil(checker.reviewingRelease)
        XCTAssertTrue(runner.runArgs.isEmpty)
        XCTAssertTrue(runner.detachedArgs.isEmpty)
    }
}
