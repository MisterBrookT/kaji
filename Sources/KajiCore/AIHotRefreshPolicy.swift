import Foundation

public enum HoverDisclosurePolicy {
    public static let initialOpenDelay: TimeInterval = 0.10
    public static let transitionDelay: TimeInterval = 0
    public static let closeDelay: TimeInterval = 0.35

    public static func openDelay(hasActiveTopic: Bool) -> TimeInterval {
        hasActiveTopic ? transitionDelay : initialOpenDelay
    }
}

public enum HoverSelectionPolicy {
    public static func dismissed<ID: Equatable>(current: ID?, dismissing: ID) -> ID? {
        current == dismissing ? nil : current
    }
}

public enum GoalControlMetrics {
    public static let diameter: CGFloat = 9
    public static let rowIsCompletionTarget = true
}

public enum AIHotRefreshPolicy {
    public static let allowedHours = [1, 3, 5, 12, 24]
    public static let defaultHours = 5
    public static let serverFreshnessFloor: TimeInterval = 300
    public static func normalize(hours: Int) -> Int { allowedHours.contains(hours) ? hours : defaultHours }
    public static func dueDate(lastSuccessfulRefresh: Date?, hours: Int, now: Date) -> Date {
        guard let lastSuccessfulRefresh else { return now }
        return lastSuccessfulRefresh.addingTimeInterval(TimeInterval(normalize(hours: hours) * 3600))
    }
    public static func shouldRefresh(hasCache: Bool, lastSuccessfulRefresh: Date?, hours: Int, now: Date) -> Bool {
        !hasCache || dueDate(lastSuccessfulRefresh: lastSuccessfulRefresh, hours: hours, now: now) <= now
    }
    public static func retryDelay(statusCode: Int, retryAfter: String?, attempt: Int) -> TimeInterval? {
        if statusCode == 429 || statusCode == 503 {
            guard attempt == 0, let retryAfter, let seconds = TimeInterval(retryAfter), seconds > 0 else { return nil }
            return seconds
        }
        if statusCode >= 500 || statusCode == 0 { return attempt == 0 ? 2 : nil }
        return nil
    }
}
