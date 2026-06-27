import SwiftUI
import AppKit

private func hex(_ v: UInt32) -> Color {
    Color(.sRGB,
          red: Double((v >> 16) & 0xFF) / 255,
          green: Double((v >> 8) & 0xFF) / 255,
          blue: Double(v & 0xFF) / 255,
          opacity: 1)
}

private struct PNGImage: View {
    let path: String

    var body: some View {
        if let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Color.clear
        }
    }
}

struct HeroView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [hex(0xFFFFFF), hex(0xF8F8F6)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)

            HStack(alignment: .center, spacing: 50) {
                copy
                    .frame(width: 545, alignment: .leading)

                VStack(alignment: .center, spacing: 24) {
                    statusCard
                    productCard
                    petSticker
                }
                .frame(width: 650)
            }
            .padding(.horizontal, 70)
        }
        .frame(width: 1400, height: 800)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Kaji")
                .font(.system(size: 86, weight: .bold, design: .rounded))
                .foregroundColor(hex(0x20201D))
                .padding(.bottom, 16)

            Text("A quiet menu bar for AI coding usage.")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundColor(hex(0x20201D))
                .padding(.bottom, 18)

            Text("Local-first quota rings across AI coding vendors.")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(hex(0x70706A))
                .padding(.bottom, 30)

            HStack(spacing: 22) {
                pill("Mono default", filled: true)
                pill("Status layer", filled: false)
            }
            .padding(.bottom, 108)

            metric("5h", "Live quota window")
            metric("7d", "Weekly reset time")
            metric("Pet", "State bridge")
        }
    }

    private func metric(_ label: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(label)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(hex(0x666660))
                .frame(width: 58, alignment: .leading)
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(hex(0x20201D))
        }
        .padding(.bottom, 30)
    }

    private func pill(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundColor(filled ? .white : hex(0x20201D))
            .frame(width: filled ? 235 : 245, height: 54)
            .background(filled ? hex(0x666660) : hex(0xF8F8F6))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(hex(0xDADAD6), lineWidth: filled ? 0 : 1.5))
    }

    private var statusCard: some View {
        PNGImage(path: "docs/menubar-light.png")
            .frame(width: 520, height: 39)
            .frame(width: 600, height: 82)
            .background(card)
    }

    private var productCard: some View {
        PNGImage(path: "docs/gauge-light.png")
            .frame(width: 500, height: 440)
            .frame(width: 600, height: 480)
            .background(card)
    }

    private var petSticker: some View {
        PNGImage(path: "docs/pet-panda.png")
            .frame(width: 285, height: 164)
            .frame(width: 600, height: 164, alignment: .trailing)
            .padding(.top, -2)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(hex(0xFFFFFF).opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(hex(0xDADAD6), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.045), radius: 28, x: 0, y: 20)
    }
}

@MainActor
func renderHero(to path: String) {
    let renderer = ImageRenderer(content: HeroView())
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) size=\(image.size)")
}

@main
struct HeroMain {
    static func main() {
        MainActor.assumeIsolated {
            let out = CommandLine.arguments.dropFirst().first ?? "docs/hero.png"
            renderHero(to: out)
        }
    }
}
