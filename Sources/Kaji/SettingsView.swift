import AppKit
import SwiftUI

// MARK: - SettingsView
//
// Slower preferences live outside the status popover so the main surface stays
// focused on quota, system state, and pet controls.
struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var petCatalog: PetCatalogStore

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme, prefs.menubarStyle) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            settingBlock(title: L10n.t(.appearance, prefs.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    settingRow(title: L10n.t(.language, prefs.language)) {
                        segment(prefs.language.label, on: true) {
                            prefs.language = prefs.language.toggled
                        }
                    }
                    settingRow(title: L10n.t(.menubar, prefs.language)) {
                        segment(L10n.t(.styleBlackWhite, prefs.language), on: prefs.menubarStyle == .blackWhite) {
                            prefs.menubarStyle = .blackWhite
                        }
                        segment(L10n.t(.styleMono, prefs.language), on: prefs.menubarStyle == .mono) {
                            prefs.menubarStyle = .mono
                        }
                        segment(L10n.t(.styleColor, prefs.language), on: prefs.menubarStyle == .color) {
                            prefs.menubarStyle = .color
                        }
                    }
                    settingRow(title: L10n.t(.usage, prefs.language)) {
                        segment(L10n.t(.showUsed, prefs.language), on: !prefs.showRemaining) {
                            prefs.showRemaining = false
                        }
                        segment(L10n.t(.showRemaining, prefs.language), on: prefs.showRemaining) {
                            prefs.showRemaining = true
                        }
                    }
                    settingRow(title: L10n.t(.panelSize, prefs.language)) {
                        segment(L10n.t(.sizeSmall, prefs.language), on: prefs.panelSize == .small) {
                            prefs.panelSize = .small
                        }
                        segment(L10n.t(.sizeMedium, prefs.language), on: prefs.panelSize == .medium) {
                            prefs.panelSize = .medium
                        }
                    }
                }
            }
            settingBlock(title: L10n.t(.petChoice, prefs.language)) {
                LazyVGrid(columns: petColumns, alignment: .trailing, spacing: 7) {
                    ForEach(petCatalog.options) { pet in
                        segment(pet.choiceTitle, on: prefs.petId == pet.id) {
                            prefs.petId = pet.id
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                HStack {
                    Spacer()
                    outlineButton(title: L10n.t(.petGallery, prefs.language), systemImage: "globe") {
                        openPetGallery()
                    }
                    outlineButton(title: L10n.t(.refreshNow, prefs.language), systemImage: "arrow.clockwise") {
                        petCatalog.refresh(selectedPetId: prefs.petId)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 360, alignment: .topLeading)
        .background(t.bg)
        .onAppear {
            petCatalog.refresh(selectedPetId: prefs.petId)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t(.settings, prefs.language))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(t.cream)
            Text("Kaji")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(t.mute)
        }
    }

    private func settingRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(t.mute)
                .frame(width: 88, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                content()
            }
        }
    }

    private func settingBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(t.mute)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var petColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 86, maximum: 132), spacing: 7, alignment: .trailing)]
    }

    private func openPetGallery() {
        guard let url = URL(string: "https://misterbrookt.github.io/pethatch/") else { return }
        NSWorkspace.shared.open(url)
    }

    private func outlineButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundColor(t.mute)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.clear)
                .overlay(Capsule().stroke(t.track, lineWidth: 1))
        )
        .accessibilityLabel(Text(title))
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(on ? t.bg : t.mute)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(on ? t.gold : Color.clear)
                        .overlay(Capsule().stroke(on ? Color.clear : t.track, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}
