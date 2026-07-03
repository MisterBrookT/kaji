import Foundation

// MARK: - PetHatch locator

enum PetHatchLocator {
    static let rootDefaultsKey = "petHatchRoot"

    static func findRoot() -> URL? {
        let candidates = configuredRoots() + [
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("workspace/pethatch"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Developer/pethatch"),
        ]
        return candidates.first { root in
            FileManager.default.fileExists(atPath: root.appendingPathComponent("bin/pethatch").path)
        }
    }

    private static func configuredRoots() -> [URL] {
        var roots: [URL] = []
        if let env = ProcessInfo.processInfo.environment["KAJI_PETHATCH_ROOT"], !env.isEmpty {
            roots.append(URL(fileURLWithPath: NSString(string: env).expandingTildeInPath))
        }
        if let raw = UserDefaults.standard.string(forKey: rootDefaultsKey), !raw.isEmpty {
            roots.append(URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath))
        }
        return roots
    }
}
