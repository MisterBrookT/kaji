import Foundation
import KajiCore
import KajiSleepSupport
import ServiceManagement

@MainActor
final class SleepController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var targetEnabled: Bool?
    @Published private(set) var lastError: String?

    var onStateChanged: ((Bool) -> Void)?

    private static let daemon = SMAppService.daemon(
        plistName: "dev.kaji.sleep-helper.plist"
    )

    enum AuthorizationStatus: Equatable {
        case authorized, notAuthorized, needsReauthorization
    }

    static var authorizationStatus: AuthorizationStatus {
        switch daemon.status {
        case .enabled: .authorized
        case .requiresApproval: .needsReauthorization
        case .notRegistered, .notFound: .notAuthorized
        @unknown default: .notAuthorized
        }
    }

    init(previewEnabled: Bool? = nil) {
        if let previewEnabled {
            isEnabled = previewEnabled
        } else {
            refresh()
        }
    }

    func refresh() {
        let observed = Self.readSleepDisabled()
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
            do {
                try Self.registerHelperIfNeeded()
                commandSucceeded = await Self.requestSleepDisabled(enabled)
            } catch SleepControllerError.approvalRequired {
                SMAppService.openSystemSettingsLoginItems()
                commandSucceeded = false
            } catch {
                commandSucceeded = false
            }

            let observed = Self.readSleepDisabled()
            isBusy = false
            targetEnabled = nil
            isEnabled = observed
            onStateChanged?(observed)

            if case .failure = SleepControlLogic.resolvedState(
                requested: enabled,
                commandSucceeded: commandSucceeded,
                observed: observed
            ) {
                lastError = "pmset_failed"
            }
        }
    }

    func restoreAndRemoveHelper() async throws {
        guard await Self.requestSleepDisabled(false) else {
            throw SleepControllerError.restoreFailed
        }
        try await Self.daemon.unregister()
        refresh()
    }

    private static func registerHelperIfNeeded() throws {
        switch daemon.status {
        case .enabled:
            return
        case .notRegistered, .notFound:
            try daemon.register()
            guard daemon.status == .enabled else {
                throw SleepControllerError.approvalRequired
            }
        case .requiresApproval:
            throw SleepControllerError.approvalRequired
        @unknown default:
            throw SleepControllerError.registrationFailed
        }
    }

    private static func requestSleepDisabled(_ disabled: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: kajiSleepHelperMachService)
            connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)

            let completion = SleepRequestCompletion(
                connection: connection,
                continuation: continuation
            )

            connection.interruptionHandler = { completion.finish(false) }
            connection.invalidationHandler = { completion.finish(false) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3) {
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
