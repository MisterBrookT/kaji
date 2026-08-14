import Foundation
import Security

struct MailBriefOAuthCredential: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var account: String?
    var scopes: [String]?
}

enum MailBriefCredentialStore {
    private static let service = "dev.kaji.mail-brief.gmail"
    private static let credentialAccount = "oauth-credential-v1"

    static var hasCredential: Bool { (try? credential()) != nil }
    static var account: String? { try? credential().account }
    static var canModify: Bool { (try? credential().scopes?.contains(MailBriefOAuthFlow.modifyScope)) ?? false }

    static func credential() throws -> MailBriefOAuthCredential {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: credentialAccount, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = try? JSONDecoder().decode(MailBriefOAuthCredential.self, from: data) else {
            throw MailBriefError.notConnected
        }
        return value
    }

    static func save(_ credential: MailBriefOAuthCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                     kSecAttrAccount: credentialAccount] as CFDictionary
        SecItemDelete(query)
        var attributes = query as! [CFString: Any]
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw MailBriefError.oauth("Could not save Gmail credential")
        }
    }

    static func validAccessToken(clientID: String, clientSecret: String) async throws -> String {
        var value = try credential()
        if value.expiresAt.timeIntervalSinceNow > 120 { return value.accessToken }
        guard let refreshToken = value.refreshToken else { throw MailBriefError.notConnected }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["client_id": clientID, "client_secret": clientSecret,
                                 "refresh_token": refreshToken, "grant_type": "refresh_token"])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let refreshed = try? JSONDecoder().decode(TokenRefresh.self, from: data) else {
            throw MailBriefError.oauth("Gmail authorization expired; connect again")
        }
        value.accessToken = refreshed.accessToken
        value.expiresAt = Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
        try save(value)
        return value.accessToken
    }

    static func delete() {
        SecItemDelete([kSecClass: kSecClassGenericPassword,
                       kSecAttrService: service,
                       kSecAttrAccount: credentialAccount] as CFDictionary)
    }

    private struct TokenRefresh: Decodable {
        let accessToken: String; let expiresIn: Int
        enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case expiresIn = "expires_in" }
    }
    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
}
