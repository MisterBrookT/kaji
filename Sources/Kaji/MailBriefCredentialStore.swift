import Foundation
import Security
import LocalAuthentication

struct MailBriefOAuthCredential: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var account: String?
    var scopes: [String]?
}

final class MailBriefCredentialCache: @unchecked Sendable {
    private enum State {
        case empty
        case absent
        case loaded(MailBriefOAuthCredential)
    }
    private let lock = NSLock()
    private var state: State = .empty

    func value(load: () throws -> MailBriefOAuthCredential) throws -> MailBriefOAuthCredential {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .loaded(let value):
            return value
        case .absent:
            throw MailBriefError.notConnected
        case .empty:
            do {
                let value = try load()
                state = .loaded(value)
                return value
            } catch MailBriefError.notConnected {
                state = .absent
                throw MailBriefError.notConnected
            } catch {
                // Access and transient Keychain failures must remain retryable.
                throw error
            }
        }
    }

    func store(_ value: MailBriefOAuthCredential?) {
        lock.withLock { state = value.map(State.loaded) ?? .absent }
    }

    func invalidate() {
        lock.withLock { state = .empty }
    }
}

enum MailBriefCredentialStatus: Equatable {
    case absent
    case unavailable
    case present(account: String?, canModify: Bool)
    case needsGoogleReauthorization
}

enum KeychainInteractionScope {
    private static let lock = NSRecursiveLock()

    static func run<T>(allowed: Bool, _ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        var previous = DarwinBoolean(false)
        SecKeychainGetUserInteractionAllowed(&previous)
        SecKeychainSetUserInteractionAllowed(allowed)
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return try operation()
    }
}
private final class MailBriefReauthorizationState: @unchecked Sendable {
    private let lock = NSLock()
    private var required = false

    func read() -> Bool { lock.withLock { required } }
    func set(_ value: Bool) { lock.withLock { required = value } }
}


enum MailBriefCredentialStore {
    private static let service = "dev.kaji.mail-brief.gmail"
    private static let credentialAccount = "oauth-credential-v3"
    private static let previousCredentialAccount = "oauth-credential-v2"
    private static let legacyCredentialAccount = "oauth-credential-v1"
    private static let cache = MailBriefCredentialCache()
    private static let reauthorizationState = MailBriefReauthorizationState()

    enum AuthorizationStatus: Equatable {
        case authorized
        case notAuthorized
        case needsReauthorization
    }

    static func status() -> MailBriefCredentialStatus {
        if reauthorizationState.read() {
            return .needsGoogleReauthorization
        }
        do {
            let value = try credential()
            return .present(
                account: value.account,
                canModify: value.scopes?.contains(MailBriefOAuthFlow.modifyScope) ?? false
            )
        } catch MailBriefError.notConnected {
            return .absent
        } catch {
            return .unavailable
        }
    }

    static func authorizationStatus() -> AuthorizationStatus {
        cache.invalidate()
        switch status() {
        case .present: return .authorized
        case .absent: return .notAuthorized
        case .unavailable, .needsGoogleReauthorization: return .needsReauthorization
        }
    }

    static func authorizeAccess() throws {
        try KeychainInteractionScope.run(allowed: true) {
            guard let credential = try read(account: credentialAccount, allowsInteraction: true) else {
                throw MailBriefError.notConnected
            }
            // Rewriting is intentional: it replaces the stale ACL immediately after
            // the user's deliberate authorization.
            try write(credential, account: credentialAccount, allowsInteraction: true)
            cache.store(credential)
        }
    }
    static func credential() throws -> MailBriefOAuthCredential {
        try cache.value {
            try migratedCredential(
                read: { try read(account: $0) },
                write: { try write($0, account: credentialAccount) },
                deleteOld: { delete(account: $0) }
            )
        }
    }

    static func migratedCredential(
        read: (String) throws -> MailBriefOAuthCredential?,
        write: (MailBriefOAuthCredential) throws -> Void,
        deleteOld: (String) -> Void
    ) throws -> MailBriefOAuthCredential {
        if let value = try read(credentialAccount) { return value }
        for oldAccount in [previousCredentialAccount, legacyCredentialAccount] {
            if let old = try read(oldAccount) {
                try write(old)
                deleteOld(oldAccount)
                return old
            }
        }
        throw MailBriefError.notConnected
    }

    static func save(_ credential: MailBriefOAuthCredential) throws {
        try write(credential, account: credentialAccount)
        cache.store(credential)
        reauthorizationState.set(false)
    }

    static func validAccessToken(
        clientID: String,
        clientSecret: String,
        forceRefresh: Bool = false,
        session: URLSession = .shared
    ) async throws -> String {
        var value = try credential()
        if !forceRefresh, value.expiresAt.timeIntervalSinceNow > 120 { return value.accessToken }
        guard let refreshToken = value.refreshToken else {
            markNeedsGoogleReauthorization()
            throw MailBriefError.reauthorizationRequired
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form(["client_id": clientID, "client_secret": clientSecret,
                                 "refresh_token": refreshToken, "grant_type": "refresh_token"])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MailBriefError.transient("Gmail token refresh is temporarily unavailable")
        }
        guard let http = response as? HTTPURLResponse else {
            throw MailBriefError.transient("Gmail token refresh returned an invalid response")
        }
        if let refreshError = tokenRefreshError(statusCode: http.statusCode, data: data) {
            if case .reauthorizationRequired = refreshError {
                markNeedsGoogleReauthorization()
            }
            throw refreshError
        }
        guard let refreshed = try? JSONDecoder().decode(TokenRefresh.self, from: data) else {
            throw MailBriefError.transient("Gmail token refresh is temporarily unavailable")
        }
        value.accessToken = refreshed.accessToken
        value.expiresAt = Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
        try save(value)
        return value.accessToken
    }

    static func markNeedsGoogleReauthorization() {
        reauthorizationState.set(true)
    }
    static func tokenRefreshError(statusCode: Int, data: Data) -> MailBriefError? {
        if statusCode == 200 { return nil }
        if statusCode == 400,
           (try? JSONDecoder().decode(TokenRefreshError.self, from: data).error) == "invalid_grant" {
            return .reauthorizationRequired
        }
        return .transient("Gmail token refresh is temporarily unavailable")
    }


    static func disconnectByUser() {
        delete(account: credentialAccount)
        delete(account: previousCredentialAccount)
        delete(account: legacyCredentialAccount)
        cache.store(nil)
        reauthorizationState.set(false)
    }

    private static func read(account: String, allowsInteraction: Bool = false) throws -> MailBriefOAuthCredential? {
        try KeychainInteractionScope.run(allowed: allowsInteraction) {
            var query = query(account: account) as! [CFString: Any]
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
            if !allowsInteraction {
                query[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail
                let context = LAContext()
                context.interactionNotAllowed = true
                query[kSecUseAuthenticationContext] = context
            }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            return try decodedCredential(status: status, result: result)
        }
    }

    static func decodedCredential(status: OSStatus, result: CFTypeRef?) throws -> MailBriefOAuthCredential {
        if status == errSecInteractionNotAllowed || status == errSecUserCanceled ||
            status == errSecAuthFailed {
            throw MailBriefError.credentialUnavailable
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw MailBriefError.credentialUnavailable
        }
        return try JSONDecoder().decode(MailBriefOAuthCredential.self, from: data)
    }

    private static func write(_ credential: MailBriefOAuthCredential, account: String,
                              allowsInteraction: Bool = false) throws {
        try KeychainInteractionScope.run(allowed: allowsInteraction) {
            let data = try JSONEncoder().encode(credential)
            let itemQuery = query(account: account)
            var attributes: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            if isAdHocSigned { attributes[kSecAttrAccess] = try pathStableAccess() }

            let updateQuery = allowsInteraction ? itemQuery : nonInteractiveQuery(account: account)
            let updateStatus = SecItemUpdate(updateQuery, attributes as CFDictionary)
            switch writeAction(for: updateStatus) {
            case .complete:
                return
            case .add:
                break
            case .replace:
                let deleteQuery = allowsInteraction ? itemQuery : nonInteractiveQuery(account: account)
                let deleteStatus = SecItemDelete(deleteQuery)
                guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                    throw MailBriefError.oauth("Could not replace Gmail credential (\(deleteStatus))")
                }
            case .fail:
                throw MailBriefError.oauth("Could not update Gmail credential (\(updateStatus))")
            }

            var newItem = itemQuery as! [CFString: Any]
            attributes.forEach { newItem[$0.key] = $0.value }
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw MailBriefError.oauth("Could not save Gmail credential (\(addStatus))")
            }
        }
    }

    enum WriteAction: Equatable {
        case complete, add, replace, fail
    }

    static func writeAction(for updateStatus: OSStatus) -> WriteAction {
        switch updateStatus {
        case errSecSuccess: .complete
        case errSecItemNotFound: .add
        case errSecInteractionNotAllowed, errSecUserCanceled: .replace
        default: .fail
        }
    }

    private static func delete(account: String) {
        _ = KeychainInteractionScope.run(allowed: false) {
            SecItemDelete(nonInteractiveQuery(account: account))
        }
    }

    private static func nonInteractiveQuery(account: String) -> CFDictionary {
        var value = query(account: account) as! [CFString: Any]
        value[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail
        let context = LAContext()
        context.interactionNotAllowed = true
        value[kSecUseAuthenticationContext] = context
        return value as CFDictionary
    }

    private static var isAdHocSigned: Bool {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess, let dynamicCode else { return true }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
              let staticCode else { return true }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let values = information as? [CFString: Any],
              let flags = values[kSecCodeInfoFlags] as? NSNumber else { return true }
        let csAdhoc: UInt32 = 0x2 // CS_ADHOC from the Security framework's cs_blobs.h.
        return flags.uint32Value & csAdhoc != 0
    }

    // Ad-hoc builds have no stable signing identity. These narrowly scoped path
    // trusts cover Kaji's two real execution locations (installed and local dist)
    // across rebuilds, at the cost that another binary placed at either exact path
    // could read the credential. Truly permanent cross-version authorization
    // requires stable Developer ID signing via KAJI_CODESIGN_IDENTITY.
    private static func pathStableAccess() throws -> SecAccess {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let paths = [
            "/Applications/Kaji.app/Contents/MacOS/Kaji",
            sourceRoot.appendingPathComponent("dist/Kaji.app/Contents/MacOS/Kaji").path
        ]
        var trustedApplications: [SecTrustedApplication] = []
        for path in paths {
            var trustedApplication: SecTrustedApplication?
            let status = SecTrustedApplicationCreateFromPath(path, &trustedApplication)
            guard status == errSecSuccess, let trustedApplication else {
                throw MailBriefError.oauth("Could not create Kaji keychain trust (\(status))")
            }
            trustedApplications.append(trustedApplication)
        }
        var access: SecAccess?
        let accessStatus = SecAccessCreate("Kaji Gmail credential" as CFString,
                                           trustedApplications as CFArray, &access)
        guard accessStatus == errSecSuccess, let access else {
            throw MailBriefError.oauth("Could not create Kaji keychain access (\(accessStatus))")
        }
        return access
    }

    private static func query(account: String) -> CFDictionary {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
         kSecAttrAccount: account] as CFDictionary
    }

    private struct TokenRefresh: Decodable {
        let accessToken: String; let expiresIn: Int
        enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case expiresIn = "expires_in" }
    }
    private struct TokenRefreshError: Decodable {
        let error: String
    }
    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
}
