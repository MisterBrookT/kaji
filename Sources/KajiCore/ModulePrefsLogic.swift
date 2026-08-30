import Foundation

/// First-party menu-bar modules (lean-modules-v1).
public enum KajiModuleID: String, CaseIterable, Codable, Sendable, Comparable {
    case quota
    case work
    case system
    case goals
    case mailBrief
    case launchd

    /// Stable popover order. Unknown / disabled ids never appear here.
    public static let stableOrder: [KajiModuleID] = [.quota, .work, .system, .goals, .mailBrief, .launchd]

    public static func < (lhs: KajiModuleID, rhs: KajiModuleID) -> Bool {
        let li = stableOrder.firstIndex(of: lhs) ?? Int.max
        let ri = stableOrder.firstIndex(of: rhs) ?? Int.max
        return li < ri
    }
}

/// Prefs / popover helpers for enabled modules.
///
/// Spec: `dev_docs/specs/2026-07-24-lean-modules-v1.md`
public enum ModulePrefsLogic {
    /// Default after first migration / empty prefs: quota only.
    public static let slimDefault: Set<KajiModuleID> = [.quota]

    /// Normalize raw UserDefaults strings into a valid enabled set.
    /// - Always includes `.quota`
    /// - Drops unknown ids
    /// - Empty / nil → `slimDefault`
    public static func normalizeEnabledModules(_ raw: [String]?) -> Set<KajiModuleID> {
        guard let raw, !raw.isEmpty else {
            return slimDefault
        }

        var enabled = Set(raw.compactMap { KajiModuleID(rawValue: $0) })
        if enabled.isEmpty {
            return slimDefault
        }
        enabled.insert(.quota)
        return enabled
    }

    /// Keep at most two enabled, non-quota favorites in insertion order.
    public static func normalizedFavorites(
        _ favorites: [KajiModuleID],
        enabled: Set<KajiModuleID>
    ) -> [KajiModuleID] {
        var seen = Set<KajiModuleID>()
        return favorites.filter { module in
            module != .quota && enabled.contains(module) && seen.insert(module).inserted
        }.prefix(2).map { $0 }
    }

    /// Quota plus the user's two menu-bar favorites.
    public static func primaryModules(
        enabled: Set<KajiModuleID>,
        favorites: [KajiModuleID]
    ) -> [KajiModuleID] {
        [.quota] + normalizedFavorites(favorites, enabled: enabled)
    }

    /// Enabled modules not already promoted to the primary menu-bar surface.
    public static func moreModules(
        enabled: Set<KajiModuleID>,
        favorites: [KajiModuleID]
    ) -> [KajiModuleID] {
        let primary = Set(primaryModules(enabled: enabled, favorites: favorites))
        return KajiModuleID.stableOrder.filter { enabled.contains($0) && !primary.contains($0) }
    }
}
