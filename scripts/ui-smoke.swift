import AppKit
import CoreGraphics
import Foundation

struct SmokeError: Error, CustomStringConvertible {
    let description: String
}

struct DesktopState: Equatable {
    let mouse: CGPoint
    let frontmostBundleID: String?
    let frontmostPID: pid_t?

    static func capture() throws -> DesktopState {
        guard let event = CGEvent(source: CGEventSource(stateID: .hidSystemState)) else {
            throw SmokeError(description: "could not read mouse position")
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        return DesktopState(
            mouse: event.location,
            frontmostBundleID: frontmost?.bundleIdentifier,
            frontmostPID: frontmost?.processIdentifier
        )
    }
}

func rpc(port: UInt16, nonce: String, surface: String, selection: String, outputPath: String) throws -> [String: Any] {
    let body: [String: Any] = [
        "jsonrpc": "2.0",
        "id": UUID().uuidString,
        "method": "kaji/test/render",
        "params": [
            "nonce": nonce,
            "surface": surface,
            "selection": selection,
            "outputPath": outputPath,
        ],
    ]
    let bodyData = try JSONSerialization.data(withJSONObject: body)
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = bodyData
    request.timeoutInterval = 10

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<[String: Any], Error>?
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error {
            result = .failure(error)
            return
        }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["result"] as? [String: Any] else {
            let responseBody = data.map { String(decoding: $0, as: UTF8.self) } ?? "<empty>"
            result = .failure(SmokeError(description: "RPC failed: \(responseBody)"))
            return
        }
        result = .success(payload)
    }.resume()
    guard semaphore.wait(timeout: .now() + 12) == .success, let result else {
        throw SmokeError(description: "RPC timed out for \(surface):\(selection)")
    }
    return try result.get()
}

func waitForServer(port: UInt16, nonce: String, artifactRoot: String) throws {
    let deadline = Date().addingTimeInterval(10)
    var lastError: Error?
    while Date() < deadline {
        do {
            _ = try rpc(
                port: port,
                nonce: nonce,
                surface: "status",
                selection: "status",
                outputPath: URL(fileURLWithPath: artifactRoot).appendingPathComponent("status.png").path
            )
            return
        } catch {
            lastError = error
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    throw lastError ?? SmokeError(description: "test UI server did not become ready")
}

func assertPNG(_ path: String, label: String) throws {
    guard let image = NSImage(contentsOfFile: path), image.size.width > 0, image.size.height > 0,
          let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let bytes = attributes[.size] as? NSNumber, bytes.intValue > 256 else {
        throw SmokeError(description: "ASSERT render-\(label): FAIL missing or blank PNG at \(path)")
    }
    print("ASSERT render-\(label): PASS \(Int(image.size.width))x\(Int(image.size.height)) \(bytes.intValue) bytes")
}

func assertNoInputAutomation(in paths: [String]) throws {
    let forbidden = [
        "CGWarpMouse" + "CursorPosition",
        "leftMouse" + "Down",
        "leftMouse" + "Up",
        "mouse" + "Moved",
        ".post(" + "tap:",
        "CGEvent" + "Post",
        "key" + "Down",
        "key" + "Up",
        "perform" + "Click",
        "osa" + "script",
        "AXUIElement" + "PerformAction",
    ]
    for path in paths {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        if let match = forbidden.first(where: source.contains) {
            throw SmokeError(description: "ASSERT no-input-implementation: FAIL \(path) contains \(match)")
        }
    }
    print("ASSERT no-input-implementation: PASS no posting, warp, keyboard, AppleScript, AX action, or AppKit click APIs")
}

func run() throws {
    guard CommandLine.arguments.count == 9,
          let pid = pid_t(CommandLine.arguments[1]),
          let port = UInt16(CommandLine.arguments[4]) else {
        throw SmokeError(description: "usage: ui-smoke-helper PID ARTIFACTS NONCE PORT PAGE_IDS SETTINGS_SECTIONS SWIFT_SOURCE SHELL_SOURCE")
    }
    let artifacts = CommandLine.arguments[2]
    let nonce = CommandLine.arguments[3]
    let pageIDs = CommandLine.arguments[5].split(separator: "|").map(String.init)
    let settingsSections = CommandLine.arguments[6].split(separator: "|").map(String.init)
    let implementationPaths = [CommandLine.arguments[7], CommandLine.arguments[8]]

    guard kill(pid, 0) == 0 else { throw SmokeError(description: "Kaji test process is not running") }
    try assertNoInputAutomation(in: implementationPaths)
    let before = try DesktopState.capture()
    try waitForServer(port: port, nonce: nonce, artifactRoot: artifacts)
    try assertPNG(URL(fileURLWithPath: artifacts).appendingPathComponent("status.png").path, label: "status")

    for page in pageIDs {
        let path = URL(fileURLWithPath: artifacts).appendingPathComponent("popover-\(page).png").path
        _ = try rpc(port: port, nonce: nonce, surface: "popover", selection: page, outputPath: path)
        try assertPNG(path, label: "popover-\(page)")
    }
    for section in settingsSections {
        let safeName = section.replacingOccurrences(of: " ", with: "-").lowercased()
        let path = URL(fileURLWithPath: artifacts).appendingPathComponent("settings-\(safeName).png").path
        _ = try rpc(port: port, nonce: nonce, surface: "settings", selection: section, outputPath: path)
        try assertPNG(path, label: "settings-\(safeName)")
    }

    let after = try DesktopState.capture()
    guard before.mouse == after.mouse else {
        throw SmokeError(description: "ASSERT mouse-position: FAIL \(before.mouse) -> \(after.mouse)")
    }
    print("ASSERT mouse-position: PASS unchanged at \(before.mouse)")
    guard before.frontmostBundleID == after.frontmostBundleID,
          before.frontmostPID == after.frontmostPID else {
        throw SmokeError(description: "ASSERT frontmost-application: FAIL \(String(describing: before.frontmostBundleID))/\(String(describing: before.frontmostPID)) -> \(String(describing: after.frontmostBundleID))/\(String(describing: after.frontmostPID))")
    }
    print("ASSERT frontmost-application: PASS unchanged \(before.frontmostBundleID ?? "<none>") pid=\(before.frontmostPID.map(String.init) ?? "<none>")")
    print("ASSERT keyboard-events: PASS implementation contains no keyboard event API")
}

do {
    try run()
} catch {
    fputs("UI-SMOKE FAIL: \(error)\n", stderr)
    exit(1)
}
