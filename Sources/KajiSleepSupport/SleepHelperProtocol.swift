import Foundation

public let kajiSleepHelperMachService = "dev.kaji.sleep-helper"

public enum SleepLeaseRestoration {
    public static func parseMarker(_ data: Data) -> Bool? {
        if data == Data("0".utf8) { return false }
        if data == Data("1".utf8) { return true }
        return nil
    }

    // A user may change pmset during our lease; never undo their subsequent edit.
    public static func parsePmsetState(_ output: String) -> Bool? {
        let values = output.split(whereSeparator: \.isNewline).compactMap { line -> Bool? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0] == "SleepDisabled" else { return nil }
            if fields[1] == "0" { return false }
            if fields[1] == "1" { return true }
            return nil
        }
        return values.count == 1 ? values[0] : nil
    }

    public static func target(saved: Bool, current: Bool) -> Bool? {
        saved == false && current == true ? false : nil
    }

    public static func acceptsCodeHash(_ value: String) -> Bool {
        value.count == 40 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }
}

@objc public protocol SleepHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool, String?) -> Void)
    func renewLease(reply: @escaping (Bool) -> Void)
}
