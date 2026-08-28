import Foundation
import KajiCore
import KajiSleepSupport
import ServiceManagement

enum SleepGuidanceKind: Equatable {
    case approval, repair
}

struct SleepApprovalFlow: Equatable {
    private(set) var pendingTarget: Bool?
    private(set) var guidance: SleepGuidanceKind?

    var isGuidancePresented: Bool { guidance != nil }

    mutating func requireApproval(for target: Bool) {
        pendingTarget = target
        guidance = .approval
    }

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

    mutating func consumePendingTarget(ifAuthorized authorized: Bool) -> Bool? {
        guard authorized, let pendingTarget else { return nil }
        cancel()
        return pendingTarget
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

    private static let daemon = SMAppService.daemon(
        plistName: "dev.kaji.sleep-helper.plist"
    )

    enum AuthorizationStatus: Equatable {
        case authorized, notAuthorized, needsReauthorization
    }
    enum HelperRegistrationAction: Equatable {
        case reuse, register, requestApproval, fail
    }

    struct Environment {
        let status: @MainActor () -> SMAppService.Status
        let register: @MainActor () throws -> Void
        let unregister: @MainActor () async throws -> Void
        let request: @Sendable (Bool) async -> Bool
        let readState: @MainActor () -> Bool
        let openSettings: @MainActor () -> Void

        static let live = Environment(
            status: { SleepController.daemon.status },
            register: { try SleepController.daemon.register() },
            unregister: { try await SleepController.daemon.unregister() },
            request: { await SleepController.requestSleepDisabled($0) },
            readState: { SleepController.readSleepDisabled() },
            openSettings: { SMAppService.openSystemSettingsLoginItems() }
        )
    }

    private let environment: Environment

    static var authorizationStatus: AuthorizationStatus {
        switch daemon.status {
        case .enabled: .authorized
        case .requiresApproval: .needsReauthorization
        case .notRegistered, .notFound: .notAuthorized
        @unknown default: .notAuthorized
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
            var guidanceWasRequested = false
            do {
                try registerHelperIfNeeded()
                commandSucceeded = await environment.request(enabled)
                if !commandSucceeded {
                    approvalFlow.requireRepair(for: enabled)
                    guidanceWasRequested = true
                }
            } catch SleepControllerError.approvalRequired {
                approvalFlow.requireApproval(for: enabled)
                guidanceWasRequested = true
                commandSucceeded = false
            } catch {
                commandSucceeded = false
            }

            let observed = environment.readState()
            isBusy = false
            targetEnabled = nil
            isEnabled = observed
            onStateChanged?(observed)

            if !guidanceWasRequested,
               case .failure = SleepControlLogic.resolvedState(
                   requested: enabled,
                   commandSucceeded: commandSucceeded,
                   observed: observed
               ) {
                lastError = "pmset_failed"
            }
        }
    }

    func performGuidanceAction() {
        switch approvalFlow.guidance {
        case .approval:
            openApprovalSettings()
        case .repair:
            repairHelper()
        case nil:
            break
        }
    }

    func openApprovalSettings() {
        approvalFlow.dismissGuidance()
        environment.openSettings()
    }

    func dismissApprovalGuidance() {
        approvalFlow.dismissGuidance()
    }

    func cancelApprovalRequest() {
        approvalFlow.cancel()
    }

    func resumePendingApprovalIfAuthorized() {
        let authorized = Self.registrationAction(for: environment.status()) == .reuse
        guard let target = approvalFlow.consumePendingTarget(ifAuthorized: authorized) else {
            return
        }
        setEnabled(target)
    }

    func restoreAndRemoveHelper() async throws {
        guard await environment.request(false) else {
            throw SleepControllerError.restoreFailed
        }
        try await environment.unregister()
        refresh()
    }

    private func repairHelper() {
        guard let target = approvalFlow.pendingTarget else { return }
        approvalFlow.dismissGuidance()
        isBusy = true
        Task {
            do {
                if Self.registrationAction(for: environment.status()) == .reuse {
                    try await environment.unregister()
                }
                try environment.register()
                guard Self.registrationAction(for: environment.status()) == .reuse else {
                    throw SleepControllerError.approvalRequired
                }
                approvalFlow.cancel()
                isBusy = false
                setEnabled(target)
            } catch SleepControllerError.approvalRequired {
                isBusy = false
                approvalFlow.requireApproval(for: target)
                openApprovalSettings()
            } catch {
                isBusy = false
                lastError = "helper_repair_failed"
            }
        }
    }

    private func registerHelperIfNeeded() throws {
        switch Self.registrationAction(for: environment.status()) {
        case .reuse:
            return
        case .register:
            try environment.register()
            guard Self.registrationAction(for: environment.status()) == .reuse else {
                throw SleepControllerError.approvalRequired
            }
        case .requestApproval:
            throw SleepControllerError.approvalRequired
        case .fail:
            throw SleepControllerError.registrationFailed
        }
    }

    nonisolated static func registrationAction(
        for status: SMAppService.Status
    ) -> HelperRegistrationAction {
        switch status {
        case .enabled:
            .reuse
        case .notRegistered, .notFound:
            .register
        case .requiresApproval:
            .requestApproval
        @unknown default:
            .fail
        }
    }

    nonisolated static func requestSleepDisabled(
        _ disabled: Bool,
        machServiceName: String = kajiSleepHelperMachService,
        timeout: TimeInterval = 3
    ) async -> Bool {
        await withCheckedContinuation { continuation in
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
            helper.setSleepDisabled(disabled) { ok, _ in completion.finish(ok) }
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

    func finish(_ value: Bool) {
        guard gate.claim() else { return }
        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        continuation.resume(returning: value)
        connection.invalidate()
    }
}

private enum SleepControllerError: Error {
    case approvalRequired
    case registrationFailed
    case restoreFailed
}
