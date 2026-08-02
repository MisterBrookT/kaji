import XCTest
import KajiCore

final class BreakSceneModelTests: XCTestCase {
    func testSceneCatalog_containsFourApprovedScenes() {
        XCTAssertEqual(
            BreakSceneID.allCases,
            [.windowRain, .rainField, .mistHill, .sunlitMeadow]
        )
    }

    func testSelection_isStableForSameSessionSeed() {
        let first = BreakSceneModel.scene(sessionSeed: 42)
        let second = BreakSceneModel.scene(sessionSeed: 42)

        XCTAssertEqual(first, second)
    }

    func testSelection_wrapsAcrossCatalog() {
        XCTAssertEqual(BreakSceneModel.scene(sessionSeed: 0), .windowRain)
        XCTAssertEqual(BreakSceneModel.scene(sessionSeed: 1), .rainField)
        XCTAssertEqual(BreakSceneModel.scene(sessionSeed: 2), .mistHill)
        XCTAssertEqual(BreakSceneModel.scene(sessionSeed: 3), .sunlitMeadow)
        XCTAssertEqual(BreakSceneModel.scene(sessionSeed: 4), .windowRain)
    }

    func testMotionPolicy_respectsReduceMotion() {
        XCTAssertTrue(BreakSceneModel.allowsMotion(reduceMotion: false))
        XCTAssertFalse(BreakSceneModel.allowsMotion(reduceMotion: true))
    }

    func testSceneResources_areStableAndUnique() {
        let names = BreakSceneID.allCases.map(\.resourceName)

        XCTAssertEqual(
            names,
            [
                "break-window-rain",
                "break-rain-field",
                "break-mist-hill",
                "break-sunlit-meadow"
            ]
        )
        XCTAssertEqual(Set(names).count, BreakSceneID.allCases.count)
    }
}
