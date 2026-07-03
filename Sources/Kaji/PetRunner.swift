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

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        if isBusy || isRunning { return }
        guard let root = Self.findPetHatchRoot() else {
            lastError = "pethatch_missing"
            return
        }

        isBusy = true
        lastError = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.currentDirectoryURL = root
        process.arguments = [
            "-lc",
            "./bin/pethatch run xiaochai --size small --pin >> /tmp/kaji-xiaochai.log 2>&1",
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
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

    private static func findPetHatchRoot() -> URL? {
        let candidates = [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("workspace/pethatch"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Developer/pethatch"),
        ]
        return candidates.first { url in
            FileManager.default.fileExists(atPath: url.appendingPathComponent("bin/pethatch").path)
        }
    }
}
