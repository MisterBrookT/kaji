import XCTest
import KajiCore

final class AIHotRefreshPolicyTests: XCTestCase {
    func testRefreshHoursNormalizeAndDuePolicy() {
        XCTAssertEqual(AIHotRefreshPolicy.normalize(hours: 7), 5)
        XCTAssertEqual(AIHotRefreshPolicy.allowedHours, [1, 3, 5, 12, 24])
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertFalse(AIHotRefreshPolicy.shouldRefresh(hasCache: true, lastSuccessfulRefresh: now.addingTimeInterval(-4 * 3600), hours: 5, now: now))
        XCTAssertTrue(AIHotRefreshPolicy.shouldRefresh(hasCache: true, lastSuccessfulRefresh: now.addingTimeInterval(-5 * 3600), hours: 5, now: now))
        XCTAssertTrue(AIHotRefreshPolicy.shouldRefresh(hasCache: false, lastSuccessfulRefresh: now, hours: 5, now: now))
    }

    func testRetryOccursAtMostOnce() {
        XCTAssertEqual(AIHotRefreshPolicy.retryDelay(statusCode: 429, retryAfter: "17", attempt: 0), 17)
        XCTAssertNil(AIHotRefreshPolicy.retryDelay(statusCode: 429, retryAfter: "17", attempt: 1))
        XCTAssertEqual(AIHotRefreshPolicy.retryDelay(statusCode: 500, retryAfter: nil, attempt: 0), 2)
        XCTAssertNil(AIHotRefreshPolicy.retryDelay(statusCode: 500, retryAfter: nil, attempt: 1))
    }
}
