import XCTest
@testable import Kaji

final class SourceUpdateInstallerTests: XCTestCase {
    final class FakeRunner: SourceUpdateProcessRunning, @unchecked Sendable {
        var status: Int32 = 0
        var output = ""
        var runArgs: [[String]] = []
        var detachedArgs: [[String]] = []
        func run(_ executable: URL, arguments: [String], logURL: URL,
                 timeout: Duration) async throws -> (status: Int32, output: String) {
            runArgs.append(arguments)
            return (status, output)
        }
        func launchDetached(_ executable: URL, arguments: [String], logURL: URL) throws {
            detachedArgs.append(arguments)
        }
    }

    private var dir: URL!
    private var script: URL!
    private let rev = String(repeating: "a", count: 40)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceUpdateInstallerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        script = dir.appendingPathComponent("source-update.sh")
        try "#!/bin/bash\n".write(to: script, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func installer(_ runner: FakeRunner, script: URL? = nil) -> SourceUpdateInstaller {
        SourceUpdateInstaller(scriptURL: script ?? self.script,
                              destinationAppURL: URL(fileURLWithPath: "/Apps/Kaji.app"),
                              logURL: dir.appendingPathComponent("log"),
                              hostPID: 4242, runner: runner)
    }

    func testPreparePinsTagRevisionAndParsesStagedPath() async throws {
        let runner = FakeRunner()
        runner.output = "==> building\nSTAGED=/Apps/.kaji-update.X/Kaji.app\n"
        let prepared = try await installer(runner).prepare(tag: "v1.2.3", version: "1.2.3", revision: rev)
        XCTAssertEqual(prepared.stagedAppURL.path, "/Apps/.kaji-update.X/Kaji.app")
        XCTAssertEqual(runner.runArgs.first, [script.path, "prepare", "--tag", "v1.2.3", "--version", "1.2.3",
                                              "--dest-app", "/Apps/Kaji.app", "--revision", rev])
    }

    func testPrepareRejectsUnstableInputsWithoutRunning() async {
        let runner = FakeRunner()
        let cases: [(String, String, String?)] = [
            ("latest", "1.2.3", nil), ("v1.2.4", "1.2.3", nil), ("v1.2.3-beta", "1.2.3-beta", nil),
            ("v1.2.3", "1.2.3", "abc"), ("v1.2.3", "1.2.3", String(repeating: "A", count: 40)),
            ("v1.2.3\n", "1.2.3\n", nil), ("v1.2.3", "1.2.3", String(repeating: "a", count: 40) + "\n"),
        ]
        for (tag, version, revision) in cases {
            do {
                _ = try await installer(runner).prepare(tag: tag, version: version, revision: revision)
                XCTFail("accepted \(tag) \(version) \(revision ?? "-")")
            } catch {}
        }
        XCTAssertTrue(runner.runArgs.isEmpty)
    }

    func testPrepareFailureSurfacesStatus() async {
        let runner = FakeRunner()
        runner.status = 1
        do {
            _ = try await installer(runner).prepare(tag: "v1.2.3", version: "1.2.3", revision: nil)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? SourceUpdateInstaller.Failure, .prepareFailed(status: 1))
        }
    }

    func testPrepareWithoutStagedLineFails() async {
        let runner = FakeRunner()
        runner.output = "ok\n"
        do {
            _ = try await installer(runner).prepare(tag: "v1.2.3", version: "1.2.3", revision: nil)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? SourceUpdateInstaller.Failure, .noStagedBundle)
        }
    }

    func testMissingScriptFails() async {
        let runner = FakeRunner()
        do {
            _ = try await installer(runner, script: dir.appendingPathComponent("nope.sh"))
                .prepare(tag: "v1.2.3", version: "1.2.3", revision: nil)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? SourceUpdateInstaller.Failure, .scriptMissing)
        }
    }

    func testLaunchReplacementWaitsOnHostPID() throws {
        let runner = FakeRunner()
        let prepared = PreparedUpdate(tag: "v1.2.3", version: "1.2.3",
                                      stagedAppURL: URL(fileURLWithPath: "/Apps/.kaji-update.X/Kaji.app"),
                                      destinationAppURL: URL(fileURLWithPath: "/Apps/Kaji.app"))
        try installer(runner).launchReplacement(prepared)
        XCTAssertEqual(runner.detachedArgs.first, [script.path, "replace", "--staged", "/Apps/.kaji-update.X/Kaji.app",
                                                   "--version", "1.2.3", "--dest-app", "/Apps/Kaji.app",
                                                   "--host-pid", "4242", "--result-file", dir.appendingPathComponent("log.result").path])
    }

    func testSystemRunnerCapturesOutputAndTimesOut() async throws {
        let log = dir.appendingPathComponent("run.log")
        let runner = SystemSourceUpdateRunner()
        let ok = try await runner.run(URL(fileURLWithPath: "/bin/bash"), arguments: ["-c", "echo hi; exit 3"],
                                      logURL: log, timeout: .seconds(10))
        XCTAssertEqual(ok.status, 3)
        XCTAssertEqual(ok.output, "hi\n")
        do {
            _ = try await runner.run(URL(fileURLWithPath: "/bin/bash"), arguments: ["-c", "sleep 30"],
                                     logURL: log, timeout: .milliseconds(200))
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? SourceUpdateInstaller.Failure, .timedOut)
        }
    }

    func testSystemRunnerCancellationTerminates() async throws {
        let log = dir.appendingPathComponent("cancel.log")
        let task = Task {
            try await SystemSourceUpdateRunner().run(URL(fileURLWithPath: "/bin/bash"), arguments: ["-c", "sleep 30"],
                                                     logURL: log, timeout: .seconds(60))
        }
        try await Task.sleep(for: .milliseconds(200))
        let start = Date()
        task.cancel()
        _ = try? await task.value
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
