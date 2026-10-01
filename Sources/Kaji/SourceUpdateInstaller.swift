import Foundation

/// A source build that `scripts/source-update.sh prepare` staged beside the
/// installed app. The installed app has not been touched yet.
struct PreparedUpdate: Equatable, Sendable {
    let tag: String
    let version: String
    let stagedAppURL: URL
    let destinationAppURL: URL
}

/// Runs the update helper script. Injected so tests never build or install.
protocol SourceUpdateProcessRunning: Sendable {
    /// Runs to completion (or until `timeout` / task cancellation, which
    /// terminate the process) and returns its exit status and combined output.
    func run(_ executable: URL, arguments: [String], logURL: URL,
             timeout: Duration) async throws -> (status: Int32, output: String)
    /// Starts a process that outlives the caller; output is appended to `logURL`.
    func launchDetached(_ executable: URL, arguments: [String], logURL: URL) throws
}

/// Pinned source update: clone exactly `tag` from the fixed repo, build ad-hoc,
/// stage on the destination filesystem while this app keeps running, then hand
/// off to a detached script that waits for `hostPID` to exit before swapping.
/// The caller terminates the app after `launchReplacement` returns.
final class SourceUpdateInstaller: Sendable {
    enum Failure: Error, Equatable, LocalizedError {
        case invalidTag(String)
        case invalidVersion(String)
        case invalidRevision(String)
        case scriptMissing
        case prepareFailed(status: Int32)
        case noStagedBundle
        case timedOut

        var errorDescription: String? {
            switch self {
            case .invalidTag(let tag): "Invalid source update tag: \(tag)"
            case .invalidVersion(let version): "Invalid source update version: \(version)"
            case .invalidRevision: "The update source revision is invalid."
            case .scriptMissing: "The bundled source update script is missing."
            case .prepareFailed(let status): "Source build or verification failed (exit \(status)). See the log."
            case .noStagedBundle: "The source update did not produce a staged application."
            case .timedOut: "The source build timed out. The current application was not replaced."
            }
        }
    }

    let scriptURL: URL
    let destinationAppURL: URL
    /// Full transcript of the last prepare / replacement; show on failure.
    let logURL: URL
    var resultURL: URL { logURL.appendingPathExtension("result") }
    let hostPID: Int32
    let buildTimeout: Duration
    private let runner: SourceUpdateProcessRunning

    init(scriptURL: URL? = Bundle.main.url(forResource: "source-update", withExtension: "sh"),
         destinationAppURL: URL = Bundle.main.bundleURL,
         logURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kaji-source-update-\(UUID().uuidString).log"),
         hostPID: Int32 = ProcessInfo.processInfo.processIdentifier,
         buildTimeout: Duration = .seconds(900),
         runner: SourceUpdateProcessRunning = SystemSourceUpdateRunner()) {
        self.scriptURL = scriptURL ?? URL(fileURLWithPath: "/nonexistent/source-update.sh")
        self.destinationAppURL = destinationAppURL
        self.logURL = logURL
        self.hostPID = hostPID
        self.buildTimeout = buildTimeout
        self.runner = runner
    }

    static func isStableVersion(_ s: String) -> Bool {
        s.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) == (s.startIndex..<s.endIndex)
    }

    static func isFullRevision(_ s: String) -> Bool {
        s.range(of: #"^[0-9a-f]{40}$"#, options: .regularExpression) == (s.startIndex..<s.endIndex)
    }

    func prepare(tag: String, version: String, revision: String?) async throws -> PreparedUpdate {
        guard Self.isStableVersion(version) else { throw Failure.invalidVersion(version) }
        guard tag == "v\(version)" else { throw Failure.invalidTag(tag) }
        if let revision, !Self.isFullRevision(revision) { throw Failure.invalidRevision(revision) }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { throw Failure.scriptMissing }

        var args = [scriptURL.path, "prepare", "--tag", tag, "--version", version,
                    "--dest-app", destinationAppURL.path]
        if let revision { args += ["--revision", revision] }
        let result = try await runner.run(URL(fileURLWithPath: "/bin/bash"), arguments: args,
                                          logURL: logURL, timeout: buildTimeout)
        guard result.status == 0 else { throw Failure.prepareFailed(status: result.status) }
        let staged = result.output.split(separator: "\n").reversed()
            .first { $0.hasPrefix("STAGED=") }
            .map { String($0.dropFirst("STAGED=".count)) }
        guard let staged, !staged.isEmpty else { throw Failure.noStagedBundle }
        return PreparedUpdate(tag: tag, version: version,
                              stagedAppURL: URL(fileURLWithPath: staged),
                              destinationAppURL: destinationAppURL)
    }

    /// Starts the detached swap. It waits for `hostPID` to exit; the caller
    /// must terminate the app afterwards. Does not stop anything itself.
    func launchReplacement(_ prepared: PreparedUpdate) throws {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { throw Failure.scriptMissing }
        try runner.launchDetached(URL(fileURLWithPath: "/bin/bash"), arguments: [
            scriptURL.path, "replace", "--staged", prepared.stagedAppURL.path,
            "--version", prepared.version, "--dest-app", prepared.destinationAppURL.path,
            "--host-pid", String(hostPID), "--result-file", resultURL.path,
        ], logURL: logURL)
    }
}

/// Real `Process` runner. Never blocks the calling actor: completion arrives
/// through `terminationHandler`; timeout and cancellation terminate the child.
struct SystemSourceUpdateRunner: SourceUpdateProcessRunning {
    private var environment: [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["PATH"] = (values["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin") + ":/opt/homebrew/bin:/usr/local/bin"
        return values
    }

    func run(_ executable: URL, arguments: [String], logURL: URL,
             timeout: Duration) async throws -> (status: Int32, output: String) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        process.environment = environment

        let status: Int32 = try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Int32?.self) { group in
                group.addTask {
                    await withCheckedContinuation { cont in
                        process.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
                        do { try process.run() } catch {
                            process.terminationHandler = nil
                            cont.resume(returning: -1)
                        }
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return nil
                }
                let first = try await group.next() ?? nil
                if first == nil, process.isRunning { process.terminate() }
                group.cancelAll()
                guard let first else {
                    _ = try await group.next()
                    throw SourceUpdateInstaller.Failure.timedOut
                }
                return first
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        return (status, output)
    }

    func launchDetached(_ executable: URL, arguments: [String], logURL: URL) throws {
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        log.seekToEndOfFile()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice
        process.environment = environment
        try process.run()
    }
}
