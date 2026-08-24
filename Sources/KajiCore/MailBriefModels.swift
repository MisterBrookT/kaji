import Foundation

public enum MailBriefBucket: String, Codable, Sendable { case act, watch, quiet }
public enum MailBriefAction: String, Codable, Sendable { case reply, createGoal, watch, none }
public enum MailBriefConfidence: String, Codable, Sendable { case low, medium, high }

public enum MailBriefRunTrigger: String, Codable, Sendable { case automatic, manual, catchUp }
public enum MailBriefRunStatus: String, Codable, Sendable { case running, succeeded, failed, cancelled }
public enum MailBriefRunStage: String, Codable, Sendable {
    case connecting, fetching, classifying, publishing, finished
}

public struct MailBriefRunRecord: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let id: UUID
    public let trigger: MailBriefRunTrigger
    public let startedAt: Date
    public var finishedAt: Date?
    public var status: MailBriefRunStatus
    public var stage: MailBriefRunStage
    public let modelID: String
    public let batchSize: Int
    public let concurrency: Int
    public var snapshotInboxCount: Int?
    public var newOrChangedCount: Int?
    public var reusedCount: Int?
    public var classifiedCount: Int
    public var publishedCount: Int?
    public var safeErrorCode: String?

    public init(id: UUID = UUID(), trigger: MailBriefRunTrigger, startedAt: Date = Date(),
                finishedAt: Date? = nil, status: MailBriefRunStatus = .running,
                stage: MailBriefRunStage = .connecting, modelID: String, batchSize: Int,
                concurrency: Int, snapshotInboxCount: Int? = nil,
                newOrChangedCount: Int? = nil, reusedCount: Int? = nil,
                classifiedCount: Int = 0, publishedCount: Int? = nil,
                safeErrorCode: String? = nil) {
        self.schemaVersion = Self.currentSchemaVersion; self.id = id; self.trigger = trigger
        self.startedAt = startedAt; self.finishedAt = finishedAt; self.status = status; self.stage = stage
        self.modelID = modelID; self.batchSize = batchSize; self.concurrency = concurrency
        self.snapshotInboxCount = snapshotInboxCount; self.newOrChangedCount = newOrChangedCount
        self.reusedCount = reusedCount; self.classifiedCount = classifiedCount
        self.publishedCount = publishedCount; self.safeErrorCode = safeErrorCode
    }
}

public enum MailBriefRunHistory {
    public static let limit = 7

    public static func normalized(_ records: [MailBriefRunRecord], now: Date = Date()) -> [MailBriefRunRecord] {
        var seen = Set<UUID>()
        return records.sorted { $0.startedAt > $1.startedAt }.compactMap { value in
            guard seen.insert(value.id).inserted else { return nil }
            var record = value
            if record.status == .running {
                record.status = .cancelled; record.stage = .finished; record.finishedAt = now
                record.safeErrorCode = "interrupted"
            }
            return record
        }.prefix(limit).map { $0 }
    }

    public static func upserting(_ record: MailBriefRunRecord,
                                 into records: [MailBriefRunRecord]) -> [MailBriefRunRecord] {
        Array(([record] + records.filter { $0.id != record.id })
            .sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }
}

public enum MailBriefModel: String, Codable, CaseIterable, Sendable {
    case spark = "gpt-5.3-codex-spark"
    case luna = "gpt-5.6-luna"

    public static let defaultValue: Self = .spark
    public var displayName: String {
        switch self {
        case .spark: "GPT-5.3 Codex Spark"
        case .luna: "GPT-5.6 Luna"
        }
    }
    public static func normalize(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? defaultValue
    }
}

public struct MailBriefMessage: Codable, Equatable, Sendable {
    public let sender: String
    public let sentAt: Date
    public let body: String
    public init(sender: String, sentAt: Date, body: String) {
        self.sender = sender; self.sentAt = sentAt; self.body = body
    }
}

public struct MailBriefCandidate: Codable, Equatable, Sendable {
    public let threadID: String
    public let subject: String
    public let participants: [String]
    public let messages: [MailBriefMessage]
    public let isImportant: Bool
    public let isStarred: Bool
    public let directlyAddressed: Bool
    public let changedAt: Date
    public init(threadID: String, subject: String, participants: [String], messages: [MailBriefMessage],
                isImportant: Bool, isStarred: Bool, directlyAddressed: Bool, changedAt: Date) {
        self.threadID = threadID; self.subject = subject; self.participants = participants
        self.messages = messages; self.isImportant = isImportant; self.isStarred = isStarred
        self.directlyAddressed = directlyAddressed; self.changedAt = changedAt
    }
}

public struct MailBriefEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { threadID }
    public let threadID: String
    public let subject: String
    public let sender: String
    public let gmailURL: URL?
    public let level: Int
    public let bucket: MailBriefBucket
    public let summaryZH: String
    public let reasonZH: String
    public let suggestedAction: MailBriefAction
    public let deadline: Date?
    public let confidence: MailBriefConfidence
    public let goalTitleZH: String?
    public var changedAt: Date?
    public var isStarred: Bool?
    public init(threadID: String, subject: String, sender: String, gmailURL: URL?, level: Int,
                bucket: MailBriefBucket, summaryZH: String, reasonZH: String,
                suggestedAction: MailBriefAction, deadline: Date?, confidence: MailBriefConfidence,
                goalTitleZH: String?, changedAt: Date? = nil, isStarred: Bool? = nil) {
        self.threadID = threadID; self.subject = subject; self.sender = sender; self.gmailURL = gmailURL
        self.level = min(3, max(0, level)); self.bucket = bucket; self.summaryZH = summaryZH
        self.reasonZH = reasonZH; self.suggestedAction = suggestedAction; self.deadline = deadline
        self.confidence = confidence; self.goalTitleZH = goalTitleZH
        self.changedAt = changedAt; self.isStarred = isStarred
    }
}

public struct MailBriefGeneration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let generationID: UUID
    public let briefDay: String
    public let createdAt: Date
    public var entries: [MailBriefEntry]
    public var dismissedThreadIDs: Set<String>
    public var convertedGoalIDs: [String: UUID]
    public var archivedThreadIDs: Set<String>
    public var trashedThreadIDs: Set<String>
    public var snapshotInboxThreadCount: Int
    public var isComplete: Bool?
    public var classifierModelID: String?
    public let overflowCount: Int
    public init(generationID: UUID = UUID(), briefDay: String, createdAt: Date = Date(), entries: [MailBriefEntry],
                dismissedThreadIDs: Set<String> = [], convertedGoalIDs: [String: UUID] = [:],
                archivedThreadIDs: Set<String> = [], trashedThreadIDs: Set<String> = [],
                snapshotInboxThreadCount: Int? = nil, isComplete: Bool? = true,
                classifierModelID: String? = nil, overflowCount: Int = 0) {
        self.schemaVersion = Self.currentSchemaVersion; self.generationID = generationID; self.briefDay = briefDay
        self.createdAt = createdAt; self.entries = entries; self.dismissedThreadIDs = dismissedThreadIDs
        self.convertedGoalIDs = convertedGoalIDs; self.archivedThreadIDs = archivedThreadIDs
        self.trashedThreadIDs = trashedThreadIDs
        self.snapshotInboxThreadCount = snapshotInboxThreadCount ?? entries.count
        self.isComplete = isComplete
        self.classifierModelID = classifierModelID
        self.overflowCount = overflowCount
    }
}

public struct MailBriefSection: Equatable, Sendable {
    public let level: Int
    public let entries: [MailBriefEntry]
}

public enum MailBriefPresentation {
    public static func sections(entries: [MailBriefEntry], dismissedIDs: Set<String>,
                                archivedIDs: Set<String> = [], trashedIDs: Set<String> = []) -> [MailBriefSection] {
        (0...3).reversed().compactMap { level in
            let values = entries.filter {
                $0.level == level && !dismissedIDs.contains($0.threadID)
                    && !archivedIDs.contains($0.threadID) && !trashedIDs.contains($0.threadID)
            }.sorted {
                if ($0.isStarred ?? false) != ($1.isStarred ?? false) { return $0.isStarred ?? false }
                return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
            }
            return values.isEmpty ? nil : MailBriefSection(level: level, entries: values)
        }
    }

    public static func actCount(entries: [MailBriefEntry], dismissedIDs: Set<String>,
                                archivedIDs: Set<String> = [], trashedIDs: Set<String> = []) -> Int {
        entries.filter { $0.bucket == .act && !dismissedIDs.contains($0.threadID)
            && !archivedIDs.contains($0.threadID) && !trashedIDs.contains($0.threadID) }.count
    }
}

public enum MailBriefCandidatePolicy {
    public struct Selection: Equatable, Sendable {
        public let selected: [MailBriefCandidate]
        public let overflowCount: Int
    }
    public static func select(_ candidates: [MailBriefCandidate], limit: Int = 100) -> Selection {
        let sorted = candidates.sorted {
            let lhs = ($0.isImportant ? 4 : 0) + ($0.isStarred ? 2 : 0) + ($0.directlyAddressed ? 1 : 0)
            let rhs = ($1.isImportant ? 4 : 0) + ($1.isStarred ? 2 : 0) + ($1.directlyAddressed ? 1 : 0)
            return lhs == rhs ? $0.changedAt > $1.changedAt : lhs > rhs
        }
        let bounded = max(0, limit)
        return Selection(selected: Array(sorted.prefix(bounded)), overflowCount: max(0, sorted.count - bounded))
    }
}

public enum MailBriefBatchPolicy {
    public static let allowedBatchSizes = [5, 10, 20, 50, 100]
    public static let allowedConcurrency = Array(1...4)
    public static func batchSize(_ value: Int) -> Int {
        allowedBatchSizes.min(by: { abs($0 - value) < abs($1 - value) }) ?? 10
    }
    public static func concurrency(_ value: Int) -> Int { min(4, max(1, value)) }
}
