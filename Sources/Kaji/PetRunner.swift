import Foundation

// MARK: - PetRunner
// Owns the optional desktop pet process launched from Kaji.
// PetHatch remains the pet/runtime project; Kaji only exposes a thin start/stop entrypoint.

@MainActor
final class PetRunner: ObservableObject {
    enum ActivitySource: String {
        case runtimeEvent
        case keyboardMouse
        case automatic
    }

    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?
    @Published private(set) var runningPetId: String?

    private var process: Process?
    private var requestedStopPids = Set<Int32>()
    private var launchedRootURL: URL?
    private let logger = Logger()

    deinit {
        if let process {
            Self.terminateChildren(of: process.processIdentifier)
            process.terminate()
        }
        Self.terminateKajiPetRuntimes(root: launchedRootURL)
    }

    func toggle(petId: String) {
        if isRunning {
            if runningPetId == petId {
                stop()
            } else {
                stop()
                start(petId: petId, activitySource: .runtimeEvent)
            }
        } else {
            start(petId: petId, activitySource: .runtimeEvent)
        }
    }

    func start(petId: String) {
        start(petId: petId, activitySource: .runtimeEvent)
    }

    func start(petId: String, activitySource: ActivitySource) {
        if isBusy || isRunning { return }
        guard let root = PetHatchLocator.findRoot() else {
            lastError = "pethatch_missing"
            return
        }

        isBusy = true
        lastError = nil
        runningPetId = petId

        var args: [String] = [
            "run",
            petId,
            "--size", "small",
            "--pin",
            "--state-file", PetBridge.outputURL.path,
            "--hide-message",
        ]
        switch activitySource {
        case .runtimeEvent:
            args.append(contentsOf: ["--activity-source", "runtimeEvent"])
        case .keyboardMouse:
            args.append(contentsOf: ["--activity-source", "keyboardMouse"])
        case .automatic:
            break
        }

        let process = Process()
        process.executableURL = root.appendingPathComponent("bin/pethatch")
        process.currentDirectoryURL = root
        process.arguments = args
        launchedRootURL = root
        let logs = Self.logFileHandle()
        process.standardOutput = logs
        process.standardError = logs

        process.terminationHandler = { [weak self] process in
            let pid = process.processIdentifier
            let failed = process.terminationReason != .exit || process.terminationStatus != 0
            Task { @MainActor in
                guard let self else { return }
                let requestedStop = self.requestedStopPids.remove(pid) != nil
                let isCurrent = self.process?.processIdentifier == pid
                guard isCurrent else {
                    if failed && !requestedStop {
                        self.lastError = "runtime_failed"
                    }
                    return
                }
                if self.process?.processIdentifier == pid {
                    self.process = nil
                }
                self.runningPetId = nil
                self.isRunning = false
                self.isBusy = false
                if failed && !requestedStop {
                    self.lastError = "runtime_failed"
                }
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            isBusy = false
            logger.log("started pet", metadata: ["petId": petId, "source": String(describing: activitySource)])
        } catch {
            lastError = "launch_failed"
            runningPetId = nil
            isRunning = false
            isBusy = false
            logger.log("launch failed", metadata: ["error": "\(error)"])
        }
    }

    func stop() {
        stop(force: false)
    }

    func stop(force: Bool) {
        if isBusy && !force { return }
        isBusy = true
        lastError = nil
        if let process {
            requestedStopPids.insert(process.processIdentifier)
        }
        terminateCurrentProcess()
        if force {
            Self.terminateKajiPetRuntimes(root: launchedRootURL)
        }
        process = nil
        runningPetId = nil
        launchedRootURL = nil
        isRunning = false
        isBusy = false
    }

    private func terminateCurrentProcess() {
        guard let process else { return }
        Self.terminateChildren(of: process.processIdentifier)
        process.terminate()
    }

    nonisolated private static func terminateChildren(of pid: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-TERM", "-P", String(pid)]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Best-effort cleanup; the parent process is still terminated below.
        }
    }

    nonisolated private static func terminateKajiPetRuntimes(root: URL?) {
        let rootPath = root?.path ?? "pethatch"
        let escapedRoot = NSRegularExpression.escapedPattern(for: rootPath)
        let patterns = [
            "\(escapedRoot).*run-pet.py.*pet-state.json",
            "\(escapedRoot).*pethatch.py.*run.*--state-file.*pet-state.json",
            "bin/pethatch.*run.*--state-file.*pet-state.json",
        ]
        for signal in ["-TERM", "-KILL"] {
            for pattern in patterns {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                task.arguments = [signal, "-f", pattern]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try? task.run()
                task.waitUntilExit()
            }
            if signal == "-TERM" {
                Thread.sleep(forTimeInterval: 0.15)
            }
        }
    }

    private static func logFileHandle() -> FileHandle {
        let path = "/tmp/kaji-pethatch.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        let url = URL(fileURLWithPath: path)
        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            return handle
        } catch {
            return FileHandle.nullDevice
        }
    }
}

// MARK: - logger

private struct Logger {
    func log(_ message: String, metadata: [String: String] = [:]) {
        let tag = "[kaji.pet-runner]"
        let details = metadata.isEmpty ? "" : " " + metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        NSLog("\(tag) \(message)\(details)")
    }
}
