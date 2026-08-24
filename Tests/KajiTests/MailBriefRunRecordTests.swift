import XCTest
@testable import KajiCore

final class MailBriefRunRecordTests: XCTestCase {
    func testUpsertPreservesActiveRunningState() {
        let running = MailBriefRunRecord(trigger: .manual, modelID: "spark", batchSize: 10, concurrency: 2)
        XCTAssertEqual(MailBriefRunHistory.upserting(running, into: []).first?.status, .running)
    }

    func testUpsertKeepsOneRecordPerRunAndLatestValues() {
        let id = UUID(), start = Date(timeIntervalSince1970: 100)
        let running = MailBriefRunRecord(id: id, trigger: .manual, startedAt: start,
                                         modelID: "spark", batchSize: 10, concurrency: 2)
        var complete = running
        complete.status = .succeeded; complete.stage = .finished
        complete.finishedAt = Date(timeIntervalSince1970: 110); complete.publishedCount = 84

        let values = MailBriefRunHistory.upserting(complete, into: [running])
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].status, .succeeded)
        XCTAssertEqual(values[0].publishedCount, 84)
    }

    func testHistoryKeepsLatestSeven() {
        let values = (0..<8).map { index in
            MailBriefRunRecord(trigger: .automatic, startedAt: Date(timeIntervalSince1970: Double(index)),
                               status: .succeeded, stage: .finished,
                               modelID: "spark", batchSize: 10, concurrency: 2)
        }
        let result = MailBriefRunHistory.normalized(values)
        XCTAssertEqual(result.count, 7)
        XCTAssertEqual(result.first?.startedAt, Date(timeIntervalSince1970: 7))
        XCTAssertEqual(result.last?.startedAt, Date(timeIntervalSince1970: 1))
    }

    func testOrphanRunningBecomesInterruptedCancellation() {
        let running = MailBriefRunRecord(trigger: .catchUp, startedAt: Date(timeIntervalSince1970: 10),
                                         modelID: "luna", batchSize: 20, concurrency: 3)
        let result = MailBriefRunHistory.normalized([running], now: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(result[0].status, .cancelled)
        XCTAssertEqual(result[0].stage, .finished)
        XCTAssertEqual(result[0].safeErrorCode, "interrupted")
        XCTAssertEqual(result[0].finishedAt, Date(timeIntervalSince1970: 20))
    }

    func testCodableRoundTripContainsOnlyRunMetadata() throws {
        var record = MailBriefRunRecord(trigger: .manual, modelID: "spark", batchSize: 10, concurrency: 2)
        record.snapshotInboxCount = 84; record.newOrChangedCount = 6; record.reusedCount = 78
        let data = try JSONEncoder().encode(record)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("subject"))
        XCTAssertFalse(text.contains("sender"))
        XCTAssertFalse(text.contains("threadID"))
        XCTAssertEqual(try JSONDecoder().decode(MailBriefRunRecord.self, from: data), record)
    }
}
