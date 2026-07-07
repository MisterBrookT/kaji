import Foundation

// MARK: - Pet catalog

struct PetOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let assetLicense: String?
    let commercialUseAllowed: Bool?
    let sourceURL: URL?

    var choiceTitle: String {
        displayName
    }

    var isNonCommercial: Bool {
        if commercialUseAllowed == false { return true }
        return assetLicense?.lowercased().contains("nc") == true
    }

    var licenseTitle: String {
        assetLicense ?? "unknown"
    }
}

@MainActor
final class PetCatalogStore: ObservableObject {
    @Published private(set) var options: [PetOption]
    @Published private(set) var resolvedPetId: String

    init() {
        options = PetCatalogStore.fallbackOptions
        resolvedPetId = PetCatalogStore.defaultFallbackPetId
    }

    @discardableResult
    func refresh(selectedPetId: String? = nil) -> String {
        options = Self.fallbackOptions
        resolvedPetId = "navi"
        return resolvedPetId
    }

    func displayName(for petId: String) -> String {
        options.first(where: { $0.id == petId })?.displayName ?? petId
    }

    func summary(language: Lang) -> String {
        if language == .zh {
            return "\u{9ED8}\u{8BA4}\u{5BA0}\u{7269}\u{FF1A}navi"
        }
        return "Default pet: navi"
    }

    func selectedPet(for petId: String) -> PetOption? {
        options.first(where: { $0.id == petId })
    }

    private static let fallbackOptions: [PetOption] = [
        PetOption(id: "navi", displayName: "navi", assetLicense: "MIT", commercialUseAllowed: true, sourceURL: nil),
    ]

    private static var defaultFallbackPetId: String {
        resolveSelectedPetId(nil, in: fallbackOptions)
    }

    private static func resolveSelectedPetId(_ selectedPetId: String?, in options: [PetOption]) -> String {
        "navi"
    }

    private static func petInfo(for entry: PetHatchManifestPet, root: URL) -> PetHatchPetManifest? {
        guard let manifestPath = entry.manifest, !manifestPath.isEmpty else { return nil }
        let url = root.appendingPathComponent(manifestPath)
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PetHatchPetManifest.self, from: data)
        } catch {
            return nil
        }
    }

    private static func isRunnable(_ entry: PetHatchManifestPet, root: URL) -> Bool {
        guard let manifest = entry.manifest, !manifest.isEmpty,
              let runtime = entry.runtime, !runtime.isEmpty,
              let spritesheet = entry.spritesheet, !spritesheet.isEmpty else {
            return false
        }
        let fm = FileManager.default
        return fm.fileExists(atPath: root.appendingPathComponent(manifest).path)
            && fm.fileExists(atPath: root.appendingPathComponent(runtime).path)
            && fm.fileExists(atPath: root.appendingPathComponent(spritesheet).path)
    }

    private static func sourceURL(for pet: PetHatchPetManifest?) -> URL? {
        let raw = pet?.author?.url ?? pet?.license?.source
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

private struct PetHatchManifest: Decodable {
    let featuredPetIds: [String]
    let pets: [PetHatchManifestPet]

    private enum CodingKeys: String, CodingKey {
        case featuredPetIds
        case pets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        featuredPetIds = try container.decodeIfPresent([String].self, forKey: .featuredPetIds) ?? []
        pets = try container.decode([PetHatchManifestPet].self, forKey: .pets)
    }
}

private struct PetHatchManifestPet: Decodable {
    let id: String
    let displayName: String
    let manifest: String?
    let runtime: String?
    let spritesheet: String?
}

private struct PetHatchPetManifest: Decodable {
    let license: PetHatchPetLicense?
    let author: PetHatchPetAuthor?
}

private struct PetHatchPetLicense: Decodable {
    let assets: String?
    let commercialUse: Bool?
    let source: String?
}

private struct PetHatchPetAuthor: Decodable {
    let url: String?
}
