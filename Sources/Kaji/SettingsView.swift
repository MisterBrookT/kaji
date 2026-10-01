import AppKit
import SwiftUI
import KajiCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case work = "Work"
    case quota = "Quota"
    case permissions = "Permissions"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .work: "timer"
        case .quota: "gauge.with.dots.needle.67percent"
        case .permissions: "lock.shield"
        }
    }
}

private enum PermissionState: Equatable {
    case authorized, notAuthorized, needsReauthorization
}

// MARK: - SettingsView
//
// Slower preferences live outside the status popover so the main surface stays
// focused on modules, appearance, system, and fixed-plan templates.
struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var sleepController: SleepController
    @ObservedObject var fixedPlanStore: FixedPlanStore
    @ObservedObject var updateChecker: UpdateChecker
    let onInstallUpdate: (UpdateChecker.Release) -> Void
    let onOpenReleasePage: (URL) -> Void

    @State private var selection: SettingsSection = .general
    @State private var loginPermission: PermissionState = .notAuthorized
    @State private var sleepPermission: PermissionState = .notAuthorized


    init(
        prefs: Prefs,
        sleepController: SleepController,
        fixedPlanStore: FixedPlanStore,
        updateChecker: UpdateChecker = UpdateChecker(),
        initialSection: SettingsSection = .general,
        onInstallUpdate: @escaping (UpdateChecker.Release) -> Void = { _ in },
        onOpenReleasePage: @escaping (URL) -> Void = { _ in },
    ) {
        self.prefs = prefs
        self.sleepController = sleepController
        self.fixedPlanStore = fixedPlanStore
        self.updateChecker = updateChecker
        self.onInstallUpdate = onInstallUpdate
        self.onOpenReleasePage = onOpenReleasePage
        _selection = State(initialValue: initialSection)
    }
    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    private var visibleSections: [SettingsSection] {
        SettingsSection.allCases.filter { section in
            switch section {
            case .general, .quota, .permissions:
                return true
            case .work:
                return prefs.isModuleEnabled(.work)
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(visibleSections, selection: $selection) { section in
                Label(section == .permissions ? L10n.t(.permissions, prefs.language) : section.rawValue,
                      systemImage: section.systemImage)
                    .tag(section)
                    .accessibilityIdentifier("kaji.settings.section.\(section.rawValue)")
            }
            .listStyle(.sidebar)
            .frame(minWidth: 170, idealWidth: 190, maxWidth: 210)
            Divider().overlay(t.track)
            ScrollView {
                mainSettings
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(t.bg)
        .frame(minWidth: 640, minHeight: 460)
        .alert(
            sleepGuidanceTitle,
            isPresented: Binding(
                get: { sleepController.approvalFlow.isGuidancePresented },
                set: { presented in
                    if !presented {
                        sleepController.dismissApprovalGuidance()
                    }
                }
            )
        ) {
            Button(sleepGuidanceActionTitle) {
                sleepController.performGuidanceAction()
            }
            .accessibilityIdentifier("kaji.sleep-helper.guidance-action")
            Button(L10n.t(.cancel, prefs.language), role: .cancel) {
                sleepController.cancelApprovalRequest()
            }
            .accessibilityIdentifier("kaji.sleep-helper.cancel")
        } message: {
            Text(sleepGuidanceMessage)
        }
        .sheet(item: $updateChecker.reviewingRelease) { release in
            UpdateNotesSheet(
                release: release,
                currentVersion: updateChecker.currentVersion,
                language: prefs.language,
                onInstall: {
                    updateChecker.reviewingRelease = nil
                    onInstallUpdate(release)
                },
                onViewRelease: { onOpenReleasePage(release.url) },
                onCancel: { updateChecker.reviewingRelease = nil }
            )
        }
        .onChange(of: prefs.enabledModules) { _ in
            if !visibleSections.contains(selection) { selection = .general }
        }
    }

    private var updateButtonTitle: String {
        if let release = updateChecker.available {
            return L10n.t(.updateTo, prefs.language) + " " + release.tag
        }
        if updateChecker.isChecking { return L10n.t(.updateChecking, prefs.language) }
        if updateChecker.lastError != nil { return L10n.t(.updateFailed, prefs.language) }
        if updateChecker.lastChecked != nil { return L10n.t(.updateCurrent, prefs.language) }
        return L10n.t(.checkUpdates, prefs.language)
    }

    private var sleepGuidanceTitle: String {
        L10n.t(.sleepRepairTitle, prefs.language)
    }

    private var sleepGuidanceMessage: String {
        L10n.t(.sleepRepairMessage, prefs.language)
    }

    private var sleepGuidanceActionTitle: String {
        L10n.t(.repairHelper, prefs.language)
    }

    private var mainSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if selection == .general {
                settingBlock(title: L10n.t(.modules, prefs.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t(.modulesHint, prefs.language))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(t.mute)
                        .fixedSize(horizontal: false, vertical: true)
                    moduleRow(.quota, title: L10n.t(.moduleQuota, prefs.language), lockedOn: true)
                    moduleRow(.work, title: L10n.t(.moduleWork, prefs.language), lockedOn: false)
                    moduleRow(.goals, title: L10n.t(.moduleGoals, prefs.language), lockedOn: false)
                }
            }
                settingBlock(title: L10n.t(.appearance, prefs.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    settingRow(title: L10n.t(.language, prefs.language)) {
                        Picker(L10n.t(.language, prefs.language), selection: $prefs.language) {
                            ForEach(Lang.allCases, id: \.rawValue) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityIdentifier("kaji.settings.language")
                    }
                    settingRow(title: L10n.t(.usage, prefs.language)) {
                        Picker(L10n.t(.usage, prefs.language), selection: $prefs.showRemaining) {
                            Text(L10n.t(.showUsed, prefs.language)).tag(false)
                            Text(L10n.t(.showRemaining, prefs.language)).tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityIdentifier("kaji.settings.usage")
                    }
                }
            }
            settingBlock(title: L10n.t(.updates, prefs.language)) {
                settingRow(title: L10n.t(.currentVersion, prefs.language)) {
                    Text(updateChecker.currentVersion)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(t.mute)
                        .accessibilityIdentifier("kaji.settings.update.version")
                    segment(updateButtonTitle, on: updateChecker.available != nil,
                            accessibilityIdentifier: "kaji.settings.update.action") {
                        if let release = updateChecker.available {
                            updateChecker.reviewingRelease = release
                        } else {
                            updateChecker.checkIfDue(force: true)
                        }
                    }
                    .disabled(updateChecker.isChecking)
                    .help(updateChecker.lastError ?? updateButtonTitle)
                }
                if let error = updateChecker.lastError {
                    Text(error)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(t.mute)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kaji.settings.update.error")
                }
            }
            settingBlock(title: L10n.t(.system, prefs.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    settingRow(title: L10n.t(.launchAtLogin, prefs.language)) {
                        settingsToggle(isOn: $prefs.launchAtLogin,
                                       title: L10n.t(.launchAtLogin, prefs.language),
                                       identifier: "kaji.settings.launch-at-login.toggle")
                    }
                    settingRow(title: L10n.t(.keepAwake, prefs.language)) {
                        settingsToggle(
                            isOn: Binding(get: { sleepController.isEnabled },
                                          set: { _ in sleepController.toggle() }),
                            title: L10n.t(.keepAwake, prefs.language),
                            identifier: "kaji.prevent-sleep.toggle"
                        )
                        .disabled(sleepController.isBusy)
                        .help(L10n.t(.sleepPermissionWhy, prefs.language))
                    }
                    if sleepController.lastError != nil {
                        Text(L10n.t(.sleepRepairMessage, prefs.language))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(t.amber)
                    }
                }
            }
            }
            if selection == .permissions {
                settingBlock(title: L10n.t(.permissions, prefs.language)) {
                    VStack(alignment: .leading, spacing: 12) {
                        permissionRow(
                            title: L10n.t(.loginPermission, prefs.language),
                            why: L10n.t(.loginPermissionWhy, prefs.language),
                            status: loginPermission
                        ) {
                            _ = LoginItemManager.setEnabled(true)
                            refreshPermissions()
                        }
                        permissionRow(
                            title: L10n.t(.sleepPermission, prefs.language),
                            why: L10n.t(.sleepPermissionWhy, prefs.language),
                            status: sleepPermission
                        ) {
                            sleepController.setEnabled(true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                refreshPermissions()
                            }
                        }
                    }
                }
                .onAppear { refreshPermissions() }
            }
            if selection == .work {
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
            }
            if selection == .quota {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(providerSettingsKeys, id: \.self) { key in
                        providerRow(key)
                    }
                }
            }
        }
        .padding(24)
    }

    private func refreshPermissions() {
        switch LoginItemManager.authorizationStatus {
        case .authorized: loginPermission = .authorized
        case .notAuthorized: loginPermission = .notAuthorized
        case .needsReauthorization: loginPermission = .needsReauthorization
        }
        switch SleepController.authorizationStatus {
        case .authorized: sleepPermission = .authorized
        case .notAuthorized: sleepPermission = .notAuthorized
        case .needsReauthorization: sleepPermission = .needsReauthorization
        }
    }

    private func permissionRow(title: String, why: String, status: PermissionState,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(t.cream)
                Text(why)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(t.mute)
            }
            Spacer(minLength: 8)
            Text(permissionStatusText(status))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(t.mute)
            if status != .authorized {
                outlineButton(title: L10n.t(.authorize, prefs.language),
                              systemImage: "checkmark.shield", action: action)
            }
        }
        .padding(.vertical, 4)
    }

    private func permissionStatusText(_ status: PermissionState) -> String {
        switch status {
        case .authorized: L10n.t(.authorized, prefs.language)
        case .notAuthorized: L10n.t(.notAuthorized, prefs.language)
        case .needsReauthorization: L10n.t(.needsReauthorization, prefs.language)
        }
    }



    private func moduleRow(_ id: KajiModuleID, title: String, lockedOn: Bool) -> some View {
        let enabled = Binding(
            get: { prefs.isModuleEnabled(id) },
            set: { value in
                if !lockedOn { prefs.setModule(id, enabled: value) }
            }
        )
        return settingRow(title: title) {
            settingsToggle(isOn: enabled, title: title,
                           identifier: "kaji.module.\(id.rawValue).enabled")
                .disabled(lockedOn)
        }
    }

    // Use the same native switch for every Boolean setting. The system draws
    // the thumb consistently instead of mixing white thumbs with accent pills.
    private func settingsToggle(isOn: Binding<Bool>, title: String, identifier: String) -> some View {
        Toggle(title, isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(t.sun)
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t(.settings, prefs.language))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(t.cream)
            Text(selection.rawValue)
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

    private var providerSettingsKeys: [String] {
        Providers.sorted(Array(Providers.available))
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
                    Text(L10n.t(prefs.isVisible(key) ? .show : .hide, prefs.language))
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

    private func segment(
        _ title: String,
        on: Bool,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
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
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

extension UpdateChecker.Release: Identifiable {
    var id: String { tag }
}

// MARK: - UpdateNotesSheet
//
// Confirmation shown before a manual update: the release body grouped into
// Fixed / Added / Removed, rendered as plain text. Installing happens only
// from the explicit button; dismissing does nothing.
struct UpdateNotesSheet: View {
    let release: UpdateChecker.Release
    let currentVersion: String
    let language: AppLanguage
    let onInstall: () -> Void
    let onViewRelease: () -> Void
    let onCancel: () -> Void

    static let sections: [(ReleaseNotes.Category, L10n.K)] = [
        (.fixed, .updateFixed), (.added, .updateAdded), (.removed, .updateRemoved), (.other, .updateOther),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(L10n.t(.updateChangesTitle, language)) \(release.tag)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("\(currentVersion) → \(release.version)")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundColor(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if release.notes.isEmpty {
                        Text(L10n.t(.updateNoNotes, language))
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("kaji.update.notes.empty")
                    }
                    ForEach(Self.sections, id: \.0) { category, title in
                        let items = release.notes.items(category)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.t(title, language))
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                    Text("• " + item)
                                        .font(.system(size: 11.5, design: .rounded))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityIdentifier("kaji.update.notes.\(category.rawValue)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            Text(L10n.t(.updateInstallHint, language))
                .font(.system(size: 10.5, design: .rounded))
                .foregroundColor(.secondary)
            HStack {
                Button(L10n.t(.updateViewRelease, language), action: onViewRelease)
                Spacer()
                Button(L10n.t(.cancel, language), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t(.updateInstall, language), action: onInstall)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("kaji.update.install")
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}
