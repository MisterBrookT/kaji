import AppKit
import SwiftUI
import KajiCore

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

    @State private var fixedPlanWeekday = Calendar.current.component(.weekday, from: Date())
    @State private var showsFixedPlanEditor = false

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme) }

    var body: some View {
        HStack(spacing: 0) {
            mainSettings
            if showsFixedPlanEditor {
                Divider().overlay(t.track)
                fixedPlanEditor
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(t.bg)
        .animation(.easeOut(duration: 0.16), value: showsFixedPlanEditor)
        .onChange(of: showsFixedPlanEditor) { shown in
            onFixedPlanEditorChange?(shown)
        }
        .onChange(of: prefs.enabledModules) { modules in
            if !modules.contains(.goals) {
                showsFixedPlanEditor = false
            }
        }
    }

    private var mainSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
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
                    if prefs.isModuleEnabled(.goals) {
                        HStack {
                            Spacer()
                            outlineButton(title: "编辑固定计划", systemImage: "sidebar.right") {
                                showsFixedPlanEditor = true
                            }
                        }
                    }
                }
            }
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
                        segment(preventSleepTitle, on: sleepController.isEnabled) {
                            sleepController.toggle()
                        }
                        .disabled(sleepController.isBusy)
                    }
                }
            }
            if prefs.isModuleEnabled(.work) {
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
        .padding(18)
        .frame(width: 360, alignment: .topLeading)
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

    private var fixedPlanEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t(.fixedPlan, prefs.language))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(t.cream)
                    Text("每周重复")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(t.mute)
                }
                Spacer()
                Button {
                    showsFixedPlanEditor = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(t.panel))
                }
                .buttonStyle(.plain)
                .foregroundColor(t.mute)
            }
            VStack(alignment: .leading, spacing: 9) {
                Picker("", selection: $fixedPlanWeekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(weekdayName(day)).tag(day)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                TextField("标题", text: Binding(
                    get: { fixedPlanStore.plan(for: fixedPlanWeekday).title },
                    set: { fixedPlanStore.update(weekday: fixedPlanWeekday, title: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                Picker("Category", selection: Binding(
                    get: {
                        let plan = fixedPlanStore.plan(for: fixedPlanWeekday)
                        return GoalTagLogic.resolve(plan.tag, title: plan.title)
                    },
                    set: {
                        fixedPlanStore.update(weekday: fixedPlanWeekday, tag: $0.rawValue)
                    }
                )) {
                    ForEach(GoalTag.allCases, id: \.rawValue) { tag in
                        Label(tag.label, systemImage: tag.systemImage).tag(tag)
                    }
                }
                .pickerStyle(.menu)
                HStack {
                    Text("计划事项")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(t.mute)
                    Spacer()
                    outlineButton(title: "添加", systemImage: "plus") {
                        _ = fixedPlanStore.addItem(weekday: fixedPlanWeekday)
                    }
                }
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 7) {
                        ForEach(fixedPlanStore.plan(for: fixedPlanWeekday).items) { item in
                            fixedPlanItemRow(item)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(minHeight: 220, maxHeight: .infinity)
                HStack {
                    Spacer()
                    outlineButton(title: "恢复默认", systemImage: "arrow.counterclockwise") {
                        fixedPlanStore.reset(weekday: fixedPlanWeekday)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(t.bg)
    }

    private func fixedPlanItemRow(_ item: FixedPlanItem) -> some View {
        HStack(spacing: 7) {
            VStack(spacing: 5) {
                TextField("事项", text: Binding(
                    get: {
                        fixedPlanStore.plan(for: fixedPlanWeekday).items
                            .first(where: { $0.id == item.id })?.title ?? ""
                    },
                    set: {
                        fixedPlanStore.updateItem(
                            weekday: fixedPlanWeekday,
                            id: item.id,
                            title: $0
                        )
                    }
                ))
                TextField("说明（可选）", text: Binding(
                    get: {
                        fixedPlanStore.plan(for: fixedPlanWeekday).items
                            .first(where: { $0.id == item.id })?.dose ?? ""
                    },
                    set: {
                        fixedPlanStore.updateItem(
                            weekday: fixedPlanWeekday,
                            id: item.id,
                            dose: $0
                        )
                    }
                ))
            }
            .textFieldStyle(.roundedBorder)
            Button {
                fixedPlanStore.deleteItem(weekday: fixedPlanWeekday, id: item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(t.panel))
            }
            .buttonStyle(.plain)
            .foregroundColor(t.mute)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(t.panel.opacity(0.65)))
    }

    private func weekdayName(_ weekday: Int) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][max(1, min(7, weekday)) - 1]
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
