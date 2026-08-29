import XCTest
@testable import Kaji

@MainActor
final class QuotaStoreTests: XCTestCase {
    private func provider(
        _ id: String,
        fiveHourPercent: Double?
    ) -> ProviderView {
        ProviderView(
            id: id,
            mark: id,
            displayName: id,
            fiveHourPercent: fiveHourPercent,
            weekPercent: nil,
            resetDate: nil,
            weekResetDate: nil
        )
    }

    func testMostConstrainedPicksHighestPercentAndSkipsNoData() {
        let providers = [
            provider("claude", fiveHourPercent: 56),
            provider("codex", fiveHourPercent: 82),
            provider("ark", fiveHourPercent: nil),
        ]
        XCTAssertEqual(
            QuotaStore.mostConstrained(in: providers)?.id,
            "codex"
        )
    }

    func testMostConstrainedTieBreaksToEarlierProvider() {
        let providers = [
            provider("codex", fiveHourPercent: 70),
            provider("claude", fiveHourPercent: 70),
        ]
        XCTAssertEqual(
            QuotaStore.mostConstrained(in: providers)?.id,
            "codex"
        )
    }

    func testMostConstrainedReturnsNilWithoutData() {
        XCTAssertNil(QuotaStore.mostConstrained(in: []))
        XCTAssertNil(
            QuotaStore.mostConstrained(in: [
                provider("codex", fiveHourPercent: nil),
                provider("claude", fiveHourPercent: nil),
            ])
        )
    }
}