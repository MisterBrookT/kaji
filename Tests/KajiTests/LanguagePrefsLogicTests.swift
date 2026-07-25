import XCTest
@testable import KajiCore

final class LanguagePrefsLogicTests: XCTestCase {
    func testFreshInstallDefaultsToEnglishRegardlessOfSystemLanguage() {
        let result = LanguagePrefsLogic.resolve(
            storedRawValue: nil,
            hadExistingPreferences: false,
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(result.language, .en)
        XCTAssertTrue(result.shouldPersist)
    }

    func testExistingEnglishSelectionIsPreserved() {
        let result = LanguagePrefsLogic.resolve(
            storedRawValue: "en",
            hadExistingPreferences: true,
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(result.language, .en)
        XCTAssertFalse(result.shouldPersist)
    }

    func testExistingChineseSelectionIsPreserved() {
        let result = LanguagePrefsLogic.resolve(
            storedRawValue: "zh",
            hadExistingPreferences: true,
            preferredLanguages: ["en-US"]
        )

        XCTAssertEqual(result.language, .zh)
        XCTAssertFalse(result.shouldPersist)
    }

    func testExistingInstallWithoutLanguageMigratesLegacyChineseChoice() {
        let result = LanguagePrefsLogic.resolve(
            storedRawValue: nil,
            hadExistingPreferences: true,
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(result.language, .zh)
        XCTAssertTrue(result.shouldPersist)
    }

    func testExistingInstallWithoutLanguageMigratesLegacyNonChineseChoice() {
        let result = LanguagePrefsLogic.resolve(
            storedRawValue: nil,
            hadExistingPreferences: true,
            preferredLanguages: ["pt-BR"]
        )

        XCTAssertEqual(result.language, .en)
        XCTAssertTrue(result.shouldPersist)
    }

    func testUnknownStoredValueFallsBackToEnglish() {
        let result = LanguagePrefsLogic.resolve(
            storedRawValue: "broken",
            hadExistingPreferences: true,
            preferredLanguages: ["zh-Hans-CN"]
        )

        XCTAssertEqual(result.language, .en)
        XCTAssertTrue(result.shouldPersist)
    }

    func testAllFourSupportedValuesRoundTrip() {
        for language in AppLanguage.allCases {
            let result = LanguagePrefsLogic.resolve(
                storedRawValue: language.rawValue,
                hadExistingPreferences: true,
                preferredLanguages: []
            )
            XCTAssertEqual(result.language, language)
            XCTAssertFalse(result.shouldPersist)
        }
    }
}
