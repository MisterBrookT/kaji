import Foundation
import KajiCore
import KajiSleepSupport

enum SleepGuidanceKind: Equatable {
    case repair
}

struct SleepApprovalFlow: Equatable {
    private(set) var pendingTarget: Bool?
    private(set) var guidance: SleepGuidanceKind?

    var isGuidancePresented: Bool { guidance != nil }

    mutating func requireRepair(for target: Bool) {
        pendingTarget = target
        guidance = .repair
    }

    mutating func dismissGuidance() {
        guidance = nil
    }

    mutating func cancel() {
        pendingTarget = nil
        guidance = nil
    }
}

@MainActor
final class SleepController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var targetEnabled: Bool?
    @Published private(set) var lastError: String?
    @Published private(set) var approvalFlow = SleepApprovalFlow()

    var onStateChanged: ((Bool) -> Void)?

    enum AuthorizationStatus: Equatable {
        case authorized, notAuthorized, needsUpdate, needsReauthorization
    }

    struct Environment {
        let status: @MainActor () -> SleepHelperInstallStatus
        let install: @MainActor () async throws -> Void
        let request: @Sendable (Bool) async -> Bool
        let readState: @MainActor () -> Bool

        static let live = Environment(
            status: { SleepHelperInstaller.live.status() },
            install: { try await SleepHelperInstaller.live.install() },
            request: { await SleepController.requestSleepDisabled($0) },
            readState: { SleepController.readSleepDisabled() }
        )
    }

    private let environment: Environment

    static var authorizationStatus: AuthorizationStatus {
        authorizationStatus(for: SleepHelperInstaller.live.status())
    }

    // Binary mismatch after an app upgrade is an update/repair requirement,
    // not evidence that macOS revoked permission. Keep the integrity check.
    static func authorizationStatus(for status: SleepHelperInstallStatus) -> AuthorizationStatus {
        switch status {
        case .installed: .authorized
        case .notInstalled: .notAuthorized
        case .needsRepair: .needsUpdate
        case .unavailable: .needsReauthorization
        }
    }

    init(previewEnabled: Bool? = nil, environment: Environment = .live) {
        self.environment = environment
        if let previewEnabled {
            isEnabled = previewEnabled
        } else {
            refresh()
        }
    }

    func refresh() {
        let observed = environment.readState()
        isEnabled = observed
        onStateChanged?(observed)
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard !isBusy else { return }
        refresh()
        guard isEnabled != enabled else { return }

        isBusy = true
        targetEnabled = enabled
        lastError = nil

        Task {
            let commandSucceeded: Bool
            var installedNow = false
            do {
                switch environment.status() {
                case .installed:
                    break
                case .notInstalled:
                    try await environment.install()
                    installedNow = true
                    guard environment.status() == .installed else {
                        throw SleepControllerError.installationFailed
                    }
                case .needsRepair, .unavailable:
                    throw SleepControllerError.installationFailed
                }
                commandSucceeded = await request(enabled, attempts: installedNow ? 3 : 1)
                if !commandSucceeded {
                    approvalFlow.requireRepair(for: enabled)
                }
            } catch {
                commandSucceeded = false
                approvalFlow.requireRepair(for: enabled)
            }
            let observed = environment.readState()
            isBusy = false
            targetEnabled = nil
            isEnabled = observed
            onStateChanged?(observed)
        }
    }
    func performGuidanceAction() {
        repairHelper()
    }

    func dismissApprovalGuidance() {
        approvalFlow.dismissGuidance()
    }

    func cancelApprovalRequest() {
        approvalFlow.cancel()
    }

    private func repairHelper() {
        guard let target = approvalFlow.pendingTarget else { return }
        approvalFlow.dismissGuidance()
        isBusy = true
        targetEnabled = target
        lastError = nil

        Task {
            do {
                try await environment.install()
                guard environment.status() == .installed else {
                    throw SleepControllerError.installationFailed
                }
                let commandSucceeded = await request(target, attempts: 3)
                let observed = environment.readState()
                isBusy = false
                targetEnabled = nil
                isEnabled = observed
                onStateChanged?(observed)

                if commandSucceeded, observed == target {
                    approvalFlow.cancel()
                } else {
                    approvalFlow.requireRepair(for: target)
                    lastError = "helper_repair_failed"
                }
            } catch {
                isBusy = false
                targetEnabled = nil
                approvalFlow.requireRepair(for: target)
                lastError = "helper_repair_failed"
            }
        }
    }

    private func request(_ target: Bool, attempts: Int) async -> Bool {
        for attempt in 1...attempts {
            if await environment.request(target) { return true }
            if attempt < attempts {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        return false
    }

    nonisolated static func requestSleepDisabled(
        _ disabled: Bool,
        machServiceName: String = kajiSleepHelperMachService,
        timeout: TimeInterval = 3
    ) async -> Bool {
        if !disabled, let released = await SleepLeaseClient.shared.disable(timeout: timeout) {
            return released
        }
        return await withCheckedContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: machServiceName)
            connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)

            let completion = SleepRequestCompletion(
                connection: connection,
                continuation: continuation
            )

            connection.interruptionHandler = { completion.finish(false) }
            connection.invalidationHandler = { completion.finish(false) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                completion.finish(false)
            }
            connection.resume()

            guard let helper = connection.remoteObjectProxyWithErrorHandler({ _ in
                completion.finish(false)
            }) as? SleepHelperProtocol else {
                completion.finish(false)
                return
            }
            helper.setSleepDisabled(disabled) { ok, _ in
                completion.finish(ok, keepLease: ok && disabled)
            }
        }
    }

    private static func readSleepDisabled() -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        return SleepControlLogic.parseSleepDisabled(output)
    }

    static func parseSleepDisabled(_ output: String) -> Bool {
        SleepControlLogic.parseSleepDisabled(output)
    }
}

final class SleepRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}

private final class SleepRequestCompletion: @unchecked Sendable {
    private let gate = SleepRequestGate()
    private let connection: NSXPCConnection
    private let continuation: CheckedContinuation<Bool, Never>

    init(connection: NSXPCConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ value: Bool, keepLease: Bool = false) {
        guard gate.claim() else { return }
        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        if keepLease { SleepLeaseClient.shared.hold(connection) }
        else { connection.invalidate() }
        continuation.resume(returning: value)
    }
}

// A live connection owns the helper lease. If the app exits, launchd/XPC closes
// it and the daemon restores the recorded prior value. Renewal bounds a broken
// connection that fails to deliver an invalidation callback.
final class SleepLeaseClient: @unchecked Sendable {
    static let shared = SleepLeaseClient()
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var timer: DispatchSourceTimer?

    func hold(_ newConnection: NSXPCConnection) {
        lock.lock()
        connection?.invalidate()
        timer?.cancel()
        connection = newConnection
        let leaseTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        leaseTimer.schedule(deadline: .now() + 15, repeating: 15)
        leaseTimer.setEventHandler { [weak self, weak newConnection] in
            guard let self, let newConnection,
                  let proxy = newConnection.remoteObjectProxyWithErrorHandler({ _ in self.close() }) as? SleepHelperProtocol else {
                self?.close()
                return
            }
            proxy.renewLease { valid in if !valid { self.close() } }
        }
        timer = leaseTimer
        leaseTimer.resume()
        lock.unlock()
    }

    private func currentConnection() -> NSXPCConnection? {
        lock.lock()
        defer { lock.unlock() }
        return connection
    }

    func disable(timeout: TimeInterval) async -> Bool? {
        guard let active = currentConnection() else { return nil }
        return await withCheckedContinuation { continuation in
            let gate = SleepRequestGate()
            let complete: @Sendable (Bool) -> Void = { [self] result in
                guard gate.claim() else { return }
                self.close()
                continuation.resume(returning: result)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { complete(false) }
            guard let proxy = active.remoteObjectProxyWithErrorHandler({ _ in complete(false) }) as? SleepHelperProtocol else {
                complete(false)
                return
            }
            proxy.setSleepDisabled(false) { ok, _ in complete(ok) }
        }
    }

    func close() {
        lock.lock()
        timer?.cancel()
        timer = nil
        connection?.invalidate()
        connection = nil
        lock.unlock()
    }
}

private enum SleepControllerError: Error {
    case installationFailed
}
