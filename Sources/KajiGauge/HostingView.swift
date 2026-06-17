import AppKit

// Shared AppKit host setup for SwiftUI surfaces.
extension NSView {
    func configureKajiHost(cornerRadius: CGFloat? = nil) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        if let cornerRadius {
            layer?.cornerRadius = cornerRadius
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
        }
    }
}
