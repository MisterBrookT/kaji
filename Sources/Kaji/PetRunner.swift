import Foundation

// MARK: - PetRunner
//
// Owns the optional desktop-pet process launched from Kaji. PetHatch remains
// the pet/runtime project; Kaji only exposes a small start/stop entrypoint.
@MainActor
final class PetRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?

    private var process: Process?
    private var requestedStopPids = Set<Int32>()

    deinit {
        if let process {
            Self.terminateChildren(of: process.processIdentifier)
            process.terminate()
        }
    }

    func toggle(petId: String) {
        isRunning ? stop() : start(petId: petId)
    }

    func start(petId: String) {
        if isBusy || isRunning { return }
        guard let root = PetHatchLocator.findRoot() else {
            lastError = "pethatch_missing"
            return
        }

        isBusy = true
        lastError = nil

        let process = Process()
        process.executableURL = root.appendingPathComponent("bin/pethatch")
        process.currentDirectoryURL = root
        process.arguments = [
            "run", petId,
            "--size", "small",
            "--pin",
            "--state-file", PetBridge.outputURL.path,
        ]
        let logHandle = Self.logFileHandle()
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.terminationHandler = { [weak self] process in
            let pid = process.processIdentifier
            let failed = process.terminationReason != .exit || process.terminationStatus != 0
            Task { @MainActor in
                guard let self else { return }
                let requestedStop = self.requestedStopPids.remove(pid) != nil
                if self.process?.processIdentifier == pid {
                    self.process = nil
                }
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
        } catch {
            lastError = "launch_failed"
            isRunning = false
            isBusy = false
        }
    }

    func stop() {
        if isBusy { return }
        isBusy = true
        lastError = nil
        if let process {
            requestedStopPids.insert(process.processIdentifier)
        }
        terminateCurrentProcess()
        process = nil
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
