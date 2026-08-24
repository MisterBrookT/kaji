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
}

private struct PopoverContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private enum GoalCreationKind: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case vision = "Vision"
    case fixed = "Schedule"
}

struct KajiPopoverView: View {
    @ObservedObject var store: QuotaStore
    @ObservedObject var prefs: Prefs
    @ObservedObject var workSession: WorkSessionController
    @ObservedObject var systemMonitor: SystemMonitor
    @ObservedObject var dailyGoals: DailyGoalStore
    @ObservedObject var fixedPlanStore: FixedPlanStore
    @ObservedObject var aiNewsStore: AIHotNewsStore
    @ObservedObject var mailBriefStore: MailBriefStore
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
    @State private var shownScheduleDetailsID: UUID?
    @State private var fixedPlanHoverGeneration = 0
    @FocusState private var focusedGoalID: UUID?
    @State private var showCleanConfirmation = false
    @State private var showsGoalCreator = false
    @State private var goalCreationKind: GoalCreationKind = .today
    @State private var goalCreationTitle = ""
    @State private var goalCreationTag: GoalTag = .personal
    @State private var goalCreationWeekdays: Set<Int> = [
        Calendar.current.component(.weekday, from: Date())
    ]
    @State private var goalCreationNote = ""
    @State private var shownGoalNoteID: UUID?
    @State private var goalNoteHoverGeneration = 0
    @State private var hoveredNewsID: String?
    @State private var newsHoverGeneration = 0
    @State private var hoveredMailID: String?
    @State private var mailHoverGeneration = 0
    @Environment(\.colorScheme) private var scheme

    private var t: KajiTheme { .resolve(scheme) }
    private var shown: [ProviderView] { store.providers.filter { prefs.isVisible($0.id) } }
    private var panelScrollMaxHeight: CGFloat { max(180, maxContentHeight - 104) }
    private var pages: [KajiModuleID] { prefs.popoverModulePages }
    private var panel: KajiModuleID {
        get { navigation.panel }
        nonmutating set { navigation.panel = newValue }
    }
    private var pageIndex: Int {
        pages.firstIndex(of: panel) ?? 0
    }

    var body: some View {
        mainSurface
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            GeometryReader { proxy in
                Color.clear.preference(key: PopoverContentSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PopoverContentSizeKey.self) { size in
            onContentSizeChange?(size)
        }
        .onAppear { clampPanelToEnabledPages() }
        .onChange(of: prefs.enabledModules) { _ in
            clampPanelToEnabledPages()
        }
        .onChange(of: panel) { _ in
            shownScheduleDetailsID = nil
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
            } else {
                panelBody
            }
            Divider().overlay(t.track.opacity(0.8))
            controlsFooter
        }
        .padding(12)
        .frame(width: PanelSize.medium.frameSize.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if pages.count > 1 {
                arrow("chevron.left") { move(-1) }
            }
            Text(panelTitle)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(t.cream)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(pageIndex + 1)/\(max(pages.count, 1))")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(t.ash)
            if pages.count > 1 {
                arrow("chevron.right") { move(1) }
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
        case .aiNews:
            aiNewsPanel
        case .mailBrief:
            mailBriefPanel
        }
    }

    private var aiNewsPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch aiNewsStore.state {
            case .loading where aiNewsStore.topics.isEmpty:
                HStack { Spacer(); ProgressView(); Text(L10n.t(.loading, prefs.language)); Spacer() }.padding(24)
            case .failed where aiNewsStore.topics.isEmpty:
                Button(L10n.t(.retry, prefs.language)) { aiNewsStore.refresh(force: true) }
                    .frame(maxWidth: .infinity).padding(20)
            case .empty:
                Text(L10n.t(.noHotNews, prefs.language)).foregroundColor(t.mute).frame(maxWidth: .infinity).padding(24)
            default:
                ForEach(aiNewsStore.topics) { topic in
                    aiNewsRow(topic)
                }
            }
            if aiNewsStore.state == .stale {
                Text("AI HOT unavailable · cached results")
                    .font(.system(size: 9, weight: .medium)).foregroundColor(t.mute)
            }
            HStack {
                Button { aiNewsStore.refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                }.buttonStyle(.plain).help(L10n.t(.refreshNow, prefs.language))
                Spacer()
                Link("\(L10n.t(.dataSource, prefs.language)): AI HOT", destination: URL(string: "https://aihot.virxact.com")!)
                    .font(.system(size: 9, weight: .medium)).foregroundColor(t.mute)
            }.padding(.top, 3)
        }
    }

    private var mailBriefPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch mailBriefStore.state {
            case .disabled:
                EmptyView()
            case .disconnected:
                VStack(spacing: 8) {
                    Text("Connect Gmail to create one quiet brief each day.")
                        .font(.system(size: 10.5, weight: .medium)).foregroundColor(t.mute)
                    Button("Connect Gmail") { mailBriefStore.connect() }.buttonStyle(.bordered)
                    if let error = mailBriefStore.lastError {
                        Text(error)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(t.mute)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity).padding(22)
            case .scheduled where mailBriefStore.generation == nil:
                Text("Next brief \(mailBriefStore.nextDue?.formatted(date: .omitted, time: .shortened) ?? "09:00")")
                    .font(.system(size: 10.5, weight: .medium)).foregroundColor(t.mute)
                    .frame(maxWidth: .infinity).padding(22)
            case .failed where mailBriefStore.generation == nil:
                VStack(spacing: 7) {
                    Text(mailBriefStore.lastError ?? "Mail Brief failed").foregroundColor(t.mute)
                    Button("Retry") { mailBriefStore.generateNow() }.buttonStyle(.plain)
                }.frame(maxWidth: .infinity).padding(20)
            default:
                if mailBriefStore.state != .running && mailBriefStore.sections.filter({ $0.level > 0 }).isEmpty {
                    Text("今天没有需要处理的邮件")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(t.mute)
                        .frame(maxWidth: .infinity).padding(20)
                }
                ForEach(mailBriefStore.sections.filter { $0.level > 0 }, id: \.level) { section in
                    mailBriefSection(section)
                }
                if let quiet = mailBriefStore.sections.first(where: { $0.level == 0 }) {
                    DisclosureGroup("Quiet  \(quiet.entries.count)") {
                        ForEach(quiet.entries) { mailBriefRow($0) }
                    }.font(.system(size: 10, weight: .semibold)).foregroundColor(t.mute)
                }
                if !mailBriefStore.dismissedEntries.isEmpty {
                    DisclosureGroup("已忽略  \(mailBriefStore.dismissedEntries.count)") {
                        ForEach(mailBriefStore.dismissedEntries) { entry in
                            HStack {
                                Text(entry.subject).lineLimit(1).font(.system(size: 10.5, weight: .medium))
                                Spacer()
                                Button { mailBriefStore.restore(entry) } label: { Image(systemName: "arrow.uturn.backward") }
                                    .buttonStyle(.plain).help("恢复")
                            }.padding(.vertical, 5)
                        }
                    }.font(.system(size: 10, weight: .semibold)).foregroundColor(t.mute)
                }
                if !mailBriefStore.archivedEntries.isEmpty {
                    DisclosureGroup("已完成  \(mailBriefStore.archivedEntries.count)") {
                        ForEach(mailBriefStore.archivedEntries) { entry in
                            mailBriefUndoRow(entry, action: { mailBriefStore.unarchive(entry) }, help: "撤销归档")
                        }
                    }.font(.system(size: 10, weight: .semibold)).foregroundColor(t.mute)
                }
                if !mailBriefStore.trashedEntries.isEmpty {
                    DisclosureGroup("已删除  \(mailBriefStore.trashedEntries.count)") {
                        ForEach(mailBriefStore.trashedEntries) { entry in
                            mailBriefUndoRow(entry, action: { mailBriefStore.untrash(entry) }, help: "移出垃圾箱")
                        }
                    }.font(.system(size: 10, weight: .semibold)).foregroundColor(t.mute)
                }
            }
            HStack {
                if mailBriefStore.state == .running {
                    ProgressView().controlSize(.small)
                    if let progress = mailBriefStore.syncProgress {
                        Text("已分类 \(progress.completed) / Inbox \(progress.total)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(t.mute)
                    } else {
                        Text("正在读取 Inbox…").font(.system(size: 9, weight: .medium)).foregroundColor(t.mute)
                    }
                } else if let count = mailBriefStore.generation?.snapshotInboxThreadCount {
                    Text("Inbox \(count)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(t.mute)
                }
                if mailBriefStore.state == .stale { Text("上次生成失败，显示旧简报").font(.system(size: 9)).foregroundColor(t.mute) }
                if let error = mailBriefStore.lastError, mailBriefStore.state != .stale {
                    Text(error).font(.system(size: 9)).foregroundColor(t.mute).lineLimit(2)
                }
                Spacer()
                Button { mailBriefStore.generateNow() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(!mailBriefStore.isConnected || mailBriefStore.state == .running)
                    .help("立即生成")
            }
        }
    }

    private func mailBriefSection(_ section: MailBriefSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                levelBlocks(section.level)
                Text(mailLevelTitle(section.level))
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(t.cream)
                Text("\(section.entries.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(t.mute)
            }.accessibilityElement(children: .ignore).accessibilityLabel("\(mailLevelTitle(section.level))，\(section.entries.count) 封")
            ForEach(section.entries) { mailBriefRow($0) }
        }
    }

    private func levelBlocks(_ level: Int) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.2)
                    .fill(index < level ? t.cream.opacity(0.72) : t.ash.opacity(0.28))
                    .frame(width: 5, height: 5)
            }
        }.accessibilityHidden(true)
    }

    private func mailLevelTitle(_ level: Int) -> String {
        switch level { case 3: "优先处理"; case 2: "今天处理"; case 1: "留意"; default: "Quiet" }
    }

    private func mailBriefRow(_ entry: MailBriefEntry) -> some View {
        HStack(spacing: 7) {
            Button { if let url = entry.gmailURL { NSWorkspace.shared.open(url) } } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.subject).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(t.cream).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if !entry.sender.isEmpty { Text(entry.sender).font(.system(size: 8.5)).foregroundColor(t.mute).lineLimit(1) }
                }
            }.buttonStyle(.plain)
            if mailBriefStore.pendingThreadIDs.contains(entry.threadID) {
                ProgressView().controlSize(.mini).frame(width: 50)
            } else {
                Button { mailBriefStore.archive(entry) } label: { Image(systemName: "archivebox") }
                    .buttonStyle(.plain).help("完成并归档")
                Button { mailBriefStore.toggleStar(entry) } label: {
                    Image(systemName: (entry.isStarred ?? false) ? "star.fill" : "star")
                }.buttonStyle(.plain).help((entry.isStarred ?? false) ? "取消 Flag" : "Flag")
                Button { mailBriefStore.trash(entry) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("移到 Gmail 垃圾箱")
                Button { convertMailToGoal(entry) } label: {
                    Image(systemName: mailBriefStore.isConverted(entry) ? "checkmark.circle.fill" : "checkmark.circle")
                }.buttonStyle(.plain).disabled(mailBriefStore.isConverted(entry)).help("转成 Today Goal")
            }
        }
        .padding(7).background(RoundedRectangle(cornerRadius: 7).fill(t.panel.opacity(0.7)))
        .onHover { inside in updateMailHover(entry, inside: inside) }
        .popover(isPresented: Binding(get: { hoveredMailID == entry.threadID }, set: { if !$0 { hoveredMailID = nil } }), arrowEdge: .trailing) {
            mailBriefDetail(entry).onHover { updateMailDetailHover(inside: $0) }
        }
        .contextMenu {
            Button("忽略本次简报") { mailBriefStore.dismiss(entry) }
        }
    }

    private func mailBriefUndoRow(_ entry: MailBriefEntry, action: @escaping () -> Void, help: String) -> some View {
        HStack {
            Text(entry.subject).lineLimit(1).font(.system(size: 10.5, weight: .medium))
            Spacer()
            if mailBriefStore.pendingThreadIDs.contains(entry.threadID) {
                ProgressView().controlSize(.mini)
            } else {
                Button(action: action) { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain).help(help)
            }
        }.padding(.vertical, 5)
    }

    private func mailBriefDetail(_ entry: MailBriefEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.subject).font(.system(size: 12, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            if !entry.sender.isEmpty { Text(entry.sender).font(.system(size: 9, weight: .medium)).foregroundColor(t.mute) }
            Divider()
            Text(entry.summaryZH).font(.system(size: 10.5)).fixedSize(horizontal: false, vertical: true)
            Text(entry.reasonZH).font(.system(size: 9.5, weight: .medium)).foregroundColor(t.mute).fixedSize(horizontal: false, vertical: true)
            if let deadline = entry.deadline { Text("截止：\(deadline.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 9.5, weight: .semibold)) }
            if let url = entry.gmailURL { Link("在 Gmail 打开", destination: url).font(.system(size: 9.5, weight: .semibold)) }
        }.padding(12).frame(width: 260, alignment: .leading)
    }

    private func convertMailToGoal(_ entry: MailBriefEntry) {
        guard !mailBriefStore.isConverted(entry) else { return }
        let note = [entry.summaryZH, entry.reasonZH, entry.gmailURL?.absoluteString].compactMap { $0 }.joined(separator: "\n\n")
        if let goal = try? dailyGoals.addGoal(title: entry.goalTitleZH ?? entry.subject,
                                              tag: GoalTag.work.rawValue, note: note, in: .today) {
            mailBriefStore.markConverted(entry, goalID: goal.id)
        }
    }

    private func updateMailHover(_ entry: MailBriefEntry, inside: Bool) {
        let hadActive = hoveredMailID != nil; mailHoverGeneration += 1; let generation = mailHoverGeneration
        let delay = inside ? HoverDisclosurePolicy.openDelay(hasActiveTopic: hadActive) : HoverDisclosurePolicy.closeDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == mailHoverGeneration else { return }
            if inside { hoveredMailID = entry.threadID } else if hoveredMailID == entry.threadID { hoveredMailID = nil }
        }
    }
    private func updateMailDetailHover(inside: Bool) {
        mailHoverGeneration += 1; guard !inside else { return }; let generation = mailHoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + HoverDisclosurePolicy.closeDelay) {
            guard generation == mailHoverGeneration else { return }; hoveredMailID = nil
        }
    }

    private func aiNewsRow(_ topic: AIHotTopic) -> some View {
        Button {
            aiNewsStore.markRead(topic)
            NSWorkspace.shared.open(topic.originalURL)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(String(format: "%02d", topic.rank))
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(t.ash).frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(t.cream).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(topic.latestAt.formatted(.relative(presentation: .numeric)))
                        .font(.system(size: 8.5, weight: .medium)).foregroundColor(t.mute).lineLimit(1)
                }
            }.padding(7).background(RoundedRectangle(cornerRadius: 7).fill(t.panel.opacity(0.7)))
                .opacity(aiNewsStore.readTopicIDs.contains(topic.id) ? 0.58 : 1)
        }
        .buttonStyle(.plain)
        .onHover { inside in updateNewsHover(topic, inside: inside) }
        .popover(
            isPresented: Binding(
                get: { hoveredNewsID == topic.id },
                set: {
                    if !$0, hoveredNewsID == topic.id {
                        newsHoverGeneration += 1
                        hoveredNewsID = nil
                    }
                }
            ),
            arrowEdge: .trailing
        ) {
            aiNewsDetail(topic)
                .onHover { updateNewsDetailHover(inside: $0) }
        }
    }

    private func aiNewsDetail(_ topic: AIHotTopic) -> some View {
        let story = topic.storyPublicID.flatMap { aiNewsStore.hoveredStoryByID[$0] }
        let sourceNames = topic.sourceNames.isEmpty ? [topic.sourceName] : topic.sourceNames
        let sourceSummary = sourceNames.prefix(3).joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 7) {
            Text(topic.title)
                .font(.system(size: 12, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollView {
                Text(story?.digest ?? story?.latest ?? L10n.t(.loading, prefs.language))
                    .font(.system(size: 10))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            Divider()
            Text(sourceSummary)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(t.mute)
                .lineLimit(2)
            Text("\(topic.sourceCount) \(L10n.t(.sources, prefs.language)) · \(topic.latestAt.formatted(.relative(presentation: .numeric)))")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(t.mute)
            Link("AI HOT", destination: topic.aiHotURL).font(.system(size: 9, weight: .semibold))
        }.padding(12).frame(width: 250, alignment: .leading)
    }

    private func updateNewsHover(_ topic: AIHotTopic, inside: Bool) {
        let hadActiveTopic = hoveredNewsID != nil
        newsHoverGeneration += 1
        let generation = newsHoverGeneration
        let delay = inside
            ? HoverDisclosurePolicy.openDelay(hasActiveTopic: hadActiveTopic)
            : HoverDisclosurePolicy.closeDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == newsHoverGeneration else { return }
            if inside { hoveredNewsID = topic.id; aiNewsStore.loadStory(for: topic) }
            else if hoveredNewsID == topic.id { hoveredNewsID = nil }
        }
    }

    private func updateNewsDetailHover(inside: Bool) {
        newsHoverGeneration += 1
        guard !inside else { return }
        let generation = newsHoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + HoverDisclosurePolicy.closeDelay) {
            guard generation == newsHoverGeneration else { return }
            hoveredNewsID = nil
        }
    }

    private func scheduleGoalRow(_ schedule: ScheduledGoal) -> some View {
        let completed = fixedPlanStore.isCompleted(schedule)
        return Button {
            fixedPlanStore.toggleCompletion(schedule)
        } label: {
            HStack(spacing: 8) {
                completionIcon(isDone: completed)
                Text(schedule.title)
                    .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                    .foregroundColor(completed ? t.mute : t.cream)
                    .strikethrough(completed)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !schedule.note.isEmpty {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(t.mute)
                        .frame(width: 30, alignment: .trailing)
                }
            }
            .padding(8)
            .background(goalRowSurface(opacity: 0.92))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            updateScheduleHover(schedule, inside: inside)
        }
        .popover(isPresented: Binding(
            get: { shownScheduleDetailsID == schedule.id && !schedule.note.isEmpty },
            set: { if !$0 { shownScheduleDetailsID = nil } }
        ), arrowEdge: .trailing) {
            scheduleDetails(schedule)
                .onHover { inside in
                    updateScheduleHover(schedule, inside: inside)
                }
        }
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

    private func updateScheduleHover(_ schedule: ScheduledGoal, inside: Bool) {
        guard !schedule.note.isEmpty else { return }
        fixedPlanHoverGeneration += 1
        let generation = fixedPlanHoverGeneration
        if inside {
            shownScheduleDetailsID = schedule.id
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard generation == fixedPlanHoverGeneration else { return }
            shownScheduleDetailsID = nil
        }
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(t.cream.opacity(0.06), lineWidth: 0.5)
        )
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
            diskOverview
            diskCategoryBreakdown
        }
        .onAppear {
            systemMonitor.scanDiskInsights()
        }
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
        VStack(alignment: .leading, spacing: 13) {
            goalSection(.today, title: "今天", showsHeatmap: true)
            if !dailyGoals.yesterdayPending.isEmpty {
                yesterdayPendingSection
            }
            Divider().overlay(t.track.opacity(0.7))
            goalSection(.week, title: "本周", showsHeatmap: false)
            Divider().overlay(t.track.opacity(0.7))
            visionSection
        }
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
                            Button {
                                shownGoalNoteID = vision.id
                            } label: {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(t.mute)
                            .onHover { updateGoalNoteHover(vision, inside: $0) }
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
                .contextMenu {
                    Button(vision.note.isEmpty ? "添加说明" : "编辑说明") {
                        shownGoalNoteID = vision.id
                    }
                }
                .popover(isPresented: Binding(
                    get: { shownGoalNoteID == vision.id },
                    set: { if !$0 { shownGoalNoteID = nil } }
                ), arrowEdge: .trailing) {
                    goalNoteEditor(vision, horizon: .longTerm)
                        .onHover { updateGoalNoteHover(vision, inside: $0) }
                }
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
        let schedules = includesSchedules ? fixedPlanStore.today : []
        let completed = summary.completed + (includesSchedules ? fixedPlanStore.todayCompletedCount : 0)
        let total = summary.total + schedules.count
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
                if horizon == .today {
                    Button {
                        beginGoalCreation(.today)
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
                    .popover(isPresented: $showsGoalCreator, arrowEdge: .trailing) {
                        goalCreationPopover
                    }
                }
            }
            if showsHeatmap {
                goalHeatmap
            }
            if includesSchedules {
                ForEach(schedules) { schedule in
                    scheduleGoalRow(schedule)
                }
            }
            ForEach(goals) { goal in
                goalRow(goal, horizon: horizon)
            }
            if goals.isEmpty && schedules.isEmpty {
                Text("暂无目标")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(t.mute)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            }
        }
    }

    private var goalCreationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建目标")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Picker("类型", selection: $goalCreationKind) {
                ForEach(GoalCreationKind.allCases, id: \.rawValue) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            if goalCreationKind == .fixed {
                HStack(spacing: 5) {
                    Text("星期")
                    Spacer()
                    ForEach(1...7, id: \.self) { day in
                        Button {
                            if goalCreationWeekdays.contains(day) {
                                goalCreationWeekdays.remove(day)
                            } else {
                                goalCreationWeekdays.insert(day)
                            }
                        } label: {
                            Text(["日", "一", "二", "三", "四", "五", "六"][day - 1])
                                .frame(width: 22, height: 22)
                                .background(
                                    Circle().fill(goalCreationWeekdays.contains(day) ? t.gold : t.panel)
                                )
                                .foregroundColor(goalCreationWeekdays.contains(day) ? t.bg : t.mute)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField(goalCreationKind == .vision ? "长期方向" : "标题", text: $goalCreationTitle)
                .textFieldStyle(.roundedBorder)
            Picker("标签", selection: $goalCreationTag) {
                ForEach(GoalTag.selectableCases, id: \.rawValue) { tag in
                    Image(systemName: tag.systemImage)
                        .accessibilityLabel(tag.label)
                        .tag(tag)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 10, weight: .regular))
            TextField("说明（可选）", text: $goalCreationNote, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
            HStack {
                Button("取消") { showsGoalCreator = false }
                Spacer()
                Button("保存") { saveGoalCreation() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        goalCreationTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (goalCreationKind == .fixed && goalCreationWeekdays.isEmpty)
                    )
            }
        }
        .padding(16)
        .frame(width: goalCreationKind == .fixed ? 360 : 320)
        .background(t.bg)
        .foregroundColor(t.cream)
    }

    private func beginGoalCreation(_ kind: GoalCreationKind) {
        goalCreationKind = kind
        goalCreationTitle = ""
        goalCreationTag = .personal
        goalCreationWeekdays = [Calendar.current.component(.weekday, from: Date())]
        goalCreationNote = ""
        showsGoalCreator = true
    }

    private func saveGoalCreation() {
        let title = goalCreationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if goalCreationKind == .fixed {
            _ = fixedPlanStore.add(
                title: title,
                tag: goalCreationTag.rawValue,
                note: goalCreationNote,
                weekdays: goalCreationWeekdays
            )
        } else {
            let horizon: GoalHorizon
            switch goalCreationKind {
            case .today: horizon = .today
            case .week: horizon = .week
            case .vision: horizon = .longTerm
            case .fixed: return
            }
            let id = dailyGoals.addGoal(in: horizon)
            if let goal = dailyGoals.goals(for: horizon).first(where: { $0.id == id }) {
                dailyGoals.updateTitle(goal, title: title, in: horizon)
                dailyGoals.updateTag(goal, tag: goalCreationTag.rawValue, in: horizon)
                dailyGoals.updateNote(goal, note: goalCreationNote, in: horizon)
            }
        }
        showsGoalCreator = false
    }

    private func goalRow(_ goal: DailyGoal, horizon: GoalHorizon) -> some View {
        HStack(spacing: 8) {
            goalCompletionButton(goal, horizon: horizon)
            if goal.isDone {
                Text(goal.title)
                    .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                    .foregroundColor(t.mute)
                    .strikethrough()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if focusedGoalID == goal.id {
                    TextField("", text: Binding(
                        get: { goal.title },
                        set: { dailyGoals.updateTitle(goal, title: $0, in: horizon) }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                    .foregroundColor(t.cream)
                    .lineLimit(1...2)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($focusedGoalID, equals: goal.id)
                    .onSubmit {
                        dailyGoals.removeIfBlank(goal, in: horizon)
                    }
                } else {
                    goalTitleLabel(goal.title, size: 10.8) {
                        focusedGoalID = goal.id
                    }
                }
            }
            HStack(spacing: 4) {
                if !goal.note.isEmpty {
                    Button {
                        shownGoalNoteID = goal.id
                    } label: {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(t.mute)
                    .onHover { updateGoalNoteHover(goal, inside: $0) }
                }
                miniButton("trash") {
                    dailyGoals.delete(goal, in: horizon)
                }
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(8)
        .background(goalRowSurface(opacity: 0.92))
        .contextMenu {
            Button(goal.note.isEmpty ? "添加说明" : "编辑说明") {
                shownGoalNoteID = goal.id
            }
            Menu("标签") {
                ForEach(GoalTag.selectableCases, id: \.rawValue) { tag in
                    Button {
                        dailyGoals.updateTag(goal, tag: tag.rawValue, in: horizon)
                    } label: {
                        Label(tag.label, systemImage: tag.systemImage)
                    }
                }
            }
        }
        .popover(isPresented: Binding(
            get: { shownGoalNoteID == goal.id },
            set: { if !$0 { shownGoalNoteID = nil } }
        ), arrowEdge: .trailing) {
            goalNoteEditor(goal, horizon: horizon)
                .onHover { updateGoalNoteHover(goal, inside: $0) }
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

    private func goalNoteEditor(_ goal: DailyGoal, horizon: GoalHorizon) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goal.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            TextField("说明（可选）", text: Binding(
                get: { dailyGoals.goals(for: horizon).first(where: { $0.id == goal.id })?.note ?? "" },
                set: { dailyGoals.updateNote(goal, note: $0, in: horizon) }
            ), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...8)
        }
        .padding(10)
        .frame(width: 260)
        .background(t.bg)
        .foregroundColor(t.cream)
    }

    private func updateGoalNoteHover(_ goal: DailyGoal, inside: Bool) {
        let hadActiveGoal = shownGoalNoteID != nil
        goalNoteHoverGeneration += 1
        let generation = goalNoteHoverGeneration
        let delay = inside
            ? HoverDisclosurePolicy.openDelay(hasActiveTopic: hadActiveGoal)
            : HoverDisclosurePolicy.closeDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == goalNoteHoverGeneration else { return }
            if inside {
                shownGoalNoteID = goal.id
            } else if shownGoalNoteID == goal.id {
                shownGoalNoteID = nil
            }
        }
    }

    private func goalTagMenu(_ goal: DailyGoal, horizon: GoalHorizon) -> some View {
        let selected = GoalTagLogic.resolve(goal.tag, title: goal.title)
        return Menu {
            ForEach(GoalTag.selectableCases, id: \.rawValue) { tag in
                Button {
                    dailyGoals.updateTag(goal, tag: tag.rawValue, in: horizon)
                } label: {
                    Image(systemName: tag.systemImage)
                        .accessibilityLabel(tag.label)
                }
            }
        } label: {
            tagIcon(selected)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
    }

    private func goalCompletionButton(_ goal: DailyGoal, horizon: GoalHorizon) -> some View {
        Button {
            dailyGoals.toggle(goal, in: horizon)
        } label: {
            completionIcon(isDone: goal.isDone)
        }
        .buttonStyle(.plain)
        .help(goal.isDone ? "标记为未完成" : "标记为完成")
        .accessibilityLabel(goal.isDone ? "标记为未完成" : "标记为完成")
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
        .background(goalRowSurface(opacity: 0.7))
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
            Spacer()
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
        case .aiNews: return L10n.t(.aiNews, prefs.language)
        case .mailBrief: return "Mail Brief"
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

    private func move(_ delta: Int) {
        let list = pages
        guard list.count > 1 else { return }
        let next = (pageIndex + delta + list.count) % list.count
        panel = list[next]
    }

    private func clampPanelToEnabledPages() {
        let list = pages
        if list.isEmpty {
            panel = .quota
            return
        }
        if !list.contains(panel) {
            panel = list[0]
        }
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

