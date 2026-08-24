import AppKit
import Foundation
import KajiCore

enum MailBriefState: Equatable {
    case disabled, disconnected, scheduled, running, ready, stale, failed
}

@MainActor
final class MailBriefStore: ObservableObject {
    @Published private(set) var state: MailBriefState = .disabled
    @Published private(set) var generation: MailBriefGeneration?
    @Published private(set) var lastError: String?
    @Published private(set) var nextDue: Date?
    @Published private(set) var syncProgress: (completed: Int, total: Int)?
    @Published private(set) var pendingThreadIDs: Set<String> = []
    @Published private(set) var runRecords: [MailBriefRunRecord] = []

    private let cacheURL: URL
    private let runHistoryURL: URL
    private var enabled = false
    private var timer: Timer?
    private var runTask: Task<Void, Never>?
    private var hour = 9
    private var minute = 0
    private var batchSize = 10
    private var concurrency = 2
    private var model = MailBriefModel.defaultValue

    init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? Self.defaultCacheURL()
        self.runHistoryURL = self.cacheURL.deletingLastPathComponent()
            .appendingPathComponent("mail-brief-runs-v1.json")
        loadCache()
        loadRunHistory()
    }

    var entries: [MailBriefEntry] { generation?.entries ?? [] }
    var dismissedEntries: [MailBriefEntry] {
        guard let generation else { return [] }
        return generation.entries.filter { generation.dismissedThreadIDs.contains($0.threadID) }
    }
    var archivedEntries: [MailBriefEntry] {
        guard let generation else { return [] }
        return generation.entries.filter { generation.archivedThreadIDs.contains($0.threadID) }
    }
    var trashedEntries: [MailBriefEntry] {
        guard let generation else { return [] }
        return generation.entries.filter { generation.trashedThreadIDs.contains($0.threadID) }
    }
    var sections: [MailBriefSection] {
        guard let generation else { return [] }
        return MailBriefPresentation.sections(entries: generation.entries, dismissedIDs: generation.dismissedThreadIDs,
                                              archivedIDs: generation.archivedThreadIDs,
                                              trashedIDs: generation.trashedThreadIDs)
    }
    var actCount: Int {
        guard let generation else { return 0 }
        return MailBriefPresentation.actCount(entries: generation.entries, dismissedIDs: generation.dismissedThreadIDs,
                                              archivedIDs: generation.archivedThreadIDs,
                                              trashedIDs: generation.trashedThreadIDs)
    }
    var isConnected: Bool { MailBriefCredentialStore.hasCredential }
    var accountLabel: String? { MailBriefCredentialStore.account }
    var canModify: Bool { MailBriefCredentialStore.canModify }

    func setEnabled(_ enabled: Bool, hour: Int, minute: Int, batchSize: Int, concurrency: Int,
                    model: MailBriefModel) {
        self.enabled = enabled; self.hour = hour; self.minute = minute
        self.batchSize = MailBriefBatchPolicy.batchSize(batchSize)
        self.concurrency = MailBriefBatchPolicy.concurrency(concurrency)
        self.model = model
        guard enabled else { stop(); state = .disabled; return }
        evaluateSchedule()
    }

    func evaluateSchedule(now: Date = Date()) {
        guard enabled else { return }
        guard isConnected else { timer?.invalidate(); state = .disconnected; return }
        let decision = MailBriefSchedulePolicy.decision(now: now, hour: hour, minute: minute,
                                                        calendar: .current,
                                                        lastAutomaticSuccess: generation?.isComplete == false ? nil : generation?.createdAt)
        nextDue = decision.nextDue
        if decision.isDue { generateNow(automatic: true); return }
        state = generation == nil ? .scheduled : .ready
        scheduleTimer(at: decision.nextDue)
    }

    func generateNow(automatic: Bool = false) {
        guard enabled, isConnected, runTask == nil else {
            if !isConnected { state = .disconnected }
            return
        }
        state = .running; lastError = nil
        let generationModel = model
        let runID = UUID()
        updateRun(MailBriefRunRecord(id: runID, trigger: automatic ? .automatic : .manual,
                                     modelID: generationModel.rawValue, batchSize: batchSize,
                                     concurrency: concurrency))
        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let clientID = Bundle.main.object(forInfoDictionaryKey: "KajiGoogleOAuthClientID") as? String,
                      let clientSecret = Bundle.main.object(forInfoDictionaryKey: "KajiGoogleOAuthClientSecret") as? String,
                      !clientID.isEmpty, !clientSecret.isEmpty else { throw MailBriefError.oauth("Google OAuth client is not configured") }
                let token = try await MailBriefCredentialStore.validAccessToken(clientID: clientID, clientSecret: clientSecret)
                updateRun(id: runID) { $0.stage = .fetching }
                let candidates = try await GmailMailBriefClient().fetchCandidates(accessToken: token)
                syncProgress = (0, candidates.count)
                let canReuse = generation?.classifierModelID == generationModel.rawValue
                let oldByID = Dictionary(uniqueKeysWithValues: (canReuse ? generation?.entries ?? [] : []).map { ($0.threadID, $0) })
                var entries: [MailBriefEntry] = []
                var changed: [MailBriefCandidate] = []
                for candidate in candidates {
                    if let old = oldByID[candidate.threadID], old.changedAt == candidate.changedAt,
                       old.isStarred == candidate.isStarred {
                        entries.append(old)
                    } else {
                        changed.append(candidate)
                    }
                }
                updateRun(id: runID) {
                    $0.stage = .classifying
                    $0.snapshotInboxCount = candidates.count
                    $0.newOrChangedCount = changed.count
                    $0.reusedCount = entries.count
                }
                syncProgress = (entries.count, candidates.count)
                let day = MailBriefSchedulePolicy.decision(now: Date(), hour: hour, minute: minute,
                                                           calendar: .current, lastAutomaticSuccess: nil).briefDay
                publishCheckpoint(day: day, inboxEntries: entries, inboxCount: candidates.count,
                                  model: generationModel)
                let batches = stride(from: 0, to: changed.count, by: batchSize).map {
                    Array(changed[$0..<min($0 + batchSize, changed.count)])
                }
                var nextBatch = 0
                try await withThrowingTaskGroup(of: [MailBriefEntry].self) { group in
                    func addNext() {
                        guard nextBatch < batches.count else { return }
                        let batch = batches[nextBatch]; nextBatch += 1
                        group.addTask { try await CodexMailBriefExecutor().summarize(batch, model: generationModel) }
                    }
                    for _ in 0..<min(concurrency, batches.count) { addNext() }
                    while let result = try await group.next() {
                        entries.append(contentsOf: result)
                        updateRun(id: runID) { $0.classifiedCount += result.count }
                        syncProgress = (entries.count, candidates.count)
                        publishCheckpoint(day: day, inboxEntries: entries, inboxCount: candidates.count,
                                          model: generationModel)
                        addNext()
                    }
                }
                guard !Task.isCancelled else { return }
                updateRun(id: runID) { $0.stage = .publishing }
                publishCheckpoint(day: day, inboxEntries: entries, inboxCount: candidates.count,
                                  model: generationModel, complete: true)
                try saveCache()
                updateRun(id: runID) {
                    $0.status = .succeeded; $0.stage = .finished; $0.finishedAt = Date()
                    $0.publishedCount = candidates.count
                }
                syncProgress = nil
                state = .ready
            } catch is CancellationError {
                finishRun(id: runID, status: .cancelled, errorCode: "cancelled")
                state = generation == nil ? .scheduled : .ready
            } catch {
                syncProgress = nil
                lastError = Self.safeError(error)
                finishRun(id: runID, status: .failed, errorCode: Self.safeErrorCode(error))
                state = generation == nil ? .failed : .stale
            }
            runTask = nil
            if automatic || generation != nil { evaluateSchedule() }
        }
    }

    func dismiss(_ entry: MailBriefEntry) {
        guard var value = generation else { return }
        value.dismissedThreadIDs.insert(entry.threadID); generation = value; try? saveCache()
    }

    func restore(_ entry: MailBriefEntry) {
        guard var value = generation else { return }
        value.dismissedThreadIDs.remove(entry.threadID); generation = value; try? saveCache()
    }

    func markConverted(_ entry: MailBriefEntry, goalID: UUID) {
        guard var value = generation else { return }
        value.convertedGoalIDs[entry.threadID] = goalID; generation = value; try? saveCache()
    }

    func isConverted(_ entry: MailBriefEntry) -> Bool {
        generation?.convertedGoalIDs[entry.threadID] != nil
    }

    func connect() {
        lastError = nil
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "KajiGoogleOAuthClientID") as? String,
              let clientSecret = Bundle.main.object(forInfoDictionaryKey: "KajiGoogleOAuthClientSecret") as? String,
              !clientID.isEmpty, !clientSecret.isEmpty else {
            lastError = "Google OAuth client is not configured"
            state = .failed
            return
        }
        Task { [weak self] in
            do {
                try await MailBriefOAuthFlow(clientID: clientID, clientSecret: clientSecret, requestsModify: false).connect()
                self?.evaluateSchedule()
            } catch {
                self?.lastError = Self.safeError(error)
                self?.state = .disconnected
            }
        }
    }

    func archive(_ entry: MailBriefEntry) { mutate(entry, .archive) }
    func unarchive(_ entry: MailBriefEntry) { mutate(entry, .unarchive) }
    func toggleStar(_ entry: MailBriefEntry) { mutate(entry, (entry.isStarred ?? false) ? .unstar : .star) }
    func trash(_ entry: MailBriefEntry) { mutate(entry, .trash) }
    func untrash(_ entry: MailBriefEntry) { mutate(entry, .untrash) }

    private func mutate(_ entry: MailBriefEntry, _ mutation: GmailThreadMutation) {
        guard !pendingThreadIDs.contains(entry.threadID) else { return }
        pendingThreadIDs.insert(entry.threadID); lastError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { pendingThreadIDs.remove(entry.threadID) }
            do {
                guard let clientID = Bundle.main.object(forInfoDictionaryKey: "KajiGoogleOAuthClientID") as? String,
                      let clientSecret = Bundle.main.object(forInfoDictionaryKey: "KajiGoogleOAuthClientSecret") as? String,
                      !clientID.isEmpty, !clientSecret.isEmpty else {
                    throw MailBriefError.oauth("Google OAuth client is not configured")
                }
                if !MailBriefCredentialStore.canModify {
                    try await MailBriefOAuthFlow(clientID: clientID, clientSecret: clientSecret,
                                                 requestsModify: true).connect()
                }
                let token = try await MailBriefCredentialStore.validAccessToken(clientID: clientID,
                                                                                 clientSecret: clientSecret)
                try await GmailMailBriefClient().mutate(threadID: entry.threadID, mutation: mutation,
                                                        accessToken: token)
                guard var value = generation else { return }
                switch mutation {
                case .archive:
                    value.archivedThreadIDs.insert(entry.threadID); value.snapshotInboxThreadCount -= 1
                case .unarchive:
                    value.archivedThreadIDs.remove(entry.threadID); value.snapshotInboxThreadCount += 1
                case .trash:
                    value.trashedThreadIDs.insert(entry.threadID); value.snapshotInboxThreadCount -= 1
                case .untrash:
                    value.trashedThreadIDs.remove(entry.threadID); value.snapshotInboxThreadCount += 1
                case .star, .unstar:
                    if let index = value.entries.firstIndex(where: { $0.threadID == entry.threadID }) {
                        value.entries[index].isStarred = mutation == .star
                    }
                }
                generation = value; try saveCache()
            } catch {
                lastError = Self.safeError(error)
            }
        }
    }

    func disconnect(deleteBrief: Bool = false) {
        MailBriefCredentialStore.delete(); timer?.invalidate(); cancelActiveRun(); runTask?.cancel(); runTask = nil
        if deleteBrief {
            generation = nil; runRecords = []
            try? FileManager.default.removeItem(at: cacheURL)
            try? FileManager.default.removeItem(at: runHistoryURL)
        }
        state = enabled ? .disconnected : .disabled
    }

    func stop() {
        timer?.invalidate(); timer = nil; cancelActiveRun(); runTask?.cancel(); runTask = nil
    }

    private func scheduleTimer(at date: Date) {
        timer?.invalidate()
        timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.evaluateSchedule() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let value = try? JSONDecoder.mailBrief.decode(MailBriefGeneration.self, from: data),
              value.schemaVersion == MailBriefGeneration.currentSchemaVersion else { return }
        generation = value
    }

    private func saveCache() throws {
        guard let generation else { return }
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.mailBrief.encode(generation).write(to: cacheURL, options: .atomic)
    }

    private func loadRunHistory() {
        guard let data = try? Data(contentsOf: runHistoryURL),
              let stored = try? JSONDecoder.mailBrief.decode([MailBriefRunRecord].self, from: data) else { return }
        runRecords = MailBriefRunHistory.normalized(stored)
        try? saveRunHistory()
    }

    private func saveRunHistory() throws {
        try FileManager.default.createDirectory(at: runHistoryURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder.mailBrief.encode(runRecords).write(to: runHistoryURL, options: .atomic)
    }

    private func updateRun(_ record: MailBriefRunRecord) {
        runRecords = MailBriefRunHistory.upserting(record, into: runRecords)
        try? saveRunHistory()
    }

    private func updateRun(id: UUID, mutate: (inout MailBriefRunRecord) -> Void) {
        guard var record = runRecords.first(where: { $0.id == id }), record.status == .running else { return }
        mutate(&record); updateRun(record)
    }

    private func finishRun(id: UUID, status: MailBriefRunStatus, errorCode: String?) {
        updateRun(id: id) {
            $0.status = status; $0.stage = .finished; $0.finishedAt = Date(); $0.safeErrorCode = errorCode
        }
    }

    private func cancelActiveRun() {
        guard let active = runRecords.first(where: { $0.status == .running }) else { return }
        finishRun(id: active.id, status: .cancelled, errorCode: "cancelled")
    }

    private func publishCheckpoint(day: String, inboxEntries: [MailBriefEntry], inboxCount: Int,
                                   model: MailBriefModel, complete: Bool = false) {
        let inboxIDs = Set(inboxEntries.map(\.threadID))
        let sameDay = generation?.briefDay == day
        let archivedIDs = sameDay ? (generation?.archivedThreadIDs ?? []).subtracting(inboxIDs) : []
        let trashedIDs = sameDay ? (generation?.trashedThreadIDs ?? []).subtracting(inboxIDs) : []
        let retainedIDs = archivedIDs.union(trashedIDs).subtracting(inboxIDs)
        let retainedEntries = sameDay ? (generation?.entries ?? []).filter { retainedIDs.contains($0.threadID) } : []
        generation = MailBriefGeneration(briefDay: day, entries: inboxEntries + retainedEntries,
            dismissedThreadIDs: (generation?.dismissedThreadIDs ?? []).intersection(inboxIDs),
            convertedGoalIDs: (generation?.convertedGoalIDs ?? [:]).filter { inboxIDs.contains($0.key) },
            archivedThreadIDs: archivedIDs, trashedThreadIDs: trashedIDs,
            snapshotInboxThreadCount: inboxCount, isComplete: complete,
            classifierModelID: model.rawValue)
        try? saveCache()
    }

    private static func defaultCacheURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Kaji", isDirectory: true).appendingPathComponent("mail-brief-cache-v1.json")
    }
    private static func safeError(_ error: Error) -> String {
        if let value = error as? MailBriefError { return value.errorDescription }
        return "Mail Brief failed"
    }
    private static func safeErrorCode(_ error: Error) -> String {
        guard let value = error as? MailBriefError else { return "unknown" }
        return switch value {
        case .notConnected, .oauth: "oauth"
        case .invalidResponse: "gmail_invalid_response"
        case .executorUnavailable: "codex_unavailable"
        case .invalidOutput: "invalid_result"
        }
    }
}

enum MailBriefError: Error {
    case notConnected, invalidResponse, executorUnavailable, invalidOutput, oauth(String)
    var errorDescription: String {
        switch self {
        case .notConnected: "Connect Gmail first"
        case .invalidResponse: "Gmail returned an invalid response"
        case .executorUnavailable: "Codex is unavailable or not signed in"
        case .invalidOutput: "Codex returned an invalid brief"
        case .oauth(let value): value
        }
    }
}

private extension JSONEncoder {
    static var mailBrief: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
}
private extension JSONDecoder {
    static var mailBrief: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}
