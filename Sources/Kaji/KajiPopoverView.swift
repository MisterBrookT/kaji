import SwiftUI

private enum KajiPanel: Int, CaseIterable {
    case quota
    case work
    case system
    case goals
}

private struct PopoverContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct KajiPopoverView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var prefs: Prefs
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var sleepController: SleepController
    @ObservedObject var petRunner: PetRunner
    @ObservedObject var petCatalog: PetCatalogStore
    @ObservedObject var workSession: WorkSessionController
    @ObservedObject var systemMonitor: SystemMonitor
    @ObservedObject var dailyGoals: DailyGoalStore

    let controls: GaugeRowView.Controls
    let maxContentHeight: CGFloat
    let onContentSizeChange: ((CGSize) -> Void)?

    @State private var panel: KajiPanel = .quota
    @State private var hoveredGoalDay: DailyGoalHistoryDay?
    @Environment(\.colorScheme) private var scheme

    private var t: KajiTheme { .resolve(scheme, prefs.menubarStyle) }
    private var shown: [ProviderView] { store.providers.filter { prefs.isVisible($0.id) } }
    private var panelScrollMaxHeight: CGFloat { max(180, maxContentHeight - 104) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().overlay(t.track.opacity(0.8))
            ScrollView(.vertical, showsIndicators: false) {
                panelBody
            }
            .frame(maxHeight: panelScrollMaxHeight)
            Divider().overlay(t.track.opacity(0.8))
            controlsFooter
        }
        .padding(12)
        .frame(width: prefs.panelSize.frameSize.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(background)
        .overlay(
            GeometryReader { proxy in
                Color.clear.preference(key: PopoverContentSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PopoverContentSizeKey.self) { size in
            onContentSizeChange?(size)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            arrow("chevron.left") { move(-1) }
            VStack(alignment: .leading, spacing: 2) {
                Text(panelTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(t.cream)
                    .lineLimit(1)
                Text(panelSubtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(t.mute)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(panel.rawValue + 1)/\(KajiPanel.allCases.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(t.ash)
            arrow("chevron.right") { move(1) }
        }
    }

    @ViewBuilder
    private var panelBody: some View {
        switch panel {
        case .quota:
            quotaPanel
        case .work:
            workPanel
        case .system:
            systemPanel
        case .goals:
            goalsPanel
        }
    }

    private var quotaPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            if shown.isEmpty {
                emptyQuota
            } else {
                quotaSummary
                ForEach(shown.prefix(4)) { provider in
                    quotaRow(provider)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var quotaSummary: some View {
        HStack(spacing: 8) {
            miniStat("Today", tokenText(totalTokensToday), "tokens")
            miniStat("Cost", usdText(totalCostToday), totalCostIsEstimated ? "est today" : "today")
            miniStat("Pressure", percent(totalPressure), "5h max")
        }
    }

    private func quotaRow(_ provider: ProviderView) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                ProviderLogo(key: provider.id, color: provider.isNearLimit ? t.amber : t.gold, size: 12)
                Text(provider.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(t.cream)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(percent(provider.fiveHourPercent))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(provider.isNearLimit ? t.amber : t.gold)
            }
            progressBar(provider.usedFraction, color: provider.isNearLimit ? t.amber : t.gold)
            HStack(spacing: 6) {
                Text("5h")
                Text(ResetFormat.short(provider.resetDate))
                    .foregroundColor(t.gold.opacity(0.9))
                Spacer(minLength: 6)
                if let tokens = provider.tokensToday {
                    Text(tokenText(tokens))
                        .foregroundColor(t.gold.opacity(0.9))
                }
                if let cost = provider.costTodayUSD {
                    Text("·")
                    Text(usdText(cost) + (provider.costIsEstimated ? " est" : ""))
                        .foregroundColor(t.gold.opacity(0.9))
                }
                Text("·")
                Text("7d")
                Text(percent(provider.weekPercent))
                    .foregroundColor(provider.weekNearLimit ? t.amber : t.gold.opacity(0.9))
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundColor(t.mute)
            SparklineView(values: provider.tokenHistory, color: provider.isNearLimit ? t.amber : t.gold, track: t.track)
                .frame(height: 18)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.panel.opacity(0.75)))
    }

    private var emptyQuota: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.t(.waiting, prefs.language))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
            Text(store.lastError == Config.noPythonSentinel ? L10n.t(.needPython, prefs.language) : "Kaji")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(t.mute)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var workPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(workPrimaryClock)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(workSession.phase == .breakDue ? t.amber : t.cream)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(prefs.focusMinutes)m / \(prefs.breakMinutes)m")
                    Text("Skip \(workSession.skipCountToday)")
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(t.mute)
            }
            progressBar(workSession.phase == .breaking ? workSession.breakProgress : workSession.workProgress,
                        color: workSession.phase == .breakDue ? t.amber : t.gold)
            Text(workStatusText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(t.mute)
                .lineLimit(2)
                .frame(minHeight: 30, alignment: .topLeading)
            rhythmControls
            HStack(spacing: 8) {
                chip(workSession.phase == .breaking ? "Break" : "Start Break", filled: true) {
                    workSession.startBreak()
                }
                if prefs.allowBreakSkip {
                    chip("Skip", filled: false) {
                        workSession.skipBreak()
                    }
                    .disabled(workSession.phase == .working)
                }
                chip("Reset", filled: false) {
                    workSession.resetWork()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var rhythmControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            rhythmRow("Focus",
                      value: "\(prefs.focusMinutes)m",
                      canDec: prefs.focusMinutes > 5,
                      canInc: prefs.focusMinutes < 180) {
                prefs.focusMinutes = max(5, prefs.focusMinutes - 5)
            } inc: {
                prefs.focusMinutes = min(180, prefs.focusMinutes + 5)
            }
            rhythmRow("Break",
                      value: "\(prefs.breakMinutes)m",
                      canDec: prefs.breakMinutes > 1,
                      canInc: prefs.breakMinutes < 30) {
                prefs.breakMinutes = max(1, prefs.breakMinutes - 1)
            } inc: {
                prefs.breakMinutes = min(30, prefs.breakMinutes + 1)
            }
        }
    }

    private func rhythmRow(_ title: String,
                           value: String,
                           canDec: Bool,
                           canInc: Bool,
                           dec: @escaping () -> Void,
                           inc: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(t.mute)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(t.cream)
                .monospacedDigit()
            stepButton("minus", enabled: canDec, action: dec)
            stepButton("plus", enabled: canInc, action: inc)
        }
    }

    private var systemPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                metricCard("CPU", "cpu", systemValue(systemMonitor.snapshot.cpuPercent),
                           fraction: systemMonitor.snapshot.cpuPercent / 100,
                           warning: systemMonitor.snapshot.cpuPercent >= 80)
                metricCard("Mem", "memorychip", systemValue(systemMonitor.snapshot.memoryPercent),
                           fraction: systemMonitor.snapshot.memoryPercent / 100,
                           warning: systemMonitor.snapshot.memoryPercent >= 75)
            }
            HStack(spacing: 8) {
                metricCard("Disk", "internaldrive", systemValue(systemMonitor.snapshot.diskPercent),
                           fraction: systemMonitor.snapshot.diskPercent / 100,
                           warning: systemMonitor.snapshot.diskPercent >= 85)
                metricCard("Clean", "sparkles", bytes(systemMonitor.selectedCleanableBytes),
                           fraction: cleanFraction,
                           warning: systemMonitor.selectedCleanableBytes >= 512 * 1024 * 1024)
            }
            systemRows
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            cleanControls
            autoCleanStatus
        }
        .onAppear {
            systemMonitor.refresh()
            systemMonitor.scanCleanables()
        }
    }

    private var cleanControls: some View {
        Button {
            prefs.autoCleanEnabled.toggle()
            if prefs.autoCleanEnabled {
                systemMonitor.runAutoMaintenanceIfNeeded()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: prefs.autoCleanEnabled ? "bolt.circle.fill" : "bolt.circle")
                    .font(.system(size: 11, weight: .bold))
                Text(prefs.autoCleanEnabled ? "Auto Reclaim On" : "Auto Reclaim")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer(minLength: 8)
                Text(prefs.autoCleanEnabled ? "On" : "Off")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundColor(prefs.autoCleanEnabled ? t.bg : t.mute)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prefs.autoCleanEnabled ? t.gold : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(prefs.autoCleanEnabled ? Color.clear : t.track, lineWidth: 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var autoCleanStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: prefs.autoCleanEnabled ? "bolt.circle.fill" : "bolt.circle")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(prefs.autoCleanEnabled ? t.gold : t.ash)
            Text(autoCleanText)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(t.mute)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
    }

    private var autoCleanText: String {
        if !prefs.autoCleanEnabled {
            return "Auto off · no background cleanup"
        }
        if systemMonitor.isAutoCleaning {
            return "Cleaning safe caches"
        }
        if systemMonitor.isReclaimingMemory {
            return "Reclaiming inactive memory"
        }
        if systemMonitor.lastAutoCleanedBytes > 0 {
            return "Cleaned \(bytes(systemMonitor.lastAutoCleanedBytes)) · Mem 75% / Disk 85%"
        }
        if systemMonitor.lastMemoryReclaimAt != nil {
            return "Memory reclaimed · Mem 75% / Disk 85%"
        }
        if systemMonitor.lastOrphanCleanedCount > 0 {
            return "Cleaned \(systemMonitor.lastOrphanCleanedCount) Kaji orphan processes"
        }
        return "Auto on · Mem 75% / Disk 85% / Kaji orphans / Cache 512M"
    }

    private var systemRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("Processes")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(systemMonitor.snapshot.processCount)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(t.gold)
                    .monospacedDigit()
            }
            ForEach(systemMonitor.snapshot.topProcesses.prefix(2)) { proc in
                HStack(spacing: 8) {
                    Text(proc.command)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(t.cream)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(Int(proc.cpu.rounded()))%")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(t.gold)
                        .monospacedDigit()
                }
            }
            if !systemMonitor.orphanProcesses.isEmpty {
                HStack(spacing: 8) {
                    Text("Kaji orphans")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(t.mute)
                    Spacer(minLength: 6)
                    Text("\(systemMonitor.orphanProcesses.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(t.amber)
                        .monospacedDigit()
                }
            }
        }
    }

    private var goalsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(dailyGoals.completedCount)/\(dailyGoals.goals.count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(t.cream)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Goals")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(t.cream)
                    Text("明天自动清空完成状态")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(t.mute)
                }
                Spacer()
                chip("Reset", filled: false) {
                    dailyGoals.resetToday()
                }
                chip("Add", filled: true) {
                    dailyGoals.addGoal()
                }
            }
            goalHeatmap
            ForEach(dailyGoals.goals) { goal in
                HStack(spacing: 8) {
                    Button {
                        dailyGoals.toggle(goal)
                    } label: {
                        Image(systemName: goal.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(goal.isDone ? t.gold : t.mute)
                    }
                    .buttonStyle(.plain)
                    TextField("", text: Binding(
                        get: { goal.title },
                        set: { dailyGoals.updateTitle(goal, title: $0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(goal.isDone ? t.mute : t.cream)
                    miniButton("trash") {
                        dailyGoals.delete(goal)
                    }
                    .disabled(dailyGoals.goals.count <= 1)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.panel.opacity(0.75)))
            }
        }
    }

    private var goalHeatmap: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("35d")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(t.mute)
                Spacer()
                Text(goalHeatmapCaption)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.ash)
            }
            GeometryReader { geo in
                let spacing: CGFloat = 3
                let side = max(5, (geo.size.width - spacing * 34) / 35)
                HStack(spacing: spacing) {
                    ForEach(dailyGoals.heatmapDays) { day in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(goalHeatColor(day.ratio, empty: day.total == 0))
                            .frame(width: side, height: side)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .stroke(hoveredGoalDay?.day == day.day ? t.cream.opacity(0.75) : Color.clear, lineWidth: 1)
                            )
                            .onHover { hovering in
                                hoveredGoalDay = hovering ? day : nil
                            }
                            .help(goalHeatDescription(day))
                    }
                }
            }
            .frame(height: 14)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.panel.opacity(0.55)))
    }

    private func goalHeatColor(_ ratio: Double, empty: Bool) -> Color {
        if empty { return t.track.opacity(0.5) }
        if ratio >= 0.99 { return t.gold }
        if ratio >= 0.66 { return t.gold.opacity(0.72) }
        if ratio >= 0.33 { return t.gold.opacity(0.42) }
        return t.track.opacity(0.9)
    }

    private var goalHeatmapCaption: String {
        if let hoveredGoalDay {
            return goalHeatDescription(hoveredGoalDay)
        }
        let today = dailyGoals.heatmapDays.last ?? DailyGoalHistoryDay(day: "", completed: 0, total: 0)
        return "\(Int(today.ratio * 100))% today"
    }

    private func goalHeatDescription(_ day: DailyGoalHistoryDay) -> String {
        if day.total == 0 { return "\(day.day) no goals" }
        return "\(day.day) \(day.completed)/\(day.total) · \(Int(day.ratio * 100))%"
    }

    private var controlsFooter: some View {
        HStack(spacing: 7) {
            iconButton("pawprint", title: L10n.t(.pet, prefs.language), action: controls.onTogglePet,
                       filled: petRunner.isRunning)
            Spacer(minLength: 4)
            compactTab("Q", active: panel == .quota) { panel = .quota }
            compactTab("W", active: panel == .work) { panel = .work }
            compactTab("S", active: panel == .system) { panel = .system }
            compactTab("G", active: panel == .goals) { panel = .goals }
            Spacer(minLength: 4)
            iconButton("gearshape", title: L10n.t(.settings, prefs.language), action: controls.onOpenSettings)
            iconButton("power", title: L10n.t(.quit, prefs.language), action: controls.onQuit)
        }
        .frame(height: 32)
    }

    private var panelTitle: String {
        switch panel {
        case .quota: return "Quota"
        case .work: return "Work / Break"
        case .system: return "System"
        case .goals: return "Goals"
        }
    }

    private var panelSubtitle: String {
        switch panel {
        case .quota: return "5h + 7d pressure"
        case .work: return "45m work, hard break"
        case .system: return "CPU + processes + Kaji clean"
        case .goals: return "Daily completion"
        }
    }

    private var workPrimaryClock: String {
        switch workSession.phase {
        case .working, .breakDue:
            return workSession.workClock
        case .breaking:
            return workSession.breakClock
        }
    }

    private var workStatusText: String {
        switch workSession.phase {
        case .working:
            return "工作中。到点后宠物会弹出拦截。"
        case .breakDue:
            return "该休息了。宠物会挡住工作，Skip 会记录。"
        case .breaking:
            return "休息中。站起来，走两分钟。"
        }
    }

    private var background: some View {
        LinearGradient(colors: [t.bgTop, t.bg],
                       startPoint: .topTrailing,
                       endPoint: .bottomLeading)
    }

    private func move(_ delta: Int) {
        let count = KajiPanel.allCases.count
        let next = (panel.rawValue + delta + count) % count
        panel = KajiPanel(rawValue: next) ?? .quota
    }

    private func arrow(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(t.cream)
                .frame(width: 30, height: 30)
                .background(Circle().fill(t.panel.opacity(0.9)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ systemName: String,
                            title: String,
                            action: @escaping () -> Void,
                            filled: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(filled ? t.bg : t.mute)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(filled ? t.gold : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(filled ? Color.clear : t.track, lineWidth: 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
    }

    private func miniButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(t.mute)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(t.track, lineWidth: 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func stepButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(enabled ? t.cream : t.ash)
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(enabled ? t.panel.opacity(0.92) : t.panel.opacity(0.42))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(t.track, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(systemName == "plus" ? "Increase" : "Decrease")
    }

    private func compactTab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(active ? t.bg : t.mute)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? t.gold : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(active ? Color.clear : t.track, lineWidth: 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(filled ? t.bg : t.mute)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(filled ? t.gold : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(filled ? Color.clear : t.track, lineWidth: 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func metricCard(_ title: String,
                            _ systemImage: String,
                            _ value: String,
                            fraction: Double? = nil,
                            warning: Bool = false) -> some View {
        let safeFraction = fraction.map { min(max($0, 0), 1) }
        let accent = warning ? t.amber : t.gold
        return HStack(spacing: 8) {
            ZStack {
                GaugeDot(fraction: safeFraction ?? 0, color: accent, track: t.track)
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(accent)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(title)
                    if warning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7.5, weight: .bold))
                    }
                }
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(warning ? accent : t.mute)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(t.cream)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let safeFraction {
                    progressBar(safeFraction, color: accent)
                        .frame(height: 4)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.panel.opacity(0.75)))
    }

    private func miniStat(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(t.mute)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(t.cream)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundColor(t.ash)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.panel.opacity(0.62)))
    }

    private func progressBar(_ value: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(t.track.opacity(0.7))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 7)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "\u{2014}" }
        return "\(Int(value.rounded()))%"
    }

    private func bytes(_ value: Int64) -> String {
        if value <= 0 { return "0" }
        if value < 1024 * 1024 { return "\(value / 1024)K" }
        return "\(value / 1024 / 1024)M"
    }

    private func systemValue(_ value: Double) -> String {
        systemMonitor.snapshot.hasSample ? "\(Int(value.rounded()))%" : "..."
    }

    private var totalTokensToday: Int {
        shown.compactMap(\.tokensToday).reduce(0, +)
    }

    private var totalPressure: Double? {
        shown.compactMap(\.fiveHourPercent).max()
    }

    private var totalCostToday: Double? {
        let costs = shown.compactMap(\.costTodayUSD)
        guard !costs.isEmpty else { return nil }
        return costs.reduce(0, +)
    }

    private var totalCostIsEstimated: Bool {
        shown.contains { $0.costTodayUSD != nil && $0.costIsEstimated }
    }

    private func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func usdText(_ value: Double?) -> String {
        guard let value else { return "\u{2014}" }
        if value < 0.01 {
            return String(format: "$%.3f", value)
        }
        return String(format: "$%.2f", value)
    }

    private var cleanFraction: Double {
        guard systemMonitor.cleanableBytes > 0 else { return 0 }
        return Double(systemMonitor.selectedCleanableBytes) / Double(systemMonitor.cleanableBytes)
    }
}

private struct GaugeDot: View {
    let fraction: Double
    let color: Color
    let track: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(track.opacity(0.75), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 12, height: 12)
        }
    }
}

private struct SparklineView: View {
    let values: [Double]
    let color: Color
    let track: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(track.opacity(0.35))
                if normalizedSamples.count < 2 {
                    dottedEmpty(in: geo.size)
                        .fill(color.opacity(0.45))
                } else {
                    sparkPath(in: geo.size, filled: true)
                        .fill(
                            LinearGradient(colors: [color.opacity(0.22), color.opacity(0.02)],
                                           startPoint: .top,
                                           endPoint: .bottom)
                        )
                    sparkPath(in: geo.size, filled: false)
                        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func sparkPath(in size: CGSize, filled: Bool) -> Path {
        let samples = normalizedSamples
        var path = Path()
        guard !samples.isEmpty else { return path }
        let step = samples.count <= 1 ? 0 : size.width / CGFloat(samples.count - 1)
        if filled {
            path.move(to: CGPoint(x: 0, y: size.height))
        }
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * step
            let y = size.height - CGFloat(sample) * size.height
            if index == 0 && !filled {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        if filled {
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
        return path
    }

    private var normalizedSamples: [Double] {
        let raw = values.suffix(24)
        guard raw.count >= 2 else { return [] }
        let minValue = raw.min() ?? 0
        let maxValue = raw.max() ?? 0
        let span = max(maxValue - minValue, 1)
        return raw.map { min(max(($0 - minValue) / span, 0.08), 1) }
    }

    private func dottedEmpty(in size: CGSize) -> Path {
        var path = Path()
        let count = 9
        for index in 0..<count {
            let x = CGFloat(index) * size.width / CGFloat(count - 1)
            let y = size.height * 0.62
            path.addEllipse(in: CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6))
        }
        return path
    }
}
