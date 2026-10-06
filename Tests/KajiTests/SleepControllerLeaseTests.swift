import XCTest
@testable import Kaji

@MainActor
final class SleepControllerLeaseTests: XCTestCase {
    func testTurningOffRequestsRestoreWithoutInstallingOrCallingPmset() async {
        var observed = true
        var requests: [Bool] = []
        let controller = SleepController(environment: .init(
            status: { .installed },
            install: { XCTFail("Must not install") },
            request: { target in
                // Test closure never invokes XPC or system pmset.
                await MainActor.run {
                    requests.append(target)
                    observed = false
                }
                return true
            },
            readState: { observed }
        ))
        controller.setEnabled(false)
        for _ in 0..<50 where controller.isBusy {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(requests, [false])
        XCTAssertFalse(controller.isEnabled)
    }
}
