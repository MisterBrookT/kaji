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
            ProviderView(id: "claude", mark: "", displayName: "Claude Code",
                         fiveHourPercent: 56, weekPercent: 36, tokensToday: 120_000,
                         resetDate: Date(timeIntervalSinceNow: 72 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 38 * 3600),
                         plan: "plan",
                         history: [20, 28, 22, 40, 55, 48, 60, 52, 68, 56]),
            ProviderView(id: "codex", mark: "", displayName: "Codex",
                         fiveHourPercent: 82, weekPercent: 64, tokensToday: 90_000,
                         resetDate: Date(timeIntervalSinceNow: 47 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 5 * 24 * 3600),
                         plan: "plus",
                         history: [30, 45, 50, 62, 70, 75, 80, 78, 85, 82]),
            ProviderView(id: "ark-agent", mark: "", displayName: "Ark Agent",
                         fiveHourPercent: 0, weekPercent: 87, tokensToday: 12_000,
                         resetDate: nil,
                         weekResetDate: Date(timeIntervalSinceNow: 13 * 3600),
                         plan: "team",
                         history: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            ProviderView(id: "minimax", mark: "", displayName: "MiniMax",
                         fiveHourPercent: 69, weekPercent: 17, tokensToday: 42_000,
                         resetDate: Date(timeIntervalSinceNow: 22 * 60),
                         weekResetDate: Date(timeIntervalSinceNow: 14 * 3600),
                         plan: "plan",
                         history: [10, 15, 20, 28, 38, 46, 54, 61, 66, 69]),
        ]
    }

    @MainActor
    static func makePrefs(_ lang: Lang, style: MenubarStyle, showRemaining: Bool) -> Prefs {
        let p = Prefs()
        p.language = lang
        p.visibleProviders = ["claude", "codex", "ark-agent", "minimax"]
        p.menubarStyle = style
        p.showRemaining = showRemaining
        p.panelSize = .medium
        return p
    }

    static func main() {
        MainActor.assumeIsolated {
            let mocks = makeMocks()
            let args = Array(CommandLine.arguments.dropFirst())
            let lang: Lang = args.contains("zh") ? .zh : .en
            let showRemaining = args.contains("remaining")
            let style: MenubarStyle
            if args.contains("playful") || args.contains("color") {
                style = .color
            } else if args.contains("calm") || args.contains("blue") || args.contains("mono") {
                style = .mono
            } else {
                style = .blackWhite
            }
            let prefs = makePrefs(lang, style: style, showRemaining: showRemaining)

            let panel = GaugeRowView(store: QuotaStore(previewProviders: mocks, updated: Date()),
                                     prefs: prefs,
                                     updateChecker: UpdateChecker(),
                                     sleepController: SleepController(),
                                     panelSize: prefs.panelSize)
            let popover = GaugeRowView(
                store: QuotaStore(previewProviders: mocks, updated: Date()),
                prefs: prefs,
                updateChecker: UpdateChecker(),
                sleepController: SleepController(),
                controls: .init(onRefresh: {}, onUpdate: {}, onToggleKeepAwake: {}, onQuit: {}),
                panelSize: prefs.panelSize
            )
            // Menu-bar right cluster mock: the Kaji dual-rings sitting among the
            // real system status items (control center, wifi, battery, clock) so
            // the README shows the app *in the menu bar*, not floating on grey.
            func statusStrip(_ scheme: ColorScheme, _ mbStyle: MenubarStyle = .blackWhite) -> some View {
                let glyph: Color = scheme == .dark
                    ? Color.white.opacity(0.82) : Color.black.opacity(0.78)
                func sys(_ name: String, _ size: CGFloat = 14) -> some View {
                    Image(systemName: name)
                        .font(.system(size: size, weight: .regular))
                        .foregroundColor(glyph)
                }
                return HStack(spacing: 13) {
                    StatusItemView(providers: mocks, style: mbStyle, showRemaining: showRemaining)
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
                            ? LinearGradient(colors: [Color(hex: 0x2C2C2A), Color(hex: 0x1E1E1C)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(hex: 0xF7F5F1), Color(hex: 0xE7E1D6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                )
            }

            let arg = args.first ?? "both"
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
