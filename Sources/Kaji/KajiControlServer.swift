import Foundation
import Network
import KajiCore

@MainActor
final class KajiControlServer {
    nonisolated static let port: UInt16 = 37_841
    nonisolated static let baseURL = "http://127.0.0.1:\(port)/v1"

    private weak var goals: DailyGoalStore?
    private let snapshotProvider: () -> [String: Any]
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "dev.kaji.control")

    init(
        goals: DailyGoalStore,
        host: String = "127.0.0.1",
        port: UInt16 = KajiControlServer.port,
        snapshotProvider: @escaping () -> [String: Any] = { [:] }
    ) {
        self.goals = goals
        self.snapshotProvider = snapshotProvider
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    Task { @MainActor in
                        self?.listener?.cancel()
                        self?.listener = nil
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: queue)
        } catch {
            listener = nil
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
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
            if let request = ControlHTTPRequest.parse(next) {
                Task { @MainActor in
                    guard let self else { connection.cancel(); return }
                    let response = self.handle(request)
                    connection.send(content: response, completion: .contentProcessed { _ in
                        Task { @MainActor in self.finish(connection) }
                    })
                }
                return
            }
            if isComplete || error != nil || next.count > 1_048_576 {
                Task { @MainActor in self?.finish(connection) }
            } else {
                Task { @MainActor in self?.receive(on: connection, buffer: next) }
            }
        }
    }

    private func finish(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private func handle(_ request: ControlHTTPRequest) -> Data {
        guard let goals else { return .json(status: "503 Service Unavailable", object: ["error": "Goals store unavailable"]) }
        do {
            let components = request.path.split(separator: "/").map(String.init)
            let payload: Any
            if request.method == "GET", components == ["v1", "state"] {
                payload = snapshotProvider()
            } else if request.method == "GET", components == ["v1", "goals"] {
                payload = [
                    "goals": goals.goals(for: .today).map(goalObject),
                    "tags": goals.tagDefinitions.map { ["name": $0.name, "colorHex": String(format: "%06X", $0.colorHex)] }
                ]
            } else if request.method == "POST", components == ["v1", "goals"] {
                let body = try request.jsonBody()
                guard let title = body["title"] as? String else { throw ControlError.invalid("title is required") }
                let tag = goals.ensureTag(name: body["tag"] as? String ?? GoalTag.personal.rawValue, colorHex: 0x8E6AD8)
                payload = goalObject(try goals.addGoal(title: title, tag: tag, note: body["note"] as? String ?? "", in: .today))
            } else if request.method == "PATCH", components.count == 3,
                      components[0] == "v1", components[1] == "goals" {
                let id = try parseID(components[2])
                let body = try request.jsonBody()
                let title = body["title"] as? String
                let tag = body["tag"] as? String
                let note = body["note"] as? String
                guard title != nil || tag != nil || note != nil else { throw ControlError.invalid("title, tag, or note is required") }
                try goals.updateGoal(id: id, title: title, tag: tag, note: note, in: .today)
                payload = goalObject(try findGoal(id, store: goals))
            } else if request.method == "POST", components.count == 4,
                      components[0] == "v1", components[1] == "goals", components[3] == "completion" {
                let id = try parseID(components[2])
                let body = try request.jsonBody()
                guard let isDone = body["isDone"] as? Bool else { throw ControlError.invalid("isDone is required") }
                try goals.setGoalCompleted(id: id, isDone: isDone, in: .today)
                payload = goalObject(try findGoal(id, store: goals))
            } else if request.method == "DELETE", components.count == 3,
                      components[0] == "v1", components[1] == "goals" {
                let id = try parseID(components[2])
                try goals.deleteGoal(id: id, in: .today)
                payload = ["deleted": id.uuidString.lowercased()]
            } else {
                return .json(status: "404 Not Found", object: ["error": "Unknown local control route"])
            }
            return .json(object: payload)
        } catch {
            return .json(status: "400 Bad Request", object: ["error": message(for: error)])
        }
    }

    private func parseID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw ControlError.invalid("id must be a UUID") }
        return id
    }

    private func findGoal(_ id: UUID, store: DailyGoalStore) throws -> DailyGoal {
        guard let goal = store.goals(for: .today).first(where: { $0.id == id }) else { throw GoalStoreMutationError.goalNotFound }
        return goal
    }

    private func goalObject(_ goal: DailyGoal) -> [String: Any] {
        ["id": goal.id.uuidString.lowercased(), "title": goal.title, "isDone": goal.isDone, "tag": goal.tag, "note": goal.note]
    }

    private func message(for error: Error) -> String {
        switch error {
        case GoalStoreMutationError.goalNotFound: "Goal not found"
        case GoalStoreMutationError.emptyTitle: "title cannot be empty"
        case ControlError.invalid(let message): message
        default: error.localizedDescription
        }
    }

    private enum ControlError: Error { case invalid(String) }
}

private struct ControlHTTPRequest {
    let method: String
    let path: String
    let body: Data

    func jsonBody() throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw BodyError.invalid
        }
        return value
    }

    static func parse(_ data: Data) -> ControlHTTPRequest? {
        let marker = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: marker),
              let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        let contentLength = lines.dropFirst().compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { return nil }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        return ControlHTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), body: data.subdata(in: bodyStart..<(bodyStart + contentLength)))
    }

    private enum BodyError: Error { case invalid }
}

private extension Data {
    static func json(status: String = "200 OK", object: Any) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + body
    }
}
