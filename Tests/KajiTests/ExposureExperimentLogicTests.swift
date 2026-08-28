import XCTest
@testable import Kaji
@testable import KajiCore

final class ExposureExperimentLogicTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testExactElapsedPhaseBoundariesAndAutomaticCompletion() {
        let state = ExposureExperimentState(startedAt: start)
        XCTAssertEqual(ExposureExperimentLogic.phase(state: state, now: start), .baseline)
        XCTAssertEqual(ExposureExperimentLogic.phase(state: state, now: start.addingTimeInterval(72 * 60 * 60 - 0.001)), .baseline)
        XCTAssertEqual(ExposureExperimentLogic.phase(state: state, now: start.addingTimeInterval(72 * 60 * 60)), .treatment)
        XCTAssertEqual(ExposureExperimentLogic.phase(state: state, now: start.addingTimeInterval((72 + 14 * 24) * 60 * 60 - 0.001)), .treatment)
        XCTAssertEqual(ExposureExperimentLogic.phase(state: state, now: start.addingTimeInterval((72 + 14 * 24) * 60 * 60)), .completed)
    }

    func testRollbackImmediatelyRestoresLegacyAndCannotRestart() {
        var state = ExposureExperimentState()
        ExposureExperimentLogic.start(state: &state, now: start)
        let originalStart = state.startedAt
        let treatment = start.addingTimeInterval(72 * 60 * 60)
        ExposureExperimentLogic.rollback(state: &state, now: treatment)
        XCTAssertEqual(ExposureExperimentLogic.phase(state: state, now: treatment), .rolledBack)
        XCTAssertTrue(ExposureExperimentLogic.phase(state: state, now: treatment).usesLegacyExposure)
        ExposureExperimentLogic.start(state: &state, now: treatment.addingTimeInterval(1))
        XCTAssertEqual(state.startedAt, originalStart)
    }

    func testBaselineAndCompletedPreserveExistingPagesExactly() {
        let enabled = Set(KajiModuleID.allCases)
        for phase in [ExposureExperimentPhase.notStarted, .baseline, .completed, .rolledBack] {
            XCTAssertEqual(
                ExposureExperimentLogic.visiblePopoverModules(phase: phase, enabled: enabled, favorites: [.goals, .work]),
                ModulePrefsLogic.popoverPages(enabled: enabled)
            )
        }
    }

    func testTreatmentPrimaryAndMoreAreStableBoundedAndExcludeDisabled() {
        let enabled: Set<KajiModuleID> = [.quota, .work, .system, .goals, .aiNews]
        XCTAssertEqual(
            ExposureExperimentLogic.primaryModules(enabled: enabled, favorites: [.goals, .work, .aiNews]),
            [.quota, .goals, .work]
        )
        XCTAssertEqual(
            ExposureExperimentLogic.moreModules(enabled: enabled, favorites: [.goals, .work]),
            [.system, .aiNews]
        )
        XCTAssertEqual(
            ExposureExperimentLogic.primaryModules(enabled: [.quota, .goals], favorites: [.work, .goals]),
            [.quota, .goals]
        )
    }

    func testAggregateSchemaIsBoundedAndContainsNoContentFields() throws {
        var record = ExposureStudyRecord(experiment: .init(startedAt: start))
        for day in 0..<40 {
            let now = start.addingTimeInterval(TimeInterval(day * 86_400))
            record.record(event: .popoverOpen, module: .goals, source: .more, now: now)
            record.recordStatusWidth(120 + day, now: now)
        }
        XCTAssertEqual(record.days.count, ExposureStudyRecord.maximumDailyBuckets)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(record), as: UTF8.self)
        for forbidden in ["title", "text", "subject", "process", "label", "feedback", "mailMetadata", "news"] {
            XCTAssertFalse(json.localizedCaseInsensitiveContains(forbidden), "unexpected content field: \(forbidden)")
        }
        XCTAssertTrue(json.contains("moduleEntries"))
        XCTAssertTrue(json.contains("maximumStatusWidth"))
    }

    @MainActor
    func testLocalStorePersistsAtomicallyAndClearRetainsExperimentState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("study.json")
        var now = start
        let store = ExposureStudyStore(fileURL: url, clock: { now })
        store.startIfNeeded()
        store.record(.popoverOpen, module: .quota, source: .statusItem)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let startedAt = store.record.experiment.startedAt
        store.clearAggregates()
        XCTAssertEqual(store.record.days, [])
        XCTAssertEqual(store.record.experiment.startedAt, startedAt)

        now = start.addingTimeInterval(72 * 60 * 60)
        let reloaded = ExposureStudyStore(fileURL: url, clock: { now })
        XCTAssertEqual(reloaded.phase, .treatment)
        XCTAssertEqual(reloaded.record.experiment.startedAt, startedAt)
        try? FileManager.default.removeItem(at: directory)
    }
}
