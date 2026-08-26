import Foundation

public enum LaunchdJobState: Int, Codable, Sendable, CaseIterable {
    case failed
    case running
    case idle
    case unloaded

    public var sortRank: Int { rawValue }
}

public enum LaunchdJobCategory: Sendable, CaseIterable {
    case userAgent
    case application
    case appleSystem
}

public struct LaunchdJob: Identifiable, Equatable, Sendable {
    public let label: String
    public let pid: Int?
    public let lastExitCode: Int?
    public let isInstalledUserAgent: Bool
    public let state: LaunchdJobState

    public var id: String { label }

    public var category: LaunchdJobCategory {
        if isInstalledUserAgent { return .userAgent }
        if label.hasPrefix("com.apple.") || label.hasPrefix("application.com.apple.") {
            return .appleSystem
        }
        return .application
    }

    public init(
        label: String,
        pid: Int?,
        lastExitCode: Int?,
        isInstalledUserAgent: Bool,
        state: LaunchdJobState
    ) {
        self.label = label
        self.pid = pid
        self.lastExitCode = lastExitCode
        self.isInstalledUserAgent = isInstalledUserAgent
        self.state = state
    }
}

public struct LaunchdInstalledJobSummary: Equatable, Sendable {
    public let runningCount: Int
    public let failedCount: Int
    public let unloadedCount: Int
    public let idleCount: Int

    public init(runningCount: Int, failedCount: Int, unloadedCount: Int, idleCount: Int) {
        self.runningCount = runningCount
        self.failedCount = failedCount
        self.unloadedCount = unloadedCount
        self.idleCount = idleCount
    }
}

public struct LaunchdJobSnapshot: Equatable, Sendable {
    public let jobs: [LaunchdJob]

    public init(jobs: [LaunchdJob]) {
        self.jobs = jobs
    }

    public var installedJobs: [LaunchdJob] {
        jobs(in: .userAgent)
    }

    public func jobs(in category: LaunchdJobCategory) -> [LaunchdJob] {
        jobs.filter { $0.category == category }
    }

    public func count(in category: LaunchdJobCategory) -> Int {
        jobs.count { $0.category == category }
    }

    public var installedSummary: LaunchdInstalledJobSummary {
        var runningCount = 0
        var failedCount = 0
        var unloadedCount = 0
        var idleCount = 0
        for job in jobs where job.isInstalledUserAgent {
            switch job.state {
            case .running: runningCount += 1
            case .failed: failedCount += 1
            case .unloaded: unloadedCount += 1
            case .idle: idleCount += 1
            }
        }
        return LaunchdInstalledJobSummary(
            runningCount: runningCount,
            failedCount: failedCount,
            unloadedCount: unloadedCount,
            idleCount: idleCount
        )
    }
}

public enum LaunchdJobLogic {
    /// Parses the tab-separated output of `launchctl list` in one pass, then
    public static func snapshot(listOutput: String, installedLabels: Set<String>) -> LaunchdJobSnapshot {
        var jobsByLabel: [String: LaunchdJob] = [:]

        for line in listOutput.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }
            let pidText = String(columns[0])
            let exitText = String(columns[1])
            let label = columns.dropFirst(2).joined(separator: "\t")
            guard label != "Label", !label.isEmpty else { continue }

            let pid = Int(pidText)
            let lastExitCode = Int(exitText)
            let isInstalledUserAgent = installedLabels.contains(label)
            let state: LaunchdJobState
            if pid != nil {
                state = .running
            } else if isInstalledUserAgent, let lastExitCode, lastExitCode != 0 {
                state = .failed
            } else {
                state = .idle
            }
            jobsByLabel[label] = LaunchdJob(
                label: label,
                pid: pid,
                lastExitCode: lastExitCode,
                isInstalledUserAgent: isInstalledUserAgent,
                state: state
            )
        }

        for label in installedLabels where jobsByLabel[label] == nil {
            jobsByLabel[label] = LaunchdJob(
                label: label,
                pid: nil,
                lastExitCode: nil,
                isInstalledUserAgent: true,
                state: .unloaded
            )
        }

        let jobs = jobsByLabel.values.sorted {
            if $0.isInstalledUserAgent != $1.isInstalledUserAgent {
                return $0.isInstalledUserAgent && !$1.isInstalledUserAgent
            }
            if $0.state.sortRank != $1.state.sortRank {
                return $0.state.sortRank < $1.state.sortRank
            }
            return $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
        return LaunchdJobSnapshot(jobs: jobs)
    }
}
