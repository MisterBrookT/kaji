import XCTest
@testable import Kaji

final class AccountsTests: XCTestCase {
    private func account(_ id: String, _ provider: String = "claude", ready: Bool? = true) -> AccountQuota {
        AccountQuota(id: id, provider: provider, label: id, ready: ready, limits: nil)
    }

    func testSnapshotDecodesProvidersAndAccounts() throws {
        let json = #"{"claude":{"limits":{"five_hour_used_percent":40}},"accounts":[{"id":"own","provider":"claude","label":"brook","ready":true,"limits":{"seven_day_used_percent":70,"seven_day_resets_at":1781774199}},{"id":"codex","provider":"codex","label":"codex"}]}"#
        let snap = try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snap.providers["claude"]?.limits?.fiveHourUsedPercent, 40)
        XCTAssertNil(snap.providers["accounts"])
        XCTAssertEqual(snap.accounts.map(\.id), ["own", "codex"])
        XCTAssertEqual(snap.accounts[0].limits?.sevenDayUsedPercent, 70)
        XCTAssertNil(snap.accounts[1].limits)
    }

    func testSnapshotWithoutAccountsStillDecodes() throws {
        let snap = try JSONDecoder().decode(QuotaSnapshot.self, from: Data(#"{"codex":{"tokens_today":0}}"#.utf8))
        XCTAssertEqual(snap.accounts, [])
        XCTAssertNotNil(snap.providers["codex"])
    }

    private func active(_ accounts: [AccountQuota], route: String = "auto",
                        usage: [String: AccountUsage], stored: String? = nil) -> String? {
        AccountRouting.activeClaudeID(accounts: accounts, route: route, usage: usage,
                                      storedActive: stored, bandWidth: 25, nowMs: 1_000)
    }

    func testPinnedRouteWins() {
        let all = [account("a"), account("b")]
        XCTAssertEqual(active(all, route: "b", usage: ["a": .init(left: 90)]), "b")
        XCTAssertEqual(active(all, route: "gone", usage: ["b": .init(left: 90)]), "b",
                       "unknown route falls back to auto")
    }

    func testBandRuleKeepsCurrentOnTie() {
        let all = [account("a"), account("b")]
        // 60 and 70 share band 2: stay on the stored account.
        XCTAssertEqual(active(all, usage: ["a": .init(left: 70), "b": .init(left: 60)], stored: "b"), "b")
        // 80 is band 3 > band 2: switch.
        XCTAssertEqual(active(all, usage: ["a": .init(left: 80), "b": .init(left: 60)], stored: "b"), "a")
    }

    func testUnknownIsLowestBandAndCoolingOrNotReadySkipped() {
        let all = [account("a"), account("b", ready: false), account("c"), account("x", "codex")]
        XCTAssertEqual(active(all, usage: ["c": .init(left: 0)]), "c", "0% beats unknown")
        XCTAssertEqual(active(all, usage: ["a": .init(left: 99, coolUntil: 2_000), "c": .init(left: 10)]), "c")
        XCTAssertEqual(active([account("a"), account("c")], usage: [:]), "a", "first in order with no data")
    }

    func testRouteWriteAndRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = PixAccountsFiles(home: dir)
        XCTAssertEqual(files.route, "auto")
        try files.writeRoute("own")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("claude-route"), encoding: .utf8), "own\n")
        XCTAssertEqual(files.route, "own")
        try #"{"own":{"left":40,"coolUntil":5},"_active":{"id":"own"}}"#
            .write(to: dir.appendingPathComponent("accounts-usage.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(files.usage["own"], AccountUsage(left: 40, coolUntil: 5))
        XCTAssertEqual(files.storedActive, "own")
        XCTAssertEqual(files.bandWidth, 25)
    }

    @MainActor func testAccountStatusRingShowsRemainingWithoutInventingUnknownQuota() {
        XCTAssertEqual(DualRing.arcFraction(usedPercent: 100), 0)
        XCTAssertEqual(DualRing.arcFraction(usedPercent: 2), 0.98, accuracy: 0.0001)
        XCTAssertEqual(DualRing.arcFraction(usedPercent: nil), 0)
    }

    @MainActor func testMenuBarRingsReplaceCoveredProviders() {
        func v(_ id: String, logo: String? = nil) -> ProviderView {
            ProviderView(id: id, mark: id, displayName: id, fiveHourPercent: 10, weekPercent: nil,
                         resetDate: nil, weekResetDate: nil, logoKey: logo)
        }
        let rings = QuotaStore.menuBarRings(
            accounts: [v("account:own", logo: "claude"), v("account:codex", logo: "codex")],
            providers: [v("claude"), v("cursor"), v("codex")], count: 4)
        XCTAssertEqual(rings.map(\.id), ["account:own", "account:codex", "cursor"])
        XCTAssertEqual(QuotaStore.menuBarRings(accounts: [], providers: [v("claude")], count: 3).map(\.id), ["claude"])
    }
}
