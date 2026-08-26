import XCTest
@testable import Kaji

@MainActor
final class KajiControlServerTests: XCTestCase {
    func testGoalLifecycleUsesPlainLocalHTTPRoutes() async throws {
        let suite = "KajiControlServerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DailyGoalStore(defaults: defaults)
        let port = UInt16.random(in: 40_000...60_000)
        let server = KajiControlServer(goals: store, port: port, snapshotProvider: { ["sample": true] })
        server.start()
        defer { server.stop() }
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1"))

        try await waitUntilReachable(base.appending(path: "goals"))
        let added = try await request(base, method: "POST", path: "goals", body: ["title": "Ship CLI", "tag": "Custom", "note": "Plain HTTP"])
        let id = try XCTUnwrap(added["id"] as? String)
        XCTAssertEqual(added["title"] as? String, "Ship CLI")

        let list = try await request(base, method: "GET", path: "goals")
        XCTAssertEqual((list["goals"] as? [[String: Any]])?.count, 1)
        let updated = try await request(base, method: "PATCH", path: "goals/\(id)", body: ["note": "Updated"])
        XCTAssertEqual(updated["note"] as? String, "Updated")
        let completed = try await request(base, method: "POST", path: "goals/\(id)/completion", body: ["isDone": true])
        XCTAssertEqual(completed["isDone"] as? Bool, true)
        let deleted = try await request(base, method: "DELETE", path: "goals/\(id)")
        XCTAssertEqual(deleted["deleted"] as? String, id)
        let state = try await request(base, method: "GET", path: "state")
        XCTAssertEqual(state["sample"] as? Bool, true)
    }

    func testUIAutomationRouteIsHiddenWithoutExactNonce() async throws {
        let suite = "KajiControlServerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DailyGoalStore(defaults: defaults)

        let unavailablePort = UInt16.random(in: 40_000...49_999)
        let unavailableServer = KajiControlServer(goals: store, port: unavailablePort)
        unavailableServer.start()
        let unavailableBase = try XCTUnwrap(URL(string: "http://127.0.0.1:\(unavailablePort)/v1"))
        try await waitUntilReachable(unavailableBase.appending(path: "goals"))
        let unavailable = try await rawRequest(
            unavailableBase,
            method: "POST",
            path: "test/render",
            body: ["nonce": "anything", "surface": "status", "selection": "status", "outputPath": "/tmp/x"]
        )
        XCTAssertEqual(unavailable.status, 404)
        unavailableServer.stop()

        let automationPort = UInt16.random(in: 50_000...60_000)
        let automationBase = try XCTUnwrap(URL(string: "http://127.0.0.1:\(automationPort)/v1"))
        let automationServer = KajiControlServer(
            goals: store,
            port: automationPort,
            testAutomation: .init(
                nonce: "exact-test-nonce",
                render: { surface, selection, outputPath in
                    ["surface": surface, "selection": selection, "path": outputPath]
                }
            )
        )
        automationServer.start()
        defer { automationServer.stop() }
        try await waitUntilReachable(automationBase.appending(path: "goals"))

        let rejected = try await rawRequest(
            automationBase,
            method: "POST",
            path: "test/render",
            body: ["nonce": "wrong", "surface": "popover", "selection": "quota", "outputPath": "/tmp/x"]
        )
        XCTAssertEqual(rejected.status, 404)

        let accepted = try await rawRequest(
            automationBase,
            method: "POST",
            path: "test/render",
            body: [
                "nonce": "exact-test-nonce",
                "surface": "popover",
                "selection": "launchd",
                "outputPath": "/tmp/render.png",
            ]
        )
        XCTAssertEqual(accepted.status, 200)
        XCTAssertEqual(accepted.object["selection"] as? String, "launchd")
        XCTAssertEqual(accepted.object["path"] as? String, "/tmp/render.png")
    }

    private func waitUntilReachable(_ url: URL) async throws {
        for _ in 0..<50 {
            var request = URLRequest(url: url)
            request.timeoutInterval = 0.1
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Local control listener did not start")
    }

    private func request(_ base: URL, method: String, path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, String(decoding: data, as: UTF8.self))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func rawRequest(
        _ base: URL,
        method: String,
        path: String,
        body: [String: Any]? = nil
    ) async throws -> (status: Int, object: [String: Any]) {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (
            try XCTUnwrap((response as? HTTPURLResponse)?.statusCode),
            try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        )
    }
}
