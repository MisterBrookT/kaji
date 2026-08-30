import AppKit
import SwiftUI
import KajiCore

@MainActor
final class PopoverNavigation: ObservableObject {
    @Published var panel: KajiModuleID = .quota
    @Published var goalHorizon: GoalHorizon = .today
}

struct KajiPopoverControls {
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    let onShowDetail: (NSView, AnyView) -> Void
    let onDismissDetail: () -> Void

    init(
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onShowDetail: @escaping (NSView, AnyView) -> Void = { _, _ in },
        onDismissDetail: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onShowDetail = onShowDetail
        self.onDismissDetail = onDismissDetail
    }
}

private struct PopoverContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Laid-out height of the scrollable panel, used to derive the chrome height
/// that the scroll budget subtracts from `maxContentHeight`.
private struct PanelScrollHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// Anchor of the hovered goal's note icon, resolved in the popover's own
/// coordinate space so the note card can live in this window.
private struct NoteAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct NoteCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private enum NoteCardMetrics {
    static let width: CGFloat = 208
    static let margin: CGFloat = 8
}


struct KajiPopoverView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var prefs: Prefs
    @ObservedObject var workSession: WorkSessionController
    @ObservedObject var systemMonitor: SystemMonitor
    @ObservedObject var dailyGoals: DailyGoalStore
    @ObservedObject var fixedPlanStore: FixedPlanStore
    @ObservedObject var navigation: PopoverNavigation

    let controls: KajiPopoverControls
    let maxContentHeight: CGFloat
    let onContentSizeChange: ((CGSize) -> Void)?
    /// Offscreen snapshots (ImageRenderer) often paint ScrollView as empty —
    /// pass `false` for screenshot harnesses.
    var scrollsContent: Bool = true

    @State private var hoveredGoalDay: DailyGoalHistoryDay?
    @State private var previousFocusedGoalID: UUID?
    @State private var previousFocusedGoalHorizon: GoalHorizon = .today
    @FocusState private var focusedGoalID: UUID?
    @State private var showCleanConfirmation = false
    @State private var showsGoalCreator = false
    @State private var goalCreationTitle = ""
    @State private var goalCreationTagName = GoalTag.personal.rawValue
    @State private var goalCreationTagColor: UInt32 = 0x8E6AD8
    @State private var goalCreationNote = ""
    @State private var hoveredNoteGoalID: UUID?
    @State private var hoveredNoteHorizon: GoalHorizon = .today
    @State private var noteHoverGeneration = 0
    @State private var noteCardHeight: CGFloat = 96
    @State private var isEditingNote = false
    @State private var noteTriggerHovered = false
    @State private var noteCardHovered = false
    @State private var panelChromeHeight: CGFloat = 0
    @State private var measuredTotalHeight: CGFloat = 0
    @State private var measuredScrollHeight: CGFloat = 0
    @FocusState private var noteFieldFocused: Bool
    @Environment(\.colorScheme) private var scheme

    private var t: KajiTheme { .resolve(scheme) }
    private var shown: [ProviderView] { store.providers.filter { prefs.isVisible($0.id) } }
    /// Measured, not assumed: an under-counted chrome estimate makes the
    /// panel overshoot `maxContentHeight` and AppKit renders the overshoot as
    /// a blank strip above the header.
    private var panelScrollMaxHeight: CGFloat {
        PopoverHeightBudget.scrollMaxHeight(
            maxContentHeight: maxContentHeight,
            measuredChrome: panelChromeHeight
        )
    }
    private var pages: [KajiModuleID] {
        ModulePrefsLogic.primaryModules(
            enabled: prefs.enabledModules,
            favorites: prefs.primaryFavorites
        )
    }
    private var panel: KajiModuleID {
        get { navigation.panel }
        nonmutating set { navigation.panel = newValue }
    }

    var body: some View {
        mainSurface
        .overlayPreferenceValue(NoteAnchorKey.self) { anchor in
            noteOverlay(anchor)
        }
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            GeometryReader { proxy in
                Color.clear.preference(key: PopoverContentSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PopoverContentSizeKey.self) { size in
            measuredTotalHeight = size.height
            reconcileChromeHeight()
            onContentSizeChange?(size)
        }
        .onPreferenceChange(PanelScrollHeightKey.self) { height in
            measuredScrollHeight = height
            reconcileChromeHeight()
        }
        .onAppear { clampPanelToEnabledPages() }
        .onChange(of: prefs.enabledModules) { _ in
            clampPanelToEnabledPages()
        }
        .onChange(of: panel) { _ in
            controls.onDismissDetail()
            noteHoverGeneration += 1
            dismissNoteCard()
        }
        .onChange(of: focusedGoalID) { newValue in
            if let previousFocusedGoalID,
               let goal = dailyGoals.goals(for: previousFocusedGoalHorizon)
                .first(where: { $0.id == previousFocusedGoalID }) {
                dailyGoals.removeIfBlank(goal, in: previousFocusedGoalHorizon)
            }
            previousFocusedGoalID = newValue
            previousFocusedGoalHorizon = navigation.goalHorizon
        }
        .onChange(of: navigation.goalHorizon) { _ in
            focusedGoalID = nil
            noteHoverGeneration += 1
            dismissNoteCard()
        }
    }

    /// Chrome is whatever the popover renders outside the scrollable panel.
    /// Deriving it from the two measured heights keeps the scroll budget
    /// exact when rows, fonts, footers or languages change the chrome.
    private func reconcileChromeHeight() {
        guard measuredTotalHeight > 0, measuredScrollHeight > 0 else { return }
        let chrome = PopoverHeightBudget.chromeHeight(
            totalHeight: measuredTotalHeight,
            scrollHeight: measuredScrollHeight
        )
        if PopoverHeightBudget.isMeaningfulChange(chrome, panelChromeHeight) {
            panelChromeHeight = chrome
        }
    }

    private var mainSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().overlay(t.track.opacity(0.8))
            if scrollsContent {
                ScrollView(.vertical, showsIndicators: false) {
                    panelBody
                }
                .frame(maxHeight: panelScrollMaxHeight)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: PanelScrollHeightKey.self, value: proxy.size.height)
                    }
                )
            } else {
                panelBody
            }
            Divider().overlay(t.track.opacity(0.8))
            controlsFooter
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 12)
        .frame(width: PanelSize.medium.frameSize.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 5) {
            ForEach(pages, id: \.self) { module in
                Button(moduleTitle(module)) {
                    panel = module
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: panel == module ? .bold : .semibold, design: .rounded))
                .foregroundColor(panel == module ? t.cream : t.ash)
                .accessibilityIdentifier("kaji.primary.\(module.rawValue)")
            }
            Spacer(minLength: 4)
            let more = ModulePrefsLogic.moreModules(
                enabled: prefs.enabledModules,
                favorites: prefs.primaryFavorites
            )
            if !more.isEmpty {
                Menu {
                    ForEach(more, id: \.self) { module in
                        Button(MoreMenuItemFormatter.label(
                            title: moduleTitle(module),
                            detail: moreDetail(module)
                        )) {
                            panel = module
                        }
                    }
                } label: {
                    Text("More")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("kaji.more")
            }
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




    private func scheduleGoalRow(_ schedule: ScheduledGoal) -> some View {
        let completed = fixedPlanStore.isCompleted(schedule)
        let tag = dailyGoals.tagDefinition(for: schedule.tag)
        return HStack(spacing: 8) {
            Button {
                fixedPlanStore.toggleCompletion(schedule)
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color(hex: tag.colorHex))
                        if completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 5, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: GoalControlMetrics.diameter, height: GoalControlMetrics.diameter)
                    .frame(width: 16, height: 16)
                    Text(schedule.title)
                        .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                        .foregroundColor(completed ? t.mute : t.cream)
                        .strikethrough(completed)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 4) {
                if !schedule.note.isEmpty {
                    DetailPopoverButton(
                        accessibilityIdentifier: "schedule-detail-\(schedule.id)",
                        help: "查看详情"
                    ) { sourceView in
                        controls.onShowDetail(sourceView, AnyView(scheduleDetails(schedule)))
                    }
                    .frame(width: 18, height: 18)
                }
                miniButton("trash") {
                    fixedPlanStore.delete(schedule)
                }
                .accessibilityIdentifier("schedule-delete-\(schedule.id)")
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(8)
        .background(goalRowSurface(opacity: 0.92))
        .compositingGroup()
        .opacity(completed ? 0.18 : 1)
        .animation(.easeOut(duration: completed ? 5 : 0.18), value: completed)
    }

    private func scheduleDetails(_ schedule: ScheduledGoal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(schedule.title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(t.cream)
            Divider().overlay(t.track.opacity(0.8))
            Text(schedule.note)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(t.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(width: 250, alignment: .topLeading)
        .background(background)
    }


    private var quotaPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            if shown.isEmpty {
                emptyQuota
            } else {
                ForEach(shown.prefix(4)) { provider in
                    quotaRow(provider)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }


    private func quotaRow(_ provider: ProviderView) -> some View {
        let windows = CursorLimitsLogic.windowLabels(for: provider.id)
        let secondary = provider.id == "cursor" ? windows.secondary : "7d"
        return VStack(alignment: .leading, spacing: 5) {
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
                Text(windows.primary)
                Text(ResetFormat.short(provider.resetDate))
                    .foregroundColor(t.gold.opacity(0.9))
                Spacer(minLength: 6)
                Text(secondary)
                Text(percent(provider.weekPercent))
                    .foregroundColor(provider.weekNearLimit ? t.amber : t.gold.opacity(0.9))
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundColor(t.mute)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(scheme == .light ? Color.white.opacity(0.92) : t.panel.opacity(0.75))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(scheme == .light ? Color.black.opacity(0.08) : t.cream.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: scheme == .light ? Color.black.opacity(0.06) : .clear, radius: 4, y: 1)
    }

    private func quotaWindowRow(label: String, value: Double, resetDate: Date?, nearLimit: Bool) -> some View {
        let color = nearLimit ? t.amber : t.gold
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundColor(t.mute)
                Text("·")
                    .foregroundColor(t.ash)
                Text(ResetFormat.phrase(resetDate, prefs.language))
                    .foregroundColor(t.gold.opacity(0.9))
                Spacer(minLength: 6)
                Text(percent(value))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(color)
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            progressBar(min(max(value / 100, 0), 1), color: color)
        }
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

    @ViewBuilder
    private var workPanel: some View {
        if workSession.phase == .breaking {
            Text(workSession.breakClock)
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(t.cream)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(workPrimaryClock)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(workSession.phase == .breakDue ? t.amber : t.cream)
                progressBar(workSession.workProgress,
                            color: workSession.phase == .breakDue ? t.amber : t.gold)
                rhythmControls
                HStack(spacing: 8) {
                    chip("Start Break", filled: true) {
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
        VStack(alignment: .leading, spacing: 10) {
            systemLoadOverview
            topProcesses
            diskOverview
            diskCategoryBreakdown
        }
        .onAppear {
            systemMonitor.refresh()
            systemMonitor.scanDiskInsights()
        }
    }

    private var systemLoadOverview: some View {
        let snapshot = systemMonitor.snapshot
        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("系统负载", detail: snapshot.hasSample ? "实时" : "采集中", image: "cpu")
            HStack(spacing: 8) {
                systemMetric("CPU", snapshot.cpuPercent)
                systemMetric("内存", snapshot.memoryPercent)
                systemMetric("磁盘", snapshot.diskPercent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(t.panel.opacity(0.78)))
    }

    private func systemMetric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(t.mute)
            Text(String(format: "%.0f%%", value))
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(t.cream)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topProcesses: some View {
        let processes = systemMonitor.snapshot.topProcesses
        return VStack(alignment: .leading, spacing: 7) {
            sectionHeader("进程", detail: "CPU / 内存", image: "list.bullet")
            if processes.isEmpty {
                Text(systemMonitor.isRefreshing ? "正在采集进程…" : "暂无进程数据")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .center)
            } else {
                ForEach(processes.prefix(5)) { process in
                    HStack(spacing: 8) {
                        Text(process.command)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(format: "%.1f%%", process.cpu))
                            .frame(width: 48, alignment: .trailing)
                        Text(String(format: "%.1f%%", process.memory))
                            .frame(width: 48, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(t.cream)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(t.panel.opacity(0.62)))
    }

    private var diskOverview: some View {
        let insight = systemMonitor.diskInsights
        let used = max(0, insight.totalBytes - insight.availableBytes)
        let ratio = insight.totalBytes > 0 ? Double(used) / Double(insight.totalBytes) : 0
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("磁盘空间")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(t.cream)
                    Text(insight.totalBytes > 0
                         ? "已用 \(bytes(used)) · 可用 \(bytes(insight.availableBytes))"
                         : "等待首次扫描")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(t.mute)
                }
                Spacer()
                Button {
                    systemMonitor.scanDiskInsights(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(t.track.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .foregroundColor(t.mute)
                .disabled(systemMonitor.isScanningDisk)
            }
            progressBar(ratio, color: ratio >= 0.85 ? t.amber : t.gold)
                .frame(height: 8)
            if systemMonitor.isScanningDisk {
                Text("正在本机扫描文件元数据…")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
            } else if let error = systemMonitor.diskScanError {
                Text("\(error) · 可点击刷新重试")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.amber)
            } else if insight.restrictedCount > 0 {
                Text("\(insight.restrictedCount) 个目录受系统权限限制；结果仅含当前可访问内容")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(t.panel.opacity(0.78)))
    }

    private var diskCategoryBreakdown: some View {
        let rows = DiskFileCategory.allCases
            .map { ($0, systemMonitor.diskInsights.bytes(for: $0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        let scannedBytes = max(rows.reduce(Int64(0)) { $0 + $1.1 }, 1)
        return VStack(alignment: .leading, spacing: 7) {
            sectionHeader("文件类型", detail: diskScanAge, image: "chart.bar.xaxis")
            if rows.isEmpty {
                Text(systemMonitor.isScanningDisk ? "正在归类文件…" : "没有可访问的分类数据")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .center)
            } else {
                ForEach(rows.prefix(6), id: \.0.rawValue) { category, value in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Circle()
                                .fill(categoryColor(category))
                                .frame(width: 6, height: 6)
                            Text(category.label)
                            Spacer()
                            Text(bytes(value)).monospacedDigit()
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(t.cream)
                        progressBar(Double(value) / Double(scannedBytes), color: categoryColor(category))
                            .frame(height: 4)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(t.panel.opacity(0.62)))
    }

    private var diskScanAge: String {
        let date = systemMonitor.diskInsights.scannedAt
        guard date != .distantPast else { return "未扫描" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func categoryColor(_ category: DiskFileCategory) -> Color {
        let opacity: Double
        switch category {
        case .appsDeveloper: opacity = 1
        case .video: opacity = 0.88
        case .images: opacity = 0.76
        case .audio: opacity = 0.66
        case .documents: opacity = 0.56
        case .archives: opacity = 0.46
        case .caches: opacity = 0.36
        case .other: opacity = 0.26
        }
        return t.gold.opacity(opacity)
    }

    private var systemPulse: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(healthColor.opacity(0.13))
                Circle()
                    .stroke(healthColor.opacity(0.25), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: Double(systemHealthScore) / 100)
                    .stroke(healthColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(systemHealthScore)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(t.cream)
                    .monospacedDigit()
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(systemHealthTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(t.cream)
                Text(systemHealthDetail)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
                    .lineLimit(2)
            }
            Spacer(minLength: 5)
            Button {
                systemMonitor.refresh()
                systemMonitor.scanCleanables()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(t.mute)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(t.track.opacity(0.55)))
                    .rotationEffect(.degrees(systemMonitor.isRefreshing ? 180 : 0))
                    .animation(systemMonitor.isRefreshing ? .linear(duration: 0.5).repeatForever(autoreverses: false) : .default,
                               value: systemMonitor.isRefreshing)
            }
            .buttonStyle(.plain)
            .disabled(systemMonitor.isRefreshing)
            .help("刷新系统状态")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.panel.opacity(0.78)))
    }

    private var systemMetrics: some View {
        HStack(spacing: 7) {
            pulseMetric("CPU", "cpu", systemMonitor.snapshot.cpuPercent, warningAt: 80)
            pulseMetric("MEM", "memorychip", systemMonitor.snapshot.memoryPercent, warningAt: 75)
            pulseMetric("DISK", "internaldrive", systemMonitor.snapshot.diskPercent, warningAt: 85)
        }
    }

    private func pulseMetric(_ title: String,
                             _ systemImage: String,
                             _ value: Double,
                             warningAt: Double) -> some View {
        let warning = value >= warningAt
        let accent = warning ? t.amber : t.gold
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                Spacer(minLength: 2)
                if warning {
                    Circle().fill(accent).frame(width: 5, height: 5)
                }
            }
            .foregroundColor(warning ? accent : t.mute)
            Text(systemValue(value))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(t.cream)
                .monospacedDigit()
            progressBar(value / 100, color: accent)
                .frame(height: 5)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.panel.opacity(0.68)))
    }

    private var hotProcesses: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader("Hot Processes", detail: "\(systemMonitor.snapshot.processCount) running", image: "flame")
            if systemMonitor.snapshot.topProcesses.isEmpty {
                Text("等待系统采样…")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)
            } else {
                ForEach(systemMonitor.snapshot.topProcesses.prefix(3)) { process in
                    processRow(process)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.panel.opacity(0.62)))
    }

    private func processRow(_ process: ProcessSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(String(process.command.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(t.bg)
                .frame(width: 22, height: 22)
                .background(Circle().fill(process.cpu >= 50 ? t.amber : t.gold))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(process.command)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(t.cream)
                        .lineLimit(1)
                    Spacer(minLength: 5)
                    Text("CPU \(Int(process.cpu.rounded()))%")
                        .foregroundColor(process.cpu >= 50 ? t.amber : t.gold)
                    Text("MEM \(String(format: "%.1f", process.memory))%")
                        .foregroundColor(t.mute)
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                progressBar(min(process.cpu / maxTopProcessCPU, 1),
                            color: process.cpu >= 50 ? t.amber : t.gold)
                    .frame(height: 4)
            }
        }
        .help("PID \(process.pid)")
    }

    private var cleanupReview: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Cleanup",
                          detail: systemMonitor.isScanningCleanables ? "Scanning…" : "Review \(bytes(systemMonitor.selectedCleanableBytes))",
                          image: "sparkles")
            let visible = systemMonitor.cleanableItems.filter { !$0.isEmpty }
            if visible.isEmpty {
                Text(systemMonitor.isScanningCleanables ? "正在扫描可清理项目…" : "当前没有可清理缓存")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
            } else {
                ForEach(visible.prefix(4)) { item in
                    cleanableRow(item)
                }
                if visible.count > 4 {
                    Text("另有 \(visible.count - 4) 项 · 清理时包含已选项目")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(t.ash)
                }
            }
            HStack(spacing: 7) {
                Button {
                    prefs.autoCleanEnabled.toggle()
                    if prefs.autoCleanEnabled { systemMonitor.runAutoMaintenanceIfNeeded() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: prefs.autoCleanEnabled ? "bolt.fill" : "bolt")
                        Text(prefs.autoCleanEnabled ? "Auto On" : "Auto")
                    }
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(prefs.autoCleanEnabled ? t.bg : t.mute)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(prefs.autoCleanEnabled ? t.gold : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(prefs.autoCleanEnabled ? Color.clear : t.track, lineWidth: 1)))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 5)
                Button {
                    showCleanConfirmation = true
                } label: {
                    Text(systemMonitor.isCleaning ? "Cleaning…" : "Clean \(bytes(systemMonitor.selectedCleanableBytes))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(t.bg)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.gold))
                }
                .buttonStyle(.plain)
                .disabled(systemMonitor.selectedCleanableBytes <= 0 || systemMonitor.isCleaning)
                .opacity(systemMonitor.selectedCleanableBytes <= 0 ? 0.45 : 1)
            }
            if systemMonitor.lastCleanedBytes > 0 {
                Text("已清理 \(bytes(systemMonitor.lastCleanedBytes))")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(t.gold)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.panel.opacity(0.62)))
    }

    private func cleanableRow(_ item: CleanableItem) -> some View {
        Button {
            systemMonitor.toggleCleanable(item)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemMonitor.selectedCleanableIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(systemMonitor.selectedCleanableIds.contains(item.id) ? t.gold : t.ash)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(t.cream)
                        .lineLimit(1)
                    Text(item.isAutoSafe ? "Kaji safe cache" : "Review before cleaning")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundColor(item.isAutoSafe ? t.mute : t.amber)
                }
                Spacer(minLength: 5)
                Text(bytes(item.bytes))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(t.mute)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .help(item.path)
    }

    private func sectionHeader(_ title: String, detail: String, image: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: image)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(t.gold)
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(t.cream)
            Spacer(minLength: 5)
            Text(detail)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(t.ash)
                .lineLimit(1)
        }
    }

    private var maxTopProcessCPU: Double {
        max(systemMonitor.snapshot.topProcesses.map(\.cpu).max() ?? 1, 1)
    }

    private var systemHealthScore: Int {
        guard systemMonitor.snapshot.hasSample else { return 0 }
        let cpuPenalty = max(0, systemMonitor.snapshot.cpuPercent - 35) * 0.48
        let memoryPenalty = max(0, systemMonitor.snapshot.memoryPercent - 55) * 0.62
        let diskPenalty = max(0, systemMonitor.snapshot.diskPercent - 70) * 0.72
        return max(0, min(100, Int((100 - cpuPenalty - memoryPenalty - diskPenalty).rounded())))
    }

    private var systemHealthTitle: String {
        if !systemMonitor.snapshot.hasSample { return "System Pulse" }
        if systemHealthScore >= 85 { return "运行流畅" }
        if systemHealthScore >= 65 { return "负载偏高" }
        return "系统忙碌"
    }

    private var systemHealthDetail: String {
        if let error = systemMonitor.lastError { return "采样失败 · \(error)" }
        if !systemMonitor.snapshot.hasSample { return "正在读取 CPU、内存和磁盘" }
        if let hottest = systemMonitor.snapshot.topProcesses.first {
            return "当前最热 \(hottest.command) · CPU \(Int(hottest.cpu.rounded()))%"
        }
        return "没有持续高负载进程"
    }

    private var healthColor: Color {
        if systemHealthScore >= 85 { return t.gold }
        if systemHealthScore >= 65 { return t.cream.opacity(0.8) }
        return t.amber
    }

    private var goalsPanel: some View {
        goalSection(.today, title: "Goals", showsHeatmap: true)
    }

    private var visionSection: some View {
        let visions = dailyGoals.goals(for: .longTerm)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text("Vision")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(t.cream)
                Spacer()
            }
            ForEach(Array(visions.enumerated()), id: \.element.id) { index, vision in
                HStack(spacing: 7) {
                    goalTagMenu(vision, horizon: .longTerm)
                    if focusedGoalID == vision.id {
                        TextField("写下一条长期方向", text: Binding(
                            get: { vision.title },
                            set: { dailyGoals.updateTitle(vision, title: $0, in: .longTerm) }
                        ), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(t.cream)
                        .lineLimit(1...2)
                        .fixedSize(horizontal: false, vertical: true)
                        .focused($focusedGoalID, equals: vision.id)
                        .onSubmit {
                            dailyGoals.removeIfBlank(vision, in: .longTerm)
                        }
                    } else {
                        goalTitleLabel(vision.title, size: 11) {
                            focusedGoalID = vision.id
                        }
                    }
                    HStack(spacing: 4) {
                        if !vision.note.isEmpty {
                            goalNoteAffordance(vision, horizon: .longTerm)
                        }
                        if index > 0 {
                            miniButton("chevron.up") {
                                dailyGoals.move(vision, in: .longTerm, offset: -1)
                            }
                        }
                        if index < visions.count - 1 {
                            miniButton("chevron.down") {
                                dailyGoals.move(vision, in: .longTerm, offset: 1)
                            }
                        }
                        miniButton("trash") {
                            dailyGoals.delete(vision, in: .longTerm)
                        }
                    }
                    .frame(width: 96, alignment: .trailing)
                }
                .padding(8)
                .background(goalRowSurface(opacity: 0.82))
            }
        }
    }

    private var yesterdayPendingSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("昨日未完成")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(t.mute)
            ForEach(dailyGoals.yesterdayPending) { goal in
                HStack(spacing: 8) {
                    tagIcon(GoalTagLogic.resolve(goal.tag, title: goal.title))
                        .foregroundColor(t.mute)
                    Text(goal.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(t.cream)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        miniButton("arrow.turn.down.right") {
                            dailyGoals.moveYesterdayGoalToToday(goal)
                        }
                        miniButton("trash") {
                            dailyGoals.dismissYesterdayGoal(goal)
                        }
                    }
                    .frame(width: 96, alignment: .trailing)
                }
                .padding(8)
                .background(goalRowSurface(opacity: 0.82))
            }
        }
    }

    private func goalSection(
        _ horizon: GoalHorizon,
        title: String,
        showsHeatmap: Bool
    ) -> some View {
        let goals = dailyGoals.goals(for: horizon)
        let summary = dailyGoals.summary(for: horizon)
        let includesSchedules = horizon == .today
        let schedules = includesSchedules ? fixedPlanStore.visibleTodaySchedules : []
        let completed = summary.completed + (includesSchedules ? fixedPlanStore.todayScheduledCompletedCount : 0)
        let total = summary.total + (includesSchedules ? fixedPlanStore.todayScheduledEntries.count : 0)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(t.cream)
                Text("\(completed)/\(total)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(t.mute)
                    .monospacedDigit()
                Spacer()
                Menu {
                    Section(L10n.t(.goalGroup, prefs.language).uppercased()) {
                        ForEach(GoalGrouping.allCases, id: \.rawValue) { grouping in
                            Button {
                                prefs.goalGrouping = grouping
                            } label: {
                                HStack {
                                    Text(goalGroupingTitle(grouping))
                                    if prefs.goalGrouping == grouping {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(t.mute)
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help(L10n.t(.goalGroup, prefs.language))
                if horizon == .today {
                    Button {
                        beginGoalCreation()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(t.mute)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(Color.clear)
                                    .overlay(Circle().stroke(t.track, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("新建目标（⌘N）")
                }
            }
            if showsGoalCreator {
                goalCreationCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showsHeatmap {
                goalHeatmap
            }
            if includesSchedules {
                ForEach(schedules) { schedule in
                    scheduleGoalRow(schedule)
                }
            }
            ForEach(
                GoalGroupingLogic.group(
                    goals,
                    by: prefs.goalGrouping,
                    tagOrder: dailyGoals.tagDefinitions.map(\.name),
                    language: prefs.language
                ),
                id: \.title
            ) { group in
                if !group.title.isEmpty {
                    Text(group.title)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(t.mute)
                        .padding(.top, 3)
                }
                ForEach(group.goals) { goal in
                    goalRow(goal, horizon: horizon)
                }
            }
            if goals.isEmpty && schedules.isEmpty {
                Text("暂无目标")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(t.mute)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            }
        }
    }
    private func goalGroupingTitle(_ grouping: GoalGrouping) -> String {
        switch grouping {
        case .none: L10n.t(.goalGroupingNone, prefs.language)
        case .byTag: L10n.t(.goalGroupingByTag, prefs.language)
        case .byCreatedTime: L10n.t(.goalGroupingByCreatedTime, prefs.language)
        }
    }


    private var goalCreationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $goalCreationTitle)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Menu {
                    ForEach(dailyGoals.tagDefinitions) { tag in
                        Button(tag.name) {
                            goalCreationTagName = tag.name
                            goalCreationTagColor = tag.colorHex
                        }
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: goalCreationTagColor))
                        .frame(width: 10, height: 10)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                TextField("Tag", text: $goalCreationTagName)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 5) {
                    ForEach([0xE05D6F, 0xD18A3C, 0x4F9D69, 0x5B7CFA, 0x8E6AD8] as [UInt32], id: \.self) { hex in
                        Button {
                            goalCreationTagColor = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle().stroke(
                                        goalCreationTagColor == hex ? t.cream : Color.clear,
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField("Description", text: $goalCreationNote, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Button("取消") { showsGoalCreator = false }
                Spacer()
                Button("保存") { saveGoalCreation() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(goalCreationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(goalRowSurface(opacity: 0.72))
        .foregroundColor(t.cream)
    }

    private func beginGoalCreation() {
        goalCreationTitle = ""
        let defaultTag = dailyGoals.tagDefinitions.first(where: { $0.name == GoalTag.personal.rawValue })
            ?? dailyGoals.tagDefinitions.first
        goalCreationTagName = defaultTag?.name ?? GoalTag.personal.rawValue
        goalCreationTagColor = defaultTag?.colorHex ?? 0x8E6AD8
        goalCreationNote = ""
        withAnimation(.easeOut(duration: 0.16)) {
            showsGoalCreator = true
        }
    }

    private func saveGoalCreation() {
        let title = goalCreationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let tag = dailyGoals.ensureTag(name: goalCreationTagName, colorHex: goalCreationTagColor)
        let id = dailyGoals.addGoal(in: .today)
        if let goal = dailyGoals.goals(for: .today).first(where: { $0.id == id }) {
            dailyGoals.updateTitle(goal, title: title, in: .today)
            dailyGoals.updateTag(goal, tag: tag, in: .today)
            dailyGoals.updateNote(goal, note: goalCreationNote, in: .today)
        }
        showsGoalCreator = false
    }

    private func goalRow(_ goal: DailyGoal, horizon: GoalHorizon) -> some View {
        HStack(spacing: 8) {
            Button {
                dailyGoals.toggle(goal, in: horizon)
            } label: {
                HStack(spacing: 8) {
                    goalStateIndicator(goal)
                    Text(goal.title)
                        .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                        .foregroundColor(goal.isDone ? t.mute : t.cream)
                        .strikethrough(goal.isDone)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(goal.isDone ? "撤回完成" : "完成")
            .accessibilityLabel(goal.isDone ? "撤回完成" : "完成")
            HStack(spacing: 4) {
                if !goal.note.isEmpty {
                    goalNoteAffordance(goal, horizon: horizon)
                }
                miniButton("trash") {
                    dailyGoals.delete(goal, in: horizon)
                }
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(8)
        .background(goalRowSurface(opacity: 0.92))
        .compositingGroup()
        .opacity(goal.isDone ? 0.18 : 1)
        .animation(.easeOut(duration: goal.isDone ? 5 : 0.18), value: goal.isDone)
        .contextMenu {
            Menu("标签") {
                ForEach(dailyGoals.tagDefinitions) { tag in
                    Button(tag.name) {
                        dailyGoals.updateTag(goal, tag: tag.name, in: horizon)
                    }
                }
            }
        }
    }

    private func goalTitleLabel(
        _ title: String,
        size: CGFloat,
        onEdit: @escaping () -> Void
    ) -> some View {
        Text(title.isEmpty ? " " : title)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundColor(t.cream)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onEdit)
    }

    /// Hover-disclosed note affordance. The card is *not* a second
    /// `NSPopover`: nesting one inside the status-item popover made the note
    /// text view resign first responder in a window that had no successor,
    /// which threw during layout and hung/killed the app. It is now a plain
    /// overlay inside the same window, anchored to this icon.
    private func goalNoteAffordance(_ goal: DailyGoal, horizon: GoalHorizon) -> some View {
        let active = hoveredNoteGoalID == goal.id
        return Image(systemName: "text.alignleft")
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(active ? t.cream : t.ash)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .help("说明")
            .accessibilityLabel("说明")
            .accessibilityIdentifier("goal-detail-\(goal.id)")
            .onHover { updateNoteHover(goal.id, horizon: horizon, inside: $0) }
            .anchorPreference(key: NoteAnchorKey.self, value: .bounds) { anchor in
                active ? anchor : nil
            }
    }

    /// The card, rendered once in the root overlay so it can never be clipped
    /// by a row and never needs a window of its own.
    @ViewBuilder
    private func noteOverlay(_ anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            if let anchor,
               let id = hoveredNoteGoalID,
               let goal = dailyGoals.goals(for: hoveredNoteHorizon).first(where: { $0.id == id }) {
                let rect = proxy[anchor]
                let width = NoteCardMetrics.width
                let x = min(max(NoteCardMetrics.margin, rect.minX - width - 6),
                            max(NoteCardMetrics.margin, proxy.size.width - width - NoteCardMetrics.margin))
                let maxY = max(NoteCardMetrics.margin,
                               proxy.size.height - noteCardHeight - NoteCardMetrics.margin)
                let y = min(max(NoteCardMetrics.margin, rect.minY - 6), maxY)
                goalNoteCard(goal, horizon: hoveredNoteHorizon)
                    .frame(width: width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { card in
                            Color.clear.preference(key: NoteCardHeightKey.self, value: card.size.height)
                        }
                    )
                    .offset(x: x, y: y)
                    .onHover { updateNoteCardHover(inside: $0) }
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(NoteCardHeightKey.self) { height in
            if height > 0 { noteCardHeight = height }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredNoteGoalID)
    }

    private func updateNoteHover(_ id: UUID, horizon: GoalHorizon, inside: Bool) {
        noteTriggerHovered = inside
        // Never yank the card away from an active edit; the focus change
        // schedules the dismissal instead.
        if !inside, isEditingNote { return }
        let hadActive = hoveredNoteGoalID != nil
        noteHoverGeneration += 1
        let generation = noteHoverGeneration
        let delay = inside
            ? HoverDisclosurePolicy.openDelay(hasActiveTopic: hadActive)
            : HoverDisclosurePolicy.closeDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == noteHoverGeneration else { return }
            if inside {
                hoveredNoteHorizon = horizon
                hoveredNoteGoalID = id
            } else if hoveredNoteGoalID == id {
                dismissNoteCard()
            }
        }
    }

    private func updateNoteCardHover(inside: Bool) {
        noteCardHovered = inside
        noteHoverGeneration += 1
        guard !inside, !isEditingNote else { return }
        scheduleNoteDismissal()
    }

    /// Called when the note field gains or loses focus. Losing focus while the
    /// pointer sits outside both the trigger and the card is the one path that
    /// would otherwise leave the card stranded on screen.
    private func noteFocusChanged(_ focused: Bool) {
        isEditingNote = focused
        guard !focused else { return }
        noteHoverGeneration += 1
        scheduleNoteDismissal()
    }

    private func scheduleNoteDismissal() {
        let generation = noteHoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + HoverDisclosurePolicy.closeDelay) {
            guard generation == noteHoverGeneration,
                  NoteCardHoverPolicy.shouldDismiss(
                      triggerHovered: noteTriggerHovered,
                      cardHovered: noteCardHovered,
                      editing: isEditingNote
                  ) else { return }
            dismissNoteCard()
        }
    }

    private func dismissNoteCard() {
        if isEditingNote {
            noteFieldFocused = false
            isEditingNote = false
        }
        noteTriggerHovered = false
        noteCardHovered = false
        hoveredNoteGoalID = nil
    }

    func goalNoteCard(_ goal: DailyGoal, horizon: GoalHorizon) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(goal.title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(t.cream)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(t.track)
                .frame(height: 1)
            TextField("说明", text: Binding(
                get: { dailyGoals.goals(for: horizon).first(where: { $0.id == goal.id })?.note ?? "" },
                set: { dailyGoals.updateNote(goal, note: $0, in: horizon) }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(t.cream)
            .lineLimit(2...10)
            .fixedSize(horizontal: false, vertical: true)
            .focused($noteFieldFocused)
            .onChange(of: noteFieldFocused) { focused in
                noteFocusChanged(focused)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(t.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(t.track, lineWidth: 1)
                )
        )
    }

    private func goalTagMenu(_ goal: DailyGoal, horizon: GoalHorizon) -> some View {
        let selected = dailyGoals.tagDefinition(for: goal.tag)
        return Circle()
            .fill(Color(hex: selected.colorHex))
            .frame(width: 9, height: 9)
            .frame(width: 18, height: 22)
            .help(selected.name)
            .contextMenu {
                ForEach(dailyGoals.tagDefinitions) { tag in
                    Button(tag.name) {
                        dailyGoals.updateTag(goal, tag: tag.name, in: horizon)
                    }
                }
            }
    }

    private func goalStateIndicator(_ goal: DailyGoal) -> some View {
        let selected = dailyGoals.tagDefinition(for: goal.tag)
        return ZStack {
            Circle()
                .fill(Color(hex: selected.colorHex))
            if goal.isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: GoalControlMetrics.diameter, height: GoalControlMetrics.diameter)
        .frame(width: 16, height: 16)
    }

    private func completionIcon(isDone: Bool) -> some View {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isDone ? t.gold : t.mute)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
    }

    private func tagIcon(_ tag: GoalTag) -> some View {
        Image(systemName: tag.systemImage)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(t.mute)
            .frame(width: 16, height: 16)
    }

    private var goalHeatmap: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 3
            let side = max(5, (geo.size.width - spacing * 29) / 30)
            HStack(spacing: spacing) {
                ForEach(dailyGoals.heatmapDays) { day in
                    Circle()
                        .fill(goalHeatColor(day.ratio, empty: day.total == 0))
                        .frame(width: side, height: side)
                        .overlay(
                            Circle()
                                .stroke(
                                    hoveredGoalDay?.day == day.day ? t.cream.opacity(0.75) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .onHover { hovering in
                            hoveredGoalDay = hovering ? day : nil
                        }
                        .help(goalHeatReadout(day))
                        .accessibilityLabel(goalHeatReadout(day))
                }
            }
        }
        .frame(height: 12)
    }

    private func goalRowSurface(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(t.panel.opacity(opacity))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(t.track.opacity(0.55), lineWidth: 0.6)
            )
    }

    private func goalHeatColor(_ ratio: Double, empty: Bool) -> Color {
        if empty { return t.track.opacity(0.5) }
        if ratio >= 0.99 { return t.gold }
        if ratio >= 0.66 { return t.gold.opacity(0.72) }
        if ratio >= 0.33 { return t.gold.opacity(0.42) }
        return t.track.opacity(0.9)
    }


    private func goalHeatReadout(_ day: DailyGoalHistoryDay) -> String {
        GoalHeatmapFormatter.string(day: day.day, completed: day.completed, total: day.total)
    }

    private var controlsFooter: some View {
        HStack(spacing: 7) {
            Spacer()
            iconButton(
                "gearshape",
                title: L10n.t(.settings, prefs.language),
                accessibilityIdentifier: "kaji.settings.open",
                action: controls.onOpenSettings
            )
            iconButton("power", title: L10n.t(.quit, prefs.language), action: controls.onQuit)
        }
        .frame(height: 32)
    }


    private func moduleTitle(_ module: KajiModuleID) -> String {
        switch module {
        case .quota: return "Quota"
        case .work: return "Work / Break"
        case .system: return "System"
        case .goals: return "Goals"
        }
    }

    /// One-line live status for the More menu. Drawn only from stores this
    /// view already observes; `nil` renders the bare title.
    private func moreDetail(_ module: KajiModuleID) -> String? {
        switch module {
        case .quota:
            return nil
        case .work:
            return workPrimaryClock
        case .system:
            return systemValue(systemMonitor.snapshot.cpuPercent)
        case .goals:
            return MenuBarSlotLogic.goalsLabel(
                enabled: prefs.isModuleEnabled(.goals),
                goals: dailyGoals.todayGoalEntries,
                scheduledCompleted: fixedPlanStore.todayScheduledCompletedCount,
                scheduledTotal: fixedPlanStore.todayScheduledEntries.count
            )
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


    private var background: some View {
        LinearGradient(colors: [t.bgTop, t.bg],
                       startPoint: .topTrailing,
                       endPoint: .bottomLeading)
    }


    private func clampPanelToEnabledPages() {
        if prefs.enabledModules.contains(panel) {
            return
        }
        let list = pages
        if list.isEmpty {
            panel = .quota
            return
        }
        if !list.contains(panel) {
            panel = list[0]
        }
    }


    private func iconButton(_ systemName: String,
                            title: String,
                            accessibilityIdentifier: String? = nil,
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
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }

    private func miniButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(t.ash)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
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
        DiskSizeFormatter.string(bytes: value)
    }

    private func systemValue(_ value: Double) -> String {
        systemMonitor.snapshot.hasSample ? "\(Int(value.rounded()))%" : "..."
    }



}

