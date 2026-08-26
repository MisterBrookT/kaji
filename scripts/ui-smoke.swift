import ApplicationServices
import CoreGraphics
import Foundation

struct WindowSnapshot {
    let id: CGWindowID
    let bounds: CGRect
}

enum SmokeError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

struct AXElementInfo {
    let role: String
    let text: String
    let identifier: String?
    let bounds: CGRect?
}

func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
    guard let raw = attribute(element, name) else { return nil }
    if CFGetTypeID(raw) == CFStringGetTypeID() {
        return unsafeBitCast(raw, to: CFString.self) as String
    }
    return nil
}

/// NSPopover's backing panel is a nonactivating borderless window; for an
/// `.accessory`-policy (LSUIElement) app like Kaji it is never listed under
/// the application element's `kAXWindowsAttribute` (confirmed empirically —
/// that attribute reports 0 windows while the popover is open). The
/// reliable way in is a system-wide hit-test at a point inside the
/// CGWindow's bounds, then reading `kAXWindowAttribute` off whatever was
/// hit to climb to the enclosing window element (role `AXPopover`).
func findAXWindow(pid: pid_t, matching target: CGRect) -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    let point = CGPoint(x: target.midX, y: target.midY)
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
          let hit else { return nil }
    var ownerPID: pid_t = 0
    AXUIElementGetPid(hit, &ownerPID)
    guard ownerPID == pid else { return nil }
    if let raw = attribute(hit, kAXWindowAttribute as CFString), CFGetTypeID(raw) == AXUIElementGetTypeID() {
        return unsafeBitCast(raw, to: AXUIElement.self)
    }
    // The hit element itself may already be the window/popover root.
    if let role = attribute(hit, kAXRoleAttribute as CFString) as? String,
       role == kAXWindowRole as String || role == "AXPopover" {
        return hit
    }
    return nil
}

/// Depth-first walk collecting every element's role/text/identifier/bounds.
/// Depth and node counts are capped so a runaway SwiftUI tree cannot hang
/// the smoke run.
func collectAXElements(_ element: AXUIElement, depth: Int = 0, budget: inout Int) -> [AXElementInfo] {
    guard depth < 40, budget > 0 else { return [] }
    budget -= 1
    let role = (attribute(element, kAXRoleAttribute as CFString) as? String)
        ?? stringAttribute(element, kAXRoleAttribute as CFString)
        ?? "?"
    let title = stringAttribute(element, kAXTitleAttribute as CFString) ?? ""
    let value = stringAttribute(element, kAXValueAttribute as CFString) ?? ""
    let description = stringAttribute(element, kAXDescriptionAttribute as CFString) ?? ""
    let text = [title, value, description].first(where: { !$0.isEmpty }) ?? ""
    let identifier = stringAttribute(element, kAXIdentifierAttribute as CFString)
    var own = [AXElementInfo(role: role, text: text, identifier: identifier, bounds: bounds(of: element))]
    for child in children(of: element) {
        own.append(contentsOf: collectAXElements(child, depth: depth + 1, budget: &budget))
    }
    return own
}

func dumpAXElements(_ elements: [AXElementInfo]) {
    for info in elements where !info.text.isEmpty || info.role == "AXButton" {
        let boundsText = info.bounds.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "-"
        let idText = info.identifier ?? "-"
        print("AX-DUMP role=\(info.role) text=\"\(info.text)\" id=\(idText) bounds=\(boundsText)")
    }
}

/// macOS surfaces real Keychain/credential prompts as separate on-screen
/// windows owned by system agent processes, never by the app itself — this
/// is the acceptance signal for "permission asks once, never again":
/// scan every on-screen window (not just Kaji's) for one owned by any of
/// these processes. Overridable via KAJI_UI_SMOKE_AUTH_PROMPT_OWNERS
/// (comma-separated) purely so this script can prove the assertion truly
/// fires (see the failure-injection run in the task write-up); the real
/// default set is fixed.
func systemAuthPromptOwnerNames() -> Set<String> {
    if let override = ProcessInfo.processInfo.environment["KAJI_UI_SMOKE_AUTH_PROMPT_OWNERS"] {
        return Set(override.split(separator: ",").map(String.init))
    }
    return ["SecurityAgent", "loginwindow", "coreauthd", "UserNotificationCenter"]
}

struct SystemAuthPromptWindow: CustomStringConvertible {
    let ownerName: String
    let ownerPID: pid_t
    let title: String
    var description: String { "owner=\(ownerName) pid=\(ownerPID) title=\"\(title)\"" }
}

func systemAuthPromptWindows() -> [SystemAuthPromptWindow] {
    let owners = systemAuthPromptOwnerNames()
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
    return raw.compactMap { info in
        guard let ownerName = info[kCGWindowOwnerName as String] as? String, owners.contains(ownerName),
              let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }
        let title = info[kCGWindowName as String] as? String ?? ""
        return SystemAuthPromptWindow(ownerName: ownerName, ownerPID: ownerPID, title: title)
    }
}

/// Call after every action that could plausibly trigger a Keychain/credential
/// prompt. Throws (and screenshots) the instant one is seen — checked at
/// every popover-page transition, every Settings-page transition, and
/// before/after opening Settings, so the whole click-through is covered.
var authPromptCheckCount = 0
func checkNoSystemAuthPrompt(_ context: String, artifacts: String) throws {
    authPromptCheckCount += 1
    let found = systemAuthPromptWindows()
    guard found.isEmpty else {
        capture("\(artifacts)/system-auth-prompt-failure.png")
        throw SmokeError.message("ASSERT no-system-auth-prompt: FAIL a system authorization window appeared during \"\(context)\": \(found.map(\.description).joined(separator: "; "))")
    }
}

/// Header chevrons are 30x30 icon-only buttons (see KajiPopoverView.arrow);
/// distinguish them from the (30x28) footer icon buttons by requiring the
/// button sit within the popover's top ~44pt, where the header row lives.
func pageArrowButtons(in elements: [AXElementInfo], windowTop: CGFloat) -> [AXElementInfo] {
    elements.filter { info in
        guard info.role == "AXButton", let rect = info.bounds else { return false }
        return rect.width >= 28 && rect.width <= 32 && rect.height >= 28 && rect.height <= 32
            && rect.minY - windowTop < 44
    }.sorted { ($0.bounds?.minX ?? 0) < ($1.bounds?.minX ?? 0) }
}

func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func children(of element: AXUIElement) -> [AXUIElement] {
    guard let raw = attribute(element, kAXChildrenAttribute as CFString),
          CFGetTypeID(raw) == CFArrayGetTypeID() else { return [] }
    let array = unsafeBitCast(raw, to: CFArray.self)
    return (0..<CFArrayGetCount(array)).map {
        unsafeBitCast(CFArrayGetValueAtIndex(array, $0), to: AXUIElement.self)
    }
}

func bounds(of element: AXUIElement) -> CGRect? {
    guard let rawPosition = attribute(element, kAXPositionAttribute as CFString),
          CFGetTypeID(rawPosition) == AXValueGetTypeID(),
          let rawSize = attribute(element, kAXSizeAttribute as CFString),
          CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
    let positionValue = unsafeBitCast(rawPosition, to: AXValue.self)
    let sizeValue = unsafeBitCast(rawSize, to: AXValue.self)
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue, .cgPoint, &position),
          AXValueGetValue(sizeValue, .cgSize, &size),
          size.width > 0, size.height > 0 else { return nil }
    return CGRect(origin: position, size: size)
}

func isMainMenuBarBounds(_ rect: CGRect) -> Bool {
    let mainFrame = CGDisplayBounds(CGMainDisplayID())
    return rect.width > 0 && rect.height > 0 &&
        rect.minX >= mainFrame.minX && rect.maxX <= mainFrame.maxX &&
        rect.minY >= mainFrame.minY && rect.minY <= mainFrame.minY + 40
}

func statusItemBounds(pid: pid_t) -> CGRect? {
    let application = AXUIElementCreateApplication(pid)
    guard let rawMenuBar = attribute(application, kAXExtrasMenuBarAttribute as CFString)
            ?? attribute(application, kAXMenuBarAttribute as CFString),
          CFGetTypeID(rawMenuBar) == AXUIElementGetTypeID() else {
        return nil
    }
    let menuBar = unsafeBitCast(rawMenuBar, to: AXUIElement.self)
    for child in children(of: menuBar) {
        guard let role = attribute(child, kAXRoleAttribute as CFString) as? String,
              role == kAXMenuBarItemRole as String else { continue }
        return bounds(of: child)
    }
    return nil
}

func windows(pid: pid_t) -> [WindowSnapshot] {
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
    return raw.compactMap { info in
        guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
              ownerPID.int32Value == pid,
              let number = info[kCGWindowNumber as String] as? NSNumber,
              let boundsObject = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        let boundsDictionary = unsafeBitCast(boundsObject, to: CFDictionary.self)
        guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
        return WindowSnapshot(id: CGWindowID(number.uint32Value), bounds: bounds)
    }
}

func popoverWindow(in snapshots: [WindowSnapshot], excluding ids: Set<CGWindowID> = []) -> WindowSnapshot? {
    snapshots.first {
        !ids.contains($0.id) &&
        $0.bounds.width >= 180 && $0.bounds.width <= 700 &&
        $0.bounds.height >= 100 && $0.bounds.height <= 1_200
    }
}

func wait<T>(timeout: TimeInterval, interval: TimeInterval = 0.1, for value: () -> T?) -> T? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let result = value() { return result }
        Thread.sleep(forTimeInterval: interval)
    } while Date() < deadline
    return nil
}

func click(_ point: CGPoint) throws {
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                             mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                           mouseCursorPosition: point, mouseButton: .left) else {
        throw SmokeError.message("could not create CGEvent mouse events")
    }
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    up.post(tap: .cghidEventTap)
}

func capture(_ path: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", path]
    try? process.run()
    process.waitUntilExit()
}

func run() throws {
    guard CommandLine.arguments.count == 4, let pid = pid_t(CommandLine.arguments[1]) else {
        throw SmokeError.message("usage: ui-smoke.swift <pid> <artifact-directory> <expected-page-titles-pipe-separated>")
    }
    let artifacts = CommandLine.arguments[2]
    let expectedPageTitles = CommandLine.arguments[3].split(separator: "|").map(String.init)

    guard AXIsProcessTrusted() else {
        throw SmokeError.message("Accessibility permission is missing. Enable System Settings > Privacy & Security > Accessibility for your terminal (or the agent host running this script), then rerun ./scripts/ui-smoke.sh")
    }

    let mainFrame = CGDisplayBounds(CGMainDisplayID())
    let mainCenter = CGPoint(x: mainFrame.midX, y: mainFrame.midY)
    CGWarpMouseCursorPosition(mainCenter)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: mainCenter, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.5)

    guard let initialBounds = wait(timeout: 10, for: { () -> CGRect? in
        guard let candidate = statusItemBounds(pid: pid), isMainMenuBarBounds(candidate) else { return nil }
        return candidate
    }) else {
        throw SmokeError.message("Kaji status item did not expose stable AX bounds on the main menu bar within 10 seconds")
    }
    print("ASSERT status-item: PASS bounds=\(Int(initialBounds.minX)),\(Int(initialBounds.minY)) \(Int(initialBounds.width))x\(Int(initialBounds.height))")
    Thread.sleep(forTimeInterval: 0.3)

    let baselineIDs = Set(windows(pid: pid).map(\.id))
    let openPoint = CGPoint(x: initialBounds.minX + min(12, initialBounds.width / 2), y: initialBounds.midY)
    if ProcessInfo.processInfo.environment["KAJI_UI_SMOKE_SKIP_CLICK"] == nil {
        try click(openPoint)
    }

    guard let opened = wait(timeout: 3, for: {
        popoverWindow(in: windows(pid: pid), excluding: baselineIDs)
    }) else {
        capture("\(artifacts)/open-failure.png")
        throw SmokeError.message("ASSERT click-opens-popover: FAIL no popover-sized Kaji window appeared within 3 seconds")
    }
    capture("\(artifacts)/open.png")
    print("ASSERT click-opens-popover: PASS window=\(opened.id) size=\(Int(opened.bounds.width))x\(Int(opened.bounds.height))")
    try checkNoSystemAuthPrompt("popover opened", artifacts: artifacts)

    // Re-hit-test on every read instead of holding one AXUIElement handle:
    // resizing the popover for a different page can tear down and rebuild
    // its AX backing objects, which would make a cached handle go stale.
    func popoverElements() throws -> [AXElementInfo] {
        guard let currentWindow = windows(pid: pid).first(where: { $0.id == opened.id })
                ?? popoverWindow(in: windows(pid: pid)),
              let element = findAXWindow(pid: pid, matching: currentWindow.bounds) else {
            throw SmokeError.message("ASSERT ax-popover-tree: FAIL could not locate the popover's AXUIElement window via system-wide hit-test")
        }
        var budget = 4000
        return collectAXElements(element, budget: &budget)
    }

    var elements = try popoverElements()
    print("ASSERT ax-popover-tree: PASS discovered \(elements.count) AX nodes")
    dumpAXElements(elements)

    let expectedQuotaTitle = ProcessInfo.processInfo.environment["KAJI_UI_SMOKE_EXPECT_QUOTA_TITLE"] ?? "Quota"
    guard elements.contains(where: { $0.role == "AXStaticText" && $0.text == expectedQuotaTitle }) else {
        capture("\(artifacts)/ax-quota-page-failure.png")
        let observedTexts = elements.filter { $0.role == "AXStaticText" && !$0.text.isEmpty }.map(\.text)
        throw SmokeError.message("ASSERT ax-quota-page: FAIL expected an AXStaticText titled \"\(expectedQuotaTitle)\"; observed static text: \(observedTexts)")
    }
    print("ASSERT ax-quota-page: PASS found AXStaticText \"\(expectedQuotaTitle)\"")

    if expectedPageTitles.count > 1 {
        let windowTop = opened.bounds.minY
        var sequence = [expectedPageTitles[0]]
        for step in 0..<expectedPageTitles.count {
            elements = try popoverElements()
            let arrows = pageArrowButtons(in: elements, windowTop: windowTop)
            guard arrows.count == 2, let nextArrow = arrows.last, let nextBounds = nextArrow.bounds else {
                capture("\(artifacts)/ax-page-nav-failure.png")
                let candidateButtons = elements.filter { $0.role == "AXButton" }
                throw SmokeError.message("""
                    ASSERT ax-page-nav: FAIL expected exactly 2 header chevron buttons \
                    (30x30 icon-only AXButton within the popover's top 44pt); found \(arrows.count). \
                    All AXButton nodes seen: \(candidateButtons). \
                    The chevrons carry no AXTitle/AXDescription/AXIdentifier, so if this heuristic \
                    ever stops matching, the fix is accessibility identifiers in Sources/Kaji/KajiPopoverView.swift: \
                    add .accessibilityIdentifier("kaji.popover.page.prev") / ("kaji.popover.page.next") to the \
                    two Button closures built by `arrow(_:action:)` (used for chevron.left / chevron.right in `header`), \
                    plus .accessibilityIdentifier("kaji.popover.title") on the `Text(panelTitle)` header line, and \
                    root-level identifiers ("kaji.popover.panel.quota" / ".work" / ".system" / ".goals" / ".aiNews" / \
                    ".mailBrief") on each case of `panelBody` for reliable per-page content assertions.
                    """)
            }
            let center = CGPoint(x: nextBounds.midX, y: nextBounds.midY)
            try click(center)
            let expected = expectedPageTitles[(step + 1) % expectedPageTitles.count]
            guard wait(timeout: 2, for: { () -> Bool? in
                (try? popoverElements())?.contains(where: { $0.role == "AXStaticText" && $0.text == expected }) == true ? true : nil
            }) != nil else {
                capture("\(artifacts)/ax-page-nav-failure.png")
                let observedTexts = (try? popoverElements())?.filter { $0.role == "AXStaticText" && !$0.text.isEmpty }.map(\.text) ?? []
                throw SmokeError.message("ASSERT ax-page-nav: FAIL clicking the next-page chevron did not surface header title \"\(expected)\"; observed static text: \(observedTexts)")
            }
            sequence.append(expected)
            try checkNoSystemAuthPrompt("popover page \(expected)", artifacts: artifacts)
        }
        print("ASSERT ax-page-nav: PASS clicked through pages in order \(sequence.joined(separator: " -> "))")
    } else {
        print("ASSERT ax-page-nav: SKIP only \(expectedPageTitles.count) page(s) enabled; header chevrons are hidden (pages.count > 1 gate in KajiPopoverView.header)")
    }

    // Settings walk: click gearshape in the popover footer, then click every
    // sidebar section and assert the visible content actually changes.
    // Mail Brief is the highest-risk page for this run — it's the module
    // whose credential lookup used to pop a live Keychain prompt.
    //
    // Re-fetch elements: the page-nav loop's last read is one click stale
    // (captured before the click back to the wrap-around page), and footer
    // buttons shift vertically with popover height, so a stale bounds would
    // miss the real button.
    elements = try popoverElements()
    let settingsButton = elements.first { $0.role == "AXButton" && $0.identifier == "gearshape" }
    guard let settingsButton, let settingsButtonBounds = settingsButton.bounds else {
        capture("\(artifacts)/settings-open-failure.png")
        throw SmokeError.message("ASSERT settings-opens: FAIL no AXButton with identifier \"gearshape\" found in the popover footer; AXButtons seen: \(elements.filter { $0.role == "AXButton" })")
    }
    let settingsBaselineIDs = Set(windows(pid: pid).map(\.id))
    try click(CGPoint(x: settingsButtonBounds.midX, y: settingsButtonBounds.midY))

    guard let settingsWindow = wait(timeout: 3, for: { () -> WindowSnapshot? in
        windows(pid: pid).first { !settingsBaselineIDs.contains($0.id) && $0.bounds.width >= 500 && $0.bounds.height >= 300 }
    }) else {
        capture("\(artifacts)/settings-open-failure.png")
        throw SmokeError.message("ASSERT settings-opens: FAIL no Settings-sized (>=500x300) Kaji window appeared within 3 seconds of clicking gearshape")
    }
    print("ASSERT settings-opens: PASS window=\(settingsWindow.id) size=\(Int(settingsWindow.bounds.width))x\(Int(settingsWindow.bounds.height))")
    try checkNoSystemAuthPrompt("settings opened", artifacts: artifacts)

    func settingsElements() throws -> [AXElementInfo] {
        guard let currentWindow = windows(pid: pid).first(where: { $0.id == settingsWindow.id }),
              let element = findAXWindow(pid: pid, matching: currentWindow.bounds) else {
            throw SmokeError.message("ASSERT settings-nav: FAIL could not locate the Settings AXUIElement window via system-wide hit-test")
        }
        var budget = 4000
        return collectAXElements(element, budget: &budget)
    }

    let settingsSections = ["General", "Modules", "Work", "Goals", "Quota", "AI News", "Mail Brief", "CLI"]
    var previousSignature: Set<String>? = nil
    for (index, section) in settingsSections.enumerated() {
        if index > 0 {
            let currentElements = try settingsElements()
            guard let row = currentElements.first(where: { $0.role == "AXStaticText" && $0.text == section }),
                  let rowBounds = row.bounds else {
                capture("\(artifacts)/settings-nav-failure.png")
                throw SmokeError.message("ASSERT settings-nav: FAIL no sidebar row titled \"\(section)\" found in the Settings AX tree; static text seen: \(currentElements.filter { $0.role == "AXStaticText" }.map(\.text))")
            }
            try click(CGPoint(x: rowBounds.midX, y: rowBounds.midY))
        }
        Thread.sleep(forTimeInterval: 1.0)
        let pageElements = try settingsElements()
        let signature = Set(pageElements.filter { $0.role == "AXStaticText" && !$0.text.isEmpty }.map(\.text))
        print("AX-DUMP [Settings:\(section)] discovered \(pageElements.count) nodes")
        for info in pageElements where !info.text.isEmpty {
            let boundsText = info.bounds.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "-"
            print("AX-DUMP [Settings:\(section)] role=\(info.role) text=\"\(info.text)\" bounds=\(boundsText)")
        }
        try checkNoSystemAuthPrompt("settings section \(section)", artifacts: artifacts)
        if let previousSignature, index > 0 {
            guard signature != previousSignature else {
                capture("\(artifacts)/settings-nav-failure.png")
                throw SmokeError.message("ASSERT settings-nav: FAIL clicking sidebar row \"\(section)\" did not change the visible content; static text stayed: \(signature.sorted())")
            }
        }
        previousSignature = signature
    }
    print("ASSERT settings-nav: PASS walked \(settingsSections.count) sidebar sections, content changed on every click")
    print("ASSERT no-system-auth-prompt: PASS checked \(authPromptCheckCount) times, no system authorization window ever appeared")


    guard let refreshedBounds = statusItemBounds(pid: pid) else {
        throw SmokeError.message("ASSERT click-closes-popover: FAIL could not refresh status-item AX bounds")
    }
    let closePoint = CGPoint(x: refreshedBounds.minX + min(12, refreshedBounds.width / 2), y: refreshedBounds.midY)
    try click(closePoint)

    guard wait(timeout: 3, for: {
        windows(pid: pid).contains(where: { $0.id == opened.id }) ? nil : true
    }) != nil else {
        capture("\(artifacts)/close-failure.png")
        throw SmokeError.message("ASSERT click-closes-popover: FAIL popover window \(opened.id) remained on screen after second click")
    }
    capture("\(artifacts)/closed.png")
    print("ASSERT click-closes-popover: PASS window=\(opened.id) disappeared")
}

do {
    try run()
} catch {
    fputs("UI-SMOKE FAIL: \(error)\n", stderr)
    exit(1)
}
