import Foundation

public let kajiSleepHelperMachService = "dev.kaji.sleep-helper"

@objc public protocol SleepHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool, String?) -> Void)
}
