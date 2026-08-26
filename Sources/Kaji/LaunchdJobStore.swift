import Foundation
import KajiCore

@MainActor
final class LaunchdJobStore: ObservableObject {
    @Published private(set) var snapshot = LaunchdJobSnapshot(jobs: [])
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let loadSnapshot: @Sendable () throws -> LaunchdJobSnapshot
    private var enabled = false
    private var popoverVisible = false
    private var refreshGeneration = 0
    private(set) var refreshInvocationCount = 0

    init(
        initialSnapshot: LaunchdJobSnapshot = LaunchdJobSnapshot(jobs: []),
        loadSnapshot: (@Sendable () throws -> LaunchdJobSnapshot)? = nil
    ) {
        snapshot = initialSnapshot
        self.loadSnapshot = loadSnapshot ?? { try LaunchdJobStore.loadLocalSnapshot() }
    }

    var isActive: Bool { enabled && popoverVisible }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if enabled {
            if popoverVisible { refresh() }
        } else {
            refreshGeneration += 1
            isRefreshing = false
            lastError = nil
            snapshot = LaunchdJobSnapshot(jobs: [])
        }
    }

    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        if visible {
            refresh()
        } else {
            refreshGeneration += 1
            isRefreshing = false
        }
    }

    func refresh() {
        guard isActive, !isRefreshing else { return }
        isRefreshing = true
        refreshInvocationCount += 1
        if ProcessInfo.processInfo.environment["KAJI_UI_SMOKE_AUDIT_LAUNCHD_REFRESH"] == "1" {
            FileHandle.standardOutput.write(Data("KAJI_UI_SMOKE launchd-refresh\n".utf8))
        }
        let generation = refreshGeneration
        let loader = loadSnapshot
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try loader() }
            DispatchQueue.main.async {
                guard let self,
                      self.isActive,
                      generation == self.refreshGeneration else { return }
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
