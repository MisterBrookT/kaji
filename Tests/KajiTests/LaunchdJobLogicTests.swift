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

        XCTAssertEqual(snapshot.installedSummary.runningCount, 1)
        XCTAssertEqual(snapshot.installedSummary.failedCount, 1)
        XCTAssertEqual(snapshot.installedSummary.unloadedCount, 1)
        XCTAssertEqual(snapshot.installedSummary.idleCount, 0)
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
    func testInstalledSummaryIgnoresLargeSessionDomainAndKeepsNonzeroExitFailed() {
        let otherJobs = (0..<128).map { index in
            index.isMultiple(of: 2)
                ? "\(index + 1000)\t0\tcom.apple.session.\(index)"
                : "-\t\(index + 1)\tcom.apple.session.\(index)"
        }
        let output = ([
            "PID\tStatus\tLabel",
            "42\t0\tdev.brook.running",
            "-\t78\tdev.brook.failed",
            "-\t0\tdev.brook.idle",
        ] + otherJobs).joined(separator: "\n")

        let snapshot = LaunchdJobLogic.snapshot(
            listOutput: output,
            installedLabels: ["dev.brook.running", "dev.brook.failed", "dev.brook.idle", "dev.brook.unloaded"]
        )

        XCTAssertEqual(snapshot.jobs.count, 132)
        XCTAssertEqual(snapshot.installedJobs.map(\.label), [
            "dev.brook.failed",
            "dev.brook.running",
            "dev.brook.idle",
            "dev.brook.unloaded",
        ])
        XCTAssertEqual(
            snapshot.installedSummary,
            LaunchdInstalledJobSummary(runningCount: 1, failedCount: 1, unloadedCount: 1, idleCount: 1)
        )
        XCTAssertEqual(snapshot.installedJobs.first(where: { $0.label == "dev.brook.failed" })?.state, .failed)
        XCTAssertEqual(snapshot.installedJobs.first(where: { $0.label == "dev.brook.failed" })?.lastExitCode, 78)
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
    func testRefreshRunsOnlyWhileEnabledAndPopoverVisible() {
        let loaded = LaunchdJobSnapshot(jobs: [
            LaunchdJob(label: "dev.kaji.test", pid: 42, lastExitCode: 0, isInstalledUserAgent: true, state: .running),
        ])
        let store = LaunchdJobStore(initialSnapshot: loaded, loadSnapshot: { loaded })

        store.refresh()
        XCTAssertEqual(store.refreshInvocationCount, 0)
        XCTAssertFalse(store.isActive)

        store.setEnabled(true)
        XCTAssertEqual(store.refreshInvocationCount, 0)
        XCTAssertFalse(store.isActive)

        store.setPopoverVisible(true)
        XCTAssertEqual(store.refreshInvocationCount, 1)
        XCTAssertTrue(store.isActive)

        store.setPopoverVisible(false)
        XCTAssertFalse(store.isActive)
        store.refresh()
        XCTAssertEqual(store.refreshInvocationCount, 1, "closing the popover must stop further refreshes")

        store.setEnabled(false)
        XCTAssertTrue(store.snapshot.jobs.isEmpty)
        store.setPopoverVisible(true)
        store.refresh()
        XCTAssertEqual(store.refreshInvocationCount, 1)
    }

    func testStatusRefreshCanRunOnceWhilePopoverIsHidden() {
        let loaded = LaunchdJobSnapshot(jobs: [])
        let store = LaunchdJobStore(initialSnapshot: loaded, loadSnapshot: { loaded })

        store.refreshStatus()
        XCTAssertEqual(store.refreshInvocationCount, 0)
        store.setEnabled(true)
        store.refreshStatus()
        XCTAssertEqual(store.refreshInvocationCount, 1)
        XCTAssertFalse(store.isActive)
    }
}
