import Foundation

// MARK: - Pet catalog

struct PetOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let assetLicense: String?
    let commercialUseAllowed: Bool?

    var choiceTitle: String {
        isNonCommercial ? "\(displayName) \u{00B7} NC" : displayName
    }

    private var isNonCommercial: Bool {
        if commercialUseAllowed == false { return true }
        return assetLicense?.lowercased().contains("nc") == true
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
                .map { entry in
                    let license = Self.licenseInfo(for: entry, root: root)
                    return PetOption(id: entry.id,
                                     displayName: entry.displayName.isEmpty ? entry.id : entry.displayName,
                                     assetLicense: license?.assets,
                                     commercialUseAllowed: license?.commercialUse)
                }
            options = pets.isEmpty ? Self.withSelectedFallback(selectedPetId) : Self.withSelected(pets, selectedPetId)
        } catch {
            options = Self.withSelectedFallback(selectedPetId)
        }
    }

    func displayName(for petId: String) -> String {
        options.first(where: { $0.id == petId })?.displayName ?? petId
    }

    private static let fallbackOptions: [PetOption] = [
        PetOption(id: "xiaochai", displayName: "小柴", assetLicense: "CC-BY-NC-4.0", commercialUseAllowed: false),
        PetOption(id: "openclaw", displayName: "Openclaw", assetLicense: "MIT", commercialUseAllowed: true),
    ]

    private static func withSelectedFallback(_ selectedPetId: String?) -> [PetOption] {
        withSelected(fallbackOptions, selectedPetId)
    }

    private static func withSelected(_ options: [PetOption], _ selectedPetId: String?) -> [PetOption] {
        guard let selectedPetId, !selectedPetId.isEmpty,
              !options.contains(where: { $0.id == selectedPetId }) else {
            return options
        }
        return [PetOption(id: selectedPetId, displayName: selectedPetId, assetLicense: nil, commercialUseAllowed: nil)] + options
    }

    private static func licenseInfo(for entry: PetHatchManifestPet, root: URL) -> PetHatchPetLicense? {
        guard let manifestPath = entry.manifest, !manifestPath.isEmpty else { return nil }
        let url = root.appendingPathComponent(manifestPath)
        do {
            let data = try Data(contentsOf: url)
            let pet = try JSONDecoder().decode(PetHatchPetManifest.self, from: data)
            return pet.license
        } catch {
            return nil
        }
    }
}

private struct PetHatchManifest: Decodable {
    let pets: [PetHatchManifestPet]
}

private struct PetHatchManifestPet: Decodable {
    let id: String
    let displayName: String
    let manifest: String?
}

private struct PetHatchPetManifest: Decodable {
    let license: PetHatchPetLicense?
}

private struct PetHatchPetLicense: Decodable {
    let assets: String?
    let commercialUse: Bool?
}
