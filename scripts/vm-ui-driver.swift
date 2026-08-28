import AppKit
import ApplicationServices
import Foundation

private enum DriverError: Error, CustomStringConvertible {
    case usage
    case accessibilityDenied
    case applicationNotFound(String)
    case elementNotFound(String)
    case ambiguousElement(String, Int)
    case actionFailed(AXError)

    var description: String {
        switch self {
        case .usage:
            "usage: vm-ui-driver trusted | request-trust | dump <bundle-id> | press-id <bundle-id> <identifier> [timeout] | press-label <bundle-id> <label> [timeout] | press-near-label <bundle-id> <label> [timeout] | set-subrole-value <bundle-id> <subrole> <value> [timeout] | count-label <bundle-id> <label>"
        case .accessibilityDenied:
            "Accessibility permission is not granted to KajiVMTestDriver"
        case .applicationNotFound(let identifier):
            "application is not running: \(identifier)"
        case .elementNotFound(let query):
            "accessible element not found: \(query)"
        case .ambiguousElement(let query, let count):
            "accessible query is ambiguous: \(query) matched \(count) controls"
        case .actionFailed(let error):
            "AXPress failed: \(error.rawValue)"
        }
    }
}

private struct ElementDescription {
    let role: String
    let subrole: String
    let identifier: String
    let label: String

    var line: String { "\(role)\t\(subrole)\t\(identifier)\t\(label)" }
}

private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return nil
}

private func children(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let children = value as? [AXUIElement] else {
        return []
    }
    return children
}

private func parent(of element: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
          let value else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}

private func supportsPress(_ element: AXUIElement) -> Bool {
    var actions: CFArray?
    guard AXUIElementCopyActionNames(element, &actions) == .success,
          let names = actions as? [String] else { return false }
    return names.contains(kAXPressAction)
}

private func describe(_ element: AXUIElement) -> ElementDescription {
    let role = stringAttribute(element, kAXRoleAttribute) ?? ""
    let subrole = stringAttribute(element, kAXSubroleAttribute) ?? ""
    let identifier = stringAttribute(element, kAXIdentifierAttribute) ?? ""
    let label = stringAttribute(element, kAXTitleAttribute)
        ?? stringAttribute(element, kAXDescriptionAttribute)
        ?? stringAttribute(element, kAXValueAttribute)
        ?? ""
    return ElementDescription(role: role, subrole: subrole, identifier: identifier, label: label)
}

private func walk(_ root: AXUIElement, visit: (AXUIElement, ElementDescription) -> Bool) -> AXUIElement? {
    var queue = [root]
    var seen = Set<CFHashCode>()
    var index = 0
    while index < queue.count, queue.count < 20_000 {
        let element = queue[index]
        index += 1
        guard seen.insert(CFHash(element)).inserted else { continue }
        if visit(element, describe(element)) { return element }
        queue.append(contentsOf: children(of: element))
    }
    return nil
}

private func applicationRoot(_ identifier: String) throws -> AXUIElement {
    let app = NSWorkspace.shared.runningApplications.first {
        $0.bundleIdentifier == identifier || $0.localizedName == identifier
    }
    guard let app else { throw DriverError.applicationNotFound(identifier) }
    return AXUIElementCreateApplication(app.processIdentifier)
}

private func matchingElement(
    application identifier: String,
    timeout: TimeInterval,
    matches: (ElementDescription) -> Bool
) throws -> AXUIElement {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let root = try applicationRoot(identifier)
        if let element = walk(root, visit: { _, description in matches(description) }) {
            return element
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw DriverError.elementNotFound(identifier)
}

private func requireAccessibility() throws {
    guard AXIsProcessTrusted() else { throw DriverError.accessibilityDenied }
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw DriverError.usage }
    if command == "request-trust" {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        print(AXIsProcessTrustedWithOptions(options) ? "true" : "false")
        return
    }
    if command == "trusted" {
        print(AXIsProcessTrusted() ? "true" : "false")
        return
    }
    try requireAccessibility()

    switch command {
    case "dump":
        guard arguments.count == 2 else { throw DriverError.usage }
        let root = try applicationRoot(arguments[1])
        _ = walk(root) { _, description in
            if !description.role.isEmpty || !description.identifier.isEmpty || !description.label.isEmpty {
                print(description.line)
            }
            return false
        }
    case "press-id", "press-label":
        guard arguments.count == 3 || arguments.count == 4 else { throw DriverError.usage }
        let timeout = arguments.count == 4 ? TimeInterval(arguments[3]) ?? 10 : 10
        let query = arguments[2]
        let element = try matchingElement(application: arguments[1], timeout: timeout) { description in
            command == "press-id" ? description.identifier == query : description.label == query
        }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else { throw DriverError.actionFailed(result) }
    case "press-near-label":
        guard arguments.count == 3 || arguments.count == 4 else { throw DriverError.usage }
        let timeout = arguments.count == 4 ? TimeInterval(arguments[3]) ?? 10 : 10
        let query = arguments[2]
        let label = try matchingElement(application: arguments[1], timeout: timeout) {
            $0.label == query
        }
        var ancestor = parent(of: label)
        var largestCandidateCount = 0
        for _ in 0..<6 {
            guard let current = ancestor else { break }
            var candidates: [AXUIElement] = []
            _ = walk(current) { element, description in
                let controlRoles = [kAXCheckBoxRole, kAXRadioButtonRole, kAXButtonRole, "AXSwitch"]
                if controlRoles.contains(description.role), supportsPress(element) {
                    candidates.append(element)
                }
                return false
            }
            largestCandidateCount = max(largestCandidateCount, candidates.count)
            if candidates.count == 1 {
                let result = AXUIElementPerformAction(candidates[0], kAXPressAction as CFString)
                guard result == .success else { throw DriverError.actionFailed(result) }
                return
            }
            ancestor = parent(of: current)
        }
        if largestCandidateCount > 1 {
            throw DriverError.ambiguousElement(query, largestCandidateCount)
        }
        throw DriverError.elementNotFound(query)
    case "set-subrole-value":
        guard arguments.count == 4 || arguments.count == 5 else { throw DriverError.usage }
        let timeout = arguments.count == 5 ? TimeInterval(arguments[4]) ?? 10 : 10
        let subrole = arguments[2]
        let element = try matchingElement(application: arguments[1], timeout: timeout) {
            $0.subrole == subrole
        }
        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            arguments[3] as CFString
        )
        guard result == .success else { throw DriverError.actionFailed(result) }
    case "count-label":
        guard arguments.count == 3 else { throw DriverError.usage }
        let root = try applicationRoot(arguments[1])
        var count = 0
        _ = walk(root) { _, description in
            if description.label == arguments[2] { count += 1 }
            return false
        }
        print(count)
    default:
        throw DriverError.usage
    }
}

do {
    try run()
} catch {
    fputs("vm-ui-driver: \(error)\n", stderr)
    exit(1)
}
