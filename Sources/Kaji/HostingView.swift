import AppKit
import SwiftUI

final class KajiHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

final class KajiHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = KajiHostingView(rootView: rootView)
    }
}

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
