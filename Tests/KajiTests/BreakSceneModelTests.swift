import XCTest
import KajiCore

final class BreakSceneModelTests: XCTestCase {
    func testSceneCatalog_containsOnlyWindowRain() {
        XCTAssertEqual(BreakSceneID.allCases, [.windowRain])
        XCTAssertEqual(BreakSceneID.windowRain.resourceName, "break-window-rain")
    }

    func testSelection_alwaysUsesWindowRain() {
        XCTAssertEqual(BreakSceneModel.scene(sessionSeed: 0), .windowRain)
        XCTAssertEqual(BreakSceneModel.scene(sessionSeed: 42), .windowRain)
        XCTAssertEqual(BreakSceneModel.scene(sessionSeed: .max), .windowRain)
    }


    func testMotionPolicy_respectsReduceMotion() {
        XCTAssertTrue(BreakSceneModel.allowsMotion(reduceMotion: false))
        XCTAssertFalse(BreakSceneModel.allowsMotion(reduceMotion: true))
    }

    func testSceneResource_isStable() {
        XCTAssertEqual(BreakSceneID.allCases.map(\.resourceName), ["break-window-rain"])
    }
}
