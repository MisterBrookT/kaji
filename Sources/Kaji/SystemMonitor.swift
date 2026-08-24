import Foundation
import KajiCore

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
    let isAutoSafe: Bool

    var isEmpty: Bool { bytes <= 0 }
}

struct DiskDirectoryUsage: Identifiable, Codable, Equatable, Sendable {
    let title: String
    let path: String
    let bytes: Int64
    var id: String { path }
}

struct DiskInsightSnapshot: Codable, Equatable, Sendable {
    let totalBytes: Int64
    let availableBytes: Int64
    let directories: [DiskDirectoryUsage]
    let categoryBytes: [String: Int64]
    let restrictedCount: Int
    let scannedAt: Date

    static let empty = DiskInsightSnapshot(totalBytes: 0, availableBytes: 0,
                                           directories: [],
                                           categoryBytes: [:],
                                           restrictedCount: 0, scannedAt: .distantPast)

    func bytes(for category: DiskFileCategory) -> Int64 {
        max(0, categoryBytes[category.rawValue] ?? 0)
    }
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
    @Published private(set) var isCleaning = false
    @Published private(set) var cleanableItems: [CleanableItem] = []
    @Published private(set) var selectedCleanableIds: Set<String> = []
    @Published private(set) var isScanningCleanables = false
    @Published private(set) var isAutoCleaning = false
    @Published private(set) var isReclaimingMemory = false
    @Published private(set) var lastAutoCleanedBytes: Int64 = 0
    @Published private(set) var lastMemoryReclaimAt: Date?
    @Published private(set) var orphanProcesses: [OrphanProcessSnapshot] = []
    @Published private(set) var lastOrphanCleanedCount = 0
    @Published private(set) var diskInsights = DiskInsightSnapshot.empty
    @Published private(set) var isScanningDisk = false
    @Published private(set) var diskScanError: String?

    nonisolated(unsafe) private var timer: Timer?
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastAutoMaintenanceAt: Date?
    private var hasInitializedCleanableSelection = false

    private enum AutoClean {
        static let memoryPercent = 75.0
        static let diskPercent = 85.0
        static let cleanableBytes: Int64 = 512 * 1024 * 1024
        static let cooldown: TimeInterval = 30 * 60
    }

    private enum Key {
        static let diskInsights = "diskInsightSnapshotV2"
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Key.diskInsights),
           let cached = try? JSONDecoder().decode(DiskInsightSnapshot.self, from: data) {
            diskInsights = cached
        }
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        scanDiskInsights()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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

    private var autoCleanableBytes: Int64 {
        cleanableItems
            .filter(\.isAutoSafe)
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
                let availableIds = Set(items.filter { !$0.isEmpty }.map(\.id))
                if self.hasInitializedCleanableSelection {
                    self.selectedCleanableIds.formIntersection(availableIds)
                } else {
                    self.selectedCleanableIds = Set(items.filter { $0.isAutoSafe && !$0.isEmpty }.map(\.id))
                    self.hasInitializedCleanableSelection = true
                }
                self.isScanningCleanables = false
            }
        }
    }

    func scanDiskInsights(force: Bool = false) {
        guard !isScanningDisk else { return }
        guard DiskInsightScanPolicy.shouldScan(
            lastSuccessfulAt: diskInsights.scannedAt == .distantPast ? nil : diskInsights.scannedAt,
            now: now(),
            force: force
        ) else { return }
        isScanningDisk = true
        diskScanError = nil
        Task {
            let result = await Task.detached(priority: .utility) {
                Self.readDiskInsights()
            }.value
            await MainActor.run {
                self.isScanningDisk = false
                switch result {
                case .success(let insights):
                    self.diskInsights = insights
                    self.defaults.set(try? JSONEncoder().encode(insights), forKey: Key.diskInsights)
                case .failure:
                    self.diskScanError = "无法完成磁盘扫描"
                }
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
        scanDiskInsights()
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
        refreshOrphans()
    }

    func runAutoMaintenanceIfNeeded() {
        scanDiskInsights()
    }

    private func autoCleanDisk() {
        scanDiskInsights()
    }

    func reclaimMemory() {
        refresh()
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
        return false
    }

    nonisolated private static func scanKajiCleanables() -> [CleanableItem] {
        cleanableURLs().map { title, url, isAutoSafe in
            CleanableItem(id: url.path,
                          title: title,
                          path: url.path,
                          bytes: sizeOfItem(at: url),
                          isAutoSafe: isAutoSafe)
        }
    }

    nonisolated private static func readDiskInsights() -> Result<DiskInsightSnapshot, Error> {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        do {
            let volume = try URL(fileURLWithPath: "/").resourceValues(
                forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
            )
            let roots: [(String, String)] = [
                ("Downloads", "Downloads"), ("Documents", "Documents"),
                ("Desktop", "Desktop"), ("Movies", "Movies"),
                ("Pictures", "Pictures"), ("Music", "Music"),
                ("Caches", "Library/Caches"),
                ("Developer", "Library/Developer"),
                ("Applications", "Applications"),
            ]
            var restricted = 0
            var directories: [DiskDirectoryUsage] = []
            var categoryTotals: [DiskFileCategory: Int64] = [:]
            for (title, relativePath) in roots {
                let url = home.appendingPathComponent(relativePath, isDirectory: true)
                guard fm.isReadableFile(atPath: url.path) else {
                    if fm.fileExists(atPath: url.path) { restricted += 1 }
                    continue
                }
                var directoryBytes: Int64 = 0
                let keys: Set<URLResourceKey> = [.fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
                if let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: Array(keys),
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for case let fileURL as URL in enumerator {
                        let values = try? fileURL.resourceValues(forKeys: keys)
                        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
                        let size = Int64(values?.fileAllocatedSize ?? values?.fileSize ?? 0)
                        directoryBytes += size
                        let category = DiskFileCategoryLogic.category(
                            path: fileURL.path,
                            pathExtension: fileURL.pathExtension
                        )
                        categoryTotals[category, default: 0] += size
                    }
                }
                directories.append(DiskDirectoryUsage(title: title, path: url.path, bytes: directoryBytes))
            }
            return .success(DiskInsightSnapshot(
                totalBytes: Int64(volume.volumeTotalCapacity ?? 0),
                availableBytes: volume.volumeAvailableCapacityForImportantUsage ?? 0,
                directories: directories.sorted { $0.bytes > $1.bytes },
                categoryBytes: Dictionary(uniqueKeysWithValues:
                    DiskFileCategoryLogic.normalizedTotals(categoryTotals).map { ($0.key.rawValue, $0.value) }
                ),
                restrictedCount: restricted,
                scannedAt: Date()
            ))
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func cleanableURLs() -> [(title: String, url: URL, isAutoSafe: Bool)] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return [
            ("Kaji cache", home.appendingPathComponent("Library/Caches/Kaji", isDirectory: true), true),
            ("Kaji cache", home.appendingPathComponent("Library/Caches/dev.kaji", isDirectory: true), true),
            ("Kaji logs", home.appendingPathComponent("Library/Logs/Kaji", isDirectory: true), true),
            ("Xcode DerivedData", home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true), false),
            ("SwiftPM cache", home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true), false),
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
                                             options: []) else {
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

}
