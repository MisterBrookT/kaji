import XCTest
@testable import Kaji

final class AIHotAPIClientTests: XCTestCase {
    override func tearDown() {
        AIHotURLProtocol.handler = nil
        super.tearDown()
    }

    func testHotTopicsSendsIdentityAndConditionalETag() async throws {
        AIHotURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://aihot.virxact.com/api/v1/hot-topics")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "old-tag")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Kaji/0.6 (+https://github.com/blackblue-labs/kaji)")
            let response = HTTPURLResponse(url: request.url!, statusCode: 304, httpVersion: nil,
                                           headerFields: ["ETag": "new-tag", "Cache-Control": "s-maxage=300"])!
            return (response, Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AIHotURLProtocol.self]
        let result = try await AIHotAPIClient(session: URLSession(configuration: config)).hotTopics(etag: "old-tag")
        XCTAssertEqual(result.statusCode, 304)
        XCTAssertEqual(result.etag, "new-tag")
        XCTAssertNil(result.value)
    }

    func testRateLimitResponsePreservesRetryAfterWithoutDecodingProblemBody() async throws {
        AIHotURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                           headerFields: ["Retry-After": "23"])!
            return (response, Data(#"{"title":"rate limited"}"#.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AIHotURLProtocol.self]
        let result = try await AIHotAPIClient(session: URLSession(configuration: config)).hotTopics(etag: nil)
        XCTAssertEqual(result.retryAfter, "23")
        XCTAssertNil(result.value)
    }
}

private final class AIHotURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
