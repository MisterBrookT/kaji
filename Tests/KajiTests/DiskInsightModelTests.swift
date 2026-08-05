import XCTest
@testable import KajiCore

final class DiskInsightModelTests: XCTestCase {
    func testClassifiesKnownFileTypesAndPathOverrides() {
        XCTAssertEqual(DiskFileCategoryLogic.category(path: "/Users/me/Movies/a.mp4", pathExtension: "mp4"), .video)
        XCTAssertEqual(DiskFileCategoryLogic.category(path: "/Users/me/Pictures/a.HEIC", pathExtension: "HEIC"), .images)
        XCTAssertEqual(DiskFileCategoryLogic.category(path: "/Users/me/Music/a.flac", pathExtension: "flac"), .audio)
        XCTAssertEqual(DiskFileCategoryLogic.category(path: "/Users/me/Documents/a.pdf", pathExtension: "pdf"), .documents)
        XCTAssertEqual(DiskFileCategoryLogic.category(path: "/Users/me/Downloads/a.zip", pathExtension: "zip"), .archives)
        XCTAssertEqual(DiskFileCategoryLogic.category(path: "/Users/me/project/main.swift", pathExtension: "swift"), .appsDeveloper)
        XCTAssertEqual(DiskFileCategoryLogic.category(path: "/Users/me/Library/Caches/a.mp4", pathExtension: "mp4"), .caches)
        XCTAssertEqual(DiskFileCategoryLogic.category(path: "/Users/me/Library/Developer/Xcode/a.dat", pathExtension: "dat"), .appsDeveloper)
    }

    func testUnknownTypeFallsIntoOther() {
        XCTAssertEqual(DiskFileCategoryLogic.category(path: "/Users/me/file.unknown", pathExtension: "unknown"), .other)
    }

    func testNormalizedTotalsIncludesEveryCategoryAndClampsNegativeValues() {
        let totals = DiskFileCategoryLogic.normalizedTotals([.video: 42, .audio: -1])
        XCTAssertEqual(totals.count, DiskFileCategory.allCases.count)
        XCTAssertEqual(totals[.video], 42)
        XCTAssertEqual(totals[.audio], 0)
        XCTAssertEqual(totals[.other], 0)
    }

    func testScanPolicyUsesTwentyFourHourSuccessfulCache() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(DiskInsightScanPolicy.shouldScan(lastSuccessfulAt: nil, now: now))
        XCTAssertFalse(DiskInsightScanPolicy.shouldScan(
            lastSuccessfulAt: now.addingTimeInterval(-DiskInsightScanPolicy.interval + 1),
            now: now
        ))
        XCTAssertTrue(DiskInsightScanPolicy.shouldScan(
            lastSuccessfulAt: now.addingTimeInterval(-DiskInsightScanPolicy.interval),
            now: now
        ))
        XCTAssertTrue(DiskInsightScanPolicy.shouldScan(
            lastSuccessfulAt: now,
            now: now,
            force: true
        ))
    }
}

