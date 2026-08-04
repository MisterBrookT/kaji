import XCTest
import KajiCore

final class AIHotModelsTests: XCTestCase {
    func testValidFixturePreservesOrderAndExtractsStoryPathSegment() throws {
        let data = Data(#"{"schemaVersion":1,"count":2,"items":[{"rank":2,"id":"b","title":"Second","source":{"name":"Beta"},"links":{"aihot":"https://aihot.virxact.com/hot/b","original":"https://example.com/b"},"sourceCount":2,"signalCount":4,"sourceNames":["Beta","B2"],"latestAt":"2026-08-05T01:02:03Z"},{"rank":1,"id":"a","title":"First","source":{"name":"Alpha"},"links":{"aihot":"https://aihot.virxact.com/hot/a","original":"https://example.com/a","story":"https://aihot.virxact.com/stories/story-public-1"},"sourceCount":3,"signalCount":5,"sourceNames":["Alpha"],"latestAt":"2026-08-05T02:02:03.123Z","future":"ok"}]}"#.utf8)
        let topics = try AIHotDecoder.topics(from: data)
        XCTAssertEqual(topics.map(\.rank), [2, 1])
        XCTAssertEqual(topics[0].sourceCount, 2)
        XCTAssertNil(topics[0].storyPublicID)
        XCTAssertEqual(topics[1].storyPublicID, "story-public-1")
    }

    func testMalformedItemIsSkippedWithoutClearingValidItems() throws {
        let data = Data(#"{"items":[{"rank":1,"id":"ok","title":"Good","source":{"name":"A"},"links":{"aihot":"https://aihot.virxact.com/x","original":"https://example.com/x"},"latestAt":"2026-08-05T00:00:00Z"},{"rank":2,"id":"bad","title":"Bad","source":{"name":"B"},"links":{"aihot":"not-a-url","original":"https://example.com"},"latestAt":"oops"}]}"#.utf8)
        XCTAssertEqual(try AIHotDecoder.topics(from: data).map(\.id), ["ok"])
    }
}
