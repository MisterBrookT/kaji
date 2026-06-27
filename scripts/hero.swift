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

            HStack(alignment: .center, spacing: 84) {
                copy
                    .frame(width: 610, alignment: .leading)

                VStack(alignment: .center, spacing: 34) {
                    PNGImage(path: "docs/menubar-light.png")
                        .frame(width: 520, height: 40)
                        .padding(.horizontal, 38)
                        .padding(.vertical, 26)
                        .background(card)

                    ZStack(alignment: .bottomTrailing) {
                        PNGImage(path: "docs/gauge-light.png")
                            .frame(width: 470, height: 414)
                            .padding(30)
                            .background(card)

                        PetMascot()
                            .frame(width: 164, height: 116)
                            .offset(x: 18, y: 24)
                    }
                }
                .frame(width: 560)
            }
            .padding(.horizontal, 96)
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

private struct PetMascot: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            speech
                .offset(x: -6, y: -12)

            ZStack {
                // Tail / body shadow.
                Capsule()
                    .fill(hex(0xD9D9D4))
                    .frame(width: 118, height: 54)
                    .rotationEffect(.degrees(-4))
                    .offset(x: -10, y: 36)

                Capsule()
                    .fill(hex(0xF7F7F3))
                    .frame(width: 118, height: 58)
                    .overlay(Capsule().stroke(hex(0x2B2B28), lineWidth: 4))
                    .rotationEffect(.degrees(-4))
                    .offset(x: -10, y: 31)

                // Head.
                Circle()
                    .fill(hex(0xF8F8F5))
                    .frame(width: 58, height: 58)
                    .overlay(Circle().stroke(hex(0x2B2B28), lineWidth: 4))
                    .offset(x: 44, y: 18)

                // Ears.
                Circle()
                    .fill(hex(0x2B2B28))
                    .frame(width: 22, height: 22)
                    .offset(x: 24, y: -4)
                Circle()
                    .fill(hex(0x2B2B28))
                    .frame(width: 22, height: 22)
                    .offset(x: 63, y: -2)

                // Eye patches.
                Capsule()
                    .fill(hex(0x2B2B28))
                    .frame(width: 18, height: 13)
                    .rotationEffect(.degrees(-22))
                    .offset(x: 34, y: 17)
                Capsule()
                    .fill(hex(0x2B2B28))
                    .frame(width: 18, height: 13)
                    .rotationEffect(.degrees(18))
                    .offset(x: 55, y: 17)

                Circle()
                    .fill(hex(0xF8F8F5))
                    .frame(width: 4, height: 4)
                    .offset(x: 37, y: 15)
                Circle()
                    .fill(hex(0xF8F8F5))
                    .frame(width: 4, height: 4)
                    .offset(x: 52, y: 15)

                // Nose / tired mouth.
                Circle()
                    .fill(hex(0x2B2B28))
                    .frame(width: 6, height: 5)
                    .offset(x: 45, y: 28)
                Path { p in
                    p.move(to: CGPoint(x: 84, y: 69))
                    p.addQuadCurve(to: CGPoint(x: 98, y: 69),
                                   control: CGPoint(x: 91, y: 75))
                }
                .stroke(hex(0x2B2B28), lineWidth: 2)

                // Front paw hanging over the card.
                Capsule()
                    .fill(hex(0x2B2B28))
                    .frame(width: 38, height: 16)
                    .rotationEffect(.degrees(-8))
                    .offset(x: 36, y: 60)

                // Token battery tag.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hex(0xFFFFFF))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(hex(0x2B2B28), lineWidth: 2))
                    .frame(width: 44, height: 22)
                    .overlay(
                        Text("15%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(hex(0x2B2B28))
                    )
                    .offset(x: -30, y: 4)
            }
            .offset(x: 12, y: 28)
        }
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("15% tokens")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text("need recharge")
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundColor(hex(0x2B2B28))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hex(0xFFFFFF))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(hex(0xDADAD6), lineWidth: 1.5)
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 5)
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
