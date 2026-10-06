import XCTest
import KajiCore
@testable import Kaji

@MainActor
final class WorkWatchdogLifecycleTests: XCTestCase {
    func testWatchdogRunsOnlyWhileWorkModuleEnabled() {
        let suite = "work-watchdog-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let delegate = AppDelegate(defaults: defaults)
        XCTAssertFalse(delegate.isBreakWatchdogRunning)
        delegate.applyModuleLifecycle([.work])
        XCTAssertTrue(delegate.isBreakWatchdogRunning)
        delegate.applyModuleLifecycle([])
        XCTAssertFalse(delegate.isBreakWatchdogRunning)
    }
}
