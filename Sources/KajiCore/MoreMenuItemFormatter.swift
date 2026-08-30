import Foundation

/// Builds the single-line label for a popover "More" menu item:
/// `Title` with no detail, or `Title · detail` when the module has a
/// live status worth showing. One `Text` per item — a two-line menu item
/// would be new to this codebase and would break the measured popover
/// chrome budget.
public enum MoreMenuItemFormatter {
    public static func label(title: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return title }
        return "\(title) · \(detail)"
    }
}