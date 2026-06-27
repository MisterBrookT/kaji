import Foundation

// MARK: - Pet bridge
//
// Kaji does not own a desktop-pet runtime. It publishes a small local state file
// so pet runtimes can map quota pressure to animation.

enum PetAnimationState: String, Codable {
    case idle
    case running
    case waiting
    case failed
    case review
}

struct PetProviderSignal: Codable, Equatable {
    let id: String
    let displayName: String
    let fiveHourPercent: Double?
    let sevenDayPercent: Double?
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
    let dataStatus: String
    let pressure: String
}

struct PetBridgeState: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let animationState: PetAnimationState
    let reason: String
    let summary: String
    let severity: Double
    let dominantProvider: String?
    let providers: [PetProviderSignal]
}

enum PetBridge {
    static let schemaVersion = 1

    static var outputURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Kaji", isDirectory: true)
            .appendingPathComponent("pet-state.json")
    }

    static func write(providers: [ProviderView], lastError: String?, generatedAt: Date = Date()) {
        let state = makeState(providers: providers, lastError: lastError, generatedAt: generatedAt)
        do {
            let url = outputURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[Kaji] pet bridge write failed: %@", error.localizedDescription)
        }
    }

    static func makeState(providers: [ProviderView],
                          lastError: String?,
                          generatedAt: Date = Date()) -> PetBridgeState {
        let signals = providers.map(signal)
        let dominant = providers.max { pressureScore($0) < pressureScore($1) }
        let severity = min(max(dominant.map(pressureScore) ?? 0, 0), 1)

        if let lastError, !lastError.isEmpty {
            return PetBridgeState(
                schemaVersion: schemaVersion,
                generatedAt: generatedAt,
                animationState: .failed,
                reason: lastError == Config.noPythonSentinel ? "python_missing" : "quota_refresh_failed",
                summary: lastError == Config.noPythonSentinel
                    ? "Kaji cannot find a working python3."
                    : "Kaji could not refresh quota data.",
                severity: max(severity, 0.75),
                dominantProvider: dominant?.id,
                providers: signals
            )
        }

        guard let dominant else {
            return PetBridgeState(
                schemaVersion: schemaVersion,
                generatedAt: generatedAt,
                animationState: .waiting,
                reason: "no_provider_data",
                summary: "Kaji has no readable provider quota data yet.",
                severity: 0.5,
                dominantProvider: nil,
                providers: signals
            )
        }

        let score = pressureScore(dominant)
        let rising = isRising(dominant)
        let state: PetAnimationState
        let reason: String
        let summary: String

        if score >= 0.95 {
            state = .waiting
            reason = "quota_limit"
            summary = "\(dominant.displayName) is at or near its quota limit."
        } else if score >= 0.80 {
            state = .review
            reason = "quota_pressure"
            summary = "\(dominant.displayName) quota is getting tight."
        } else if rising {
            state = .running
            reason = "quota_active"
            summary = "\(dominant.displayName) usage is moving."
        } else {
            state = .idle
            reason = "quota_healthy"
            summary = "Provider quota looks healthy."
        }

        return PetBridgeState(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            animationState: state,
            reason: reason,
            summary: summary,
            severity: score,
            dominantProvider: dominant.id,
            providers: signals
        )
    }

    private static func signal(_ provider: ProviderView) -> PetProviderSignal {
        PetProviderSignal(
            id: provider.id,
            displayName: provider.displayName,
            fiveHourPercent: provider.fiveHourPercent,
            sevenDayPercent: provider.weekPercent,
            fiveHourResetsAt: provider.resetDate,
            sevenDayResetsAt: provider.weekResetDate,
            dataStatus: hasAnyData(provider) ? "ok" : "missing",
            pressure: pressureLabel(provider)
        )
    }

    private static func pressureScore(_ provider: ProviderView) -> Double {
        let five = (provider.fiveHourPercent ?? 0) / 100
        let week = (provider.weekPercent ?? 0) / 100
        return max(five, week)
    }

    private static func pressureLabel(_ provider: ProviderView) -> String {
        let score = pressureScore(provider)
        if score >= 0.95 { return "limit" }
        if score >= 0.80 { return "warn" }
        if hasAnyData(provider) { return "healthy" }
        return "unknown"
    }

    private static func hasAnyData(_ provider: ProviderView) -> Bool {
        provider.fiveHourPercent != nil
            || provider.weekPercent != nil
            || provider.resetDate != nil
            || provider.weekResetDate != nil
    }

    private static func isRising(_ provider: ProviderView) -> Bool {
        guard provider.history.count >= 2,
              let last = provider.history.last,
              let prev = provider.history.dropLast().last else {
            return false
        }
        return last - prev >= 0.5
    }
}
