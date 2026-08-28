import Foundation

public enum ExposureExperimentPhase: String, Codable, Sendable {
    case notStarted
    case baseline
    case treatment
    case rolledBack

    public var usesLegacyExposure: Bool {
        self != .treatment
    }
}

public struct ExposureExperimentState: Codable, Equatable, Sendable {
    public var startedAt: Date?
    public var rolledBackAt: Date?

    public init(startedAt: Date? = nil, rolledBackAt: Date? = nil) {
        self.startedAt = startedAt
        self.rolledBackAt = rolledBackAt
    }
}

public enum ExposureEntrySource: String, Codable, CaseIterable, Sendable {
    case statusItem
    case primary
    case more
    case cli
}

public enum ExposureExperimentLogic {
    public static let baselineDuration: TimeInterval = 72 * 60 * 60

    public static func phase(state: ExposureExperimentState, now: Date) -> ExposureExperimentPhase {
        guard let start = state.startedAt else { return .notStarted }
        if let rollback = state.rolledBackAt, rollback <= now { return .rolledBack }
        let elapsed = now.timeIntervalSince(start)
        if elapsed < 0 || elapsed < baselineDuration { return .baseline }
        return .treatment
    }

    public static func start(state: inout ExposureExperimentState, now: Date) {
        guard state.startedAt == nil else { return }
        state.startedAt = now
        state.rolledBackAt = nil
    }

    public static func rollback(state: inout ExposureExperimentState, now: Date) {
        guard state.startedAt != nil else { return }
        state.rolledBackAt = now
    }

    public static func normalizedFavorites(
        _ favorites: [KajiModuleID],
        enabled: Set<KajiModuleID>
    ) -> [KajiModuleID] {
        var seen = Set<KajiModuleID>()
        return favorites.filter { module in
            module != .quota && enabled.contains(module) && seen.insert(module).inserted
        }.prefix(2).map { $0 }
    }

    public static func primaryModules(
        enabled: Set<KajiModuleID>,
        favorites: [KajiModuleID]
    ) -> [KajiModuleID] {
        [.quota] + normalizedFavorites(favorites, enabled: enabled)
    }

    public static func moreModules(
        enabled: Set<KajiModuleID>,
        favorites: [KajiModuleID]
    ) -> [KajiModuleID] {
        let primary = Set(primaryModules(enabled: enabled, favorites: favorites))
        return KajiModuleID.stableOrder.filter { enabled.contains($0) && !primary.contains($0) }
    }

    public static func visiblePopoverModules(
        phase: ExposureExperimentPhase,
        enabled: Set<KajiModuleID>,
        favorites: [KajiModuleID]
    ) -> [KajiModuleID] {
        if phase.usesLegacyExposure {
            return ModulePrefsLogic.popoverPages(enabled: enabled)
        }
        return primaryModules(enabled: enabled, favorites: favorites)
    }
}
