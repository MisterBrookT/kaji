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

    func testEnabledHelperIsReusedWithoutAnotherAuthorization() {
        XCTAssertEqual(SleepController.registrationAction(for: .enabled), .reuse)
        XCTAssertEqual(SleepController.registrationAction(for: .notRegistered), .register)
        XCTAssertEqual(SleepController.registrationAction(for: .requiresApproval), .requestApproval)
    }

    func testApprovalGuidanceRetainsAndResumesRequestedState() {
        var flow = SleepApprovalFlow()

        flow.requireApproval(for: true)
        XCTAssertTrue(flow.isGuidancePresented)
        XCTAssertEqual(flow.pendingTarget, true)

        flow.dismissGuidance()
        XCTAssertFalse(flow.isGuidancePresented)
        XCTAssertNil(flow.consumePendingTarget(ifAuthorized: false))
        XCTAssertEqual(flow.consumePendingTarget(ifAuthorized: true), true)
        XCTAssertNil(flow.pendingTarget)
    }

    func testCancellingApprovalGuidanceDropsPendingRequest() {
        var flow = SleepApprovalFlow()
        flow.requireApproval(for: true)

        flow.cancel()

        XCTAssertFalse(flow.isGuidancePresented)
        XCTAssertNil(flow.pendingTarget)
    }

    @MainActor
    func testUnavailableRegisteredHelperRequestsRepair() async {
        let environment = SleepController.Environment(
            status: { .enabled },
            register: {},
            unregister: {},
            request: { _ in false },
            readState: { false },
            openSettings: {}
        )
        let controller = SleepController(previewEnabled: false, environment: environment)

        controller.setEnabled(true)
        while controller.isBusy {
            await Task.yield()
        }

        XCTAssertEqual(controller.approvalFlow.guidance, .repair)
        XCTAssertEqual(controller.approvalFlow.pendingTarget, true)
        XCTAssertNil(controller.lastError)
    }

    @MainActor
    func testRepairReregistersOnceAndSubsequentToggleReusesHelper() async {
        let state = SleepEnvironmentState()
        var registered = true
        var registerCount = 0
        var unregisterCount = 0
        let environment = SleepController.Environment(
            status: { registered ? .enabled : .notRegistered },
            register: {
                registerCount += 1
                registered = true
            },
            unregister: {
                unregisterCount += 1
                registered = false
            },
            request: { target in state.request(target) },
            readState: { state.observed },
            openSettings: {}
        )
        let controller = SleepController(previewEnabled: false, environment: environment)

        controller.setEnabled(true)
        while controller.isBusy { await Task.yield() }
        XCTAssertEqual(controller.approvalFlow.guidance, .repair)

        state.requestSucceeds = true
        controller.performGuidanceAction()
        while controller.isBusy || !controller.isEnabled { await Task.yield() }

        XCTAssertEqual(unregisterCount, 1)
        XCTAssertEqual(registerCount, 1)
        XCTAssertEqual(state.requestCount, 2)

        controller.setEnabled(false)
        while controller.isBusy { await Task.yield() }

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(unregisterCount, 1)
        XCTAssertEqual(registerCount, 1)
        XCTAssertEqual(state.requestCount, 3)
    }


}

private final class SleepEnvironmentState: @unchecked Sendable {
    private let lock = NSLock()
    private var _requestSucceeds = false
    private var _observed = false
    private var _requestCount = 0

    var requestSucceeds: Bool {
        get { withLock { _requestSucceeds } }
        set { withLock { _requestSucceeds = newValue } }
    }

    var observed: Bool { withLock { _observed } }
    var requestCount: Int { withLock { _requestCount } }

    func request(_ target: Bool) -> Bool {
        withLock {
            _requestCount += 1
            if _requestSucceeds { _observed = target }
            return _requestSucceeds
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
