import AppKit
import ApplicationServices
let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func walk(_ e: AXUIElement, _ d: Int = 0, _ f: (AXUIElement) -> Bool) -> AXUIElement? {
    if f(e) { return e }; if d > 40 { return nil }
    for k in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { if let r = walk(k, d+1, f) { return r } }
    for k in (attr(e, "AXExtrasMenuBar").map { [$0 as! AXUIElement] } ?? []) where d == 0 { if let r = walk(k, d+1, f) { return r } }
    return nil
}
func id(_ e: AXUIElement) -> String { attr(e, "AXIdentifier") as? String ?? "" }
let cmd = CommandLine.arguments[2], target = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
print("trusted:", AXIsProcessTrusted())
if cmd == "dump" {
    func d(_ e: AXUIElement, _ n: Int) { let i = id(e); let t = (attr(e,"AXValue") as? String) ?? (attr(e,"AXTitle") as? String) ?? (attr(e,"AXDescription") as? String) ?? ""; if !i.isEmpty || !t.isEmpty { print(String(repeating:" ",count:n), attr(e,"AXRole") ?? "", i, t) }; if n < 60 { for k in (attr(e,"AXChildren") as? [AXUIElement]) ?? [] { d(k, n+1) } } }
    d(app, 0); if let m = attr(app, "AXExtrasMenuBar") { d(m as! AXUIElement, 0) }
} else if let e = walk(app, 0, { id($0) == target }) {
    print("press", target, AXUIElementPerformAction(e, kAXPressAction as CFString).rawValue)
} else { print("notfound", target); exit(2) }
