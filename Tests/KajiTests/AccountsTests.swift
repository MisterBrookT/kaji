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

    // brook, 11-13: "Kaji = display only: reads, writes nothing to
    // accounts-usage.json". The account in use is pix's printout (pix.db kv route),
    // not a Kaji copy of the band rule.
    func testSnapshotDecodesRealFetchTime() throws {
        let json = #"{"accounts":[{"id":"own","provider":"claude","label":"brook","checked_at":1700000000000,"limits":{"five_hour_used_percent":1}},{"id":"b","provider":"claude","label":"b","checked_at":null}]}"#
        let snap = try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snap.accounts[0].checkedAt, 1_700_000_000_000)
        XCTAssertNil(snap.accounts[1].checkedAt)
    }

    func testCurrentClaudeFollowsRouteJSONAndPinWins() {
        let all = [account("a"), account("b"), account("x", "codex")]
        let pix = PixRoute(claude: "a", codex: "x")
        XCTAssertEqual(AccountRouting.currentClaudeID(accounts: all, route: "auto", current: pix), "a")
        XCTAssertEqual(AccountRouting.currentClaudeID(accounts: all, route: "b", current: pix), "b", "pin wins")
        XCTAssertEqual(AccountRouting.currentClaudeID(accounts: all, route: "gone", current: pix), "a",
                       "a pin that names no Claude account is not a pin")
        XCTAssertEqual(AccountRouting.currentClaudeID(accounts: all, route: "x", current: pix), "a",
                       "a Codex id is not a Claude pin")
        XCTAssertNil(AccountRouting.currentClaudeID(accounts: all, route: "auto", current: PixRoute()),
                     "no route printout = no current account; Kaji does not guess")
    }

    func testRouteWriteAndRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = PixAccountsFiles(home: dir)
        XCTAssertEqual(files.route, "auto")
        XCTAssertEqual(files.current, PixRoute(), "no route printout")
        // brook 2026-11-20: the pin lives in the one hand-edited ~/.pix/config.json; brook's other keys stay.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"knobs":{"x":1}}"#.write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try files.writeRoute("own")
        let c = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("config.json"))) as! [String: Any]
        XCTAssertEqual((c["route"] as? [String: Any])?["claude"] as? String, "own")
        XCTAssertEqual((c["knobs"] as? [String: Any])?["x"] as? Int, 1)
        XCTAssertEqual(files.route, "own")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["config.json"],
                       "the pin is the only thing Kaji writes under ~/.pix")
    }

    func testRouteJSONRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = PixAccountsFiles(home: dir)
        try seedPixRoute(dir, #"{"provider":"pix-anthropic","model":"claude-fable-5-2","account":"old","accounts":{"claude":"bench","codex":"apple"},"stage":0,"reason":"Auto policy","since":1}"#)
        XCTAssertEqual(files.current, PixRoute(claude: "bench", codex: "apple"))
        try seedPixRoute(dir, #"{"account":"own","accounts":{}}"#)
        XCTAssertEqual(files.current, PixRoute(claude: "own", codex: nil), "falls back to `account`")
        try seedPixRoute(dir, #"{"account":null}"#)
        XCTAssertEqual(files.current, PixRoute())
        try seedPixRoute(dir, "not json")
        XCTAssertEqual(files.current, PixRoute())
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


import SQLite3
/// pix's route printout as pix writes it (brook 11-20: pix.db kv "route", plugins/core/pixdb.ts schema).
func seedPixRoute(_ dir: URL, _ json: String) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    guard sqlite3_open(dir.appendingPathComponent("pix.db").path, &db) == SQLITE_OK else { throw CocoaError(.fileWriteUnknown) }
    sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT, updated INTEGER)", nil, nil, nil)
    var st: OpaquePointer?
    defer { sqlite3_finalize(st) }
    sqlite3_prepare_v2(db, "INSERT INTO kv(key,value,updated) VALUES('route',?,0) ON CONFLICT(key) DO UPDATE SET value=excluded.value", -1, &st, nil)
    sqlite3_bind_text(st, 1, json, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    sqlite3_step(st)
}
/// The Claude pin in config.json (route.claude), or nil.
func configPin(_ dir: URL) -> String? {
    guard let d = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
          let c = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
    return (c["route"] as? [String: Any])?["claude"] as? String
}
/// Set the pin the way brook or pix does (outside Kaji).
func setConfigPin(_ dir: URL, _ v: String) throws {
    try #"{"route":{"claude":"\#(v)"}}"#.write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
}
