import Foundation
import Network
import KajiCore

@MainActor
final class KajiMCPServer: ObservableObject {
    nonisolated static let port: UInt16 = 37_841
    nonisolated static let endpoint = "http://127.0.0.1:\(port)/mcp"

    enum Status: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var status: Status = .stopped

    private weak var goals: DailyGoalStore?
    private let snapshotProvider: () -> [String: Any]
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "dev.kaji.mcp")

    init(
        goals: DailyGoalStore,
        host: String = "127.0.0.1",
        port: UInt16 = KajiMCPServer.port,
        snapshotProvider: @escaping () -> [String: Any] = { [:] }
    ) {
        self.goals = goals
        self.snapshotProvider = snapshotProvider
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    func start() {
        guard listener == nil else { return }
        status = .starting
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: host,
                port: port
            )
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.status = .running
                    case .failed(let error):
                        self.listener?.cancel()
                        self.listener = nil
                        self.status = .failed(error.localizedDescription)
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: queue)
        } catch {
            listener = nil
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        status = .stopped
    }

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            var next = buffer
            if let data { next.append(data) }
            if let request = MCPHTTPRequest.parse(next) {
                Task { @MainActor in
                    guard let self else {
                        connection.cancel()
                        return
                    }
                    let response = self.handle(request)
                    connection.send(
                        content: response,
                        contentContext: .defaultMessage,
                        isComplete: false,
                        completion: .contentProcessed { sendError in
                            Task { @MainActor in
                                if sendError != nil {
                                    self.finish(connection)
                                } else {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        self.finish(connection)
                                    }
                                }
                            }
                        }
                    )
                }
                return
            }
            if isComplete || error != nil || next.count > 1_048_576 {
                Task { @MainActor in self?.finish(connection) }
                return
            }
            Task { @MainActor in self?.receive(on: connection, buffer: next) }
        }
    }

    private func finish(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private func handle(_ request: MCPHTTPRequest) -> Data {
        guard request.method == "POST", request.path == "/mcp" else {
            return MCPHTTPResponse.json(
                status: "404 Not Found",
                object: ["error": "Use POST /mcp"]
            )
        }
        guard let value = try? JSONSerialization.jsonObject(with: request.body),
              let rpc = value as? [String: Any] else {
            return rpcError(id: NSNull(), code: -32700, message: "Parse error")
        }
        let id = rpc["id"] ?? NSNull()
        guard let method = rpc["method"] as? String else {
            return rpcError(id: id, code: -32600, message: "Invalid Request")
        }

        switch method {
        case "notifications/initialized":
            return MCPHTTPResponse.empty(status: "202 Accepted")
        case "ping":
            return rpcResult(id: id, result: [:])
        case "initialize":
            let params = rpc["params"] as? [String: Any]
            return rpcResult(id: id, result: [
                "protocolVersion": params?["protocolVersion"] as? String ?? "2025-03-26",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "Kaji", "version": "0.9.1"]
            ])
        case "tools/list":
            return rpcResult(id: id, result: ["tools": Self.toolDefinitions])
        case "tools/call":
            guard let params = rpc["params"] as? [String: Any],
                  let name = params["name"] as? String else {
                return rpcError(id: id, code: -32602, message: "Missing tool name")
            }
            return callTool(
                id: id,
                name: name,
                arguments: params["arguments"] as? [String: Any] ?? [:]
            )
        default:
            return rpcError(id: id, code: -32601, message: "Method not found")
        }
    }

    private func callTool(id: Any, name: String, arguments: [String: Any]) -> Data {
        guard let goals else { return toolError(id: id, message: "Goals store unavailable") }
        do {
            let payload: Any
            switch name {
            case "kaji_state":
                payload = snapshotProvider()
            case "kaji_goals_list":
                payload = [
                    "goals": goals.goals(for: .today).map(goalObject),
                    "tags": goals.tagDefinitions.map {
                        ["name": $0.name, "colorHex": String(format: "%06X", $0.colorHex)]
                    }
                ]
            case "kaji_goal_add":
                guard let title = arguments["title"] as? String else {
                    throw MCPToolError.invalid("title is required")
                }
                let tag = goals.ensureTag(
                    name: arguments["tag"] as? String ?? GoalTag.personal.rawValue,
                    colorHex: 0x8E6AD8
                )
                let goal = try goals.addGoal(
                    title: title,
                    tag: tag,
                    note: arguments["note"] as? String ?? "",
                    in: .today
                )
                payload = goalObject(goal)
            case "kaji_goal_update":
                let goalID = try requiredID(arguments)
                let title = arguments["title"] as? String
                let tag = arguments["tag"] as? String
                let note = arguments["note"] as? String
                guard title != nil || tag != nil || note != nil else {
                    throw MCPToolError.invalid("title, tag, or note is required")
                }
                try goals.updateGoal(
                    id: goalID,
                    title: title,
                    tag: tag,
                    note: note,
                    in: .today
                )
                payload = goalObject(try findGoal(goalID, store: goals))
            case "kaji_goal_complete":
                let goalID = try requiredID(arguments)
                guard let isDone = arguments["isDone"] as? Bool else {
                    throw MCPToolError.invalid("isDone is required")
                }
                try goals.setGoalCompleted(id: goalID, isDone: isDone, in: .today)
                payload = goalObject(try findGoal(goalID, store: goals))
            case "kaji_goal_delete":
                let goalID = try requiredID(arguments)
                try goals.deleteGoal(id: goalID, in: .today)
                payload = ["deleted": goalID.uuidString.lowercased()]
            default:
                throw MCPToolError.invalid("Unknown tool: \(name)")
            }
            return toolResult(id: id, payload: payload)
        } catch {
            return toolError(id: id, message: message(for: error))
        }
    }


    private func requiredID(_ arguments: [String: Any]) throws -> UUID {
        guard let raw = arguments["id"] as? String,
              let id = UUID(uuidString: raw) else {
            throw MCPToolError.invalid("id must be a UUID")
        }
        return id
    }

    private func findGoal(
        _ id: UUID,
        store: DailyGoalStore
    ) throws -> DailyGoal {
        guard let goal = store.goals(for: .today).first(where: { $0.id == id }) else {
            throw GoalStoreMutationError.goalNotFound
        }
        return goal
    }

    private func goalObject(_ goal: DailyGoal) -> [String: Any] {
        [
            "id": goal.id.uuidString.lowercased(),
            "title": goal.title,
            "isDone": goal.isDone,
            "tag": goal.tag,
            "note": goal.note
        ]
    }

    private func message(for error: Error) -> String {
        switch error {
        case GoalStoreMutationError.goalNotFound: "Goal not found"
        case GoalStoreMutationError.emptyTitle: "title cannot be empty"
        case MCPToolError.invalid(let message): message
        default: error.localizedDescription
        }
    }

    private func rpcResult(id: Any, result: Any) -> Data {
        MCPHTTPResponse.json(object: ["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func rpcError(id: Any, code: Int, message: String) -> Data {
        MCPHTTPResponse.json(object: [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": message]
        ])
    }

    private func toolResult(id: Any, payload: Any) -> Data {
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return rpcResult(id: id, result: [
            "content": [["type": "text", "text": text]],
            "structuredContent": payload,
            "isError": false
        ])
    }

    private func toolError(id: Any, message: String) -> Data {
        rpcResult(id: id, result: [
            "content": [["type": "text", "text": message]],
            "isError": true
        ])
    }

    private enum MCPToolError: Error {
        case invalid(String)
    }


    private static let toolDefinitions: [[String: Any]] = [
        tool(
            "kaji_state",
            "Read the complete current Kaji state.",
            properties: [:]
        ),
        tool(
            "kaji_goals_list",
            "List Kaji goals and their colored tags.",
            properties: [:]
        ),
        tool(
            "kaji_goal_add",
            "Add a Goal with an optional tag and note.",
            properties: [
                "title": ["type": "string"],
                "tag": ["type": "string"],
                "note": ["type": "string"]
            ],
            required: ["title"]
        ),
        tool(
            "kaji_goal_update",
            "Update a Goal title, tag, and/or note.",
            properties: [
                "id": ["type": "string"],
                "title": ["type": "string"],
                "tag": ["type": "string"],
                "note": ["type": "string"]
            ],
            required: ["id"]
        ),
        tool(
            "kaji_goal_complete",
            "Set a Goal's completion state.",
            properties: [
                "id": ["type": "string"],
                "isDone": ["type": "boolean"]
            ],
            required: ["id", "isDone"]
        ),
        tool(
            "kaji_goal_delete",
            "Delete a Goal by ID.",
            properties: ["id": ["type": "string"]],
            required: ["id"]
        )
    ]

    private static func tool(
        _ name: String,
        _ description: String,
        properties: [String: Any],
        required: [String] = []
    ) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "additionalProperties": false
        ]
        if !required.isEmpty { schema["required"] = required }
        return [
            "name": name,
            "description": description,
            "inputSchema": schema
        ]
    }
}

private struct MCPHTTPRequest {
    let method: String
    let path: String
    let body: Data

    static func parse(_ data: Data) -> MCPHTTPRequest? {
        let marker = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: marker),
              let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        let contentLength = lines.dropFirst().compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                    == "content-length" else { return nil }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        return MCPHTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            body: data.subdata(in: bodyStart..<(bodyStart + contentLength))
        )
    }
}

private enum MCPHTTPResponse {
    static func json(status: String = "200 OK", object: Any) -> Data {
        let body = (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )) ?? Data()
        let header = "HTTP/1.1 \(status)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        return Data(header.utf8) + body
    }

    static func empty(status: String) -> Data {
        Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }
}
