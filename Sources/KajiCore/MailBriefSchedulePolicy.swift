import Foundation

public enum MailBriefSchedulePolicy {
    public struct Decision: Equatable, Sendable {
        public let isDue: Bool
        public let nextDue: Date
        public let briefDay: String
    }

    public static func decision(now: Date, hour: Int, minute: Int, calendar: Calendar,
                                lastAutomaticSuccess: Date?) -> Decision {
        let h = min(23, max(0, hour)); let m = min(59, max(0, minute))
        let start = calendar.startOfDay(for: now)
        let todayDue = calendar.date(bySettingHour: h, minute: m, second: 0, of: start) ?? start
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let succeededToday = lastAutomaticSuccess.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        let twelveHourGuard = lastAutomaticSuccess.map { now.timeIntervalSince($0) < 12 * 3600 } ?? false
        let due = now >= todayDue && !succeededToday && !twelveHourGuard
        let next = due ? todayDue : (now < todayDue ? todayDue : calendar.date(byAdding: .day, value: 1, to: todayDue) ?? todayDue)
        return Decision(isDue: due, nextDue: next, briefDay: formatter.string(from: now))
    }

    public static func nextAttemptAfterFailure(
        now: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        decision(
            now: now,
            hour: hour,
            minute: minute,
            calendar: calendar,
            lastAutomaticSuccess: now
        ).nextDue
    }
}

