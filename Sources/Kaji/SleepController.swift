import Foundation

// MARK: - SleepController
//
// Manages macOS SleepDisabled via pmset. This is intentionally explicit: closed
// lid / hardware sleep prevention requires a privileged system setting, unlike
// a plain IOPMAssertion/caffeinate idle assertion.
@MainActor
final class SleepController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var targetEnabled: Bool?
    @Published private(set) var lastError: String?

    init(previewEnabled: Bool? = nil) {
        if let previewEnabled {
            isEnabled = previewEnabled
        } else {
            refresh()
        }
    }

    func refresh() {
        isEnabled = Self.readSleepDisabled()
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        if isBusy { return }
        refresh()
        if isEnabled == enabled { return }
        isBusy = true
        targetEnabled = enabled
        lastError = nil
        Task {
            let ok = await Self.runPrivilegedPmset(disabled: enabled)
            await MainActor.run {
                self.isBusy = false
                self.targetEnabled = nil
                self.refresh()
                if !ok {
                    self.lastError = "pmset_failed"
                }
            }
        }
    }

    private static func readSleepDisabled() -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return false }
        return parseSleepDisabled(out)
    }

    static func parseSleepDisabled(_ output: String) -> Bool {
        output
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let parts = line.split(whereSeparator: \.isWhitespace)
                return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
            }
    }

    private static func runPrivilegedPmset(disabled: Bool) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let value = disabled ? "1" : "0"
            let command = "/usr/bin/pmset -a disablesleep \(value)"
            let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "do shell script \"\(escaped)\" with administrator privileges"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }
}
