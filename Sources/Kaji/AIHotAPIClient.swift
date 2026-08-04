import Foundation
import KajiCore

struct AIHotResponse<Value> {
    let value: Value?
    let statusCode: Int
    let etag: String?
    let cacheControl: String?
    let retryAfter: String?
}

final class AIHotAPIClient: @unchecked Sendable {
    static let baseURL = URL(string: "https://aihot.virxact.com/api/v1/")!
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func hotTopics(etag: String?) async throws -> AIHotResponse<[AIHotTopic]> {
        var request = request(path: "hot-topics", etag: etag)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request, delegate: AIHotRedirectDelegate(allowsStoryRedirect: false))
        let http = try validated(response, expectedPathPrefix: "/api/v1/hot-topics")
        let topics = http.statusCode == 200 ? try AIHotDecoder.topics(from: data) : nil
        return responseValue(topics, http)
    }

    func story(publicID: String, etag: String?) async throws -> AIHotResponse<AIHotStory> {
        let safeID = publicID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let (data, response) = try await session.data(for: request(path: "stories/\(safeID)", etag: etag),
                                                      delegate: AIHotRedirectDelegate(allowsStoryRedirect: true))
        let http = try validated(response, expectedPathPrefix: "/api/v1/stories/")
        let story = http.statusCode == 200 ? try AIHotDecoder.story(from: data) : nil
        return responseValue(story, http)
    }

    private func request(path: String, etag: String?) -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.setValue("Kaji/0.6 (+https://github.com/blackblue-labs/kaji)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        return request
    }

    private func validated(_ response: URLResponse, expectedPathPrefix: String) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse, let url = http.url,
              url.scheme == "https", url.host == "aihot.virxact.com",
              url.path.hasPrefix(expectedPathPrefix) else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 || http.statusCode == 304 || http.statusCode == 429 ||
                http.statusCode == 503 || (500...599).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return http
    }

    private func responseValue<Value>(_ value: Value?, _ http: HTTPURLResponse) -> AIHotResponse<Value> {
        AIHotResponse(value: value, statusCode: http.statusCode,
                      etag: http.value(forHTTPHeaderField: "ETag"),
                      cacheControl: http.value(forHTTPHeaderField: "Cache-Control"),
                      retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
}

private final class AIHotRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowsStoryRedirect: Bool
    private var followed = false
    init(allowsStoryRedirect: Bool) { self.allowsStoryRedirect = allowsStoryRedirect }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard allowsStoryRedirect, !followed, response.statusCode == 308,
              let url = request.url, url.scheme == "https", url.host == "aihot.virxact.com",
              url.path.hasPrefix("/api/v1/stories/") else {
            completionHandler(nil); return
        }
        followed = true
        completionHandler(request)
    }
}
