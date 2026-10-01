import AppKit
import SwiftUI
import XCTest
@testable import Kaji

@MainActor
final class SettingsRenderTests: XCTestCase {
    func testGeneralSettingsRenderInBothAppearances() throws {
        _ = NSApplication.shared
        let suite = "Kaji.SettingsRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Prefs(defaults: defaults)
        let sleep = SleepController(previewEnabled: true)
        for scheme in [ColorScheme.light, .dark] {
            let view = SettingsView(prefs: prefs, sleepController: sleep,
                                    fixedPlanStore: FixedPlanStore(defaults: defaults))
                .environment(\.colorScheme, scheme)
            let image = try XCTUnwrap(renderImage(view, size: CGSize(width: 760, height: 590)))
            XCTAssertGreaterThan(image.pixelsWide, 0)
            let path = try XCTUnwrap(writePNG(image, name: "settings-general-\(scheme)"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        }
    }
}
