import XCTest
import KajiCore

/// Unit tests for mono-only theme prefs / resolve.
/// Spec cases: `dev_docs/specs/2026-07-24-mono-only.md` §5.
final class ThemePrefsLogicTests: XCTestCase {

    // MARK: - normalizeMenubarStyle (§5.1–5)

    func testNormalize_nil_yieldsBlackWhite() {
        XCTAssertEqual(ThemePrefsLogic.normalizeMenubarStyle(nil), "blackWhite")
    }

    func testNormalize_mono_yieldsBlackWhite() {
        XCTAssertEqual(ThemePrefsLogic.normalizeMenubarStyle("mono"), "blackWhite")
    }

    func testNormalize_color_yieldsBlackWhite() {
        XCTAssertEqual(ThemePrefsLogic.normalizeMenubarStyle("color"), "blackWhite")
    }

    func testNormalize_blackWhite_staysBlackWhite() {
        XCTAssertEqual(ThemePrefsLogic.normalizeMenubarStyle("blackWhite"), "blackWhite")
    }

    func testNormalize_unknown_yieldsBlackWhite() {
        XCTAssertEqual(ThemePrefsLogic.normalizeMenubarStyle("rainbow"), "blackWhite")
    }

    // MARK: - resolveTheme (§5.6–7)

    func testResolveTheme_light_isMonoLight() {
        let tokens = ThemePrefsLogic.resolveTheme(.light)
        XCTAssertEqual(tokens, ThemePrefsLogic.monoLight)
        XCTAssertEqual(tokens.bg, ThemePrefsLogic.monoLight.bg)
        XCTAssertEqual(tokens.gold, ThemePrefsLogic.monoLight.gold)
    }

    func testResolveTheme_dark_isMonoDark() {
        let tokens = ThemePrefsLogic.resolveTheme(.dark)
        XCTAssertEqual(tokens, ThemePrefsLogic.monoDark)
        XCTAssertEqual(tokens.bg, ThemePrefsLogic.monoDark.bg)
        XCTAssertEqual(tokens.gold, ThemePrefsLogic.monoDark.gold)
    }

    // MARK: - write-back (§5.8)

    func testWriteBack_color_needsRewriteToBlackWhite() {
        let raw = "color"
        let normalized = ThemePrefsLogic.normalizeMenubarStyle(raw)
        XCTAssertEqual(normalized, "blackWhite")
        XCTAssertTrue(ThemePrefsLogic.shouldRewriteMenubarStyle(raw))
        // After rewrite, stored value must be blackWhite and no further rewrite.
        XCTAssertFalse(ThemePrefsLogic.shouldRewriteMenubarStyle(normalized))
    }

    func testWriteBack_mono_needsRewriteToBlackWhite() {
        let raw = "mono"
        XCTAssertTrue(ThemePrefsLogic.shouldRewriteMenubarStyle(raw))
        XCTAssertEqual(ThemePrefsLogic.normalizeMenubarStyle(raw), "blackWhite")
    }

    func testWriteBack_missingKey_needsRewrite() {
        // nil key → treat as needing a canonical write of blackWhite.
        XCTAssertTrue(ThemePrefsLogic.shouldRewriteMenubarStyle(nil))
    }

    func testWriteBack_alreadyBlackWhite_noRewrite() {
        XCTAssertFalse(ThemePrefsLogic.shouldRewriteMenubarStyle("blackWhite"))
    }

    // MARK: - Optional B1: legacy style names never leave mono tokens

    func testResolve_neverCalmOrPlayfulGold() {
        // Calm/Playful golds from the old Palette (must not appear).
        let calmLightGold: UInt32 = 0x607D96
        let playfulLightGold: UInt32 = 0x2FAA5F
        let playfulDarkGold: UInt32 = 0x50C878

        for scheme in [ThemeScheme.light, .dark] {
            let gold = ThemePrefsLogic.resolveTheme(scheme).gold
            XCTAssertNotEqual(gold, calmLightGold)
            XCTAssertNotEqual(gold, playfulLightGold)
            XCTAssertNotEqual(gold, playfulDarkGold)
        }
        // Legacy menubar raw values still normalize to mono-only storage.
        for legacy in ["color", "mono"] {
            XCTAssertEqual(ThemePrefsLogic.normalizeMenubarStyle(legacy), "blackWhite")
        }
    }
}
