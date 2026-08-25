import XCTest
import KajiCore
@testable import Kaji

final class MailBriefModelsTests: XCTestCase {
    func testEntriesGroupIntoNonEmptyLevelSectionsDescending() {
        let entries = [
            MailBriefEntry.fixture(id: "quiet", level: 0),
            MailBriefEntry.fixture(id: "top", level: 3),
            MailBriefEntry.fixture(id: "watch", level: 1),
            MailBriefEntry.fixture(id: "also-top", level: 3),
        ]
        let sections = MailBriefPresentation.sections(entries: entries, dismissedIDs: [])
        XCTAssertEqual(sections.map(\.level), [3, 1, 0])
        XCTAssertEqual(sections[0].entries.map(\.threadID), ["top", "also-top"])
    }

    func testDismissedEntriesAreExcludedFromSectionsAndActCount() {
        let entries = [
            MailBriefEntry.fixture(id: "a", level: 3, bucket: .act),
            MailBriefEntry.fixture(id: "b", level: 2, bucket: .act),
            MailBriefEntry.fixture(id: "c", level: 1, bucket: .watch),
        ]
        XCTAssertEqual(MailBriefPresentation.actCount(entries: entries, dismissedIDs: ["a"]), 1)
        XCTAssertEqual(
            MailBriefPresentation.sections(entries: entries, dismissedIDs: ["a"]).flatMap(\.entries).map(\.threadID),
            ["b", "c"]
        )
    }

    func testCandidatePolicyPrioritizesSignalsAndReportsOverflow() {
        var candidates: [MailBriefCandidate] = []
        for index in 0..<105 {
            let candidate = MailBriefCandidate(
                threadID: String(index), subject: "S" + String(index), participants: [], messages: [],
                isImportant: index == 104, isStarred: index == 103,
                directlyAddressed: index == 102,
                changedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            candidates.append(candidate)
        }
        let selection = MailBriefCandidatePolicy.select(candidates, limit: 100)
        XCTAssertEqual(selection.selected.count, 100)
        XCTAssertEqual(selection.overflowCount, 5)
        let firstIDs = selection.selected.prefix(3).map { $0.threadID }
        XCTAssertTrue(firstIDs.contains("104"))
        XCTAssertTrue(firstIDs.contains("103"))
        XCTAssertTrue(firstIDs.contains("102"))
    }

    func testArchivedAndTrashedEntriesLeaveActiveSectionsAndActCount() {
        let entries = [
            MailBriefEntry.fixture(id: "active", level: 3, bucket: .act),
            MailBriefEntry.fixture(id: "archived", level: 3, bucket: .act),
            MailBriefEntry.fixture(id: "trashed", level: 2, bucket: .act),
        ]
        let sections = MailBriefPresentation.sections(entries: entries, dismissedIDs: [],
                                                      archivedIDs: ["archived"], trashedIDs: ["trashed"])
        XCTAssertEqual(sections.flatMap(\.entries).map(\.threadID), ["active"])
        XCTAssertEqual(MailBriefPresentation.actCount(entries: entries, dismissedIDs: [],
                                                      archivedIDs: ["archived"], trashedIDs: ["trashed"]), 1)
    }

    func testStarredEntriesSortFirstWithoutChangingLevel() {
        var plain = MailBriefEntry.fixture(id: "plain", level: 2)
        var starred = MailBriefEntry.fixture(id: "starred", level: 2)
        plain.isStarred = false; starred.isStarred = true
        let section = MailBriefPresentation.sections(entries: [plain, starred], dismissedIDs: [])[0]
        XCTAssertEqual(section.entries.map(\.threadID), ["starred", "plain"])
    }

    func testBatchSettingsNormalizeToSupportedValues() {
        XCTAssertEqual(MailBriefBatchPolicy.batchSize(10), 10)
        XCTAssertEqual(MailBriefBatchPolicy.batchSize(12), 10)
        XCTAssertEqual(MailBriefBatchPolicy.batchSize(0), 5)
        XCTAssertEqual(MailBriefBatchPolicy.concurrency(0), 1)
        XCTAssertEqual(MailBriefBatchPolicy.concurrency(9), 4)
    }

    func testGenerationCanRepresentIncrementalCheckpoint() {
        let value = MailBriefGeneration(briefDay: "2026-08-14", entries: [.fixture(id: "done", level: 2)],
                                        snapshotInboxThreadCount: 84, isComplete: false,
                                        classifierModelID: MailBriefModel.spark.rawValue)
        XCTAssertEqual(value.entries.count, 1)
        XCTAssertEqual(value.snapshotInboxThreadCount, 84)
        XCTAssertEqual(value.isComplete, false)
        XCTAssertEqual(value.classifierModelID, "gpt-5.3-codex-spark")
    }

    func testMailBriefModelUsesAllowlistAndSparkDefault() {
        XCTAssertEqual(MailBriefModel.defaultValue, .spark)
        XCTAssertEqual(MailBriefModel.normalize("gpt-5.6-luna"), .luna)
        XCTAssertEqual(MailBriefModel.normalize("arbitrary-model"), .spark)
    }
    func testEveryGmailMutationUpdatesLocalGeneration() {
        var entry = MailBriefEntry.fixture(id: "mail", level: 3)
        entry.isStarred = false
        let generation = MailBriefGeneration(
            briefDay: "2026-08-25",
            entries: [entry],
            snapshotInboxThreadCount: 1
        )

        let archived = MailBriefStore.applying(.archive, entry: entry, to: generation)
        XCTAssertEqual(archived.archivedThreadIDs, ["mail"])
        XCTAssertEqual(archived.snapshotInboxThreadCount, 0)
        let unarchived = MailBriefStore.applying(.unarchive, entry: entry, to: archived)
        XCTAssertTrue(unarchived.archivedThreadIDs.isEmpty)
        XCTAssertEqual(unarchived.snapshotInboxThreadCount, 1)

        let starred = MailBriefStore.applying(.star, entry: entry, to: generation)
        XCTAssertEqual(starred.entries[0].isStarred, true)
        let unstarred = MailBriefStore.applying(.unstar, entry: entry, to: starred)
        XCTAssertEqual(unstarred.entries[0].isStarred, false)

        let trashed = MailBriefStore.applying(.trash, entry: entry, to: generation)
        XCTAssertEqual(trashed.trashedThreadIDs, ["mail"])
        XCTAssertEqual(trashed.snapshotInboxThreadCount, 0)
        let untrashed = MailBriefStore.applying(.untrash, entry: entry, to: trashed)
        XCTAssertTrue(untrashed.trashedThreadIDs.isEmpty)
        XCTAssertEqual(untrashed.snapshotInboxThreadCount, 1)
    }

}

private extension MailBriefEntry {
    static func fixture(id: String, level: Int, bucket: MailBriefBucket = .watch) -> MailBriefEntry {
        MailBriefEntry(threadID: id, subject: id, sender: "sender", gmailURL: nil,
                       level: level, bucket: bucket, summaryZH: "summary", reasonZH: "reason",
                       suggestedAction: .watch, deadline: nil, confidence: .high, goalTitleZH: nil)
    }
}
