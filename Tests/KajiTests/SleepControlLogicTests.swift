import XCTest
@testable import KajiCore
@testable import Kaji

final class SleepControlLogicTests: XCTestCase {
    func testParsesEnabledState() {
        XCTAssertTrue(SleepControlLogic.parseSleepDisabled("""
        System-wide power settings:
         SleepDisabled          1
        """))
    }

    func testMissingOrDisabledStateIsFalse() {
        XCTAssertFalse(SleepControlLogic.parseSleepDisabled(" SleepDisabled 0"))
        XCTAssertFalse(SleepControlLogic.parseSleepDisabled("sleep 1"))
    }

    func testSuccessfulMatchingRequestCommitsObservedState() {
        XCTAssertEqual(
            try SleepControlLogic.resolvedState(
                requested: true,
                commandSucceeded: true,
                observed: true
            ).get(),
            true
        )
    }

    func testFailedRequestDoesNotCommitRequestedState() {
        XCTAssertThrowsError(
            try SleepControlLogic.resolvedState(
                requested: true,
                commandSucceeded: false,
                observed: false
            ).get()
        ) { error in
            XCTAssertEqual(error as? SleepControlError, .commandFailed)
        }
    }

    func testObservedMismatchIsReported() {
        XCTAssertThrowsError(
            try SleepControlLogic.resolvedState(
                requested: true,
                commandSucceeded: true,
                observed: false
            ).get()
        ) { error in
            XCTAssertEqual(error as? SleepControlError, .stateMismatch(observed: false))
        }
    }
    func testSleepRequestGateCompletesOnlyOnce() {
        let gate = SleepRequestGate()
        XCTAssertTrue(gate.claim())
        XCTAssertFalse(gate.claim())
        XCTAssertFalse(gate.claim())
    }

    func testUnavailableHelperFailsWithoutCrashing() async {
        let succeeded = await SleepController.requestSleepDisabled(
            true,
            machServiceName: "dev.kaji.tests.missing-sleep-helper",
            timeout: 0.1
        )

        XCTAssertFalse(succeeded)
    }

    func testRepairGuidanceRetainsPendingTargetUntilCancelled() {
        var flow = SleepApprovalFlow()

        flow.requireRepair(for: true)
        XCTAssertTrue(flow.isGuidancePresented)
        XCTAssertEqual(flow.pendingTarget, true)

        flow.dismissGuidance()
        XCTAssertFalse(flow.isGuidancePresented)
        XCTAssertEqual(flow.pendingTarget, true)

        flow.cancel()
        XCTAssertNil(flow.pendingTarget)
    }

    @MainActor
    func testFirstInstallPromptsOnceAndSubsequentTogglesReuseHelper() async {
        let state = SleepEnvironmentState()
        state.requestSucceeds = true
        var helperStatus = SleepHelperInstallStatus.notInstalled
        var installCount = 0
        let environment = SleepController.Environment(
            status: { helperStatus },
            install: {
                installCount += 1
                helperStatus = .installed
            },
            request: { target in state.request(target) },
            readState: { state.observed }
        )
        let controller = SleepController(previewEnabled: false, environment: environment)

        controller.setEnabled(true)
        while controller.isBusy { await Task.yield() }
        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(installCount, 1)

        controller.setEnabled(false)
        while controller.isBusy { await Task.yield() }
        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(state.requestCount, 2)
    }

    @MainActor
    func testFreshInstallRetriesInitialHelperConnection() async {
        let state = SleepEnvironmentState()
        state.succeedOnRequest = 3
        var helperStatus = SleepHelperInstallStatus.notInstalled
        let environment = SleepController.Environment(
            status: { helperStatus },
            install: { helperStatus = .installed },
            request: { target in state.request(target) },
            readState: { state.observed }
        )
        let controller = SleepController(previewEnabled: false, environment: environment)

        controller.setEnabled(true)
        while controller.isBusy { await Task.yield() }

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(state.requestCount, 3)
        XCTAssertFalse(controller.approvalFlow.isGuidancePresented)
    }

    @MainActor
    func testUnavailableInstalledHelperRequestsRepair() async {
        let environment = SleepController.Environment(
            status: { .installed },
            install: {},
            request: { _ in false },
            readState: { false }
        )
        let controller = SleepController(previewEnabled: false, environment: environment)

        controller.setEnabled(true)
        while controller.isBusy { await Task.yield() }

        XCTAssertEqual(controller.approvalFlow.guidance, .repair)
        XCTAssertEqual(controller.approvalFlow.pendingTarget, true)
        XCTAssertNil(controller.lastError)
    }

    @MainActor
    func testRepairInstallsOnceAndSubsequentToggleReusesHelper() async {
        let state = SleepEnvironmentState()
        var installCount = 0
        let environment = SleepController.Environment(
            status: { .installed },
            install: { installCount += 1 },
            request: { target in state.request(target) },
            readState: { state.observed }
        )
        let controller = SleepController(previewEnabled: false, environment: environment)

        controller.setEnabled(true)
        while controller.isBusy { await Task.yield() }
        XCTAssertEqual(controller.approvalFlow.guidance, .repair)

        state.requestSucceeds = true
        controller.performGuidanceAction()
        while controller.isBusy || !controller.isEnabled { await Task.yield() }

        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(state.requestCount, 2)

        controller.setEnabled(false)
        while controller.isBusy { await Task.yield() }

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(installCount, 1)
        XCTAssertEqual(state.requestCount, 3)
    }

}

private final class SleepEnvironmentState: @unchecked Sendable {
    private let lock = NSLock()
    private var _requestSucceeds = false
    private var _observed = false
    private var _requestCount = 0
    private var _succeedOnRequest: Int?

    var requestSucceeds: Bool {
        get { withLock { _requestSucceeds } }
        set { withLock { _requestSucceeds = newValue } }
    }

    var succeedOnRequest: Int? {
        get { withLock { _succeedOnRequest } }
        set { withLock { _succeedOnRequest = newValue } }
    }

    var observed: Bool { withLock { _observed } }
    var requestCount: Int { withLock { _requestCount } }

    func request(_ target: Bool) -> Bool {
        withLock {
            _requestCount += 1
            let succeeds = _succeedOnRequest.map { _requestCount >= $0 } ?? _requestSucceeds
            if succeeds { _observed = target }
            return succeeds
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
