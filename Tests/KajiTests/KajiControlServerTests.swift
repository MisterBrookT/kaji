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
}
