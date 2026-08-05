import Foundation
import Combine
import KajiCore

enum AIHotNewsState: Equatable { case idle, loading, ready, stale, empty, failed }

@MainActor
final class AIHotNewsStore: ObservableObject {
    @Published private(set) var topics: [AIHotTopic] = []
    @Published private(set) var state: AIHotNewsState = .idle
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var hoveredStoryByID: [String: AIHotStory] = [:]
    @Published private(set) var readTopicIDs: Set<String> = []

    private let client: AIHotAPIClient
    private let cacheURL: URL
    private var cache = AIHotCache()
    private var refreshTask: Task<Void, Never>?
    private var storyTasks: [String: Task<Void, Never>] = [:]
    private var timer: Timer?
    private var enabled = false
    private var refreshHours = AIHotRefreshPolicy.defaultHours
    private var freshnessFloorUntil: Date?

    init(client: AIHotAPIClient = AIHotAPIClient(), cacheURL: URL? = nil) {
        self.client = client
        self.cacheURL = cacheURL ?? Self.defaultCacheURL()
    }

    func setEnabled(_ enabled: Bool, refreshHours: Int) {
        self.refreshHours = AIHotRefreshPolicy.normalize(hours: refreshHours)
        guard enabled else { stop(); return }
        if !self.enabled { loadCache() }
        self.enabled = true
        scheduleOrRefresh()
    }

    func updateRefreshHours(_ hours: Int) {
        refreshHours = AIHotRefreshPolicy.normalize(hours: hours)
        guard enabled else { return }
        timer?.invalidate(); timer = nil
        scheduleOrRefresh()
    }

    func refresh(force: Bool = false) {
        guard enabled, refreshTask == nil else { return }
        let now = Date()
        if let floor = freshnessFloorUntil, floor > now { schedule(at: floor); return }
        if !force && !AIHotRefreshPolicy.shouldRefresh(hasCache: !topics.isEmpty,
                                                       lastSuccessfulRefresh: lastSuccessfulRefresh,
                                                       hours: refreshHours, now: now) { scheduleDue(); return }
        state = topics.isEmpty ? .loading : .ready
        refreshTask = Task { [weak self] in await self?.performRefresh(attempt: 0) }
    }

    func loadStory(for topic: AIHotTopic) {
        guard enabled, let id = topic.storyPublicID, storyTasks[id] == nil else { return }
        if let entry = cache.stories[id], entry.lastAccessedAt >= Date().addingTimeInterval(-30 * 86400) {
            hoveredStoryByID[id] = entry.story
            return
        }
        storyTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { self.storyTasks[id] = nil }
            do {
                let response = try await self.client.story(publicID: id, etag: self.cache.stories[id]?.etag)
                guard !Task.isCancelled else { return }
                if let story = response.value {
                    self.hoveredStoryByID[id] = story
                    self.cache.stories[id] = .init(story: story, etag: response.etag, lastAccessedAt: Date())
                    self.saveCache()
                }
            } catch { }
        }
    }

    func markRead(_ topic: AIHotTopic) {
        readTopicIDs.insert(topic.id)
        cache.readEntries.removeAll { $0.topicID == topic.id }
        cache.readEntries.append(.init(topicID: topic.id, lastSeenAt: Date()))
        saveCache()
    }

    func stop() {
        enabled = false; timer?.invalidate(); timer = nil
        refreshTask?.cancel(); refreshTask = nil
        storyTasks.values.forEach { $0.cancel() }; storyTasks.removeAll()
        state = .idle
    }

    private func performRefresh(attempt: Int) async {
        do {
            let response = try await client.hotTopics(etag: cache.topicsETag)
            guard enabled, !Task.isCancelled else { return }
            if response.statusCode == 200, let newTopics = response.value {
                topics = newTopics; cache.topics = newTopics; cache.topicsETag = response.etag
            } else if response.statusCode == 304 {
                cache.topicsETag = response.etag ?? cache.topicsETag
            } else if response.statusCode != 304 {
                if let delay = AIHotRefreshPolicy.retryDelay(statusCode: response.statusCode,
                                                             retryAfter: response.retryAfter, attempt: attempt) {
                    refreshTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled else { return }
                        await self?.performRefresh(attempt: attempt + 1)
                    }
                    return
                }
                throw URLError(.badServerResponse)
            }
            let now = Date(); lastSuccessfulRefresh = now; cache.lastSuccessfulRefresh = now
            lastError = nil; state = topics.isEmpty ? .empty : .ready
            freshnessFloorUntil = now.addingTimeInterval(Self.freshnessFloor(response.cacheControl))
            refreshTask = nil; saveCache(); scheduleDue()
        } catch {
            guard enabled, !Task.isCancelled else { return }
            if attempt == 0, let delay = AIHotRefreshPolicy.retryDelay(statusCode: 0, retryAfter: nil, attempt: 0) {
                refreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    await self?.performRefresh(attempt: 1)
                }
                return
            }
            lastError = "AI HOT unavailable"; state = topics.isEmpty ? .failed : .stale
            refreshTask = nil; scheduleDue()
        }
    }

    private func scheduleOrRefresh() {
        if AIHotRefreshPolicy.shouldRefresh(hasCache: !topics.isEmpty, lastSuccessfulRefresh: lastSuccessfulRefresh,
                                            hours: refreshHours, now: Date()) { refresh() } else { scheduleDue() }
    }
    private func scheduleDue() {
        let due = AIHotRefreshPolicy.dueDate(lastSuccessfulRefresh: lastSuccessfulRefresh, hours: refreshHours, now: Date())
        schedule(at: max(due, freshnessFloorUntil ?? .distantPast))
    }
    private func schedule(at date: Date) {
        timer?.invalidate()
        timer = Timer(fireAt: date, interval: 0, target: BlockTarget { [weak self] in self?.refresh(force: true) }, selector: #selector(BlockTarget.fire), userInfo: nil, repeats: false)
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        do {
            let loaded = try JSONDecoder().decode(AIHotCache.self, from: Data(contentsOf: cacheURL))
            guard loaded.schemaVersion == AIHotCache.currentSchemaVersion else { throw CocoaError(.fileReadCorruptFile) }
            cache = loaded; cache.prune(now: Date()); topics = cache.topics
            lastSuccessfulRefresh = cache.lastSuccessfulRefresh
            readTopicIDs = Set(cache.readEntries.map(\.topicID)); state = topics.isEmpty ? .idle : .ready
        } catch {
            let diagnostic = cacheURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: cacheURL, to: diagnostic)
            lastError = "Cache unreadable"
        }
    }
    private func saveCache() {
        cache.prune(now: Date())
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
        } catch { lastError = "Cache write failed" }
    }
    private static func defaultCacheURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Kaji", isDirectory: true).appendingPathComponent("ai-news-cache-v1.json")
    }
    private static func freshnessFloor(_ cacheControl: String?) -> TimeInterval {
        guard let cacheControl,
              let match = cacheControl.range(of: #"(?:s-maxage|max-age)=(\d+)"#, options: .regularExpression),
              let value = TimeInterval(cacheControl[match].split(separator: "=").last ?? "") else {
            return AIHotRefreshPolicy.serverFreshnessFloor
        }
        return max(AIHotRefreshPolicy.serverFreshnessFloor, value)
    }
}

private final class BlockTarget: NSObject {
    private let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func fire() { block() }
}
