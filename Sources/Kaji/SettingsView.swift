import SwiftUI

// MARK: - SettingsView
//
// Slower preferences live outside the status popover so the main surface stays
// focused on quota, system state, and pet controls.
struct SettingsView: View {
    @ObservedObject var prefs: Prefs

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme, prefs.menubarStyle) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
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
            settingRow(title: L10n.t(.petChoice, prefs.language)) {
                ForEach(PetChoice.allCases, id: \.rawValue) { pet in
                    segment(pet.displayName, on: prefs.petId == pet) {
                        prefs.petId = pet
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 360, alignment: .topLeading)
        .background(t.bg)
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
