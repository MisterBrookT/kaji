import Combine
import Foundation
import KajiCore

@MainActor
final class ExposureStudyStore: ObservableObject {
    typealias Clock = () -> Date

    private(set) var record: ExposureStudyRecord

    /// Emits ONLY when the experiment phase actually changes (progression,
    /// completion, rollback), never on aggregate writes, so recording an
    /// event cannot rebuild product surfaces as a side effect.
    let didChangePhase: AnyPublisher<ExposureExperimentPhase, Never>

    private let fileURL: URL
    private let clock: Clock
    private var phaseTimer: Timer?
    private let didChangePhaseSubject = PassthroughSubject<ExposureExperimentPhase, Never>()
    private var lastReportedPhase: ExposureExperimentPhase = .notStarted

    init(fileURL: URL? = nil, clock: @escaping Clock = Date.init) {
        self.clock = clock
        self.fileURL = fileURL ?? Self.defaultFileURL()
        record = Self.load(from: self.fileURL) ?? ExposureStudyRecord()
        didChangePhase = didChangePhaseSubject.eraseToAnyPublisher()
    }

    var phase: ExposureExperimentPhase {
        ExposureExperimentLogic.phase(state: record.experiment, now: clock())
    }

    func startIfNeeded() {
        if record.experiment.startedAt == nil {
            ExposureExperimentLogic.start(state: &record.experiment, now: clock())
            persist()
        }
        startPhaseTimer()
        reportPhaseIfChanged()
    }

    func rollback() {
        ExposureExperimentLogic.rollback(state: &record.experiment, now: clock())
        persist()
        reportPhaseIfChanged()
    }

    func clearAggregates() {
        record.days = []
        persist()
    }

    func record(
        _ event: ExposureStudyEvent,
        module: KajiModuleID? = nil,
        source: ExposureEntrySource? = nil,
        statusWidth: Int? = nil
    ) {
        record.record(event: event, module: module, source: source, statusWidth: statusWidth, now: clock())
        persist()
    }

    func recordStatusWidth(_ width: Int) {
        record.recordStatusWidth(width, now: clock())
        persist()
    }

    private func startPhaseTimer() {
        guard phaseTimer == nil else { return }
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reportPhaseIfChanged() }
        }
    }

    private func reportPhaseIfChanged() {
        let current = phase
        guard current != lastReportedPhase else { return }
        lastReportedPhase = current
        didChangePhaseSubject.send(current)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.studyEncoder.encode(record)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // The study must never make the product unavailable. A later event
            // retries the same bounded aggregate write.
        }
    }

    private static func load(from url: URL) -> ExposureStudyRecord? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.studyDecoder.decode(ExposureStudyRecord.self, from: data),
              decoded.version == ExposureStudyRecord.currentVersion else { return nil }
        return ExposureStudyRecord(
            version: decoded.version,
            experiment: decoded.experiment,
            days: decoded.days
        )
    }

    private static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Kaji", isDirectory: true)
            .appendingPathComponent("exposure-study-v1.json")
    }
}

private extension JSONEncoder {
    static var studyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var studyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}