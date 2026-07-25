import XCTest
@testable import KajiCore

final class LocalizationTests: XCTestCase {
    func testEveryKeyHasNonEmptyTextInEverySupportedLanguage() {
        for key in L10n.K.allCases {
            for language in AppLanguage.allCases {
                XCTAssertFalse(
                    L10n.t(key, language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Missing \(language.rawValue) translation for \(key)"
                )
            }
        }
    }

    func testLanguageLabelsAreStableAndSelfNamed() {
        XCTAssertEqual(AppLanguage.en.label, "EN")
        XCTAssertEqual(AppLanguage.zh.label, "中文")
        XCTAssertEqual(AppLanguage.ptBR.label, "PT-BR")
        XCTAssertEqual(AppLanguage.es.label, "ES")
    }
}
