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
    private let petHatchRootKey = "petHatchRoot"

    deinit {
        process?.terminate()
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        if isBusy || isRunning { return }
        guard let root = findPetHatchRoot() else {
            lastError = "pethatch_missing"
            return
        }

        isBusy = true
        lastError = nil

        let process = Process()
        process.executableURL = root.appendingPathComponent("bin/pethatch")
        process.currentDirectoryURL = root
        process.arguments = [
            "run", "xiaochai",
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

    private func findPetHatchRoot() -> URL? {
        let candidates = configuredRoots() + [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("workspace/pethatch"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Developer/pethatch"),
        ]
        return candidates.first { url in
            FileManager.default.fileExists(atPath: url.appendingPathComponent("bin/pethatch").path)
        }
    }

    private func configuredRoots() -> [URL] {
        var roots: [URL] = []
        if let env = ProcessInfo.processInfo.environment["KAJI_PETHATCH_ROOT"], !env.isEmpty {
            roots.append(URL(fileURLWithPath: NSString(string: env).expandingTildeInPath))
        }
        if let raw = UserDefaults.standard.string(forKey: petHatchRootKey), !raw.isEmpty {
            roots.append(URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath))
        }
        return roots
    }

    private static func logFileHandle() -> FileHandle {
        let path = "/tmp/kaji-xiaochai.log"
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
