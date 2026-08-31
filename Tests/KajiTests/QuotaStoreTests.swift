import XCTest
@testable import Kaji

@MainActor
final class QuotaStoreTests: XCTestCase {
    private func provider(
        _ id: String,
        fiveHourPercent: Double?,
        weekPercent: Double? = nil
    ) -> ProviderView {
        ProviderView(
            id: id,
            mark: id,
            displayName: id,
            fiveHourPercent: fiveHourPercent,
            weekPercent: weekPercent,
            resetDate: nil,
            weekResetDate: nil
        )
    }

    func testMenuBarOrderRanksByConstraint() {
        let providers = [
            provider("claude", fiveHourPercent: 56),
            provider("codex", fiveHourPercent: 82),
            provider("cursor", fiveHourPercent: 63),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 2).map(\.id),
            ["codex", "cursor"]
        )
    }

    func testMenuBarOrderTieBreaksToEarlierProvider() {
        let providers = [
            provider("codex", fiveHourPercent: 70),
            provider("claude", fiveHourPercent: 70),
            provider("cursor", fiveHourPercent: 50),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 2).map(\.id),
            ["codex", "claude"]
        )
    }

    /// Enabling a provider is an explicit request to see it: a missing
    /// percentage must never remove its ring, only push it to the end.
    func testMenuBarOrderKeepsProvidersWithoutData() {
        let providers = [
            provider("ark", fiveHourPercent: nil),
            provider("claude", fiveHourPercent: nil, weekPercent: 8),
            provider("codex", fiveHourPercent: 2),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 3).map(\.id),
            ["claude", "codex", "ark"]
        )
    }

    /// No-data providers keep their input order among themselves.
    func testMenuBarOrderNoDataProvidersKeepInputOrder() {
        let providers = [
            provider("minimax", fiveHourPercent: nil),
            provider("ark", fiveHourPercent: nil),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 3).map(\.id),
            ["minimax", "ark"]
        )
    }

    /// Score is the worse of the two windows, not whichever field is present.
    func testMenuBarOrderUsesMaxOfBothWindows() {
        let providers = [
            provider("claude", fiveHourPercent: nil, weekPercent: 40),
            provider("codex", fiveHourPercent: 2, weekPercent: 90),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 1).map(\.id),
            ["codex"]
        )
    }

    func testMenuBarOrderBoundsAndEmpty() {
        let providers = [
            provider("codex", fiveHourPercent: 82),
            provider("claude", fiveHourPercent: 56),
        ]
        XCTAssertEqual(QuotaStore.menuBarOrder(in: providers, count: 0), [])
        XCTAssertEqual(QuotaStore.menuBarOrder(in: [], count: 3), [])
        // `count` caps, never pads.
        XCTAssertEqual(QuotaStore.menuBarOrder(in: providers, count: 9).count, 2)
    }
}
