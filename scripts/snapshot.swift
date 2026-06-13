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
        p.menubarStyle = .mono
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
            // Menu-bar right cluster mock: the Kaji dual-rings sitting among the
            // real system status items (control center, wifi, battery, clock) so
            // the README shows the app *in the menu bar*, not floating on grey.
            func statusStrip(_ scheme: ColorScheme, _ mbStyle: MenubarStyle = .mono) -> some View {
                let glyph: Color = scheme == .dark
                    ? Color.white.opacity(0.82) : Color.black.opacity(0.78)
                func sys(_ name: String, _ size: CGFloat = 14) -> some View {
                    Image(systemName: name)
                        .font(.system(size: size, weight: .regular))
                        .foregroundColor(glyph)
                }
                return HStack(spacing: 13) {
                    StatusItemView(providers: mocks, style: mbStyle)
                    sys("switch.2", 13)
                    sys("wifi", 13)
                    sys("battery.75", 16)
                    Text("Thu 13 Jun  9:41")
                        .font(.system(size: 13.5))
                        .foregroundColor(glyph)
                }
                .padding(.leading, 16).padding(.trailing, 14)
                .frame(height: 26)
                .background(
                    // A subtle translucent menu-bar slab over a hint of wallpaper.
                    ZStack {
                        (scheme == .dark
                            ? LinearGradient(colors: [Color(hex: 0x3A332B), Color(hex: 0x2A2622)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(hex: 0xF4F1EB), Color(hex: 0xE7E2D9)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                )
            }

            let arg = CommandLine.arguments.dropFirst().first ?? "both"
            if arg == "dark" || arg == "both" {
                render(panel, appearance: .darkAqua, scheme: .dark, to: "/tmp/gauge-dark.png")
                render(statusStrip(.dark), appearance: .darkAqua, scheme: .dark, to: "/tmp/status-dark.png")
                render(statusStrip(.dark, .color), appearance: .darkAqua, scheme: .dark, to: "/tmp/status-color-dark.png")
                render(popover, appearance: .darkAqua, scheme: .dark, to: "/tmp/popover-dark.png")
            }
            if arg == "light" || arg == "both" {
                render(panel, appearance: .aqua, scheme: .light, to: "/tmp/gauge-light.png")
                render(statusStrip(.light), appearance: .aqua, scheme: .light, to: "/tmp/status-light.png")
                render(statusStrip(.light, .color), appearance: .aqua, scheme: .light, to: "/tmp/status-color-light.png")
                render(popover, appearance: .aqua, scheme: .light, to: "/tmp/popover-light.png")
            }
        }
    }
}
