import XCTest
import KajiCore
@testable import Kaji

@MainActor
final class FixedPlanStoreTests: XCTestCase {
    func testCompletedScheduleRetiresWhileCompletionPersistsAndReturnsNextOccurrence() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var currentDate = makeDate(year: 2026, month: 8, day: 24)
        let store = FixedPlanStore(
            defaults: defaults,
            calendar: utcCalendar,
            now: { currentDate },
            completionRemovalDelay: .milliseconds(20)
        )
        let id = try XCTUnwrap(store.add(
            title: "Weekly review", tag: GoalTag.work.rawValue, note: "", weekdays: [2]
        ))
        let schedule = try XCTUnwrap(store.today.first)

        store.toggleCompletion(schedule)
        for _ in 0..<50 where !store.today.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(store.today.isEmpty)
        XCTAssertTrue(store.completion.completedIDs.contains(id))

        let reloadedSameDay = FixedPlanStore(defaults: defaults, calendar: utcCalendar, now: { currentDate })
        XCTAssertTrue(reloadedSameDay.today.isEmpty)
        XCTAssertTrue(reloadedSameDay.completion.completedIDs.contains(id))

        currentDate = makeDate(year: 2026, month: 8, day: 31)
        XCTAssertEqual(reloadedSameDay.today.map(\.id), [id])
        XCTAssertFalse(reloadedSameDay.completion.completedIDs.contains(id))
    }

    func testDeletingScheduleRemovesPlanEntryPersistently() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = makeDate(year: 2026, month: 8, day: 24)
        let store = FixedPlanStore(defaults: defaults, calendar: utcCalendar, now: { date })
        _ = store.add(title: "Remove me", tag: GoalTag.personal.rawValue, note: "", weekdays: [2])
        let schedule = try XCTUnwrap(store.today.first)

        store.delete(schedule)

        XCTAssertTrue(store.schedules.isEmpty)
        let reloaded = FixedPlanStore(defaults: defaults, calendar: utcCalendar, now: { date })
        XCTAssertTrue(reloaded.schedules.isEmpty)
        XCTAssertTrue(reloaded.today.isEmpty)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "FixedPlanStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(try? JSONEncoder().encode([ScheduledGoal]()), forKey: FixedPlanStore.schedulesPersistenceKey)
        return (defaults, suiteName)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
