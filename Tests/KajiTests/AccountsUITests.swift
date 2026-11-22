import XCTest
import SwiftUI
@testable import Kaji

final class AccountCopyTests: XCTestCase {
    func testHeaderAndSummaryAreAlwaysPercentLeft() {
        XCTAssertEqual(AccountCopy.header(active: "brook", pinned: false), "Using brook · Auto")
        XCTAssertEqual(AccountCopy.header(active: nil, pinned: true), "Using — · Pinned")
        XCTAssertEqual(AccountCopy.summary(left: 96.4, state: .ok), "96% left")
        XCTAssertEqual(AccountCopy.summary(left: 0, state: .ok), "0% left")
        XCTAssertEqual(AccountCopy.summary(left: nil, state: .unknown), "unknown")
        XCTAssertEqual(AccountCopy.summary(left: nil, state: .signedOut), "signed out")
        XCTAssertEqual(AccountCopy.summary(left: 40, state: .stale), "40% left · stale")
    }

    func testStateRules() {
        XCTAssertEqual(AccountRouting.state(ready: false, hasReading: true, checkedAt: nil, nowMs: 0), .signedOut)
        XCTAssertEqual(AccountRouting.state(ready: true, hasReading: false, checkedAt: nil, nowMs: 0), .unknown)
        XCTAssertEqual(AccountRouting.state(ready: nil, hasReading: true, checkedAt: 0, nowMs: 16 * 60_000), .stale)
        XCTAssertEqual(AccountRouting.state(ready: true, hasReading: true, checkedAt: 0, nowMs: 60_000), .ok)
        XCTAssertNil(AccountRouting.left(nil), "missing reading is not 100% left")
        XCTAssertEqual(AccountRouting.left(30), 70)
    }
}

@MainActor
final class AccountStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: dir) }

    // brook, 11-13: "Kaji = display only: reads, writes nothing to
    // accounts-usage.json". brook 11-20: pix's printout is pix.db kv "route";
    // the old accounts-usage.json here carries values Kaji must ignore and not touch.
    private let usageRaw = #"{"own":{"left":99,"checkedAt":1,"coolUntil":9999999999999},"_active":{"id":"own"}}"#

    private func store(route: String? = #"{"account":"bench","accounts":{"claude":"bench","codex":"codex"}}"#,
                       ownCheckedAt: String = "null") throws -> QuotaStore {
        try usageRaw.write(to: dir.appendingPathComponent("accounts-usage.json"), atomically: true, encoding: .utf8)
        if let route { try seedPixRoute(dir, route) }
        let s = QuotaStore(previewProviders: [])
        s.pixFiles = PixAccountsFiles(home: dir)
        let json = #"{"claude":{"limits":{"five_hour_used_percent":10}},"cursor":{"limits":{"five_hour_used_percent":5}},"accounts":[{"id":"own","provider":"claude","label":"brook","ready":true,"checked_at":\#(ownCheckedAt),"limits":{"five_hour_used_percent":100,"seven_day_used_percent":40}},{"id":"bench","provider":"claude","label":"bench","ready":true,"limits":{"five_hour_used_percent":4,"seven_day_used_percent":20}},{"id":"gone","provider":"claude","label":"gone","ready":false},{"id":"codex","provider":"codex","label":"codex"},{"id":"cx2","provider":"codex","label":"cx2"}]}"#
        s.ingest(try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8)))
        return s
    }

    private func byID(_ s: QuotaStore) -> [String: ProviderView] {
        Dictionary(uniqueKeysWithValues: s.accounts.map { ($0.accountID!, $0) })
    }

    func testAccountsExposeLeftStateAndActive() throws {
        let s = try store()
        let v = byID(s)
        XCTAssertEqual(v["own"]?.percentLeft, 0, "quota.py's number, not accounts-usage left")
        XCTAssertEqual(v["bench"]?.percentLeft, 80)
        XCTAssertEqual(v["gone"]?.accountState, .signedOut)
        XCTAssertEqual(v["codex"]?.accountState, .unknown)
        XCTAssertEqual(s.activeClaudeLabel, "bench", "pix route printout, not _active or coolUntil")
        XCTAssertEqual(s.accounts.filter(\.isActiveAccount).map(\.accountID), ["bench", "codex"],
                       "printout accounts.codex marks the Codex account")
        XCTAssertEqual(s.accountCoveredProviders, ["claude", "codex"])
    }

    func testNoRouteJSONMeansNoCurrentAccount() throws {
        let s = try store(route: nil)
        XCTAssertNil(s.activeClaudeLabel)
        XCTAssertEqual(s.accounts.filter(\.isActiveAccount).count, 0)
        XCTAssertEqual(AccountCopy.header(active: s.activeClaudeLabel, pinned: false), "Using — · Auto")
    }

    func testStaleBadgeUsesTheRealFetchTime() throws {
        let now = Date().timeIntervalSince1970 * 1000
        // accounts-usage.json says checkedAt 1 (ancient): ignored.
        XCTAssertEqual(byID(try store(ownCheckedAt: "\(now - 60_000)"))["own"]?.accountState, .ok)
        XCTAssertEqual(byID(try store(ownCheckedAt: "\(now - 16 * 60_000)"))["own"]?.accountState, .stale)
        XCTAssertEqual(byID(try store(ownCheckedAt: "null"))["own"]?.accountState, .ok, "unknown age is not called stale")
    }

    func testUseThenAutoRoundTripsRouteFile() throws {
        let s = try store()
        let routeBefore = s.pixFiles.current
        s.pinClaudeRoute("own")
        XCTAssertEqual(s.claudeRoute, "own")
        XCTAssertEqual(s.activeClaudeLabel, "brook", "pin wins over pix's route printout")
        XCTAssertEqual(configPin(dir), "own")
        s.pinClaudeRoute("auto")
        XCTAssertEqual(s.claudeRoute, "auto")
        XCTAssertEqual(s.activeClaudeLabel, "bench")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("accounts-usage.json"), encoding: .utf8),
                       usageRaw, "Kaji never writes accounts-usage.json")
        XCTAssertEqual(s.pixFiles.current, routeBefore)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("pix.db") }.sorted(),
                       ["accounts-usage.json", "config.json"])
    }
}

@MainActor
final class AccountPanelRenderTests: XCTestCase {
    func testAccountPanelRenders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedPixRoute(dir, #"{"account":"bench","accounts":{"claude":"bench"}}"#)
        let fixture = PopoverRenderFixture()
        defer { fixture.tearDown() }
        fixture.store.pixFiles = PixAccountsFiles(home: dir)
        let json = #"{"claude":{"limits":{"five_hour_used_percent":10}},"accounts":[{"id":"own","provider":"claude","label":"brook","ready":true,"limits":{"five_hour_used_percent":100,"seven_day_used_percent":40,"five_hour_resets_at":1900000000}},{"id":"bench","provider":"claude","label":"minarabench","ready":true,"limits":{"five_hour_used_percent":4,"seven_day_used_percent":20,"five_hour_resets_at":1900000000,"seven_day_resets_at":1900086400}},{"id":"gone","provider":"claude","label":"spare","ready":false},{"id":"codex","provider":"codex","label":"codex","limits":{"five_hour_used_percent":12}}]}"#
        fixture.store.ingest(try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8)))
        let rep = try XCTUnwrap(renderImage(fixture.view(page: .quota), size: CGSize(width: PanelSize.medium.frameSize.width, height: 640)))
        writePNG(rep, name: "popover-accounts")
    }
}

@MainActor
final class AccountInteractionTests: XCTestCase {
    private func snap(_ ownUsed: Double, _ benchUsed: Double) throws -> QuotaSnapshot {
        let json = #"{"accounts":[{"id":"own","provider":"claude","label":"brook","ready":true,"limits":{"five_hour_used_percent":\#(ownUsed)}},{"id":"bench","provider":"claude","label":"bench","ready":true,"limits":{"five_hour_used_percent":\#(benchUsed)}}]}"#
        return try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8))
    }

    func testExpansionDefaultsToActiveAndSurvivesRefresh() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try seedPixRoute(dir, #"{"account":"bench","accounts":{"claude":"bench"}}"#)
        let s = QuotaStore(previewProviders: [])
        s.pixFiles = PixAccountsFiles(home: dir)
        s.ingest(try snap(50, 10))
        var e = AccountExpansion()
        let open = { (s.accounts.filter { e.isExpanded($0.id, active: $0.isActiveAccount) }).map(\.accountID!) }
        XCTAssertEqual(open(), ["bench"], "active row open initially")
        e.toggle("account:own", accounts: s.accounts)
        XCTAssertEqual(open(), ["own", "bench"])
        e.toggle("account:bench", accounts: s.accounts)
        XCTAssertEqual(open(), ["own"])
        // Refresh: new numbers, open rows stay as the user left them.
        s.ingest(try snap(80, 30))
        XCTAssertEqual(open(), ["own"])
        XCTAssertEqual(s.accounts.first?.percentLeft, 20)
        // Refresh picks up a route pinned outside Kaji (pix / CLI).
        try setConfigPin(dir, "own")
        s.rebuildAccounts()
        XCTAssertEqual(s.claudeRoute, "own")
        XCTAssertEqual(s.activeClaudeLabel, "brook")
    }
}


final class AccountPinPolicyTests: XCTestCase {
    func testOnlyKnownFreshExhaustedClaudeNeedsConfirmation() {
        var a = ProviderView(id: "account:own", mark: "C", displayName: "brook",
                             fiveHourPercent: 100, weekPercent: 10, resetDate: nil,
                             weekResetDate: nil, logoKey: "claude")
        XCTAssertTrue(AccountPinPolicy.requiresConfirmation(a))
        a.accountState = .stale
        XCTAssertFalse(AccountPinPolicy.requiresConfirmation(a))
        a.accountState = .unknown
        XCTAssertFalse(AccountPinPolicy.requiresConfirmation(a))
        a.accountState = .signedOut
        XCTAssertFalse(AccountPinPolicy.requiresConfirmation(a))
        a.accountState = .ok
        a.logoKey = "codex"
        XCTAssertFalse(AccountPinPolicy.requiresConfirmation(a))
    }
}

final class BindingLimitTests: XCTestCase {
    func testHeadlineIsTighterWindow() {
        let own = ProviderView(id: "account:own", mark: "C", displayName: "brook",
                               fiveHourPercent: 0, weekPercent: 100, resetDate: nil,
                               weekResetDate: nil, logoKey: "claude")
        XCTAssertEqual(own.percentLeft, 0, "5h fresh but 7d used up = 0% left")
        XCTAssertEqual(AccountRouting.left(own.fiveHourPercent), 100, "expanded 5h still shows its own value")
    }
}
