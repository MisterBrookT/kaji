import Foundation

// MARK: - Pet catalog

struct PetOption: Identifiable, Equatable {
    let id: String
    let displayName: String
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
                .map { PetOption(id: $0.id, displayName: $0.displayName.isEmpty ? $0.id : $0.displayName) }
            options = pets.isEmpty ? Self.withSelectedFallback(selectedPetId) : Self.withSelected(pets, selectedPetId)
        } catch {
            options = Self.withSelectedFallback(selectedPetId)
        }
    }

    func displayName(for petId: String) -> String {
        options.first(where: { $0.id == petId })?.displayName ?? petId
    }

    private static let fallbackOptions: [PetOption] = [
        PetOption(id: "xiaochai", displayName: "小柴"),
        PetOption(id: "openclaw", displayName: "Openclaw"),
    ]

    private static func withSelectedFallback(_ selectedPetId: String?) -> [PetOption] {
        withSelected(fallbackOptions, selectedPetId)
    }

    private static func withSelected(_ options: [PetOption], _ selectedPetId: String?) -> [PetOption] {
        guard let selectedPetId, !selectedPetId.isEmpty,
              !options.contains(where: { $0.id == selectedPetId }) else {
            return options
        }
        return [PetOption(id: selectedPetId, displayName: selectedPetId)] + options
    }
}

private struct PetHatchManifest: Decodable {
    let pets: [PetHatchManifestPet]
}

private struct PetHatchManifestPet: Decodable {
    let id: String
    let displayName: String
}
