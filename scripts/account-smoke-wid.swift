import AppKit
let pid = Int(CommandLine.arguments[1])!
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
if let w = l.first(where: { ($0["kCGWindowOwnerPID"] as? Int) == pid && ($0["kCGWindowLayer"] as? Int) == 25 && (($0["kCGWindowBounds"] as? [String:CGFloat])?["Height"] ?? 0) > 100 }) { print(w["kCGWindowNumber"]!) }
