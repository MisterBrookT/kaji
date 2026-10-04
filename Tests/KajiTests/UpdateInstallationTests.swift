import Foundation
import XCTest
@testable import Kaji

@MainActor
final class UpdateInstallationTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "Kaji.UpdateInstallationTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "#!/bin/bash\n".write(to: directory.appendingPathComponent("source-update.sh"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    private var release: UpdateChecker.Release {
        UpdateChecker.Release(version: "1.0.0", tag: "v1.0.0",
                              url: URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v1.0.0")!,
                              assetURL: nil, sourceRevision: String(repeating: "a", count: 40))
    }

    private func checker(runner: SourceUpdateInstallerTests.FakeRunner) -> UpdateChecker {
        let installer = SourceUpdateInstaller(scriptURL: directory.appendingPathComponent("source-update.sh"),
                                               destinationAppURL: URL(fileURLWithPath: "/Apps/Kaji.app"),
                                               logURL: directory.appendingPathComponent("install.log"),
                                               hostPID: 4242, runner: runner)
        return UpdateChecker(available: release, installer: installer, installationDefaults: defaults,
                             binaryUpdater: nil)
    }

    func testSourceOnlyReleaseBuildsApprovedTagAndCommitBeforeHandoff() async throws {
        let runner = SourceUpdateInstallerTests.FakeRunner()
        runner.output = "STAGED=/Apps/.kaji-update.X/Kaji.app\n"
        let checker = checker(runner: runner)
        try await checker.install(release)
        XCTAssertTrue(runner.runArgs[0].contains("v1.0.0"))
        XCTAssertTrue(runner.runArgs[0].contains(String(repeating: "a", count: 40)))
        XCTAssertFalse(runner.runArgs[0].contains("latest"))
        XCTAssertEqual(runner.detachedArgs.count, 1)
        XCTAssertNotNil(defaults.string(forKey: "pendingSourceUpdateLog"))
        XCTAssertNil(checker.installError)
        XCTAssertFalse(checker.isInstalling)
    }

    func testBuildFailureDoesNotLaunchReplacementAndShowsErrorLog() async {
        let runner = SourceUpdateInstallerTests.FakeRunner()
        runner.status = 1
        let checker = checker(runner: runner)
        do {
            try await checker.install(release)
            XCTFail("expected build failure")
        } catch {}
        XCTAssertTrue(runner.detachedArgs.isEmpty)
        XCTAssertNotNil(checker.installError)
        XCTAssertNotNil(checker.installLogURL)
        XCTAssertNil(defaults.string(forKey: "pendingSourceUpdateLog"))
        XCTAssertEqual(checker.available, release)
        XCTAssertFalse(checker.isInstalling)
    }

    func testRollbackResultSurfacesFailureAfterRelaunch() throws {
        let log = directory.appendingPathComponent("install.log")
        try "failure\n".write(to: log.appendingPathExtension("result"), atomically: true, encoding: .utf8)
        defaults.set(log.path, forKey: "pendingSourceUpdateLog")
        let checker = checker(runner: SourceUpdateInstallerTests.FakeRunner())
        XCTAssertNotNil(checker.installError)
        XCTAssertEqual(checker.installLogURL, log)
        XCTAssertNil(defaults.string(forKey: "pendingSourceUpdateLog"))
    }

    func testLaunchingResultIsNotMistakenForFailureOrClearedPrematurely() throws {
        let log = directory.appendingPathComponent("install.log")
        try "launching\n".write(to: log.appendingPathExtension("result"), atomically: true, encoding: .utf8)
        defaults.set(log.path, forKey: "pendingSourceUpdateLog")
        let checker = checker(runner: SourceUpdateInstallerTests.FakeRunner())
        XCTAssertNil(checker.installError)
        XCTAssertEqual(defaults.string(forKey: "pendingSourceUpdateLog"), log.path)
    }

    func testSuccessResultDoesNotReportFailureAfterRelaunch() throws {
        let log = directory.appendingPathComponent("install.log")
        try "success\n".write(to: log.appendingPathExtension("result"), atomically: true, encoding: .utf8)
        defaults.set(log.path, forKey: "pendingSourceUpdateLog")
        let checker = checker(runner: SourceUpdateInstallerTests.FakeRunner())
        XCTAssertNil(checker.installError)
        XCTAssertNil(defaults.string(forKey: "pendingSourceUpdateLog"))
    }
}
