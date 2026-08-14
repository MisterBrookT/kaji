import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct MailBriefOAuthFlow {
    static let readScope = "https://www.googleapis.com/auth/gmail.readonly"
    static let modifyScope = "https://www.googleapis.com/auth/gmail.modify"
    let clientID: String
    let clientSecret: String
    let requestsModify: Bool

    @MainActor
    func connect() async throws {
        let state = Self.randomURLSafe(count: 24)
        let verifier = Self.randomURLSafe(count: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let receiver = try OAuthLoopbackReceiver()
        let callback = try await receiver.receive(expectedState: state) { redirectURI in
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: redirectURI),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: "openid email \(requestsModify ? Self.modifyScope : Self.readScope)"),
                .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state), .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "consent")
            ]
            guard let url = components.url else { return }
            NSWorkspace.shared.open(url)
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = MailBriefCredentialStore.form([
            "client_id": clientID, "client_secret": clientSecret,
            "code": callback.code, "code_verifier": verifier,
            "redirect_uri": callback.redirectURI, "grant_type": "authorization_code"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            let detail = (try? JSONDecoder().decode(TokenError.self, from: data))?.safeDescription
            throw MailBriefError.oauth(detail ?? "Google authorization failed")
        }
        let email = Self.email(fromIDToken: token.idToken)
        try MailBriefCredentialStore.save(.init(accessToken: token.accessToken, refreshToken: token.refreshToken,
                                                expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                                                account: email,
                                                scopes: (token.scope?.split(separator: " ").map(String.init))
                                                    ?? [requestsModify ? Self.modifyScope : Self.readScope]))
    }

    private struct TokenResponse: Decodable {
        let accessToken: String; let refreshToken: String?; let expiresIn: Int; let idToken: String?; let scope: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", idToken = "id_token", scope
        }
    }
    private struct TokenError: Decodable {
        let error: String
        let errorDescription: String?
        enum CodingKeys: String, CodingKey { case error; case errorDescription = "error_description" }
        var safeDescription: String {
            let allowed = (errorDescription ?? error).prefix(160)
            return "Google OAuth: \(allowed)"
        }
    }
    private static func randomURLSafe(count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded
    }
    private static func email(fromIDToken token: String?) -> String? {
        guard let part = token?.split(separator: ".").dropFirst().first,
              let data = Data(base64URL: String(part)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["email"] as? String
    }
}

private final class OAuthLoopbackReceiver: @unchecked Sendable {
    struct Callback { let code: String; let redirectURI: String }
    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.kaji.mail-oauth-loopback")
    private let lock = NSLock()
    private var finished = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func receive(expectedState: String, open: @escaping @MainActor (String) -> Void) async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener.port else { return }
                    let redirect = "http://127.0.0.1:\(port.rawValue)/oauth/callback"
                    Task { @MainActor in open(redirect) }
                    self.queue.asyncAfter(deadline: .now() + 180) {
                        self.complete(.failure(MailBriefError.oauth("Google authorization timed out")), continuation)
                    }
                case .failed:
                    self.complete(.failure(MailBriefError.oauth("Could not start OAuth callback")), continuation)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection, expectedState: expectedState, continuation: continuation)
            }
            listener.start(queue: queue)
        }
    }

    private func handle(_ connection: NWConnection, expectedState: String,
                        continuation: CheckedContinuation<Callback, Error>) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let target = request.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first,
                  let components = URLComponents(string: "http://127.0.0.1" + target),
                  components.path == "/oauth/callback" else {
                self?.respond(connection, status: "400 Bad Request", text: "Invalid callback")
                return
            }
            let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
            guard values["state"] == expectedState, let code = values["code"], let port = self.listener.port else {
                self.respond(connection, status: "400 Bad Request", text: "Authorization rejected")
                self.complete(.failure(MailBriefError.oauth("OAuth state validation failed")), continuation)
                return
            }
            self.respond(connection, status: "200 OK", text: "Authorization received. Return to Kaji to finish connecting Gmail.")
            self.complete(.success(.init(code: code, redirectURI: "http://127.0.0.1:\(port.rawValue)/oauth/callback")), continuation)
        }
    }

    private func respond(_ connection: NWConnection, status: String, text: String) {
        let body = Data(text.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
    private func complete(_ result: Result<Callback, Error>, _ continuation: CheckedContinuation<Callback, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }; finished = true; listener.cancel(); continuation.resume(with: result)
    }
}

private extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        var value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }
}

private func + (lhs: Data, rhs: Data) -> Data { var value = lhs; value.append(rhs); return value }
