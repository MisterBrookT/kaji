import Foundation

public struct AIHotTopic: Codable, Identifiable, Equatable, Sendable {
    public let rank: Int
    public let id: String
    public let title: String
    public let sourceName: String
    public let sourceCount: Int
    public let signalCount: Int
    public let sourceNames: [String]
    public let latestAt: Date
    public let aiHotURL: URL
    public let originalURL: URL
    public let storyPublicID: String?

    public init(rank: Int, id: String, title: String, sourceName: String, sourceCount: Int,
                signalCount: Int, sourceNames: [String], latestAt: Date, aiHotURL: URL,
                originalURL: URL, storyPublicID: String?) {
        self.rank = rank; self.id = id; self.title = title; self.sourceName = sourceName
        self.sourceCount = sourceCount; self.signalCount = signalCount; self.sourceNames = sourceNames
        self.latestAt = latestAt; self.aiHotURL = aiHotURL; self.originalURL = originalURL
        self.storyPublicID = storyPublicID
    }
}

public struct AIHotStory: Codable, Equatable, Sendable {
    public let publicID: String
    public let title: String
    public let latest: String
    public let digest: String?
    public let digestUpdatedAt: Date?
    public let sourceCount: Int
    public let latestAt: Date
    public let aiHotURL: URL
    public init(publicID: String, title: String, latest: String, digest: String?, digestUpdatedAt: Date?,
                sourceCount: Int, latestAt: Date, aiHotURL: URL) {
        self.publicID = publicID; self.title = title; self.latest = latest; self.digest = digest
        self.digestUpdatedAt = digestUpdatedAt; self.sourceCount = sourceCount
        self.latestAt = latestAt; self.aiHotURL = aiHotURL
    }
}

public enum AIHotDecoder {
    private struct Source: Decodable { let name: String }
    private struct Links: Decodable { let aihot: URL?; let original: URL?; let story: URL? }
    private struct TopicDTO: Decodable {
        let rank: Int?; let id: String?; let title: String?; let source: Source?; let links: Links?
        let sourceCount: Int?; let signalCount: Int?; let sourceNames: [String]?; let latestAt: Date?
    }
    private struct TopicsEnvelope: Decodable { let items: [Failable<TopicDTO>] }
    private struct StoryEnvelope: Decodable { let story: StoryDTO }
    private struct StoryDTO: Decodable {
        let publicId: String; let title: String; let latest: String; let digest: String?
        let digestUpdatedAt: Date?; let sourceCount: Int; let latestAt: Date; let links: Links
    }
    private struct Failable<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
        }
        return decoder
    }

    public static func topics(from data: Data) throws -> [AIHotTopic] {
        try decoder().decode(TopicsEnvelope.self, from: data).items.compactMap { item in
            guard let dto = item.value, let rank = dto.rank, (1...10).contains(rank),
                  let id = dto.id, !id.isEmpty, let title = dto.title, !title.isEmpty,
                  let source = dto.source, let links = dto.links, let aiHotURL = links.aihot,
                  let originalURL = links.original, aiHotURL.scheme == "https", originalURL.scheme == "https",
                  let latestAt = dto.latestAt else { return nil }
            let storyID = links.story?.pathComponents.last.flatMap { $0 == "/" || $0.isEmpty ? nil : $0 }
            return AIHotTopic(rank: rank, id: id, title: title, sourceName: source.name,
                              sourceCount: dto.sourceCount ?? 0, signalCount: dto.signalCount ?? 0,
                              sourceNames: dto.sourceNames ?? [], latestAt: latestAt, aiHotURL: aiHotURL,
                              originalURL: originalURL, storyPublicID: storyID)
        }
    }

    public static func story(from data: Data) throws -> AIHotStory {
        let value = try decoder().decode(StoryEnvelope.self, from: data).story
        guard let url = value.links.aihot, url.scheme == "https" else { throw URLError(.badURL) }
        return AIHotStory(publicID: value.publicId, title: value.title, latest: value.latest,
                          digest: value.digest, digestUpdatedAt: value.digestUpdatedAt,
                          sourceCount: value.sourceCount, latestAt: value.latestAt, aiHotURL: url)
    }
}
