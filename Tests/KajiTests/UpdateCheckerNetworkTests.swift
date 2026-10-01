import XCTest
@testable import Kaji

/// Deterministic stub: routes requests by URL path, never touches the network.
final class UpdateCheckerStubProtocol: URLProtocol {
    enum Stub {
        case response(status: Int, finalURL: URL? = nil, body: Data = Data())
        case failure(URLError.Code)
    }
    nonisolated(unsafe) static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) static var requested: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requested.append(request)
        guard let url = request.url, let stub = Self.stubs[url.path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch stub {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case let .response(status, finalURL, body):
            let resp = HTTPURLResponse(url: finalURL ?? url, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class UpdateCheckerNetworkTests: XCTestCase {
    private func makeChecker(current: String = "0.1.0") -> UpdateChecker {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UpdateCheckerStubProtocol.self]
        return UpdateChecker(session: URLSession(configuration: config), currentVersion: current)
    }

    override func setUp() {
        UpdateCheckerStubProtocol.stubs = [:]
        UpdateCheckerStubProtocol.requested = []
    }

    private static let manifestPath = "/MisterBrookT/kaji/releases/latest/download/update.json"
    private static let latestPath = "/MisterBrookT/kaji/releases/latest"
    private static let revision = "0123456789abcdef0123456789abcdef01234567"

    private func manifest(schemaVersion: Any = 1, version: String = "9.1.0", tag: String = "v9.1.0",
                          releaseURL: String? = nil, sourceRevision: String = revision,
                          notes: String = "### Fixed\\n- Thing works") -> Data {
        let url = releaseURL ?? "https://github.com/MisterBrookT/kaji/releases/tag/\(tag)"
        let schema = schemaVersion is String ? "\"\(schemaVersion)\"" : "\(schemaVersion)"
        return """
        {"schemaVersion":\(schema),"version":"\(version)","tag":"\(tag)",
         "releaseURL":"\(url)","sourceRevision":"\(sourceRevision)","notes":"\(notes)"}
        """.data(using: .utf8)!
    }

    private func assertNoAPIRequests(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(UpdateCheckerStubProtocol.requested.contains { $0.url?.host == "api.github.com" },
                       file: file, line: line)
    }

    func testManifestURLIsStaticReleaseAsset() {
        XCTAssertEqual(UpdateChecker.manifestURL.absoluteString,
                       "https://github.com/MisterBrookT/kaji/releases/latest/download/update.json")
    }

    func testManifestSuccessKeepsMetadataWithoutFallback() async {
        UpdateCheckerStubProtocol.stubs[Self.manifestPath] = .response(status: 200, body: manifest())
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.lastError)
        XCTAssertEqual(checker.available?.tag, "v9.1.0")
        XCTAssertEqual(checker.available?.version, "9.1.0")
        XCTAssertEqual(checker.available?.url.absoluteString,
                       "https://github.com/MisterBrookT/kaji/releases/tag/v9.1.0")
        XCTAssertEqual(checker.available?.sourceRevision, Self.revision)
        XCTAssertNil(checker.available?.assetURL)
        XCTAssertFalse(checker.available?.notes.isEmpty ?? true)
        XCTAssertEqual(UpdateCheckerStubProtocol.requested.map { $0.url?.path }, [Self.manifestPath])
        assertNoAPIRequests()
    }

    func testManifestUpToDate() async {
        UpdateCheckerStubProtocol.stubs[Self.manifestPath] = .response(status: 200,
            body: manifest(version: "0.1.0", tag: "v0.1.0"))
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.lastError)
        XCTAssertNil(checker.available)
        XCTAssertNotNil(checker.lastChecked)
        assertNoAPIRequests()
    }

    func testInvalidManifestFailsClosedWithoutFallback() async {
        let cases: [(String, Data)] = [
            ("schemaVersion", manifest(schemaVersion: 2)),
            ("schemaVersion", manifest(schemaVersion: "1")),
            ("schemaVersion", manifest(schemaVersion: true)),
            ("1 MB", Data(count: 1_048_577)),
            ("tag", manifest(version: String(repeating: "9", count: 100) + ".1.0", tag: "v9.1.0")),
            ("tag", manifest(version: "9.1.0", tag: "v9.2.0")),
            ("tag", manifest(version: "9.1.0-beta.1", tag: "v9.1.0-beta.1")),
            ("tag", manifest(version: "9.1", tag: "v9.1")),
            ("tag", manifest(version: "9.1.0", tag: "9.1.0")),
            ("releaseURL", manifest(releaseURL: "https://github.com/other/kaji/releases/tag/v9.1.0")),
            ("releaseURL", manifest(releaseURL: "http://github.com/MisterBrookT/kaji/releases/tag/v9.1.0")),
            ("releaseURL", manifest(releaseURL: "https://github.com/MisterBrookT/kaji/releases/tag/v9.0.0")),
            ("sourceRevision", manifest(sourceRevision: "0123456")),
            ("sourceRevision", manifest(sourceRevision: String(Self.revision.uppercased()))),
            ("JSON", Data("not json".utf8)),
        ]
        for (field, body) in cases {
            UpdateCheckerStubProtocol.stubs = [:]
            UpdateCheckerStubProtocol.requested = []
            let final = URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v9.9.0")!
            UpdateCheckerStubProtocol.stubs[Self.manifestPath] = .response(status: 200, body: body)
            UpdateCheckerStubProtocol.stubs[Self.latestPath] = .response(status: 200, finalURL: final)
            let checker = makeChecker()
            await checker.check()
            XCTAssertNil(checker.available, field)
            XCTAssertNil(checker.lastChecked, field)
            let error = checker.lastError ?? ""
            XCTAssertTrue(error.hasPrefix("invalid update manifest:"), error)
            XCTAssertTrue(error.contains(field), "\(field): \(error)")
            XCTAssertEqual(UpdateCheckerStubProtocol.requested.map { $0.url?.path }, [Self.manifestPath])
            assertNoAPIRequests()
        }
    }

    func testMissingManifestFallsBackToRedirect() async {
        let final = URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v9.2.0")!
        UpdateCheckerStubProtocol.stubs[Self.manifestPath] = .response(status: 404)
        UpdateCheckerStubProtocol.stubs[Self.latestPath] = .response(status: 200, finalURL: final)
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.lastError)
        XCTAssertEqual(checker.available?.version, "9.2.0")
        XCTAssertEqual(checker.available?.url, final)
        XCTAssertNil(checker.available?.assetURL)
        XCTAssertNil(checker.available?.sourceRevision)
        XCTAssertEqual(UpdateCheckerStubProtocol.requested.last?.httpMethod, "HEAD")
        assertNoAPIRequests()
    }

    func testUnreachableManifestFallsBackToRedirectUpToDate() async {
        let final = URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v0.1.0")!
        UpdateCheckerStubProtocol.stubs[Self.manifestPath] = .failure(.notConnectedToInternet)
        UpdateCheckerStubProtocol.stubs[Self.latestPath] = .response(status: 200, finalURL: final)
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.lastError)
        XCTAssertNil(checker.available)
        XCTAssertNotNil(checker.lastChecked)
        assertNoAPIRequests()
    }

    func testInvalidRedirectReportsActionableError() async {
        let final = URL(string: "https://github.com/login")!
        UpdateCheckerStubProtocol.stubs[Self.manifestPath] = .response(status: 404)
        UpdateCheckerStubProtocol.stubs[Self.latestPath] = .response(status: 200, finalURL: final)
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.available)
        XCTAssertNil(checker.lastChecked)
        let error = checker.lastError ?? ""
        XCTAssertTrue(error.contains("manifest: HTTP 404"), error)
        XCTAssertTrue(error.contains("unexpected redirect target https://github.com/login"), error)
    }

    func testBothFailReportsNetworkDetail() async {
        UpdateCheckerStubProtocol.stubs[Self.manifestPath] = .failure(.timedOut)
        UpdateCheckerStubProtocol.stubs[Self.latestPath] = .response(status: 503)
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.available)
        let error = checker.lastError ?? ""
        XCTAssertTrue(error.hasPrefix("manifest: network:"), error)
        XCTAssertTrue(error.contains("fallback: HTTP 503"), error)
        assertNoAPIRequests()
    }

    func testReleaseTagValidation() {
        XCTAssertEqual(UpdateChecker.releaseTag(fromFinalURL:
            URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v1.2.3")!), "v1.2.3")
        XCTAssertNil(UpdateChecker.releaseTag(fromFinalURL:
            URL(string: "https://github.com/MisterBrookT/kaji/releases")!))
        XCTAssertNil(UpdateChecker.releaseTag(fromFinalURL:
            URL(string: "https://github.com/other/kaji/releases/tag/v1.2.3")!))
        XCTAssertNil(UpdateChecker.releaseTag(fromFinalURL:
            URL(string: "http://github.com/MisterBrookT/kaji/releases/tag/v1.2.3")!))
        XCTAssertNil(UpdateChecker.releaseTag(fromFinalURL:
            URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/nightly")!))
        for suffix in ["v1.2.3-beta.1", "v1", "v1..3", "v1.2.3?x=1", "v1.2.3#notes"] {
            XCTAssertNil(UpdateChecker.releaseTag(fromFinalURL:
                URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/\(suffix)")!))
        }
    }
}

/// Opt-in live probe: `KAJI_LIVE_UPDATE_CHECK=1 swift test --filter UpdateCheckerLiveTests`.
@MainActor
final class UpdateCheckerLiveTests: XCTestCase {
    func testLiveCheckResolvesLatestRelease() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KAJI_LIVE_UPDATE_CHECK"] == "1")
        let checker = UpdateChecker(currentVersion: "0.0.1")
        await checker.check()
        XCTAssertNil(checker.lastError, checker.lastError ?? "")
        XCTAssertNotNil(checker.available)
        print("live update check:", checker.available?.tag ?? "nil", checker.available?.url.absoluteString ?? "")
    }
}
