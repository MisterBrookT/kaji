public enum BreakSceneID: String, CaseIterable, Codable, Sendable {
    case windowRain
    case rainField
    case mistHill
    case sunlitMeadow

    public var resourceName: String {
        switch self {
        case .windowRain:
            return "break-window-rain"
        case .rainField:
            return "break-rain-field"
        case .mistHill:
            return "break-mist-hill"
        case .sunlitMeadow:
            return "break-sunlit-meadow"
        }
    }
}

public enum BreakSceneModel {
    public static func scene(sessionSeed: UInt64) -> BreakSceneID {
        let scenes = BreakSceneID.allCases
        return scenes[Int(sessionSeed % UInt64(scenes.count))]
    }

    public static func allowsMotion(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
