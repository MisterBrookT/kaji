import XCTest
@testable import Kaji

@MainActor
final class SleepHelperStatusTests: XCTestCase {
    func testOutdatedHelperIsNotReportedAsRevokedAuthorization() {
        XCTAssertEqual(SleepController.authorizationStatus(for: .needsRepair), .needsUpdate)
        XCTAssertEqual(SleepController.authorizationStatus(for: .installed), .authorized)
        XCTAssertEqual(SleepController.authorizationStatus(for: .notInstalled), .notAuthorized)
        XCTAssertEqual(SleepController.authorizationStatus(for: .unavailable), .needsReauthorization)
    }
}
