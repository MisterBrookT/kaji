import Foundation
import Combine
import KajiCore

@MainActor
final class FixedPlanStore: ObservableObject {
    @Published private(set) var schedules: [ScheduledGoal]
    @Published private(set) var completion: ScheduleCompletionState

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    nonisolated static let schedulesPersistenceKey = "scheduledGoalsV1"

    private enum Key {
        static let schedules = schedulesPersistenceKey
        static let completion = "scheduledGoalCompletionV1"
        static let migration = "scheduledGoalsMigrationV1"
        static let legacyPlans = "fixedPlansV1"
        static let legacyCompleted = "fixedPlanCompletedV2"
        static let legacyCompletionDay = "fixedPlanCompletionDayV1"
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now

        let date = now()
        let dayKey = Self.dayKey(date, calendar: calendar)
        if let data = defaults.data(forKey: Key.schedules),
           let decoded = try? JSONDecoder().decode([ScheduledGoal].self, from: data) {
            schedules = decoded
            if let completionData = defaults.data(forKey: Key.completion),
               let decodedCompletion = try? JSONDecoder().decode(ScheduleCompletionState.self, from: completionData) {
                completion = ScheduledGoalLogic.refreshedCompletion(decodedCompletion, dayKey: dayKey)
            } else {
                completion = ScheduleCompletionState(dayKey: dayKey)
            }
        } else {
            let legacyPlans: [FixedDayPlan]
            if let data = defaults.data(forKey: Key.legacyPlans),
               let decoded = try? JSONDecoder().decode([FixedDayPlan].self, from: data) {
                legacyPlans = decoded
            } else {
                legacyPlans = FixedPlanModel.defaults
            }
            let legacyCompleted = defaults.string(forKey: Key.legacyCompletionDay) == dayKey
                && defaults.bool(forKey: Key.legacyCompleted)
            let migrated = ScheduleMigration.migrate(
                plans: legacyPlans,
                todayWeekday: calendar.component(.weekday, from: date),
                todayCompleted: legacyCompleted
            )
            schedules = migrated.schedules
            completion = ScheduleCompletionState(dayKey: dayKey, completedIDs: migrated.completedIDs)
            defaults.set(true, forKey: Key.migration)
        }
        persist()
    }

    var today: [ScheduledGoal] {
        refreshDayBoundary()
        return ScheduledGoalLogic.active(
            schedules,
            weekday: calendar.component(.weekday, from: now())
        )
    }

    var todayCompletedCount: Int {
        today.filter { completion.completedIDs.contains($0.id) }.count
    }

    func isCompleted(_ schedule: ScheduledGoal) -> Bool {
        refreshDayBoundary()
        return completion.completedIDs.contains(schedule.id)
    }

    func toggleCompletion(_ schedule: ScheduledGoal) {
        refreshDayBoundary()
        if completion.completedIDs.contains(schedule.id) {
            completion.completedIDs.remove(schedule.id)
        } else {
            completion.completedIDs.insert(schedule.id)
        }
        persistCompletion()
    }

    @discardableResult
    func add(title: String, tag: String, note: String, weekdays: Set<Int>) -> UUID? {
        guard ScheduledGoalLogic.canSave(title: title, weekdays: weekdays) else { return nil }
        let schedule = ScheduledGoal(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            tag: tag,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            weekdays: ScheduledGoalLogic.normalizedWeekdays(weekdays)
        )
        schedules.append(schedule)
        persistSchedules()
        return schedule.id
    }

    func update(
        _ schedule: ScheduledGoal,
        title: String? = nil,
        tag: String? = nil,
        note: String? = nil,
        weekdays: Set<Int>? = nil
    ) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        if let title { schedules[index].title = title }
        if let tag { schedules[index].tag = tag }
        if let note { schedules[index].note = note }
        if let weekdays {
            let normalized = ScheduledGoalLogic.normalizedWeekdays(weekdays)
            if !normalized.isEmpty { schedules[index].weekdays = normalized }
        }
        persistSchedules()
    }

    func delete(_ schedule: ScheduledGoal) {
        schedules.removeAll { $0.id == schedule.id }
        completion.completedIDs.remove(schedule.id)
        persist()
    }

    func refreshDayBoundary() {
        let key = Self.dayKey(now(), calendar: calendar)
        let refreshed = ScheduledGoalLogic.refreshedCompletion(completion, dayKey: key)
        guard refreshed != completion else { return }
        completion = refreshed
        persistCompletion()
    }

    private func persist() {
        persistSchedules()
        persistCompletion()
    }

    private func persistSchedules() {
        defaults.set(try? JSONEncoder().encode(schedules), forKey: Key.schedules)
    }

    private func persistCompletion() {
        defaults.set(try? JSONEncoder().encode(completion), forKey: Key.completion)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
