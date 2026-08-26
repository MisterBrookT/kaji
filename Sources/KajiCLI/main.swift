import Foundation

private struct Client {
    let baseURL = URL(string: ProcessInfo.processInfo.environment["KAJI_ENDPOINT"] ?? "http://127.0.0.1:37841/v1")!

    func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Any {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CLIError.message("invalid response") }
        let object = try JSONSerialization.jsonObject(with: data)
        if !(200..<300).contains(http.statusCode) {
            let message = (object as? [String: Any])?["error"] as? String ?? "HTTP \(http.statusCode)"
            throw CLIError.message(message)
        }
        return object
    }

    func goals() async throws -> [[String: Any]] {
        let object = try await request("GET", "goals") as? [String: Any]
        return object?["goals"] as? [[String: Any]] ?? []
    }

    func resolveID(_ fragment: String) async throws -> String {
        if UUID(uuidString: fragment) != nil { return fragment.lowercased() }
        let matches = try await goals().compactMap { $0["id"] as? String }.filter { $0.hasPrefix(fragment.lowercased()) }
        guard matches.count == 1 else {
            throw CLIError.message(matches.isEmpty ? "no goal id starts with '\(fragment)'" : "ambiguous id prefix '\(fragment)': \(matches.joined(separator: ", "))")
        }
        return matches[0]
    }
}

private enum CLIError: Error { case message(String) }

@main
private enum KajiCLI {
    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch {
            let message: String
            if case CLIError.message(let value) = error { message = value } else { message = error.localizedDescription }
            FileHandle.standardError.write(Data("kaji: \(message)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first, !["-h", "--help", "help"].contains(command) else { printUsage(); return }
        let args = Array(arguments.dropFirst())
        let client = Client()
        switch command {
        case "list":
            for goal in try await client.goals() {
                let done = goal["isDone"] as? Bool == true ? "[x]" : "[ ]"
                let id = String((goal["id"] as? String ?? "").prefix(8))
                let tag = goal["tag"] as? String ?? ""
                let title = goal["title"] as? String ?? ""
                let note = goal["note"] as? String ?? ""
                print("\(done) \(id)  \(tag)  \(title)\(note.isEmpty ? "" : "  # \(note)")")
            }
        case "add":
            guard let title = args.first else { throw CLIError.message("add requires a title") }
            printJSON(try await client.request("POST", "goals", body: ["title": title, "tag": args.count > 1 ? args[1] : "personal", "note": args.count > 2 ? args[2] : ""]))
        case "done", "undone":
            guard let fragment = args.first else { throw CLIError.message("goal id required") }
            let id = try await client.resolveID(fragment)
            printJSON(try await client.request("POST", "goals/\(id)/completion", body: ["isDone": command == "done"]))
        case "delete":
            guard let fragment = args.first else { throw CLIError.message("goal id required") }
            printJSON(try await client.request("DELETE", "goals/\(try await client.resolveID(fragment))"))
        case "update":
            guard let fragment = args.first else { throw CLIError.message("goal id required") }
            var body: [String: Any] = [:]
            var index = 1
            while index < args.count {
                guard index + 1 < args.count else { throw CLIError.message("missing value for \(args[index])") }
                switch args[index] {
                case "--title": body["title"] = args[index + 1]
                case "--tag": body["tag"] = args[index + 1]
                case "--note": body["note"] = args[index + 1]
                default: throw CLIError.message("unknown update flag '\(args[index])'")
                }
                index += 2
            }
            let id = try await client.resolveID(fragment)
            printJSON(try await client.request("PATCH", "goals/\(id)", body: body))
        case "state": printJSON(try await client.request("GET", "state"))
        case "raw":
            guard args.count >= 2 else { throw CLIError.message("raw requires METHOD PATH [JSON]") }
            let body: [String: Any]?
            if args.count > 2 {
                let data = Data(args[2].utf8)
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CLIError.message("raw JSON must be an object") }
                body = parsed
            } else { body = nil }
            printJSON(try await client.request(args[0].uppercased(), args[1], body: body))
        default: throw CLIError.message("unknown command '\(command)'\n\(usage)")
        }
    }

    private static func printJSON(_ object: Any) {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static var usage: String { """
    kaji — manage Kaji.app goals from the shell

    Usage:
      kaji list
      kaji add <title> [tag] [note]
      kaji done|undone <id>
      kaji update <id> [--title T] [--tag T] [--note N]
      kaji delete <id>
      kaji state
      kaji raw <METHOD> <path> [json-body]
    """ }
    private static func printUsage() { print(usage) }
}
