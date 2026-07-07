import Foundation
import Darwin

struct ProcessSnapshot: Identifiable, Equatable, Sendable {
    let pid: Int
    let cpu: Double
    let memory: Double
    let command: String

    var id: Int { pid }
}

struct SystemSnapshot: Equatable, Sendable {
    let cpuPercent: Double
    let memoryPercent: Double
    let diskPercent: Double
    let processCount: Int
    let topProcesses: [ProcessSnapshot]
    let sampledAt: Date
    let hasSample: Bool
}

struct CleanableItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let path: String
    let bytes: Int64

    var isEmpty: Bool { bytes <= 0 }
}

struct OrphanProcessSnapshot: Identifiable, Equatable, Sendable {
    let pid: Int
    let ageSeconds: Int
    let command: String

    var id: Int { pid }
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot(cpuPercent: 0,
                                                          memoryPercent: 0,
                                                          diskPercent: 0,
                                                          processCount: 0,
                                                          topProcesses: [],
                                                          sampledAt: Date(),
                                                          hasSample: false)
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastCleanedBytes: Int64 = 0
    @Published private(set) var cleanableItems: [CleanableItem] = []
    @Published private(set) var selectedCleanableIds: Set<String> = []
    @Published private(set) var isScanningCleanables = false
    @Published private(set) var isAutoCleaning = false
    @Published private(set) var isReclaimingMemory = false
    @Published private(set) var lastAutoCleanedBytes: Int64 = 0
    @Published private(set) var lastMemoryReclaimAt: Date?
    @Published private(set) var orphanProcesses: [OrphanProcessSnapshot] = []
    @Published private(set) var lastOrphanCleanedCount = 0

    private var timer: Timer?
    private var scanTimer: Timer?
    private var lastAutoMaintenanceAt: Date?

    private enum AutoClean {
        static let memoryPercent = 75.0
        static let diskPercent = 85.0
        static let cleanableBytes: Int64 = 512 * 1024 * 1024
        static let cooldown: TimeInterval = 30 * 60
    }

    deinit {
        timer?.invalidate()
        scanTimer?.invalidate()
    }

    func start() {
        refresh()
        scanCleanables()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        scanTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanCleanables()
            }
        }
    }

    func refresh() {
        if isRefreshing { return }
        isRefreshing = true
        lastError = nil
        Task {
            let result = await Task.detached(priority: .utility) {
                Self.readProcessSnapshot()
            }.value
            await MainActor.run {
                self.isRefreshing = false
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.refreshOrphans()
                case .failure:
                    self.lastError = "system_monitor_failed"
                }
            }
        }
    }

    var cleanableBytes: Int64 {
        cleanableItems.reduce(0) { $0 + $1.bytes }
    }

    var selectedCleanableBytes: Int64 {
        cleanableItems
            .filter { selectedCleanableIds.contains($0.id) }
            .reduce(0) { $0 + $1.bytes }
    }

    func scanCleanables() {
        if isScanningCleanables { return }
        isScanningCleanables = true
        Task {
            let items = await Task.detached(priority: .utility) {
                Self.scanKajiCleanables()
            }.value
            await MainActor.run {
                self.cleanableItems = items
                self.selectedCleanableIds = Set(items.filter { !$0.isEmpty }.map(\.id))
                self.isScanningCleanables = false
            }
        }
    }

    func toggleCleanable(_ item: CleanableItem) {
        guard !item.isEmpty else { return }
        if selectedCleanableIds.contains(item.id) {
            selectedCleanableIds.remove(item.id)
        } else {
            selectedCleanableIds.insert(item.id)
        }
    }

    func cleanKajiArtifacts() {
        let selected = selectedCleanableIds
        Task {
            let bytes = await Task.detached(priority: .utility) {
                Self.cleanKajiArtifacts(selectedIds: selected)
            }.value
            await MainActor.run {
                self.lastCleanedBytes = bytes
                self.scanCleanables()
            }
        }
    }

    func refreshOrphans() {
        Task {
            let orphans = await Task.detached(priority: .utility) {
                Self.readOrphans()
            }.value
            await MainActor.run {
                self.orphanProcesses = orphans
            }
        }
    }

    func cleanOrphans() {
        let pids = orphanProcesses.map(\.pid)
        guard !pids.isEmpty else { return }
        Task {
            let killed = await Task.detached(priority: .utility) {
                Self.terminate(pids: pids)
            }.value
            await MainActor.run {
                self.lastOrphanCleanedCount = killed
                self.refreshOrphans()
            }
        }
    }

    func runAutoMaintenanceIfNeeded() {
        guard !isAutoCleaning, !isReclaimingMemory, snapshot.hasSample else { return }
        if let lastAutoMaintenanceAt,
           Date().timeIntervalSince(lastAutoMaintenanceAt) < AutoClean.cooldown {
            return
        }
        let shouldReclaimMemory = snapshot.memoryPercent >= AutoClean.memoryPercent
        let shouldCleanDisk = snapshot.diskPercent >= AutoClean.diskPercent || selectedCleanableBytes >= AutoClean.cleanableBytes
        let shouldCleanOrphans = !orphanProcesses.isEmpty
        guard shouldReclaimMemory || shouldCleanDisk || shouldCleanOrphans else { return }
        if shouldCleanDisk && selectedCleanableIds.isEmpty {
            if !isScanningCleanables { scanCleanables() }
            if !shouldReclaimMemory { return }
        }
        lastAutoMaintenanceAt = Date()
        if shouldReclaimMemory {
            reclaimMemory()
        }
        if shouldCleanDisk {
            autoCleanDisk()
        } else if cleanableItems.isEmpty && !isScanningCleanables {
            scanCleanables()
        }
        if shouldCleanOrphans {
            cleanOrphans()
        }
    }

    private func autoCleanDisk() {
        let selected = selectedCleanableIds
        guard !selected.isEmpty else {
            scanCleanables()
            return
        }
        isAutoCleaning = true
        Task {
            let bytes = await Task.detached(priority: .utility) {
                Self.cleanKajiArtifacts(selectedIds: selected)
            }.value
            await MainActor.run {
                self.lastAutoCleanedBytes = bytes
                self.isAutoCleaning = false
                self.scanCleanables()
            }
        }
    }

    func reclaimMemory() {
        if isReclaimingMemory { return }
        isReclaimingMemory = true
        Task {
            _ = await Task.detached(priority: .utility) {
                Self.runPurge()
            }.value
            await MainActor.run {
                self.lastMemoryReclaimAt = Date()
                self.isReclaimingMemory = false
                self.refresh()
            }
        }
    }

    nonisolated private static func readProcessSnapshot() -> Result<SystemSnapshot, Error> {
        do {
            let out = try run("/bin/ps", ["-axo", "pid=,pcpu=,pmem=,comm="])
            let processes = parsePS(out)
            let coreCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
            let totalCPU = min(processes.reduce(0) { $0 + $1.cpu } / Double(coreCount), 100)
            let top = Array(processes.sorted { $0.cpu > $1.cpu }.prefix(5))
            return .success(SystemSnapshot(cpuPercent: totalCPU,
                                           memoryPercent: readMemoryPercent(),
                                           diskPercent: readDiskPercent(),
                                           processCount: processes.count,
                                           topProcesses: top,
                                           sampledAt: Date(),
                                           hasSample: true))
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func parsePS(_ output: String) -> [ProcessSnapshot] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let parts = line.split(maxSplits: 3, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let cpu = Double(parts[1]),
                  let memory = Double(parts[2]) else {
                return nil
            }
            let command = URL(fileURLWithPath: parts[3]).lastPathComponent
            return ProcessSnapshot(pid: pid, cpu: cpu, memory: memory, command: command)
        }
    }

    nonisolated private static func readMemoryPercent() -> Double {
        guard let out = try? run("/usr/bin/vm_stat", []) else { return 0 }
        var pageSize = 4096.0
        var pages: [String: Double] = [:]
        for raw in out.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.contains("page size of") {
                let digits = line.filter { $0.isNumber }
                if let parsed = Double(digits), parsed > 0 { pageSize = parsed }
                continue
            }
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1].filter { $0.isNumber }
            if let count = Double(value) {
                pages[key] = count
            }
        }
        let active = pages["Pages active"] ?? 0
        let wired = pages["Pages wired down"] ?? 0
        let compressed = pages["Pages occupied by compressor"] ?? 0
        let inactive = pages["Pages inactive"] ?? 0
        let speculative = pages["Pages speculative"] ?? 0
        let free = pages["Pages free"] ?? 0
        let used = active + wired + compressed
        let total = used + inactive + speculative + free
        _ = pageSize
        guard total > 0 else { return 0 }
        return min(max((used / total) * 100, 0), 100)
    }

    nonisolated private static func readDiskPercent() -> Double {
        guard let out = try? run("/bin/df", ["-k", "/"]) else { return 0 }
        let lines = out.split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else { return 0 }
        let parts = lines[1].split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 5 else { return 0 }
        let raw = parts[4].replacingOccurrences(of: "%", with: "")
        return Double(raw) ?? 0
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "Kaji.SystemMonitor", code: Int(process.terminationStatus))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    nonisolated private static func runPurge() -> Bool {
        let path = "/usr/bin/purge"
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated private static func readOrphans() -> [OrphanProcessSnapshot] {
        guard let out = try? run("/bin/ps", ["-axo", "pid=,ppid=,etimes=,stat=,comm=,args="]) else {
            return []
        }
        return out.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let parts = line.split(maxSplits: 5, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 6,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  let age = Int(parts[2]),
                  ppid == 1,
                  age >= 60,
                  !parts[3].contains("Z") else {
                return nil
            }
            let command = URL(fileURLWithPath: parts[4]).lastPathComponent
            let args = parts[5]
            guard isSafeOrphan(command: command, args: args) else {
                return nil
            }
            return OrphanProcessSnapshot(pid: pid, ageSeconds: age, command: command)
        }
    }

    nonisolated private static func isSafeOrphan(command: String, args: String) -> Bool {
        if command == "Python" || command == "python3" {
            return args.contains("Kaji.app/Contents/Resources/quota.py")
        }
        if command == "pethatch" {
            return args.contains("--state-file") && args.contains("kaji")
        }
        return false
    }

    nonisolated private static func terminate(pids: [Int]) -> Int {
        var killed = 0
        for pid in pids {
            if kill(pid_t(pid), SIGTERM) == 0 {
                killed += 1
            }
        }
        return killed
    }

    nonisolated private static func scanKajiCleanables() -> [CleanableItem] {
        cleanableURLs().map { title, url in
            CleanableItem(id: url.path,
                          title: title,
                          path: url.path,
                          bytes: sizeOfItem(at: url))
        }
    }

    nonisolated private static func cleanKajiArtifacts(selectedIds: Set<String>) -> Int64 {
        cleanableURLs().filter { selectedIds.contains($0.url.path) }.reduce(Int64(0)) { total, entry in
            total + removeItemIfPresent(entry.url)
        }
    }

    nonisolated private static func cleanableURLs() -> [(title: String, url: URL)] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return [
            ("Pet log", URL(fileURLWithPath: "/tmp/kaji-pethatch.log")),
            ("Kaji cache", home.appendingPathComponent("Library/Caches/Kaji", isDirectory: true)),
            ("Kaji cache", home.appendingPathComponent("Library/Caches/dev.kaji", isDirectory: true)),
            ("Kaji logs", home.appendingPathComponent("Library/Logs/Kaji", isDirectory: true)),
            ("Xcode DerivedData", home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)),
            ("SwiftPM cache", home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)),
            ("SwiftPM security", home.appendingPathComponent("Library/org.swift.swiftpm/security", isDirectory: true)),
        ]
    }

    nonisolated private static func sizeOfItem(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return ((try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
        }
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    nonisolated private static func removeItemIfPresent(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        let size = sizeOfItem(at: url)
        do {
            try fm.removeItem(at: url)
            return size
        } catch {
            return 0
        }
    }
}
