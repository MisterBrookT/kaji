import Foundation

public enum SleepControlLogic {
    public static func parseSleepDisabled(_ output: String) -> Bool {
        output
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let parts = line.split(whereSeparator: \.isWhitespace)
                return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
            }
    }

    public static func resolvedState(
        requested: Bool,
        commandSucceeded: Bool,
        observed: Bool
    ) -> Result<Bool, SleepControlError> {
        guard commandSucceeded else { return .failure(.commandFailed) }
        guard requested == observed else { return .failure(.stateMismatch(observed: observed)) }
        return .success(observed)
    }
}

public enum SleepControlError: Error, Equatable {
    case commandFailed
    case stateMismatch(observed: Bool)
}
