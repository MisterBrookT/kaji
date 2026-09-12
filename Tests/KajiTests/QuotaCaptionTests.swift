import AppKit
import XCTest
@testable import KajiCore

/// Regression: a provider with NO reading rendered exactly like one at 0%.
///
/// Claude's OAuth token was being discarded locally, so `quota.py` returned no
/// limits at all. The popover drew an empty bar and the ring math treated the
/// missing percentage as `0`, which reads as "plenty of quota left" — the
/// opposite of the truth, and it hid a broken sign-in indefinitely.
///
/// The contract these tests pin down: `nil` is never formatted as a number,
/// and callers can always ask whether a reading exists.
final class QuotaCaptionTests: XCTestCase {

    func testMissingPercentIsNotZero() {
        XCTAssertEqual(QuotaCaption.percent(nil), "\u{2014}")
        XCTAssertNotEqual(QuotaCaption.percent(nil), "0%")
    }

    func testRealZeroStillRendersAsZero() {
        XCTAssertEqual(QuotaCaption.percent(0), "0%")
    }

    func testPercentRounds() {
        XCTAssertEqual(QuotaCaption.percent(78.4), "78%")
        XCTAssertEqual(QuotaCaption.percent(95.6), "96%")
        XCTAssertEqual(QuotaCaption.percent(100), "100%")
    }

    func testHasReadingDistinguishesNilFromZero() {
        XCTAssertFalse(QuotaCaption.hasReading(nil))
        XCTAssertTrue(QuotaCaption.hasReading(0))
        XCTAssertTrue(QuotaCaption.hasReading(96))
    }

    func testNonFiniteIsNotAReading() {
        XCTAssertFalse(QuotaCaption.hasReading(.nan))
        XCTAssertFalse(QuotaCaption.hasReading(.infinity))
    }

    /// Cursor labels its windows "API" / "Auto" instead of "5h" / "7d". The
    /// label column must fit the longest of them on one line: a 18pt slot
    /// wrapped "Auto" and knocked the whole row out of alignment.
    func testWindowLabelColumnFitsWordLabels() {
        XCTAssertGreaterThanOrEqual(QuotaCaption.windowLabelWidth, 26)
        for label in ["5h", "7d", "API", "Auto"] {
            let width = label.size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold)
            ]).width
            XCTAssertLessThanOrEqual(
                width, QuotaCaption.windowLabelWidth,
                "\(label) does not fit the window-label column")
        }
    }

    /// The caption must say something actionable, not an em dash that looks
    /// like a styling choice.
    func testUnavailableCaptionNamesTheCause() {
        XCTAssertTrue(QuotaCaption.unavailable.contains("no data"))
        XCTAssertFalse(QuotaCaption.unavailable.isEmpty)
    }
}
