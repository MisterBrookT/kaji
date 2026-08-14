import XCTest
@testable import Kaji

final class GmailMailBriefClientTests: XCTestCase {
    override func tearDown() {
        GmailURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchPaginatesEntireInboxAndUsesInboxQuery() async throws {
        var listRequests = 0
        GmailURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path.hasSuffix("/threads") {
                listRequests += 1
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                XCTAssertEqual(query.first(where: { $0.name == "q" })?.value, "in:inbox -in:spam -in:trash")
                XCTAssertEqual(query.first(where: { $0.name == "maxResults" })?.value, "500")
                let hasPage = query.contains { $0.name == "pageToken" }
                let json = hasPage
                    ? #"{"threads":[{"id":"b"}]}"#
                    : #"{"threads":[{"id":"a"}],"nextPageToken":"next"}"#
                return Self.response(for: url, json: json)
            }
            let id = url.path.split(separator: "/").last.map(String.init) ?? ""
            return Self.response(for: url, json: Self.threadJSON(id: id))
        }
        let values = try await makeClient().fetchCandidates(accessToken: "token")
        XCTAssertEqual(listRequests, 2)
        XCTAssertEqual(Set(values.map(\.threadID)), ["a", "b"])
    }

    func testArchiveStarTrashAndUndoUseGmailThreadEndpoints() async throws {
        var requests: [(path: String, body: String)] = []
        GmailURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            requests.append((url.path, Self.bodyString(request)))
            return Self.response(for: url, json: "{}")
        }
        let client = makeClient()
        for mutation in [GmailThreadMutation.archive, .unarchive, .star, .unstar, .trash, .untrash] {
            try await client.mutate(threadID: "thread", mutation: mutation, accessToken: "token")
        }
        XCTAssertEqual(requests.map(\.path), [
            "/gmail/v1/users/me/threads/thread/modify", "/gmail/v1/users/me/threads/thread/modify",
            "/gmail/v1/users/me/threads/thread/modify", "/gmail/v1/users/me/threads/thread/modify",
            "/gmail/v1/users/me/threads/thread/trash", "/gmail/v1/users/me/threads/thread/untrash"
        ])
        XCTAssertTrue(requests[0].body.contains("INBOX"))
        XCTAssertTrue(requests[2].body.contains("STARRED"))
    }

    private func makeClient() -> GmailMailBriefClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GmailURLProtocol.self]
        return GmailMailBriefClient(session: URLSession(configuration: config))
    }

    private static func response(for url: URL, json: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
    }

    private static func threadJSON(id: String) -> String {
        #"{"id":"\#(id)","messages":[{"internalDate":"1000","labelIds":["INBOX"],"payload":{"headers":[{"name":"Subject","value":"Subject \#(id)"},{"name":"From","value":"sender@example.com"}],"body":{"data":"aGk="}}}]}"#
    }

    private static func bodyString(_ request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }; data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private final class GmailURLProtocol: URLProtocol, @unchecked Sendable {
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
