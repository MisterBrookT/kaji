import AppKit
import SwiftUI
import KajiCore

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case modules = "Modules"
    case work = "Work"
    case goals = "Goals"
    case quota = "Quota"
    case aiNews = "AI News"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .modules: "square.grid.2x2"
        case .work: "timer"
        case .goals: "checkmark.circle"
        case .quota: "gauge.with.dots.needle.67percent"
        case .aiNews: "newspaper"
        }
    }
}

// MARK: - SettingsView
//
// Slower preferences live outside the status popover so the main surface stays
// focused on modules, appearance, system, and fixed-plan templates.
struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var sleepController: SleepController
    @ObservedObject var petCatalog: PetCatalogStore
    @ObservedObject var fixedPlanStore: FixedPlanStore
    var onFixedPlanEditorChange: ((Bool) -> Void)? = nil

    @State private var selectedScheduleID: UUID?
    @State private var selection: SettingsSection = .general

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
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
                        segment(preventSleepTitle, on: sleepController.isEnabled) {
                            sleepController.toggle()
                        }
                        .disabled(sleepController.isBusy)
                        .help("保持 Mac 唤醒。首次开启可能需要在系统设置中批准 Kaji。")
                    }
                    if sleepController.lastError != nil {
                        Text("防休眠未能开启。请检查系统设置 → 登录项与扩展。")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(t.amber)
                    }
                }
            }
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
        }
        .padding(24)
        .onAppear {
            refreshPetCatalogSelection()
        }
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
        }
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

    private func refreshPetCatalogSelection() {
        let resolvedPetId = petCatalog.refresh(selectedPetId: prefs.petId)
        guard !resolvedPetId.isEmpty, prefs.petId != resolvedPetId else { return }
        prefs.petId = resolvedPetId
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
