import XCTest
import KajiCore

final class AIHotCacheTests: XCTestCase {
    func testPruneRetainsOnlyThirtyDayEntries() {
        let now = Date(timeIntervalSince1970: 4_000_000)
        let url = URL(string: "https://aihot.virxact.com/story")!
        let story = AIHotStory(publicID: "s", title: "t", latest: "l", digest: nil,
                               digestUpdatedAt: nil, sourceCount: 1, latestAt: now, aiHotURL: url)
        var cache = AIHotCache(stories: [
            "old": .init(story: story, etag: nil, lastAccessedAt: now.addingTimeInterval(-31 * 86400)),
            "new": .init(story: story, etag: nil, lastAccessedAt: now)
        ], readEntries: [
            .init(topicID: "old", lastSeenAt: now.addingTimeInterval(-31 * 86400)),
            .init(topicID: "new", lastSeenAt: now)
        ])
        cache.prune(now: now)
        XCTAssertEqual(Set(cache.stories.keys), ["new"])
        XCTAssertEqual(cache.readEntries.map(\.topicID), ["new"])
    }
}
