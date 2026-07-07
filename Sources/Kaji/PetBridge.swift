import AppKit
import CoreGraphics
import Foundation

// MARK: - Pet bridge
//
// Kaji does not own a desktop-pet runtime. It publishes a small local state file
// so pet runtimes can map quota pressure to animation.

enum PetAnimationState: String, Codable {
    case idle
    case running
    case waiting
    case failed
    case review
}

struct PetProviderSignal: Codable, Equatable {
    let id: String
    let displayName: String
    let fiveHourPercent: Double?
    let sevenDayPercent: Double?
    let fiveHourResetsAt: Date?
    let sevenDayResetsAt: Date?
    let dataStatus: String
    let pressure: String
}

struct PetBridgeState: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let animationState: PetAnimationState
    let reason: String
    let summary: String
    let severity: Double
    let dominantProvider: String?
    let appContext: PetAppContext?
    let codexContext: PetCodexContext?
    let providers: [PetProviderSignal]
}

struct PetAppContext: Codable, Equatable {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
}

struct PetCodexContext: Codable, Equatable {
    let role: String
    let text: String
    let updatedAt: Date?
    let sourcePath: String?
}

enum PetBridge {
    static let schemaVersion = 1

    static var outputURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Kaji", isDirectory: true)
            .appendingPathComponent("pet-state.json")
    }

    static var replyURL: URL {
        outputURL.deletingLastPathComponent().appendingPathComponent("pet-replies.jsonl")
    }

    static var messageTemplateURL: URL {
        outputURL.deletingLastPathComponent().appendingPathComponent("pet-messages.json")
    }

    static func write(providers: [ProviderView],
                      lastError: String?,
                      generatedAt: Date = Date(),
                      appContext: PetAppContext? = currentAppContext(),
                      codexContext: PetCodexContext? = nil) {
        let state = makeState(providers: providers,
                              lastError: lastError,
                              generatedAt: generatedAt,
                              appContext: appContext,
                              codexContext: codexContext)
        do {
            let url = outputURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[Kaji] pet bridge write failed: %@", error.localizedDescription)
        }
    }

    static func makeState(providers: [ProviderView],
                          lastError: String?,
                          generatedAt: Date = Date(),
                          appContext: PetAppContext? = currentAppContext(),
                          codexContext: PetCodexContext? = nil) -> PetBridgeState {
        let signals = providers.map(signal)
        let dominant = providers.max { pressureScore($0) < pressureScore($1) }
        let severity = min(max(dominant.map(pressureScore) ?? 0, 0), 1)

        if let lastError, !lastError.isEmpty {
            return PetBridgeState(
                schemaVersion: schemaVersion,
                generatedAt: generatedAt,
                animationState: .failed,
                reason: lastError == Config.noPythonSentinel ? "python_missing" : "quota_refresh_failed",
                summary: lastError == Config.noPythonSentinel
                    ? "Kaji cannot find a working python3."
                    : "Kaji could not refresh quota data.",
                severity: max(severity, 0.75),
                dominantProvider: dominant?.id,
                appContext: appContext,
                codexContext: codexContext,
                providers: signals
            )
        }

        guard let dominant else {
            return PetBridgeState(
                schemaVersion: schemaVersion,
                generatedAt: generatedAt,
                animationState: .waiting,
                reason: "no_provider_data",
                summary: "Kaji has no readable provider quota data yet.",
                severity: 0.5,
                dominantProvider: nil,
                appContext: appContext,
                codexContext: codexContext,
                providers: signals
            )
        }

        let score = pressureScore(dominant)
        let rising = isRising(dominant)
        let state: PetAnimationState
        let reason: String
        let summary: String

        if score >= 0.95 {
            state = .waiting
            reason = "quota_limit"
            summary = "\(dominant.displayName) is at or near its quota limit."
        } else if score >= 0.80 {
            state = .review
            reason = "quota_pressure"
            summary = "\(dominant.displayName) quota is getting tight."
        } else if rising {
            state = .running
            reason = "quota_active"
            summary = "\(dominant.displayName) usage is moving."
        } else {
            state = .idle
            reason = "quota_healthy"
            summary = "Provider quota looks healthy."
        }

        return PetBridgeState(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            animationState: state,
            reason: reason,
            summary: summary,
            severity: score,
            dominantProvider: dominant.id,
            appContext: appContext,
            codexContext: codexContext,
            providers: signals
        )
    }

    private static func signal(_ provider: ProviderView) -> PetProviderSignal {
        PetProviderSignal(
            id: provider.id,
            displayName: provider.displayName,
            fiveHourPercent: provider.fiveHourPercent,
            sevenDayPercent: provider.weekPercent,
            fiveHourResetsAt: provider.resetDate,
            sevenDayResetsAt: provider.weekResetDate,
            dataStatus: hasAnyData(provider) ? "ok" : "missing",
            pressure: pressureLabel(provider)
        )
    }

    private static func pressureScore(_ provider: ProviderView) -> Double {
        let five = (provider.fiveHourPercent ?? 0) / 100
        let week = (provider.weekPercent ?? 0) / 100
        return max(five, week)
    }

    private static func pressureLabel(_ provider: ProviderView) -> String {
        let score = pressureScore(provider)
        if score >= 0.95 { return "limit" }
        if score >= 0.80 { return "warn" }
        if hasAnyData(provider) { return "healthy" }
        return "unknown"
    }

    private static func hasAnyData(_ provider: ProviderView) -> Bool {
        provider.fiveHourPercent != nil
            || provider.weekPercent != nil
            || provider.resetDate != nil
            || provider.weekResetDate != nil
    }

    private static func isRising(_ provider: ProviderView) -> Bool {
        if provider.tokenHistory.count >= 2,
           let last = provider.tokenHistory.last,
           let prev = provider.tokenHistory.dropLast().last {
            return last - prev >= 1_000
        }
        guard provider.history.count >= 2,
              let last = provider.history.last,
              let prev = provider.history.dropLast().last else { return false }
        return last - prev >= 0.5
    }

    private static func currentAppContext() -> PetAppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let title = frontmostWindowTitle(pid: app.processIdentifier)
        return PetAppContext(appName: app.localizedName,
                             bundleIdentifier: app.bundleIdentifier,
                             windowTitle: title)
    }

    private static func frontmostWindowTitle(pid: pid_t) -> String? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else { continue }
            if let title = window[kCGWindowName as String] as? String,
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
        }
        return nil
    }
}

enum CodexMessageProbe {
    static func latestVisibleMessage() -> PetCodexContext? {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let file = latestJSONLFile(under: root) else { return nil }
        guard let text = tailText(file, maxBytes: 512 * 1024) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).reversed()

        for line in lines {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "response_item",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "message",
                  let role = payload["role"] as? String,
                  role == "user" || role == "assistant",
                  let content = payload["content"] as? [[String: Any]],
                  let message = extractText(from: content),
                  !message.isEmpty else { continue }

            let updatedAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return PetCodexContext(role: role,
                                   text: compact(message, limit: 120),
                                   updatedAt: updatedAt,
                                   sourcePath: file.path)
        }
        return nil
    }

    private static func latestJSONLFile(under root: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return nil }
        var best: (url: URL, date: Date)?
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            if best == nil || date > best!.date {
                best = (url, date)
            }
        }
        return best?.url
    }

    private static func tailText(_ url: URL, maxBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(data: data, encoding: .utf8)
    }

    private static func extractText(from content: [[String: Any]]) -> String? {
        let chunks = content.compactMap { item -> String? in
            if let text = item["text"] as? String { return text }
            if let text = item["input_text"] as? String { return text }
            if let text = item["output_text"] as? String { return text }
            return nil
        }
        let text = chunks.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func compact(_ text: String, limit: Int) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard oneLine.count > limit else { return oneLine }
        return String(oneLine.prefix(limit - 1)) + "…"
    }
}
