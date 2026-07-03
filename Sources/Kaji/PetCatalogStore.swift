import Foundation

// MARK: - Pet catalog

struct PetOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let assetLicense: String?
    let commercialUseAllowed: Bool?
    let sourceURL: URL?

    var choiceTitle: String {
        isNonCommercial ? "\(displayName) \u{00B7} NC" : displayName
    }

    var isNonCommercial: Bool {
        if commercialUseAllowed == false { return true }
        return assetLicense?.lowercased().contains("nc") == true
    }

    var licenseTitle: String {
        var parts = [assetLicense ?? "unknown"]
        parts.append(isNonCommercial ? "NC" : "ready")
        return parts.joined(separator: " \u{00B7} ")
    }
}

@MainActor
final class PetCatalogStore: ObservableObject {
    @Published private(set) var options: [PetOption]

    init() {
        options = PetCatalogStore.fallbackOptions
    }

    func refresh(selectedPetId: String? = nil) {
        guard let root = PetHatchLocator.findRoot() else {
            options = Self.withSelectedFallback(selectedPetId)
            return
        }

        let manifestURL = root.appendingPathComponent("manifest.json")
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PetHatchManifest.self, from: data)
            let pets = manifest.pets
                .filter { !$0.id.isEmpty }
                .compactMap { entry -> PetOption? in
                    guard Self.isRunnable(entry, root: root),
                          let pet = Self.petInfo(for: entry, root: root) else {
                        return nil
                    }
                    return PetOption(id: entry.id,
                                     displayName: entry.displayName.isEmpty ? entry.id : entry.displayName,
                                     assetLicense: pet.license?.assets,
                                     commercialUseAllowed: pet.license?.commercialUse,
                                     sourceURL: Self.sourceURL(for: pet))
                }
            options = pets.isEmpty ? Self.withSelectedFallback(selectedPetId) : Self.withSelected(pets, selectedPetId)
        } catch {
            options = Self.withSelectedFallback(selectedPetId)
        }
    }

    func displayName(for petId: String) -> String {
        options.first(where: { $0.id == petId })?.displayName ?? petId
    }

    func summary(language: Lang) -> String {
        let total = options.count
        let nonCommercial = options.filter(\.isNonCommercial).count
        let ready = max(total - nonCommercial, 0)
        if language == .zh {
            return "\(total) \u{53EA}\u{5BA0}\u{7269} \u{00B7} \(ready) \u{53EA}\u{53EF}\u{5546}\u{7528} \u{00B7} \(nonCommercial) \u{53EA} NC"
        }
        return "\(total) pets \u{00B7} \(ready) ready \u{00B7} \(nonCommercial) NC"
    }

    func selectedPet(for petId: String) -> PetOption? {
        options.first(where: { $0.id == petId })
    }

    private static let fallbackOptions: [PetOption] = [
        PetOption(id: "xiaochai", displayName: "小柴", assetLicense: "CC-BY-NC-4.0", commercialUseAllowed: false, sourceURL: nil),
        PetOption(id: "openclaw", displayName: "Openclaw", assetLicense: "MIT", commercialUseAllowed: true, sourceURL: nil),
    ]

    private static func withSelectedFallback(_ selectedPetId: String?) -> [PetOption] {
        withSelected(fallbackOptions, selectedPetId)
    }

    private static func withSelected(_ options: [PetOption], _ selectedPetId: String?) -> [PetOption] {
        guard let selectedPetId, !selectedPetId.isEmpty,
              !options.contains(where: { $0.id == selectedPetId }) else {
            return options
        }
        return [PetOption(id: selectedPetId, displayName: selectedPetId, assetLicense: nil, commercialUseAllowed: nil, sourceURL: nil)] + options
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
    let pets: [PetHatchManifestPet]
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
