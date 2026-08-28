import Foundation

public enum ExposureStudyEvent: String, Codable, CaseIterable, Sendable {
    case popoverOpen
    case quickSwitch
    case moreOpen
    case cantFind
}

public struct ExposureStudyDailyBucket: Codable, Equatable, Sendable {
    public let dayStartUTC: Date
    public var events: [ExposureStudyEvent: Int]
    public var moduleEntries: [KajiModuleID: Int]
    public var entriesBySource: [ExposureEntrySource: Int]
    public var maximumStatusWidth: Int

    public init(
        dayStartUTC: Date,
        events: [ExposureStudyEvent: Int] = [:],
        moduleEntries: [KajiModuleID: Int] = [:],
        entriesBySource: [ExposureEntrySource: Int] = [:],
        maximumStatusWidth: Int = 0
    ) {
        self.dayStartUTC = dayStartUTC
        self.events = events
        self.moduleEntries = moduleEntries
        self.entriesBySource = entriesBySource
        self.maximumStatusWidth = maximumStatusWidth
    }
}

public struct ExposureStudyRecord: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maximumDailyBuckets = 31

    public var version: Int
    public var experiment: ExposureExperimentState
    public var days: [ExposureStudyDailyBucket]

    public init(
        version: Int = currentVersion,
        experiment: ExposureExperimentState = .init(),
        days: [ExposureStudyDailyBucket] = []
    ) {
        self.version = version
        self.experiment = experiment
        self.days = Array(days.sorted { $0.dayStartUTC < $1.dayStartUTC }.suffix(Self.maximumDailyBuckets))
    }

    public mutating func record(
        event: ExposureStudyEvent,
        module: KajiModuleID? = nil,
        source: ExposureEntrySource? = nil,
        statusWidth: Int? = nil,
        now: Date
    ) {
        let day = Self.utcDayStart(now)
        if let index = days.firstIndex(where: { $0.dayStartUTC == day }) {
            updateBucket(at: index, event: event, module: module, source: source, statusWidth: statusWidth)
        } else {
            days.append(ExposureStudyDailyBucket(dayStartUTC: day))
            days.sort { $0.dayStartUTC < $1.dayStartUTC }
            if days.count > Self.maximumDailyBuckets {
                days.removeFirst(days.count - Self.maximumDailyBuckets)
            }
            guard let index = days.firstIndex(where: { $0.dayStartUTC == day }) else { return }
            updateBucket(at: index, event: event, module: module, source: source, statusWidth: statusWidth)
        }
    }

    private mutating func updateBucket(
        at index: Int,
        event: ExposureStudyEvent,
        module: KajiModuleID?,
        source: ExposureEntrySource?,
        statusWidth: Int?
    ) {
        days[index].events[event, default: 0] += 1
        if let module { days[index].moduleEntries[module, default: 0] += 1 }
        if let source { days[index].entriesBySource[source, default: 0] += 1 }
        if let statusWidth { days[index].maximumStatusWidth = max(days[index].maximumStatusWidth, statusWidth) }
    }

    public mutating func recordStatusWidth(_ width: Int, now: Date) {
        let day = Self.utcDayStart(now)
        if let index = days.firstIndex(where: { $0.dayStartUTC == day }) {
            days[index].maximumStatusWidth = max(days[index].maximumStatusWidth, width)
            return
        }
        days.append(ExposureStudyDailyBucket(dayStartUTC: day, maximumStatusWidth: width))
        days.sort { $0.dayStartUTC < $1.dayStartUTC }
        if days.count > Self.maximumDailyBuckets {
            days.removeFirst(days.count - Self.maximumDailyBuckets)
        }
    }

    public static func utcDayStart(_ date: Date) -> Date {
        let seconds = floor(date.timeIntervalSince1970 / 86_400) * 86_400
        return Date(timeIntervalSince1970: seconds)
    }
}
