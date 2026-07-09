import AppKit
import SwiftUI

// MARK: - SettingsView
//
// Slower preferences live outside the status popover so the main surface stays
// focused on quota, system state, and pet controls.
struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var sleepController: SleepController
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
            settingBlock(title: L10n.t(.system, prefs.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    settingRow(title: L10n.t(.launchAtLogin, prefs.language)) {
                        segment(prefs.launchAtLogin ? "On" : "Off", on: prefs.launchAtLogin) {
                            prefs.launchAtLogin.toggle()
                        }
                    }
                    settingRow(title: L10n.t(.keepAwake, prefs.language)) {
                        segment(preventSleepTitle, on: prefs.preventSleep) {
                            prefs.preventSleep.toggle()
                        }
                        .disabled(sleepController.isBusy)
                    }
                }
            }
            settingBlock(title: L10n.t(.work, prefs.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    settingRow(title: L10n.t(.focusLength, prefs.language)) {
                        segment("25m", on: prefs.focusMinutes == 25) { prefs.focusMinutes = 25 }
                        segment("45m", on: prefs.focusMinutes == 45) { prefs.focusMinutes = 45 }
                        segment("60m", on: prefs.focusMinutes == 60) { prefs.focusMinutes = 60 }
                    }
                    settingRow(title: L10n.t(.breakLength, prefs.language)) {
                        segment("2m", on: prefs.breakMinutes == 2) { prefs.breakMinutes = 2 }
                        segment("5m", on: prefs.breakMinutes == 5) { prefs.breakMinutes = 5 }
                        segment("10m", on: prefs.breakMinutes == 10) { prefs.breakMinutes = 10 }
                    }
                    settingRow(title: L10n.t(.skipBreak, prefs.language)) {
                        segment(prefs.allowBreakSkip ? "On" : "Off", on: prefs.allowBreakSkip) {
                            prefs.allowBreakSkip.toggle()
                        }
                    }
                    settingRow(title: L10n.t(.breakOverlay, prefs.language)) {
                        segment(prefs.breakOverlayEnabled ? "On" : "Off", on: prefs.breakOverlayEnabled) {
                            prefs.breakOverlayEnabled.toggle()
                        }
                    }
                }
            }
            settingBlock(title: L10n.t(.pet, prefs.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    selectedPetMeta
                }
            }
            settingBlock(title: "AI") {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(providerSettingsKeys, id: \.self) { key in
                        providerRow(key)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 360, alignment: .topLeading)
        .background(t.bg)
        .onAppear {
            refreshPetCatalogSelection()
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

    private var selectedPetMeta: some View {
        HStack(spacing: 7) {
            Spacer()
            if let pet = petCatalog.selectedPet(for: prefs.petId) {
                Text("\(pet.displayName) \u{00B7} \(pet.licenseTitle)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute.opacity(0.82))
                    .lineLimit(1)
                if let sourceURL = pet.sourceURL {
                    outlineButton(title: L10n.t(.source, prefs.language), systemImage: "link") {
                        NSWorkspace.shared.open(sourceURL)
                    }
                }
            }
        }
    }

    private var providerSettingsKeys: [String] {
        Providers.sorted(Array(Providers.available))
    }

    private var preventSleepTitle: String {
        if sleepController.isBusy {
            return prefs.preventSleep ? "On\u{2026}" : "Off\u{2026}"
        }
        return prefs.preventSleep ? "On" : "Off"
    }

    private func providerRow(_ key: String) -> some View {
        HStack(spacing: 8) {
            ProviderLogo(key: key, color: prefs.isVisible(key) ? t.gold : t.ash, size: 13)
            Text(Providers.displayName(for: key))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                prefs.toggleProvider(key)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: prefs.isVisible(key) ? "eye" : "eye.slash")
                        .font(.system(size: 10, weight: .semibold))
                    Text(prefs.isVisible(key) ? "Show" : "Hide")
                }
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(prefs.isVisible(key) ? t.bg : t.mute)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(prefs.isVisible(key) ? t.gold : Color.clear)
                        .overlay(Capsule().stroke(prefs.isVisible(key) ? Color.clear : t.track, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(prefs.isVisible(key) && prefs.visibleProviders.count <= 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.panel.opacity(0.65)))
    }

    private func openPetGallery() {
        guard let url = URL(string: "https://misterbrookt.github.io/pethatch/") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshPetCatalogSelection() {
        let resolvedPetId = petCatalog.refresh(selectedPetId: prefs.petId)
        guard !resolvedPetId.isEmpty, prefs.petId != resolvedPetId else { return }
        prefs.petId = resolvedPetId
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
