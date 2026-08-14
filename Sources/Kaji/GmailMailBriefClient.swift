import Foundation
import KajiCore

enum GmailThreadMutation: Sendable {
    case archive, unarchive, star, unstar, trash, untrash
}

struct GmailMailBriefClient {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchCandidates(accessToken: String) async throws -> [MailBriefCandidate] {
        var ids: [String] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads")!
            components.queryItems = [
                URLQueryItem(name: "q", value: "in:inbox -in:spam -in:trash"),
                URLQueryItem(name: "maxResults", value: "500")
            ]
            if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let data = try await request(url: components.url!, accessToken: accessToken)
            let list = try JSONDecoder().decode(ThreadList.self, from: data)
            ids.append(contentsOf: (list.threads ?? []).map(\.id))
            pageToken = list.nextPageToken
        } while pageToken != nil

        var values: [MailBriefCandidate] = []
        for id in ids {
            values.append(try await fetchThread(id, accessToken: accessToken))
        }
        return values
    }

    func mutate(threadID: String, mutation: GmailThreadMutation, accessToken: String) async throws {
        let escaped = threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadID
        switch mutation {
        case .trash, .untrash:
            let action = mutation == .trash ? "trash" : "untrash"
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(escaped)/\(action)")!
            _ = try await request(url: url, accessToken: accessToken, method: "POST", body: Data("{}".utf8))
        case .archive, .unarchive, .star, .unstar:
            let add: [String]
            let remove: [String]
            switch mutation {
            case .archive: add = []; remove = ["INBOX"]
            case .unarchive: add = ["INBOX"]; remove = []
            case .star: add = ["STARRED"]; remove = []
            case .unstar: add = []; remove = ["STARRED"]
            default: add = []; remove = []
            }
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(escaped)/modify")!
            let body = try JSONSerialization.data(withJSONObject: ["addLabelIds": add, "removeLabelIds": remove])
            _ = try await request(url: url, accessToken: accessToken, method: "POST", body: body)
        }
    }

    private func fetchThread(_ id: String, accessToken: String) async throws -> MailBriefCandidate {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(escaped)?format=full")!
        let data = try await request(url: url, accessToken: accessToken)
        let thread = try JSONDecoder().decode(GmailThread.self, from: data)
        guard let messages = thread.messages, let latest = messages.last else { throw MailBriefError.invalidResponse }
        let headers = latest.payload?.headers ?? []
        let subject = headers.first { $0.name.lowercased() == "subject" }?.value ?? "(No subject)"
        let sender = headers.first { $0.name.lowercased() == "from" }?.value ?? ""
        let labels = Set(messages.flatMap { $0.labelIds ?? [] })
        let mapped = messages.suffix(12).map {
            MailBriefMessage(sender: ($0.payload?.headers ?? []).first { $0.name.lowercased() == "from" }?.value ?? "",
                             sentAt: Date(timeIntervalSince1970: (Double($0.internalDate ?? "0") ?? 0) / 1000),
                             body: decodeBody($0.payload).prefixString(20_000))
        }
        return MailBriefCandidate(threadID: id, subject: subject, participants: [sender], messages: mapped,
                                  isImportant: labels.contains("IMPORTANT"), isStarred: labels.contains("STARRED"),
                                  directlyAddressed: true,
                                  changedAt: Date(timeIntervalSince1970: (Double(latest.internalDate ?? "0") ?? 0) / 1000))
    }

    private func request(url: URL, accessToken: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MailBriefError.invalidResponse
        }
        return data
    }

    private func decodeBody(_ payload: GmailPayload?) -> String {
        if let data = payload?.body?.data { return decodeBase64URL(data) }
        for part in payload?.parts ?? [] where part.mimeType == "text/plain" {
            if let data = part.body?.data { return decodeBase64URL(data) }
        }
        return ""
    }
    private func decodeBase64URL(_ value: String) -> String {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

private struct ThreadList: Decodable { let threads: [ThreadRef]?; let nextPageToken: String? }
private struct ThreadRef: Decodable { let id: String }
private struct GmailThread: Decodable { let messages: [GmailMessage]? }
private struct GmailMessage: Decodable { let internalDate: String?; let labelIds: [String]?; let payload: GmailPayload? }
private struct GmailPayload: Decodable { let mimeType: String?; let headers: [GmailHeader]?; let body: GmailBody?; let parts: [GmailPayload]? }
private struct GmailHeader: Decodable { let name: String; let value: String }
private struct GmailBody: Decodable { let data: String? }
private extension Substring { func prefixString(_ max: Int) -> String { String(prefix(max)) } }
private extension String { func prefixString(_ max: Int) -> String { String(prefix(max)) } }
