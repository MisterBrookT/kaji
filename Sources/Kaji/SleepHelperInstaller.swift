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
        guard let bundledHelper, bundledPlist != nil else { return .unavailable }
        let fileManager = FileManager.default
        let hasHelper = fileManager.isExecutableFile(atPath: installedHelper.path)
        let hasPlist = fileManager.fileExists(atPath: installedPlist.path)
        guard hasHelper || hasPlist else { return .notInstalled }
        guard hasHelper,
              hasPlist,
              filesMatch(bundledHelper, installedHelper) else {
            return .needsRepair
        }
        return .installed
    }

    func install() async throws {
        guard let bundledHelper, let bundledPlist else {
            throw SleepHelperInstallerError.missingBundleResources
        }

        let temporaryPlist = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev.kaji.sleep-helper-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: temporaryPlist) }
        try writeLegacyPlist(from: bundledPlist, to: temporaryPlist)

        let commands = [
            "/bin/launchctl bootout system/\(label) >/dev/null 2>&1 || true",
            "/bin/sleep 1",
            "/usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools",
            "/usr/bin/install -o root -g wheel -m 0755 \(shellQuote(bundledHelper.path)) \(shellQuote(installedHelper.path))",
            "/usr/bin/install -o root -g wheel -m 0644 \(shellQuote(temporaryPlist.path)) \(shellQuote(installedPlist.path))",
            "/bin/launchctl bootstrap system \(shellQuote(installedPlist.path)) >/dev/null 2>&1 || /bin/launchctl print system/\(label) >/dev/null 2>&1",
        ]
        let command = commands.joined(separator: "; ")
        try await Task.detached(priority: .userInitiated) {
            try Self.runWithAdministratorPrivileges(command)
        }.value
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

    private func writeLegacyPlist(from source: URL, to destination: URL) throws {
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
        plist["ProgramArguments"] = [installedHelper.path]
        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try output.write(to: destination, options: Data.WritingOptions.atomic)
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

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum SleepHelperInstallerError: Error {
    case missingBundleResources
    case invalidPlist
    case authorizationFailed(String)
}
