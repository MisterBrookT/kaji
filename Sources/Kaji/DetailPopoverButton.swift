import AppKit
import SwiftUI

/// An AppKit-backed detail affordance whose source view is also the exact
/// anchor rect used by the secondary `NSPopover`.
struct DetailPopoverButton: NSViewRepresentable {
    let accessibilityIdentifier: String
    let help: String
    let present: (NSView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(present: present)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: help)
        button.imagePosition = .imageOnly
        button.toolTip = help
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        button.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        button.target = context.coordinator
        button.action = #selector(Coordinator.activate(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.present = present
        button.toolTip = help
    }

    final class Coordinator: NSObject {
        var present: (NSView) -> Void

        init(present: @escaping (NSView) -> Void) {
            self.present = present
        }

        @objc func activate(_ sender: NSButton) {
            present(sender)
        }
    }
}
