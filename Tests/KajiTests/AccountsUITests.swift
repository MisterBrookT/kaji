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

    private func store(usage: String) throws -> QuotaStore {
        try usage.write(to: dir.appendingPathComponent("accounts-usage.json"), atomically: true, encoding: .utf8)
        let s = QuotaStore(previewProviders: [])
        s.pixFiles = PixAccountsFiles(home: dir)
        let json = #"{"claude":{"limits":{"five_hour_used_percent":10}},"cursor":{"limits":{"five_hour_used_percent":5}},"accounts":[{"id":"own","provider":"claude","label":"brook","ready":true,"limits":{"five_hour_used_percent":100,"seven_day_used_percent":40}},{"id":"bench","provider":"claude","label":"bench","ready":true,"limits":{"five_hour_used_percent":4,"seven_day_used_percent":20}},{"id":"gone","provider":"claude","label":"gone","ready":false},{"id":"codex","provider":"codex","label":"codex"}]}"#
        s.ingest(try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8)))
        return s
    }

    func testAccountsExposeLeftStateAndActive() throws {
        let now = Date().timeIntervalSince1970 * 1000
        let s = try store(usage: #"{"own":{"left":0,"checkedAt":\#(now)},"bench":{"left":80,"checkedAt":\#(now)},"_active":{"id":"bench"}}"#)
        let byID = Dictionary(uniqueKeysWithValues: s.accounts.map { ($0.accountID!, $0) })
        XCTAssertEqual(byID["own"]?.percentLeft, 0)
        XCTAssertEqual(byID["bench"]?.percentLeft, 80)
        XCTAssertEqual(byID["gone"]?.accountState, .signedOut)
        XCTAssertEqual(byID["codex"]?.accountState, .unknown)
        XCTAssertEqual(s.activeClaudeLabel, "bench")
        XCTAssertEqual(s.accountCoveredProviders, ["claude", "codex"])
    }

    func testUseThenAutoRoundTripsRouteFile() throws {
        let s = try store(usage: #"{"_active":{"id":"bench"}}"#)
        s.pinClaudeRoute("own")
        XCTAssertEqual(s.claudeRoute, "own")
        XCTAssertEqual(s.activeClaudeLabel, "brook")
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("claude-route"), encoding: .utf8), "own\n")
        s.pinClaudeRoute("auto")
        XCTAssertEqual(s.claudeRoute, "auto")
        XCTAssertEqual(s.activeClaudeLabel, "bench")
        let usage = try String(contentsOf: dir.appendingPathComponent("accounts-usage.json"), encoding: .utf8)
        XCTAssertTrue(usage.contains("_active"), "Kaji never rewrites pix's _active")
    }
}

@MainActor
final class AccountPanelRenderTests: XCTestCase {
    func testAccountPanelRenders() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"_active":{"id":"bench"}}"#.write(to: dir.appendingPathComponent("accounts-usage.json"), atomically: true, encoding: .utf8)
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
        try #"{"_active":{"id":"bench"}}"#.write(to: dir.appendingPathComponent("accounts-usage.json"), atomically: true, encoding: .utf8)
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
        try "own\n".write(to: dir.appendingPathComponent("claude-route"), atomically: true, encoding: .utf8)
        s.rebuildAccounts()
        XCTAssertEqual(s.claudeRoute, "own")
        XCTAssertEqual(s.activeClaudeLabel, "brook")
    }
}

