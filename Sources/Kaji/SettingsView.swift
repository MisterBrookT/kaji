import AppKit
import SwiftUI
import KajiCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case modules = "Modules"
    case work = "Work"
    case goals = "Goals"
    case quota = "Quota"
    case aiNews = "AI News"
    case mailBrief = "Mail Brief"
    case cli = "CLI"
    case permissions = "Permissions"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .modules: "square.grid.2x2"
        case .work: "timer"
        case .goals: "checkmark.circle"
        case .quota: "gauge.with.dots.needle.67percent"
        case .aiNews: "newspaper"
        case .mailBrief: "envelope"
        case .cli: "terminal"
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
    @ObservedObject var mailBriefStore: MailBriefStore
    var onFixedPlanEditorChange: ((Bool) -> Void)? = nil
    var exposurePhase: ExposureExperimentPhase
    var onRollbackExposure: () -> Void
    var onClearExposureData: () -> Void

    @State private var selectedScheduleID: UUID?
    @State private var selection: SettingsSection = .general
    @State private var showsMailRunHistory = false
    @State private var gmailPermission: PermissionState = .notAuthorized
    @State private var loginPermission: PermissionState = .notAuthorized
    @State private var sleepPermission: PermissionState = .notAuthorized


    init(
        prefs: Prefs,
        sleepController: SleepController,
        fixedPlanStore: FixedPlanStore,
        mailBriefStore: MailBriefStore,
        initialSection: SettingsSection = .general,
        exposurePhase: ExposureExperimentPhase = .notStarted,
        onRollbackExposure: @escaping () -> Void = {},
        onClearExposureData: @escaping () -> Void = {},
        onFixedPlanEditorChange: ((Bool) -> Void)? = nil
    ) {
        self.prefs = prefs
        self.sleepController = sleepController
        self.fixedPlanStore = fixedPlanStore
        self.mailBriefStore = mailBriefStore
        self.exposurePhase = exposurePhase
        self.onRollbackExposure = onRollbackExposure
        self.onClearExposureData = onClearExposureData
        self.onFixedPlanEditorChange = onFixedPlanEditorChange
        _selection = State(initialValue: initialSection)
    }
    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    private var visibleSections: [SettingsSection] {
        guard exposurePhase == .treatment else { return SettingsSection.allCases }
        return SettingsSection.allCases.filter { section in
            switch section {
            case .general, .modules, .quota, .cli, .permissions:
                return true
            case .work: return prefs.isModuleEnabled(.work)
            case .goals: return prefs.isModuleEnabled(.goals)
            case .aiNews: return prefs.isModuleEnabled(.aiNews)
            case .mailBrief: return prefs.isModuleEnabled(.mailBrief)
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
        .onChange(of: prefs.enabledModules) { _ in
            if !visibleSections.contains(selection) { selection = .modules }
        }
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
            if selection == .modules {
                settingBlock(title: L10n.t(.modules, prefs.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t(.modulesHint, prefs.language))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(t.mute)
                        .fixedSize(horizontal: false, vertical: true)
                    moduleRow(.quota, title: L10n.t(.moduleQuota, prefs.language), lockedOn: true)
                    moduleRow(.work, title: L10n.t(.moduleWork, prefs.language), lockedOn: false)
                    moduleRow(.system, title: L10n.t(.moduleSystem, prefs.language), lockedOn: false)
                    moduleRow(.goals, title: L10n.t(.moduleGoals, prefs.language), lockedOn: false)
                    moduleRow(.aiNews, title: L10n.t(.moduleAINews, prefs.language), lockedOn: false)
                    moduleRow(.mailBrief, title: "Mail Brief", lockedOn: false)
                    moduleRow(.launchd, title: "Background Tasks", lockedOn: false)
                }
            }
            }
            if selection == .general {
                settingBlock(title: L10n.t(.appearance, prefs.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    settingRow(title: L10n.t(.language, prefs.language)) {
                        ForEach(Lang.allCases, id: \.rawValue) { language in
                            segment(language.label, on: prefs.language == language) {
                                prefs.language = language
                            }
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
                        segment(
                            preventSleepTitle,
                            on: sleepController.isEnabled,
                            accessibilityIdentifier: "kaji.prevent-sleep.toggle"
                        ) {
                            sleepController.toggle()
                        }
                        .disabled(sleepController.isBusy)
                        .help(L10n.t(.sleepPermissionWhy, prefs.language))
                    }
                    if sleepController.lastError != nil {
                        Text(L10n.t(.sleepRepairMessage, prefs.language))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(t.amber)
                    }
                }
                if exposurePhase == .baseline || exposurePhase == .treatment {
                    settingRow(title: "Exposure study") {
                        Text(exposurePhase == .baseline ? "Baseline" : "Treatment")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(t.mute)
                        Button("Roll back", action: onRollbackExposure)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("kaji.exposure.rollback")
                        Button("Clear data", action: onClearExposureData)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("kaji.exposure.clear")
                    }
                }
            }
            }
            if selection == .cli {
                settingBlock(title: "CLI") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.t(.cliIntegrationHint, prefs.language))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(t.mute)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Text(L10n.t(.cliExamplePrompt, prefs.language))
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundColor(t.cream)
                                .textSelection(.enabled)
                            Spacer()
                            Button(L10n.t(.copyPrompt, prefs.language)) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    L10n.t(.cliExamplePrompt, prefs.language),
                                    forType: .string
                                )
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(t.cream)
                        }
                    }
                }
            }
            if selection == .permissions {
                settingBlock(title: L10n.t(.permissions, prefs.language)) {
                    VStack(alignment: .leading, spacing: 12) {
                        permissionRow(
                            title: L10n.t(.gmailCredential, prefs.language),
                            why: L10n.t(.gmailCredentialWhy, prefs.language),
                            status: gmailPermission
                        ) {
                            try? MailBriefCredentialStore.authorizeAccess()
                            refreshPermissions()
                        }
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
            if selection == .goals {
                EmptyView()
            }
            if selection == .quota {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(providerSettingsKeys, id: \.self) { key in
                        providerRow(key)
                    }
                }
            }
            if selection == .aiNews {
                settingBlock(title: "AI News") {
                VStack(alignment: .leading, spacing: 7) {
                    settingRow(title: L10n.t(.refreshInterval, prefs.language)) {
                        ForEach(AIHotRefreshPolicy.allowedHours, id: \.self) { hours in
                            segment("\(hours)h", on: prefs.aiNewsRefreshHours == hours) {
                                prefs.aiNewsRefreshHours = hours
                            }
                        }
                    }
                    .help("AI News uses AI HOT's anonymous read-only v1 API.")
                }
            }
            }
            if selection == .mailBrief {
                settingBlock(title: "Mail Brief") {
                    VStack(alignment: .leading, spacing: 10) {
                        settingRow(title: "Gmail") {
                            if mailBriefStore.isConnected {
                                Text(mailBriefStore.accountLabel ?? "Connected")
                                    .font(.system(size: 10, weight: .medium)).foregroundColor(t.mute)
                                Button("Disconnect") { mailBriefStore.disconnect() }.buttonStyle(.plain)
                            } else {
                                Button("Connect") { mailBriefStore.connect() }.buttonStyle(.plain)
                            }
                        }
                        settingRow(title: "Daily") {
                            Picker("Hour", selection: $prefs.mailBriefHour) {
                                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }.labelsHidden().frame(width: 64)
                            Text(":")
                            Picker("Minute", selection: $prefs.mailBriefMinute) {
                                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }.labelsHidden().frame(width: 64)
                        }
                        settingRow(title: "Batch") {
                            Picker("Batch", selection: $prefs.mailBriefBatchSize) {
                                ForEach(MailBriefBatchPolicy.allowedBatchSizes, id: \.self) { Text("\($0)").tag($0) }
                            }.labelsHidden().frame(width: 72)
                            Text("threads / run").font(.system(size: 9.5)).foregroundColor(t.mute)
                        }
                        settingRow(title: "Concurrency") {
                            Picker("Concurrency", selection: $prefs.mailBriefConcurrency) {
                                ForEach(MailBriefBatchPolicy.allowedConcurrency, id: \.self) { Text("\($0)").tag($0) }
                            }.labelsHidden().frame(width: 72)
                            Text("parallel batches").font(.system(size: 9.5)).foregroundColor(t.mute)
                        }
                        settingRow(title: "Model") {
                            Picker("Model", selection: $prefs.mailBriefModel) {
                                ForEach(MailBriefModel.allCases, id: \.self) { model in
                                    Text(model.displayName).tag(model)
                                }
                            }.labelsHidden().pickerStyle(.menu)
                        }
                        settingRow(title: "Run") {
                            Button("Generate now") { mailBriefStore.generateNow() }
                                .buttonStyle(.plain).disabled(!mailBriefStore.isConnected || mailBriefStore.state == .running)
                        }
                        mailRunActivity
                        if let error = mailBriefStore.lastError {
                            Text(error).font(.system(size: 9.5, weight: .medium)).foregroundColor(t.mute)
                        }
                        Text("Email content is sent to your signed-in Codex service. Archive, Flag and Trash require Gmail modify permission.")
                            .font(.system(size: 9.5, weight: .medium)).foregroundColor(t.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(24)
    }

    private func refreshPermissions() {
        switch MailBriefCredentialStore.authorizationStatus() {
        case .authorized: gmailPermission = .authorized
        case .notAuthorized: gmailPermission = .notAuthorized
        case .needsReauthorization: gmailPermission = .needsReauthorization
        }
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

    private var mailRunActivity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider().overlay(t.track)
            HStack {
                Text("Last run")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
                Spacer()
                if mailBriefStore.runRecords.count > 1 {
                    Button(showsMailRunHistory ? "Hide history" : "Recent runs") {
                        showsMailRunHistory.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
                }
            }
            if let latest = mailBriefStore.runRecords.first {
                mailRunRow(latest, detailed: true)
                if showsMailRunHistory {
                    ForEach(Array(mailBriefStore.runRecords.dropFirst())) { record in
                        Divider().overlay(t.track.opacity(0.7))
                        mailRunRow(record, detailed: false)
                    }
                }
            } else {
                Text("Not run yet")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(t.ash)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(t.panel.opacity(0.55)))
    }

    private func mailRunRow(_ record: MailBriefRunRecord, detailed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(mailRunStatus(record))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.cream)
                Text("· \(mailRunTrigger(record.trigger)) · \(mailRunTime(record))")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(t.mute)
                Spacer(minLength: 0)
            }
            if let summary = mailRunSummary(record) {
                Text(summary)
                    .font(.system(size: detailed ? 10 : 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(t.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(mailRunAbsoluteTime(record))
    }

    private func mailRunStatus(_ record: MailBriefRunRecord) -> String {
        switch record.status {
        case .running:
            switch record.stage {
            case .connecting: "Connecting"
            case .fetching: "Fetching Inbox"
            case .classifying: "Classifying"
            case .publishing: "Publishing"
            case .finished: "Running"
            }
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: record.safeErrorCode == "interrupted" ? "Interrupted" : "Cancelled"
        }
    }

    private func mailRunTrigger(_ trigger: MailBriefRunTrigger) -> String {
        switch trigger { case .automatic: "Automatic"; case .manual: "Manual"; case .catchUp: "Catch-up" }
    }

    private func mailRunSummary(_ record: MailBriefRunRecord) -> String? {
        guard let inbox = record.snapshotInboxCount else {
            return record.safeErrorCode.map { "Stopped before Inbox fetch · \($0.replacingOccurrences(of: "_", with: " "))" }
        }
        if record.status == .running {
            let target = record.newOrChangedCount ?? inbox
            return "Inbox \(inbox) · classified \(record.classifiedCount) / \(target)"
        }
        var values = ["Inbox \(inbox)"]
        if let changed = record.newOrChangedCount { values.append("new/changed \(changed)") }
        if let reused = record.reusedCount { values.append("reused \(reused)") }
        if let published = record.publishedCount { values.append("published \(published)") }
        if record.status == .failed, let error = record.safeErrorCode {
            values.append(error.replacingOccurrences(of: "_", with: " "))
        }
        return values.joined(separator: " · ")
    }

    private func mailRunTime(_ record: MailBriefRunRecord) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: record.finishedAt ?? record.startedAt, relativeTo: Date())
    }

    private func mailRunAbsoluteTime(_ record: MailBriefRunRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium; formatter.timeStyle = .medium
        let start = formatter.string(from: record.startedAt)
        guard let end = record.finishedAt else { return "Started \(start)" }
        return "Started \(start) · Finished \(formatter.string(from: end))"
    }


    private func moduleRow(_ id: KajiModuleID, title: String, lockedOn: Bool) -> some View {
        let on = prefs.isModuleEnabled(id)
        return settingRow(title: title) {
            segment(L10n.t(.on, prefs.language), on: on) {
                if !lockedOn { prefs.setModule(id, enabled: true) }
            }
            .disabled(lockedOn && on)
            segment(L10n.t(.off, prefs.language), on: !on) {
                if !lockedOn { prefs.setModule(id, enabled: false) }
            }
            .disabled(lockedOn)
            if exposurePhase == .treatment, id != .quota, on {
                Button {
                    togglePrimaryFavorite(id)
                } label: {
                    Image(systemName: prefs.primaryFavorites.contains(id) ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .help("Primary favorite")
                .accessibilityIdentifier("kaji.module.\(id.rawValue).primary")
            }
            if exposurePhase == .treatment, id == .work, on {
                Button {
                    prefs.showsWorkCompactSignal.toggle()
                } label: {
                    Image(systemName: prefs.showsWorkCompactSignal ? "menubar.rectangle" : "rectangle")
                }
                .buttonStyle(.plain)
                .help("Show compact Work signal")
                .accessibilityIdentifier("kaji.module.work.status-signal")
            }
        }
    }

    private func togglePrimaryFavorite(_ id: KajiModuleID) {
        if let index = prefs.primaryFavorites.firstIndex(of: id) {
            prefs.primaryFavorites.remove(at: index)
            return
        }
        var favorites = prefs.primaryFavorites
        if favorites.count == 2 { favorites.removeFirst() }
        favorites.append(id)
        prefs.primaryFavorites = ExposureExperimentLogic.normalizedFavorites(
            favorites,
            enabled: prefs.enabledModules
        )
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

    private var fixedPlanEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Schedule")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(t.cream)
                    Text("每周重复")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(t.mute)
                }
                Spacer()
                outlineButton(title: "新建", systemImage: "plus") {
                    if let id = fixedPlanStore.add(
                        title: "新 Schedule",
                        tag: GoalTag.personal.rawValue,
                        note: "",
                        weekdays: [Calendar.current.component(.weekday, from: Date())]
                    ) {
                        selectedScheduleID = id
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 6) {
                    ForEach(fixedPlanStore.schedules) { schedule in
                        Button {
                            selectedScheduleID = schedule.id
                        } label: {
                            HStack {
                                Text(schedule.title)
                                    .lineLimit(1)
                                Spacer()
                                Text(scheduleWeekdaySummary(schedule))
                                    .foregroundColor(t.mute)
                            }
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(t.cream)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(selectedScheduleID == schedule.id ? t.panel : t.panel.opacity(0.45))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 190)
                if let schedule = selectedSchedule {
                    scheduleEditor(schedule)
                } else {
                    Text("选择一个 Schedule")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(t.mute)
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            if selectedScheduleID == nil {
                selectedScheduleID = fixedPlanStore.schedules.first?.id
            }
        }
    }

    private var selectedSchedule: ScheduledGoal? {
        fixedPlanStore.schedules.first { $0.id == selectedScheduleID }
    }

    private func scheduleEditor(_ schedule: ScheduledGoal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("标题", text: Binding(
                get: { fixedPlanStore.schedules.first(where: { $0.id == schedule.id })?.title ?? "" },
                set: { fixedPlanStore.update(schedule, title: $0) }
            ))
                .textFieldStyle(.roundedBorder)
            Picker("Tag", selection: Binding(
                get: { GoalTagLogic.resolve(schedule.tag, title: schedule.title).selectableEquivalent },
                set: { fixedPlanStore.update(schedule, tag: $0.rawValue) }
            )) {
                ForEach(GoalTag.selectableCases, id: \.rawValue) { tag in
                    Image(systemName: tag.systemImage)
                        .accessibilityLabel(tag.label)
                        .tag(tag)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 10, weight: .regular))
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    Button {
                        var weekdays = schedule.weekdays
                        if weekdays.contains(day), weekdays.count > 1 {
                            weekdays.remove(day)
                        } else {
                            weekdays.insert(day)
                        }
                        fixedPlanStore.update(schedule, weekdays: weekdays)
                    } label: {
                        Text(weekdayName(day))
                            .frame(width: 24, height: 24)
                            .background(
                                Circle().fill(schedule.weekdays.contains(day) ? t.gold : t.panel)
                            )
                            .foregroundColor(schedule.weekdays.contains(day) ? t.bg : t.mute)
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("说明（可选）", text: Binding(
                get: { fixedPlanStore.schedules.first(where: { $0.id == schedule.id })?.note ?? "" },
                set: { fixedPlanStore.update(schedule, note: $0) }
            ), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...8)
            HStack {
                Spacer()
                outlineButton(title: "删除", systemImage: "trash") {
                    fixedPlanStore.delete(schedule)
                    selectedScheduleID = fixedPlanStore.schedules.first?.id
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func weekdayName(_ weekday: Int) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][max(1, min(7, weekday)) - 1]
    }

    private func scheduleWeekdaySummary(_ schedule: ScheduledGoal) -> String {
        schedule.weekdays.sorted().map(weekdayName).joined()
    }


    private var providerSettingsKeys: [String] {
        Providers.sorted(Array(Providers.available))
    }

    private var preventSleepTitle: String {
        if sleepController.isBusy {
            let key: L10n.K = sleepController.targetEnabled == true ? .on : .off
            return L10n.t(key, prefs.language) + "\u{2026}"
        }
        return L10n.t(sleepController.isEnabled ? .on : .off, prefs.language)
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
