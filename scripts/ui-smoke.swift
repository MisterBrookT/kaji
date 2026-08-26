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

struct HTTPResult {
    let status: Int
    let object: [String: Any]
}

func request(
    port: UInt16,
    method: String,
    path: String,
    body: [String: Any]? = nil
) throws -> HTTPResult {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/\(path)")!)
    request.httpMethod = method
    request.timeoutInterval = 10
    if let body {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<HTTPResult, Error>?
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error {
            result = .failure(error)
            return
        }
        guard let http = response as? HTTPURLResponse, let data else {
            result = .failure(SmokeError(description: "control request returned no HTTP response"))
            return
        }
        let object = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        result = .success(HTTPResult(status: http.statusCode, object: object))
    }.resume()
    guard semaphore.wait(timeout: .now() + 12) == .success, let result else {
        throw SmokeError(description: "control request timed out for \(method) \(path)")
    }
    return try result.get()
}

func render(
    port: UInt16,
    nonce: String,
    surface: String,
    selection: String,
    outputPath: String
) throws -> [String: Any] {
    let result = try request(
        port: port,
        method: "POST",
        path: "test/render",
        body: [
            "nonce": nonce,
            "surface": surface,
            "selection": selection,
            "outputPath": outputPath,
        ]
    )
    guard result.status == 200 else {
        throw SmokeError(description: "render \(surface):\(selection) failed with HTTP \(result.status): \(result.object)")
    }
    return result.object
}

func waitForServer(port: UInt16) throws -> [String: Any] {
    let deadline = Date().addingTimeInterval(10)
    var lastError: Error?
    while Date() < deadline {
        do {
            let result = try request(port: port, method: "GET", path: "state")
            if result.status == 200 { return result.object }
        } catch {
            lastError = error
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw lastError ?? SmokeError(description: "test control server did not become ready")
}

func waitForLaunchdSnapshot(port: UInt16, initial: [String: Any]) throws -> [String: Any] {
    var state = initial
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        if let launchd = state["launchd"] as? [String: Any],
           let user = launchd["userAgent"] as? [String: Any],
           (user["total"] as? Int ?? 0) > 0 {
            return state
        }
        Thread.sleep(forTimeInterval: 0.1)
        let result = try request(port: port, method: "GET", path: "state")
        if result.status == 200 { state = result.object }
    }
    return state
}

func assertPNG(_ path: String, label: String) throws {
    guard let image = NSImage(contentsOfFile: path),
          image.size.width > 0,
          image.size.height > 0,
          let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let bytes = attributes[.size] as? NSNumber,
          bytes.intValue > 256 else {
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
        "pk" + "ill",
    ]
    for path in paths {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        if let match = forbidden.first(where: source.contains) {
            throw SmokeError(description: "ASSERT no-input-implementation: FAIL \(path) contains \(match)")
        }
    }
    print("ASSERT no-input-implementation: PASS no posting, warp, keyboard, AppleScript, AX action, or global process-kill APIs")
}

func systemAuthPromptWindows() -> [String] {
    let owners: Set<String> = ["SecurityAgent", "loginwindow", "coreauthd", "UserNotificationCenter"]
    guard let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else { return [] }
    return windows.compactMap { window in
        guard let owner = window[kCGWindowOwnerName as String] as? String,
              owners.contains(owner) else { return nil }
        let title = window[kCGWindowName as String] as? String ?? ""
        return "\(owner):\(title)"
    }
}

func assertNoSystemAuthPrompt(_ context: String) throws {
    let prompts = systemAuthPromptWindows()
    guard prompts.isEmpty else {
        throw SmokeError(description: "ASSERT no-system-auth-prompt: FAIL during \(context): \(prompts)")
    }
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

    guard kill(pid, 0) == 0 else {
        throw SmokeError(description: "owned Kaji test process is not running")
    }
    try assertNoInputAutomation(in: implementationPaths)
    let before = try DesktopState.capture()
    try assertNoSystemAuthPrompt("before render")

    var state = try waitForServer(port: port)
    state = try waitForLaunchdSnapshot(port: port, initial: state)
    if let launchd = state["launchd"] as? [String: Any],
       let user = launchd["userAgent"] as? [String: Any] {
        print("ASSERT launchd-state: PASS My Tasks total=\(user["total"] ?? "?") running=\(user["running"] ?? "?") failed=\(user["failed"] ?? "?") idle=\(user["idle"] ?? "?") unloaded=\(user["unloaded"] ?? "?")")
    } else {
        throw SmokeError(description: "ASSERT launchd-state: FAIL control snapshot omitted launchd.userAgent")
    }

    let statusPath = URL(fileURLWithPath: artifacts).appendingPathComponent("status.png").path
    _ = try render(port: port, nonce: nonce, surface: "status", selection: "status", outputPath: statusPath)
    try assertPNG(statusPath, label: "status")

    for page in pageIDs {
        let safeName = page.replacingOccurrences(of: ":", with: "-")
        let path = URL(fileURLWithPath: artifacts).appendingPathComponent("popover-\(safeName).png").path
        _ = try render(port: port, nonce: nonce, surface: "popover", selection: page, outputPath: path)
        try assertPNG(path, label: "popover-\(safeName)")
        try assertNoSystemAuthPrompt("popover \(page)")
    }
    for section in settingsSections {
        let safeName = section.replacingOccurrences(of: " ", with: "-").lowercased()
        let path = URL(fileURLWithPath: artifacts).appendingPathComponent("settings-\(safeName).png").path
        _ = try render(port: port, nonce: nonce, surface: "settings", selection: section, outputPath: path)
        try assertPNG(path, label: "settings-\(safeName)")
        try assertNoSystemAuthPrompt("settings \(section)")
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
    print("ASSERT no-system-auth-prompt: PASS across all offscreen renders")
}

do {
    try run()
} catch {
    fputs("UI-SMOKE FAIL: \(error)\n", stderr)
    exit(1)
}
