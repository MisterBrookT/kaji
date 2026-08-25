import XCTest
@testable import Kaji

@MainActor
final class KajiMCPServerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: DailyGoalStore!
    private var server: KajiMCPServer!
    private var endpoint: URL!

    override func setUp() async throws {
        suiteName = "KajiMCPServerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = DailyGoalStore(defaults: defaults)
        let port = UInt16.random(in: 40_000...60_000)
        endpoint = URL(string: "http://127.0.0.1:\(port)/mcp")!
        server = KajiMCPServer(
            goals: store,
            port: port,
            snapshotProvider: { ["quota": ["sample": true]] }
        )
        server.start()
        try await waitUntilRunning()
    }

    override func tearDown() async throws {
        server.stop()
        defaults.removePersistentDomain(forName: suiteName)
        server = nil
        store = nil
        defaults = nil
        endpoint = nil
    }

    func testProtocolAndGoalCRUDOverRealHTTP() async throws {
        let initialized = try await rpc(method: "initialize", params: [
            "protocolVersion": "2025-03-26"
        ])
        XCTAssertEqual(
            (initialized["result"] as? [String: Any])?["protocolVersion"] as? String,
            "2025-03-26"
        )

        let ping = try await rpc(method: "ping")
        XCTAssertNotNil(ping["result"])

        let listedTools = try await rpc(method: "tools/list")
        let tools = (listedTools["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(Set(tools?.compactMap { $0["name"] as? String } ?? []), [
            "kaji_state", "kaji_goals_list", "kaji_goal_add", "kaji_goal_update",
            "kaji_goal_complete", "kaji_goal_delete"
        ])
        let snapshot = try await callTool("kaji_state", arguments: [:])
        let state = try XCTUnwrap(snapshot["structuredContent"] as? [String: Any])
        XCTAssertEqual((state["quota"] as? [String: Any])?["sample"] as? Bool, true)

        let added = try await callTool("kaji_goal_add", arguments: [
            "title": "Ship local MCP", "tag": "Custom",
            "note": "Round-trip note"
        ])
        let goal = try XCTUnwrap(added["structuredContent"] as? [String: Any])
        let id = try XCTUnwrap(goal["id"] as? String)
        XCTAssertEqual(goal["note"] as? String, "Round-trip note")

        let updated = try await callTool("kaji_goal_update", arguments: [
            "id": id, "title": "Ship Kaji MCP", "note": "Updated note"
        ])
        XCTAssertEqual(
            (updated["structuredContent"] as? [String: Any])?["note"] as? String,
            "Updated note"
        )

        let completed = try await callTool("kaji_goal_complete", arguments: [
            "id": id, "isDone": true
        ])
        XCTAssertEqual(
            (completed["structuredContent"] as? [String: Any])?["isDone"] as? Bool,
            true
        )

        let reloaded = DailyGoalStore(defaults: defaults)
        XCTAssertEqual(reloaded.goals.first?.id.uuidString.lowercased(), id)
        XCTAssertEqual(reloaded.goals.first?.note, "Updated note")
        XCTAssertEqual(reloaded.goals.first?.isDone, true)

        let deleted = try await callTool("kaji_goal_delete", arguments: [
            "id": id
        ])
        XCTAssertEqual(
            (deleted["structuredContent"] as? [String: Any])?["deleted"] as? String,
            id
        )
        XCTAssertTrue(store.goals.isEmpty)
    }

    func testInvalidArgumentsReturnStructuredToolErrors() async throws {
        let missingTitle = try await callTool("kaji_goal_add", arguments: [:])
        XCTAssertEqual(missingTitle["isError"] as? Bool, true)
        let content = missingTitle["content"] as? [[String: Any]]
        XCTAssertTrue((content?.first?["text"] as? String)?.contains("title") == true)
        let missingID = try await callTool("kaji_goal_update", arguments: [
            "id": UUID().uuidString, "note": "missing"
        ])
        XCTAssertEqual(missingID["isError"] as? Bool, true)
        XCTAssertEqual(
            (missingID["content"] as? [[String: Any]])?.first?["text"] as? String,
            "Goal not found"
        )
    }

    private func waitUntilRunning() async throws {
        for _ in 0..<100 {
            if server.status == .running { return }
            if case .failed(let message) = server.status {
                XCTFail("MCP listener failed: \(message)")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("MCP listener did not start")
    }

    private func callTool(_ name: String, arguments: [String: Any]) async throws -> [String: Any] {
        let response = try await rpc(method: "tools/call", params: [
            "name": name, "arguments": arguments
        ])
        return try XCTUnwrap(response["result"] as? [String: Any])
    }

    private func rpc(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "jsonrpc": "2.0", "id": UUID().uuidString, "method": method
        ]
        if let params { payload["params"] = params }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
