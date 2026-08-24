public enum BreakSceneID: String, CaseIterable, Codable, Sendable {
    case windowRain

    public var resourceName: String {
        "break-window-rain"
    }
}

public enum BreakSceneModel {
    public static func scene(sessionSeed: UInt64) -> BreakSceneID {
        _ = sessionSeed
        return .windowRain
    }

    public static func allowsMotion(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
