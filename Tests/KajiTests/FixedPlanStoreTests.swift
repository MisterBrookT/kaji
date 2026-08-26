import XCTest
import KajiCore
@testable import Kaji

@MainActor
final class FixedPlanStoreTests: XCTestCase {
    func testCompletedScheduleRetiresFromListWhileCountPersists() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let currentDate = makeDate(year: 2026, month: 8, day: 24)
        let store = FixedPlanStore(
            defaults: defaults,
            calendar: utcCalendar,
            now: { currentDate },
            completionRemovalDelay: .milliseconds(20)
        )
        let id = try XCTUnwrap(store.add(
            title: "Weekly review", tag: GoalTag.work.rawValue, note: "", weekdays: [2]
        ))
        let schedule = try XCTUnwrap(store.visibleTodaySchedules.first)

        store.toggleCompletion(schedule)
        for _ in 0..<50 where !store.visibleTodaySchedules.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(store.visibleTodaySchedules.isEmpty)
        XCTAssertEqual(store.todayScheduledEntries.map(\.id), [id])
        XCTAssertEqual(store.todayScheduledCompletedCount, 1)
        XCTAssertTrue(store.completion.completedIDs.contains(id))

        let reloadedSameDay = FixedPlanStore(defaults: defaults, calendar: utcCalendar, now: { currentDate })
        XCTAssertTrue(reloadedSameDay.visibleTodaySchedules.isEmpty)
        XCTAssertEqual(reloadedSameDay.todayScheduledEntries.map(\.id), [id])
        XCTAssertEqual(reloadedSameDay.todayScheduledCompletedCount, 1)
    }

    func testScheduledCountResetsAtNextDayBoundary() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var currentDate = makeDate(year: 2026, month: 8, day: 24)
        let store = FixedPlanStore(defaults: defaults, calendar: utcCalendar, now: { currentDate })
        _ = try XCTUnwrap(store.add(
            title: "Daily review", tag: GoalTag.work.rawValue, note: "", weekdays: [2, 3]
        ))
        let schedule = try XCTUnwrap(store.visibleTodaySchedules.first)
        store.toggleCompletion(schedule)
        XCTAssertEqual(store.todayScheduledCompletedCount, 1)

        currentDate = makeDate(year: 2026, month: 8, day: 25)

        XCTAssertEqual(store.todayScheduledEntries.count, 1)
        XCTAssertEqual(store.todayScheduledCompletedCount, 0)
        XCTAssertTrue(store.completion.completedIDs.isEmpty)
    }

    func testDeletingScheduleRemovesPlanEntryPersistently() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let date = makeDate(year: 2026, month: 8, day: 24)
        let store = FixedPlanStore(defaults: defaults, calendar: utcCalendar, now: { date })
        _ = store.add(title: "Remove me", tag: GoalTag.personal.rawValue, note: "", weekdays: [2])
        let schedule = try XCTUnwrap(store.visibleTodaySchedules.first)

        store.delete(schedule)

        XCTAssertTrue(store.schedules.isEmpty)
        let reloaded = FixedPlanStore(defaults: defaults, calendar: utcCalendar, now: { date })
        XCTAssertTrue(reloaded.schedules.isEmpty)
        XCTAssertTrue(reloaded.visibleTodaySchedules.isEmpty)
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
