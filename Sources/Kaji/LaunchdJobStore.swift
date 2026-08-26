import Foundation
import KajiCore

@MainActor
final class LaunchdJobStore: ObservableObject {
    @Published private(set) var snapshot = LaunchdJobSnapshot(jobs: [])
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private var timer: Timer?
    private let loadSnapshot: @Sendable () throws -> LaunchdJobSnapshot
    private(set) var refreshInvocationCount = 0

    init(
        initialSnapshot: LaunchdJobSnapshot = LaunchdJobSnapshot(jobs: []),
        loadSnapshot: (@Sendable () throws -> LaunchdJobSnapshot)? = nil
    ) {
        snapshot = initialSnapshot
        self.loadSnapshot = loadSnapshot ?? { try LaunchdJobStore.loadLocalSnapshot() }
    }

    var isPolling: Bool { timer != nil }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            refresh()
        } else {
            timer?.invalidate()
            timer = nil
            isRefreshing = false
            lastError = nil
            snapshot = LaunchdJobSnapshot(jobs: [])
        }
    }

    func refresh() {
        guard timer != nil, !isRefreshing else { return }
        isRefreshing = true
        refreshInvocationCount += 1
        let loader = loadSnapshot
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try loader() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.lastError = nil
                case .failure:
                    self.lastError = "launchctl_list_failed"
                }
            }
        }
    }

    func stop() {
        setEnabled(false)
    }

    nonisolated private static func loadLocalSnapshot() throws -> LaunchdJobSnapshot {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LaunchdJobStoreError.launchctlFailed
        }
        let listOutput = String(decoding: data, as: UTF8.self)
        return LaunchdJobLogic.snapshot(
            listOutput: listOutput,
            installedLabels: installedUserAgentLabels()
        )
    }

    nonisolated private static func installedUserAgentLabels() -> Set<String> {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return Set(files.compactMap { url in
            guard url.pathExtension == "plist" else { return nil }
            if let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
               let dictionary = plist as? [String: Any],
               let label = dictionary["Label"] as? String,
               !label.isEmpty {
                return label
            }
            // A plist file is still an installed agent even when an updater
            // omits Label or the file is temporarily malformed. Keep it
            // visible under its conventional filename-derived label.
            return url.deletingPathExtension().lastPathComponent
        })
    }
}

private enum LaunchdJobStoreError: Error {
    case launchctlFailed
}
