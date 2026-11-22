// brook 11-22: "New optional module 'GPU monitor' (off by default): shows mlkit's GPU load in the
// menu bar. Read-only ... per host and card: used/free memory, util, whose job, and host up/down;
// plus a running-jobs list and avg util. Data: don't ssh from Kaji. Read one JSON file that mlkit
// writes" (~/.mlkit/gpus.json, schema in mlkit docs/method/hosts.md).
import XCTest
import KajiCore

final class GpuSnapshotTests: XCTestCase {
    let json = """
    {"schema": 1, "time": 1000, "avg_util": 47.5,
     "hosts": [{"name": "a800", "up": true, "cards": [
        {"gpu": 0, "used_mb": 70000, "total_mb": 81920, "util": 95, "who": "train-x"},
        {"gpu": 1, "used_mb": null, "total_mb": null, "util": null, "who": ""}]},
       {"name": "gone", "up": false, "cards": []}],
     "jobs": [{"id": "j1", "name": "train-x", "kind": "train", "where": ["a800:0"], "owner": "brook",
               "state": "running", "age": 3700, "extra": 1}],
     "future": true}
    """

    func testDecodeAndFormat() throws {
        let s = try GpuSnapshot.decode(Data(json.utf8))
        XCTAssertEqual(s.hosts.map(\.name), ["a800", "gone"])
        XCTAssertFalse(s.hosts[1].up)
        let c = s.hosts[0].cards[0]
        XCTAssertEqual(c.freeMB, 11920)
        XCTAssertEqual(GpuFormat.memory(c), "68/80 GB")
        XCTAssertEqual(GpuFormat.memory(s.hosts[0].cards[1]), "mem n/a")
        XCTAssertNil(s.hosts[0].cards[1].freeMB)
        XCTAssertEqual(GpuFormat.util(c.util), "95%")
        XCTAssertEqual(GpuFormat.util(nil), "\u{2014}")
        XCTAssertEqual(s.jobs.first?.name, "train-x")
        XCTAssertEqual(GpuFormat.age(3700), "1h01m")
        XCTAssertEqual(GpuFormat.menuBarLabel(s), "48%")
        XCTAssertEqual(s.busyCards, 1)
        XCTAssertEqual(s.totalCards, 2)
    }

    func testStaleness() throws {
        let s = try GpuSnapshot.decode(Data(json.utf8))
        XCTAssertFalse(s.isStale(now: Date(timeIntervalSince1970: 1000 + 60)))
        XCTAssertTrue(s.isStale(now: Date(timeIntervalSince1970: 1000 + 16 * 60)))
    }

    func testMissingAvgAndNoCards() throws {
        let s = try GpuSnapshot.decode(Data(#"{"schema":1,"time":1,"hosts":[],"jobs":[]}"#.utf8))
        XCTAssertNil(s.avgUtil)
        XCTAssertEqual(GpuFormat.menuBarLabel(s), "\u{2014}")
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try GpuSnapshot.decode(Data("nope".utf8)))
    }
}
