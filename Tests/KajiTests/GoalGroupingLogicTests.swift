import XCTest
@testable import KajiCore

final class GoalGroupingLogicTests: XCTestCase {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .iso8601)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()

    func testNonePreservesInputInOneUnnamedGroup() {
        let goals = [goal("A"), goal("B")]
        XCTAssertEqual(GoalGroupingLogic.group(goals, by: .none), [GoalGroup(title: "", goals: goals)])
    }

    func testTagGroupingUsesDefinitionOrderThenUnknownAndUntaggedLast() {
        let untagged = goal("Untagged", tag: "")
        let personal = goal("Personal", tag: "Personal")
        let custom = goal("Custom", tag: "Custom")
        let work = goal("Work", tag: "work")
        let groups = GoalGroupingLogic.group(
            [untagged, personal, custom, work],
            by: .byTag,
            tagOrder: ["Work", "Personal"],
            language: .en
        )
        XCTAssertEqual(groups.map(\.title), ["Work", "Personal", "Custom", "Untagged"])
        XCTAssertEqual(groups.flatMap(\.goals).map(\.title), ["Work", "Personal", "Custom", "Untagged"])
    }

    func testCreatedTimeBoundariesAreNewestFirstAndLegacyOrderIsStable() {
        let now = date("2026-08-26T12:00:00Z") // Wednesday
        let legacyA = goal("Legacy A")
        let legacyB = goal("Legacy B")
        let goals = [
            legacyA,
            goal("Earlier", createdAt: date("2026-08-23T23:59:59Z")),
            goal("Week start", createdAt: date("2026-08-24T00:00:00Z")),
            goal("Yesterday start", createdAt: date("2026-08-25T00:00:00Z")),
            goal("Today start", createdAt: date("2026-08-26T00:00:00Z")),
            legacyB,
        ]
        let groups = GoalGroupingLogic.group(
            goals,
            by: .byCreatedTime,
            now: now,
            calendar: calendar,
            language: .en
        )
        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday", "This Week", "Earlier"])
        XCTAssertEqual(groups[0].goals.map(\.title), ["Today start"])
        XCTAssertEqual(groups[1].goals.map(\.title), ["Yesterday start"])
        XCTAssertEqual(groups[2].goals.map(\.title), ["Week start"])
        XCTAssertEqual(groups[3].goals.map(\.title), ["Legacy A", "Earlier", "Legacy B"])
    }

    func testEmptyInputHasNoGroups() {
        for grouping in GoalGrouping.allCases {
            XCTAssertTrue(GoalGroupingLogic.group([], by: grouping).isEmpty)
        }
    }

    func testLegacyGoalJSONDecodesWithoutCreatedAtAndPreservesFields() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let json = "{\"id\":\"\(id.uuidString)\",\"title\":\"Legacy\",\"isDone\":true,\"tag\":\"Work\",\"note\":\"Kept\"}"
        let decoded = try JSONDecoder().decode(GoalItem.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.title, "Legacy")
        XCTAssertTrue(decoded.isDone)
        XCTAssertEqual(decoded.tag, "Work")
        XCTAssertEqual(decoded.note, "Kept")
        XCTAssertNil(decoded.createdAt)
    }

    func testGroupingLocalizationKeysExistForEveryLanguage() {
        let keys: [L10n.K] = [
            .goalGroup, .goalGroupingNone, .goalGroupingByTag, .goalGroupingByCreatedTime,
            .goalGroupUntagged, .goalGroupToday, .goalGroupYesterday, .goalGroupThisWeek, .goalGroupEarlier,
        ]
        for language in AppLanguage.allCases {
            for key in keys {
                XCTAssertFalse(L10n.t(key, language).isEmpty, "Missing \(key) for \(language)")
            }
        }
    }

    private func goal(_ title: String, tag: String = "", createdAt: Date? = nil) -> GoalItem {
        GoalItem(id: UUID(), title: title, isDone: false, tag: tag, createdAt: createdAt)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
