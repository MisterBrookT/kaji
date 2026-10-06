import Foundation
import KajiSleepSupport

// The marker is root-owned and written before changing pmset. A restarted daemon
// can therefore restore an interrupted lease without guessing the user's setting.
private final class SleepLease: @unchecked Sendable {
    static let shared = SleepLease()
    static let marker = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/dev.kaji.sleep-helper.lease")
    private let queue = DispatchQueue(label: "dev.kaji.sleep-helper.lease")
    private var owner: ObjectIdentifier?
    private var deadline = Date.distantPast
    private let duration: TimeInterval = 45

    init() {
        queue.async {
            if FileManager.default.fileExists(atPath: Self.marker.path) {
                _ = self.restore()
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if (self.owner != nil && Date() >= self.deadline) ||
                (self.owner == nil && FileManager.default.fileExists(atPath: Self.marker.path)) {
                _ = self.restore()
            }
        }
        timer.resume()
        self.timer = timer
    }
    private var timer: DispatchSourceTimer?

    func set(_ disabled: Bool, for connection: NSXPCConnection, reply: @escaping (Bool, String?) -> Void) {
        let id = ObjectIdentifier(connection)
        queue.async {
            if disabled {
                guard self.owner == nil || self.owner == id else { reply(false, "Another lease is active"); return }
                if FileManager.default.fileExists(atPath: Self.marker.path) {
                    guard let data = try? Data(contentsOf: Self.marker),
                          SleepLeaseRestoration.parseMarker(data) != nil else {
                        reply(false, "Invalid sleep lease marker"); return
                    }
                    if self.owner == nil {
                        guard self.restore() else { reply(false, "Could not restore previous sleep state"); return }
                    }
                }
                if !FileManager.default.fileExists(atPath: Self.marker.path) {
                    guard let previous = self.currentValue() else { reply(false, "Cannot read pmset state"); return }
                    do {
                        try Data(previous ? "1".utf8 : "0".utf8).write(to: Self.marker, options: .atomic)
                    } catch { reply(false, error.localizedDescription); return }
                }
                guard self.runPmset("1") else { reply(false, "pmset failed"); return }
                self.owner = id
                self.deadline = Date().addingTimeInterval(self.duration)
                reply(true, nil)
            } else {
                guard self.owner == nil || self.owner == id else { reply(false, "Another lease is active"); return }
                let ok = self.restore()
                reply(ok, ok ? nil : "Could not restore previous sleep state")
            }
        }
    }

    func renew(_ connection: NSXPCConnection, reply: @escaping (Bool) -> Void) {
        let id = ObjectIdentifier(connection)
        queue.async {
            let valid = self.owner == id && Date() < self.deadline
            if valid { self.deadline = Date().addingTimeInterval(self.duration) }
            reply(valid)
        }
    }

    func disconnected(_ id: ObjectIdentifier) {
        queue.async {
            if self.owner == id { _ = self.restore() }
        }
    }

    private func restore() -> Bool {
        guard let data = try? Data(contentsOf: Self.marker),
              let saved = SleepLeaseRestoration.parseMarker(data) else {
            // Never guess an original value if the marker is corrupt.
            owner = nil
            return !FileManager.default.fileExists(atPath: Self.marker.path)
        }
        // A failed restoration must not leave a renewable lease behind.
        owner = nil
        guard let current = currentValue() else { return false }
        // Only revert a value we actually changed; do not overwrite a later user edit.
        if let target = SleepLeaseRestoration.target(saved: saved, current: current),
           !runPmset(target ? "1" : "0") { return false }
        do { try FileManager.default.removeItem(at: Self.marker) } catch { return false }
        owner = nil
        return true
    }

    private func currentValue() -> Bool? {
        guard let result = command(["-g"], timeout: 5), result.0 == 0 else { return nil }
        return SleepLeaseRestoration.parsePmsetState(result.1)
    }

    private func runPmset(_ value: String) -> Bool {
        command(["-a", "disablesleep", value], timeout: 8)?.0 == 0
    }

    private func command(_ arguments: [String], timeout: TimeInterval) -> (Int32, String)? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { return nil }
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        timer.resume()
        // pmset output is small; drain concurrently to avoid a full pipe deadlock.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

private final class SleepHelper: NSObject, SleepHelperProtocol {
    weak var connection: NSXPCConnection?
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        guard let connection else { reply(false, "Connection closed"); return }
        SleepLease.shared.set(disabled, for: connection, reply: reply)
    }
    func renewLease(reply: @escaping (Bool) -> Void) {
        guard let connection else { reply(false); return }
        SleepLease.shared.renew(connection, reply: reply)
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let requirement: String
    init?(arguments: [String]) {
        guard arguments.count == 2,
              SleepLeaseRestoration.acceptsCodeHash(arguments[1]) else { return nil }
        requirement = "cdhash H\"\(arguments[1])\""
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Foundation validates every message against the exact installed app code hash.
        // No identifier-only fallback: ad-hoc identifiers can be copied by any user.
        connection.setCodeSigningRequirement(requirement)
        let helper = SleepHelper()
        helper.connection = connection
        connection.exportedInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.exportedObject = helper
        let id = ObjectIdentifier(connection)
        connection.invalidationHandler = { SleepLease.shared.disconnected(id) }
        connection.interruptionHandler = { SleepLease.shared.disconnected(id) }
        connection.resume()
        return true
    }
}

// Reject malformed root provisioning instead of exposing an unauthenticated service.
guard let delegate = ListenerDelegate(arguments: CommandLine.arguments) else { exit(78) }
_ = SleepLease.shared
let listener = NSXPCListener(machServiceName: kajiSleepHelperMachService)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
