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

    // MARK: - mostConstrained(in:count:)

    func testMostConstrainedCountReturnsRankedList() {
        let providers = [
            provider("claude", fiveHourPercent: 56),
            provider("codex", fiveHourPercent: 82),
            provider("ark", fiveHourPercent: nil),
            provider("cursor", fiveHourPercent: 63),
        ]
        XCTAssertEqual(
            QuotaStore.mostConstrained(in: providers, count: 2).map(\.id),
            ["codex", "cursor"]
        )
        // `count` only caps the result — no-data providers are dropped, never padded.
        XCTAssertEqual(
            QuotaStore.mostConstrained(in: providers, count: 4).map(\.id),
            ["codex", "cursor", "claude"]
        )
    }

    func testMostConstrainedCountTieBreaksToEarlierProvider() {
        let providers = [
            provider("codex", fiveHourPercent: 70),
            provider("claude", fiveHourPercent: 70),
            provider("cursor", fiveHourPercent: 50),
        ]
        XCTAssertEqual(
            QuotaStore.mostConstrained(in: providers, count: 2).map(\.id),
            ["codex", "claude"]
        )
    }

    func testMostConstrainedCountBoundsAndEmpty() {
        let providers = [
            provider("codex", fiveHourPercent: 82),
            provider("claude", fiveHourPercent: 56),
        ]
        XCTAssertEqual(QuotaStore.mostConstrained(in: providers, count: 0), [])
        XCTAssertEqual(QuotaStore.mostConstrained(in: [], count: 3), [])
        XCTAssertEqual(
            QuotaStore.mostConstrained(in: [provider("ark", fiveHourPercent: nil)], count: 3),
            []
        )
    }

    func testMostConstrainedCountOneMatchesLegacySingle() {
        let providers = [
            provider("claude", fiveHourPercent: 56),
            provider("codex", fiveHourPercent: 82),
            provider("ark", fiveHourPercent: nil),
        ]
        XCTAssertEqual(
            QuotaStore.mostConstrained(in: providers, count: 1).first?.id,
            QuotaStore.mostConstrained(in: providers)?.id
        )
    }
}