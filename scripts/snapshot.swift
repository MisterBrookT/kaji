import SwiftUI
import AppKit

@MainActor
func render(_ view: some View, appearance name: NSAppearance.Name,
            scheme: ColorScheme, to path: String) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
    renderer.scale = 2
    var image: NSImage?
    if let app = NSAppearance(named: name) {
        app.performAsCurrentDrawingAppearance { image = renderer.nsImage }
    } else {
        image = renderer.nsImage
    }
    guard let img = image,
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed: \(path)"); return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) size=\(img.size)")
}

@main
struct Snap {
    @MainActor
    static func makeMocks() -> [ProviderView] {
        [
            ProviderView(id: "claude", mark: "", displayName: "Claude",
                         fiveHourPercent: 56, weekPercent: 36, tokensToday: 120_000,
                         resetDate: Date(timeIntervalSinceNow: 72 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 38 * 3600),
                         plan: "max",
                         history: [20, 28, 22, 40, 55, 48, 60, 52, 68, 56]),
            ProviderView(id: "codex", mark: "", displayName: "Codex",
                         fiveHourPercent: 82, weekPercent: 64, tokensToday: 90_000,
                         resetDate: Date(timeIntervalSinceNow: 47 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 5 * 24 * 3600),
                         plan: "plus",
                         history: [30, 45, 50, 62, 70, 75, 80, 78, 85, 82]),
        ]
    }

    @MainActor
    static func makePrefs(_ lang: Lang) -> Prefs {
        let p = Prefs()
        p.language = lang
        p.visibleProviders = ["claude", "codex"]
        p.showCenterNumber = true
        return p
    }

    static func main() {
        MainActor.assumeIsolated {
            let mocks = makeMocks()
            let lang: Lang = (CommandLine.arguments.contains("zh")) ? .zh : .en
            let prefs = makePrefs(lang)

            let panel = GaugeRowView(store: QuotaStore(previewProviders: mocks, updated: Date()),
                                     prefs: prefs)
            let popover = GaugeRowView(
                store: QuotaStore(previewProviders: mocks, updated: Date()),
                prefs: prefs,
                controls: .init(panelVisible: false, onTogglePanel: {}, onQuit: {})
            )
            // Menubar item mock: two concentric dual-rings on a menubar-ish strip.
            func statusStrip(_ scheme: ColorScheme) -> some View {
                HStack(spacing: 14) {
                    StatusItemView(providers: mocks, showCenterNumber: true)
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(scheme == .dark ? Color(hex: 0x2A2622) : Color(hex: 0xEDEAE3))
            }

            let arg = CommandLine.arguments.dropFirst().first ?? "both"
            if arg == "dark" || arg == "both" {
                render(panel, appearance: .darkAqua, scheme: .dark, to: "/tmp/gauge-dark.png")
                render(statusStrip(.dark), appearance: .darkAqua, scheme: .dark, to: "/tmp/status-dark.png")
                render(popover, appearance: .darkAqua, scheme: .dark, to: "/tmp/popover-dark.png")
            }
            if arg == "light" || arg == "both" {
                render(panel, appearance: .aqua, scheme: .light, to: "/tmp/gauge-light.png")
                render(statusStrip(.light), appearance: .aqua, scheme: .light, to: "/tmp/status-light.png")
                render(popover, appearance: .aqua, scheme: .light, to: "/tmp/popover-light.png")
            }
        }
    }
}
