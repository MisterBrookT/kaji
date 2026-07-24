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

/// README / landing hero — Mono, compact, website feel.
struct HeroView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [hex(0xFFFFFF), hex(0xF7F7F4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(alignment: .center, spacing: 48) {
                copy
                    .frame(width: 480, alignment: .leading)

                productStage
                    .frame(width: 520)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 56)
        }
        .frame(width: 1280, height: 760)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark: Koina-style cat-K fused into "Kaji"
            HStack(alignment: .center, spacing: 2) {
                PNGImage(path: "dev_docs/assets/kaji-cat-k.png")
                    .frame(width: 78, height: 78)
                    .offset(y: -2)

                Text("aji")
                    .font(.system(size: 78, weight: .bold, design: .rounded))
                    .foregroundColor(hex(0x20201D))
                    .padding(.leading, -4)
            }
            .padding(.bottom, 18)

            Text("The menu bar worth keeping\nfor AI coding.")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundColor(hex(0x20201D))
                .lineSpacing(3)
                .padding(.bottom, 14)

            Text("Quota rings at a glance. Assemble the rest only when you need it.")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(hex(0x70706A))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 26)

            HStack(spacing: 12) {
                pill("quiet", filled: true)
                pill("scalable", filled: false)
                pill("beautiful", filled: false)
            }
            .padding(.bottom, 56)

            metric("5h", "Session window")
            metric("7d", "Weekly reset")
            metric("More", "Breaker · system monitor · and more…")
        }
    }

    private func metric(_ label: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(hex(0x666660))
                .frame(width: 72, alignment: .leading)
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(hex(0x20201D))
        }
        .padding(.bottom, 20)
    }

    private func pill(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(filled ? .white : hex(0x20201D))
            .padding(.horizontal, 22)
            .frame(height: 44)
            .background(filled ? hex(0x666660) : Color.white.opacity(0.9))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(hex(0xDADAD6), lineWidth: filled ? 0 : 1.25))
    }

    private var productStage: some View {
        VStack(alignment: .center, spacing: 16) {
            PNGImage(path: "dev_docs/assets/menubar-light.png")
                .frame(width: 460, height: 34)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(hex(0xE4E4DE), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)
                )

            PNGImage(path: "dev_docs/assets/gauge-light.png")
                .frame(width: 360)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 14)
        }
    }
}

@MainActor
func renderHero(to path: String) {
    let renderer = ImageRenderer(content: HeroView())
    renderer.scale = 2
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
            let out = CommandLine.arguments.dropFirst().first ?? "dev_docs/assets/hero.png"
            renderHero(to: out)
        }
    }
}
