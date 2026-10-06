import Foundation

enum SleepHelperInstallStatus: Equatable {
    case installed
    case notInstalled
    case needsRepair
    case unavailable
}

struct SleepHelperInstaller: Sendable {
    static let live = SleepHelperInstaller()

    private let label = "dev.kaji.sleep-helper"
    private let installedHelper = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/dev.kaji.sleep-helper")
    private let installedPlist = URL(fileURLWithPath: "/Library/LaunchDaemons/dev.kaji.sleep-helper.plist")

    func status() -> SleepHelperInstallStatus {
        guard let bundledHelper, bundledPlist != nil, let hash = appCodeHash() else { return .unavailable }
        let fileManager = FileManager.default
        let hasHelper = fileManager.isExecutableFile(atPath: installedHelper.path)
        let hasPlist = fileManager.fileExists(atPath: installedPlist.path)
        guard hasHelper || hasPlist else { return .notInstalled }
        guard hasHelper,
              hasPlist,
              filesMatch(bundledHelper, installedHelper),
              installedCodeHash() == hash else {
            return .needsRepair
        }
        return .installed
    }

    func install() async throws {
        guard let bundledHelper, let bundledPlist, let hash = appCodeHash() else {
            throw SleepHelperInstallerError.missingBundleResources
        }

        let temporaryPlist = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev.kaji.sleep-helper-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: temporaryPlist) }
        try writeLegacyPlist(from: bundledPlist, to: temporaryPlist, codeHash: hash)

        let command = Self.installCommand(
            label: label, bundledHelper: bundledHelper.path, installedHelper: installedHelper.path,
            temporaryPlist: temporaryPlist.path, installedPlist: installedPlist.path
        )
        try await Task.detached(priority: .userInitiated) {
            try Self.runWithAdministratorPrivileges(command)
        }.value
    }

    static func installCommand(label: String, bundledHelper: String, installedHelper: String,
                               temporaryPlist: String, installedPlist: String) -> String {
        let commands = [
            "/bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "/bin/sleep 1",
            "/usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools",
            "/usr/bin/install -o root -g wheel -m 0755 \(shellQuote(bundledHelper)) \(shellQuote(installedHelper))",
            "/usr/bin/install -o root -g wheel -m 0644 \(shellQuote(temporaryPlist)) \(shellQuote(installedPlist))",
            "/bin/launchctl bootstrap system \(shellQuote(installedPlist))",
        ]
        return "set -e; " + commands.joined(separator: "; ")
    }

    private var bundledHelper: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HelperTools/KajiSleepHelper")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var bundledPlist: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/dev.kaji.sleep-helper.plist")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func writeLegacyPlist(from source: URL, to destination: URL, codeHash: String) throws {
        let data = try Data(contentsOf: source)
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any] else {
            throw SleepHelperInstallerError.invalidPlist
        }
        plist.removeValue(forKey: "BundleProgram")
        plist.removeValue(forKey: "AssociatedBundleIdentifiers")
        plist["ProgramArguments"] = [installedHelper.path, codeHash]
        plist["KeepAlive"] = true
        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try output.write(to: destination, options: Data.WritingOptions.atomic)
    }


    private func installedCodeHash() -> String? {
        guard let data = try? Data(contentsOf: installedPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = plist["ProgramArguments"] as? [String], args.count == 2,
              args[0] == installedHelper.path else { return nil }
        return args[1]
    }

    private func appCodeHash() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        return nil
        #endif
        process.arguments = ["-d", "--verbose=4", "--arch", architecture, Bundle.main.executableURL?.path ?? ""]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: output, encoding: .utf8),
              let range = text.range(of: #"(?m)^CDHash=([0-9a-fA-F]{40})$"#, options: .regularExpression) else { return nil }
        return String(text[range].dropFirst("CDHash=".count)).lowercased()
    }

    private func filesMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = try? FileHandle(forReadingFrom: lhs),
              let right = try? FileHandle(forReadingFrom: rhs) else { return false }
        defer {
            try? left.close()
            try? right.close()
        }
        while true {
            let leftChunk = try? left.read(upToCount: 65_536)
            let rightChunk = try? right.read(upToCount: 65_536)
            guard leftChunk == rightChunk else { return false }
            if leftChunk == nil || leftChunk?.isEmpty == true { return true }
        }
    }

    private static func runWithAdministratorPrivileges(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(escaped)\" with administrator privileges",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Authorization failed"
            throw SleepHelperInstallerError.authorizationFailed(message)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum SleepHelperInstallerError: Error {
    case missingBundleResources
    case invalidPlist
    case authorizationFailed(String)
}
