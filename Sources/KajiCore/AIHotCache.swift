import Foundation

public struct AIHotStoryCacheEntry: Codable, Equatable, Sendable {
    public let story: AIHotStory
    public let etag: String?
    public let lastAccessedAt: Date
    public init(story: AIHotStory, etag: String?, lastAccessedAt: Date) {
        self.story = story; self.etag = etag; self.lastAccessedAt = lastAccessedAt
    }
}
public struct AIHotReadEntry: Codable, Equatable, Sendable {
    public let topicID: String
    public let lastSeenAt: Date
    public init(topicID: String, lastSeenAt: Date) { self.topicID = topicID; self.lastSeenAt = lastSeenAt }
}
public struct AIHotCache: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion = AIHotCache.currentSchemaVersion
    public var topics: [AIHotTopic]
    public var topicsETag: String?
    public var lastSuccessfulRefresh: Date?
    public var stories: [String: AIHotStoryCacheEntry]
    public var readEntries: [AIHotReadEntry]
    public init(topics: [AIHotTopic] = [], topicsETag: String? = nil, lastSuccessfulRefresh: Date? = nil,
                stories: [String: AIHotStoryCacheEntry] = [:], readEntries: [AIHotReadEntry] = []) {
        self.topics = topics; self.topicsETag = topicsETag; self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.stories = stories; self.readEntries = readEntries
    }
    public mutating func prune(now: Date, retention: TimeInterval = 30 * 24 * 3600) {
        let cutoff = now.addingTimeInterval(-retention)
        stories = stories.filter { $0.value.lastAccessedAt >= cutoff }
        readEntries = readEntries.filter { $0.lastSeenAt >= cutoff }
    }
}
