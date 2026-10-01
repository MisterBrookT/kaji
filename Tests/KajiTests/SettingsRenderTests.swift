import AppKit
import SwiftUI
import XCTest
import KajiCore
@testable import Kaji

@MainActor
final class SettingsRenderTests: XCTestCase {
    private func render(language: Lang, modulesOn: Bool, name: String,
                        section: SettingsSection = .general) throws {
        _ = NSApplication.shared
        let suite = "Kaji.SettingsRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Prefs(defaults: defaults)
        prefs.language = language
        if modulesOn {
            prefs.setModule(.work, enabled: true)
            prefs.setModule(.goals, enabled: true)
        }
        let sleep = SleepController(previewEnabled: true)
        for scheme in [ColorScheme.light, .dark] {
            let view = SettingsView(prefs: prefs, sleepController: sleep,
                                    fixedPlanStore: FixedPlanStore(defaults: defaults),
                                    updateChecker: UpdateChecker(currentVersion: "1.0.0"),
                                    initialSection: section)
                .environment(\.colorScheme, scheme)
            let image = try XCTUnwrap(renderImage(view, size: CGSize(width: 760, height: 590)))
            XCTAssertGreaterThan(image.pixelsWide, 0)
            let path = try XCTUnwrap(writePNG(image, name: "\(name)-\(scheme)"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        }
    }

    func testGeneralSettingsRenderInBothAppearances() throws {
        try render(language: .en, modulesOn: false, name: "settings-general")
    }

    func testChineseGeneralSettingsWithModulesRenderInBothAppearances() throws {
        try render(language: .zh, modulesOn: true, name: "settings-general-zh-modules")
    }

    func testChineseWorkAndPermissionsRenderInBothAppearances() throws {
        try render(language: .zh, modulesOn: true, name: "settings-work-zh", section: .work)
        try render(language: .zh, modulesOn: true, name: "settings-permissions-zh", section: .permissions)
    }

    func testSectionTitlesAreLocalizedWithoutEnglishInChinese() {
        let titles = SettingsSection.allCases.map { L10n.t($0.titleKey, .zh) }
        XCTAssertEqual(titles, ["常规", "工作", "用量", "授权"])
        for key in [L10n.K.moduleQuota, .moduleWork, .moduleGoals, .modulesHint, .on, .off,
                    .sleepHelperUpdateRequired, .updateSleepHelper, .sleepHelperUpdateHint] {
            XCTAssertNil(L10n.t(key, .zh).range(of: "[A-Za-z]", options: .regularExpression), "\(key)")
        }
    }

    func testRightColumnControlsShareFixedGeometry() {
        XCTAssertEqual(SettingsControlMetrics.width, 144)
        XCTAssertGreaterThanOrEqual(SettingsControlMetrics.height, 22)
    }
}
