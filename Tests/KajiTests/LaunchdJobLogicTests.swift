import XCTest
@testable import Kaji
@testable import KajiCore

final class LaunchdJobLogicTests: XCTestCase {
    func testParsesStatesAndAddsUnloadedInstalledAgent() {
        let output = """
        PID\tStatus\tLabel
        321\t0\tdev.kaji.running
        -\t1\tdev.kaji.failed
        -\t0\tdev.kaji.idle
        """

        let snapshot = LaunchdJobLogic.snapshot(
            listOutput: output,
            installedLabels: ["dev.kaji.running", "dev.kaji.failed", "dev.kaji.unloaded"]
        )

        XCTAssertEqual(snapshot.runningCount, 1)
        XCTAssertEqual(snapshot.failedCount, 1)
        XCTAssertEqual(snapshot.unloadedCount, 1)
        XCTAssertEqual(snapshot.jobs.first(where: { $0.label == "dev.kaji.running" })?.pid, 321)
        XCTAssertEqual(snapshot.jobs.first(where: { $0.label == "dev.kaji.failed" })?.state, .failed)
        XCTAssertEqual(snapshot.jobs.first(where: { $0.label == "dev.kaji.idle" })?.state, .idle)
        XCTAssertEqual(snapshot.jobs.first(where: { $0.label == "dev.kaji.unloaded" })?.state, .unloaded)
    }

    func testSortsInstalledAgentsBeforeOtherGUIJobsAndAttentionFirst() {
        let output = """
        PID\tStatus\tLabel
        11\t0\tcom.apple.running
        22\t0\tdev.kaji.running
        -\t7\tdev.kaji.failed
        -\t0\tdev.kaji.idle
        """

        let snapshot = LaunchdJobLogic.snapshot(
            listOutput: output,
            installedLabels: ["dev.kaji.running", "dev.kaji.failed", "dev.kaji.idle"]
        )

        XCTAssertEqual(snapshot.jobs.map(\.label), [
            "dev.kaji.failed",
            "dev.kaji.running",
            "dev.kaji.idle",
            "com.apple.running",
        ])
    }

    func testSkipsHeaderAndMalformedRows() {
        let snapshot = LaunchdJobLogic.snapshot(
            listOutput: "PID\tStatus\tLabel\nnot a launchctl row\n-\t-\tvalid.label\n",
            installedLabels: []
        )

        XCTAssertEqual(snapshot.jobs.map(\.label), ["valid.label"])
        XCTAssertEqual(snapshot.jobs[0].state, .idle)
        XCTAssertNil(snapshot.jobs[0].lastExitCode)
    }
}

@MainActor
final class LaunchdJobStoreLifecycleTests: XCTestCase {
    func testDisabledStoreDoesNotRefreshAndClearsModuleState() {
        let loaded = LaunchdJobSnapshot(jobs: [
            LaunchdJob(label: "dev.kaji.test", pid: 42, lastExitCode: 0, isInstalledUserAgent: true, state: .running),
        ])
        let store = LaunchdJobStore(loadSnapshot: { loaded })

        store.refresh()
        XCTAssertEqual(store.refreshInvocationCount, 0)
        XCTAssertFalse(store.isPolling)

        store.setEnabled(true)
        XCTAssertEqual(store.refreshInvocationCount, 1)
        XCTAssertTrue(store.isPolling)

        store.setEnabled(false)
        XCTAssertFalse(store.isPolling)
        XCTAssertTrue(store.snapshot.jobs.isEmpty)
        store.refresh()
        XCTAssertEqual(store.refreshInvocationCount, 1)
    }
}
