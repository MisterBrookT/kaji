import Foundation
import XCTest
@testable import Kaji

final class MailBriefCredentialStoreTests: XCTestCase {
    private let credential = MailBriefOAuthCredential(
        accessToken: "access", refreshToken: "refresh",
        expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
        account: "user@example.com", scopes: [MailBriefOAuthFlow.readScope]
    )

    func testCacheLoadsOnlyOnce() throws {
        let cache = MailBriefCredentialCache()
        var loads = 0

        let first = try cache.value { loads += 1; return credential }
        let second = try cache.value { loads += 1; return credential }

        XCTAssertEqual(first, credential)
        XCTAssertEqual(second, credential)
        XCTAssertEqual(loads, 1)
    }

    func testCacheStoreAndInvalidate() throws {
        let cache = MailBriefCredentialCache()
        cache.store(credential)
        var loads = 0

        XCTAssertEqual(try cache.value { loads += 1; return credential }, credential)
        XCTAssertEqual(loads, 0)

        cache.invalidate()
        XCTAssertEqual(try cache.value { loads += 1; return credential }, credential)
        XCTAssertEqual(loads, 1)
    }

    func testMissingCredentialIsCachedUntilInvalidated() throws {
        let cache = MailBriefCredentialCache()
        var loads = 0
        let missing: () throws -> MailBriefOAuthCredential = {
            loads += 1
            throw MailBriefError.notConnected
        }

        XCTAssertThrowsError(try cache.value(load: missing))
        XCTAssertThrowsError(try cache.value(load: missing))
        XCTAssertEqual(loads, 1)

        cache.invalidate()
        XCTAssertThrowsError(try cache.value(load: missing))
        XCTAssertEqual(loads, 2)
    }

    func testV2CredentialMigratesToV3BeforeDeletion() throws {
        var reads: [String] = []
        var written: MailBriefOAuthCredential?
        var deleted: [String] = []

        let result = try MailBriefCredentialStore.migratedCredential(
            read: { account in
                reads.append(account)
                return account == "oauth-credential-v2" ? credential : nil
            },
            write: { written = $0 },
            deleteOld: { deleted.append($0) }
        )

        XCTAssertEqual(reads, ["oauth-credential-v3", "oauth-credential-v2"])
        XCTAssertEqual(written, credential)
        XCTAssertEqual(deleted, ["oauth-credential-v2"])
        XCTAssertEqual(result, credential)
    }

    func testV1CredentialMigratesToV3BeforeDeletion() throws {
        var reads: [String] = []
        var deleted: [String] = []

        let result = try MailBriefCredentialStore.migratedCredential(
            read: { account in
                reads.append(account)
                return account == "oauth-credential-v1" ? credential : nil
            },
            write: { _ in },
            deleteOld: { deleted.append($0) }
        )

        XCTAssertEqual(reads, ["oauth-credential-v3", "oauth-credential-v2", "oauth-credential-v1"])
        XCTAssertEqual(deleted, ["oauth-credential-v1"])
        XCTAssertEqual(result, credential)
    }

    @MainActor
    func testDisabledMailBriefStoreDoesNotReadCredentialStatus() {
        var reads = 0
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaji-disabled-mail-brief-\(UUID().uuidString).json")
        let store = MailBriefStore(cacheURL: cacheURL) {
            reads += 1
            return (true, "user@example.com", true)
        }

        XCTAssertFalse(store.isConnected)
        XCTAssertNil(store.accountLabel)
        XCTAssertFalse(store.canModify)
        XCTAssertEqual(reads, 0)
    }

    func testAuthenticationUIFailuresBecomeNotConnected() {
        for status in [errSecInteractionNotAllowed, errSecUserCanceled, errSecAuthFailed] {
            XCTAssertThrowsError(try MailBriefCredentialStore.decodedCredential(
                status: status, result: nil
            )) { error in
                guard case MailBriefError.notConnected = error else {
                    return XCTFail("Expected notConnected, got \(error)")
                }
            }
        }
    }

    func testAuthenticationUIFailureReplacesInaccessibleCredential() {
        XCTAssertEqual(MailBriefCredentialStore.writeAction(for: errSecInteractionNotAllowed),
                       .replace)
        XCTAssertEqual(MailBriefCredentialStore.writeAction(for: errSecUserCanceled),
                       .replace)
        XCTAssertEqual(MailBriefCredentialStore.writeAction(for: errSecItemNotFound),
                       .add)
        XCTAssertEqual(MailBriefCredentialStore.writeAction(for: errSecSuccess),
                       .complete)
    }

    func testInteractionScopeRestoresAfterNestedCalls() {
        var original = DarwinBoolean(false)
        SecKeychainGetUserInteractionAllowed(&original)

        KeychainInteractionScope.run(allowed: false) {
            var outer = DarwinBoolean(true)
            SecKeychainGetUserInteractionAllowed(&outer)
            XCTAssertFalse(outer.boolValue)
            KeychainInteractionScope.run(allowed: true) {
                var inner = DarwinBoolean(false)
                SecKeychainGetUserInteractionAllowed(&inner)
                XCTAssertTrue(inner.boolValue)
            }
            SecKeychainGetUserInteractionAllowed(&outer)
            XCTAssertFalse(outer.boolValue)
        }

        var restored = DarwinBoolean(false)
        SecKeychainGetUserInteractionAllowed(&restored)
        XCTAssertEqual(restored.boolValue, original.boolValue)
    }

    func testInteractionScopeRestoresWhenOperationThrows() {
        enum Expected: Error { case failure }
        var original = DarwinBoolean(false)
        SecKeychainGetUserInteractionAllowed(&original)

        XCTAssertThrowsError(try KeychainInteractionScope.run(allowed: false) {
            throw Expected.failure
        })

        var restored = DarwinBoolean(false)
        SecKeychainGetUserInteractionAllowed(&restored)
        XCTAssertEqual(restored.boolValue, original.boolValue)
    }

    func testConcurrentInteractionScopesLeaveOriginalState() {
        var original = DarwinBoolean(false)
        SecKeychainGetUserInteractionAllowed(&original)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "keychain-scope", attributes: .concurrent)
        for _ in 0..<20 {
            group.enter()
            queue.async {
                KeychainInteractionScope.run(allowed: false) {
                    var allowed = DarwinBoolean(true)
                    SecKeychainGetUserInteractionAllowed(&allowed)
                    XCTAssertFalse(allowed.boolValue)
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        var restored = DarwinBoolean(false)
        SecKeychainGetUserInteractionAllowed(&restored)
        XCTAssertEqual(restored.boolValue, original.boolValue)
    }
}
