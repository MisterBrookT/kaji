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

    deinit {
        process?.terminate()
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
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                self.isRunning = false
                self.isBusy = false
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
        process?.terminate()
        process = nil
        isRunning = false
        isBusy = false
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
