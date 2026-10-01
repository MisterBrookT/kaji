import XCTest
@testable import Kaji

/// Deterministic stub: routes requests by host, never touches the network.
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
        guard let url = request.url, let stub = Self.stubs[url.host ?? ""] else {
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

    private let apiBody = """
    {"tag_name":"v9.1.0","html_url":"https://github.com/MisterBrookT/kaji/releases/tag/v9.1.0",
     "draft":false,"prerelease":false,"body":"### Fixed\\n- Thing works",
     "assets":[{"name":"Kaji.app.zip","browser_download_url":"https://example.com/Kaji.app.zip"}]}
    """.data(using: .utf8)!

    func testAPISuccessKeepsNotesAndAssetWithoutFallback() async {
        UpdateCheckerStubProtocol.stubs["api.github.com"] = .response(status: 200, body: apiBody)
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.lastError)
        XCTAssertEqual(checker.available?.tag, "v9.1.0")
        XCTAssertEqual(checker.available?.assetURL?.absoluteString, "https://example.com/Kaji.app.zip")
        XCTAssertFalse(checker.available?.notes.isEmpty ?? true)
        XCTAssertFalse(UpdateCheckerStubProtocol.requested.contains { $0.url?.host == "github.com" })
    }

    func testAPI403FallsBackToRedirect() async {
        let final = URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v9.2.0")!
        UpdateCheckerStubProtocol.stubs["api.github.com"] = .response(status: 403)
        UpdateCheckerStubProtocol.stubs["github.com"] = .response(status: 200, finalURL: final)
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.lastError)
        XCTAssertEqual(checker.available?.version, "9.2.0")
        XCTAssertEqual(checker.available?.url, final)
        XCTAssertNil(checker.available?.assetURL)
        XCTAssertNotNil(checker.lastChecked)
    }

    func testNetworkErrorFallsBackToRedirectUpToDate() async {
        let final = URL(string: "https://github.com/MisterBrookT/kaji/releases/tag/v0.1.0")!
        UpdateCheckerStubProtocol.stubs["api.github.com"] = .failure(.notConnectedToInternet)
        UpdateCheckerStubProtocol.stubs["github.com"] = .response(status: 200, finalURL: final)
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.lastError)
        XCTAssertNil(checker.available)
        XCTAssertNotNil(checker.lastChecked)
    }

    func testInvalidRedirectReportsActionableError() async {
        let final = URL(string: "https://github.com/login")!
        UpdateCheckerStubProtocol.stubs["api.github.com"] = .response(status: 403)
        UpdateCheckerStubProtocol.stubs["github.com"] = .response(status: 200, finalURL: final)
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.available)
        XCTAssertNil(checker.lastChecked)
        let error = checker.lastError ?? ""
        XCTAssertTrue(error.contains("HTTP 403"), error)
        XCTAssertTrue(error.contains("unexpected redirect target https://github.com/login"), error)
    }

    func testBothFailReportsNetworkDetail() async {
        UpdateCheckerStubProtocol.stubs["api.github.com"] = .failure(.timedOut)
        UpdateCheckerStubProtocol.stubs["github.com"] = .response(status: 503)
        let checker = makeChecker()
        await checker.check()
        XCTAssertNil(checker.available)
        let error = checker.lastError ?? ""
        XCTAssertTrue(error.hasPrefix("api: network:"), error)
        XCTAssertTrue(error.contains("fallback: HTTP 503"), error)
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
