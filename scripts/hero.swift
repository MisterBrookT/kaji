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
                            .frame(width: 390, height: 344)
                            .padding(26)
                            .background(card)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        PetMascot()
                            .frame(width: 210, height: 170)
                            .offset(x: -70, y: 0)
                    }
                    .frame(width: 620, height: 570, alignment: .topLeading)
                }
                .frame(width: 620)
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
        ZStack(alignment: .topLeading) {
            speech
                .offset(x: 72, y: 78)
                .zIndex(2)

            ZStack {
                shadow
                pandaBody
                hindLeg
                head
                ears
                eyePatches
                face
                paws
                tokenTag
            }
            .offset(x: 20, y: 54)
            .zIndex(1)
        }
    }

    private var shadow: some View {
        Ellipse()
            .fill(.black.opacity(0.09))
            .frame(width: 150, height: 24)
            .offset(x: 20, y: 104)
    }

    private var pandaBody: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 22, y: 88))
                p.addCurve(to: CGPoint(x: 40, y: 44),
                           control1: CGPoint(x: 16, y: 64),
                           control2: CGPoint(x: 22, y: 48))
                p.addCurve(to: CGPoint(x: 118, y: 38),
                           control1: CGPoint(x: 62, y: 31),
                           control2: CGPoint(x: 94, y: 30))
                p.addCurve(to: CGPoint(x: 154, y: 74),
                           control1: CGPoint(x: 139, y: 45),
                           control2: CGPoint(x: 154, y: 54))
                p.addCurve(to: CGPoint(x: 129, y: 111),
                           control1: CGPoint(x: 157, y: 94),
                           control2: CGPoint(x: 150, y: 108))
                p.addCurve(to: CGPoint(x: 42, y: 112),
                           control1: CGPoint(x: 94, y: 117),
                           control2: CGPoint(x: 55, y: 116))
                p.addCurve(to: CGPoint(x: 22, y: 88),
                           control1: CGPoint(x: 30, y: 108),
                           control2: CGPoint(x: 24, y: 101))
            }
            .fill(hex(0xF9F9F5))
            .overlay(
                Path { p in
                    p.move(to: CGPoint(x: 22, y: 88))
                    p.addCurve(to: CGPoint(x: 40, y: 44),
                               control1: CGPoint(x: 16, y: 64),
                               control2: CGPoint(x: 22, y: 48))
                    p.addCurve(to: CGPoint(x: 118, y: 38),
                               control1: CGPoint(x: 62, y: 31),
                               control2: CGPoint(x: 94, y: 30))
                    p.addCurve(to: CGPoint(x: 154, y: 74),
                               control1: CGPoint(x: 139, y: 45),
                               control2: CGPoint(x: 154, y: 54))
                    p.addCurve(to: CGPoint(x: 129, y: 111),
                               control1: CGPoint(x: 157, y: 94),
                               control2: CGPoint(x: 150, y: 108))
                    p.addCurve(to: CGPoint(x: 42, y: 112),
                               control1: CGPoint(x: 94, y: 117),
                               control2: CGPoint(x: 55, y: 116))
                    p.addCurve(to: CGPoint(x: 22, y: 88),
                               control1: CGPoint(x: 30, y: 108),
                               control2: CGPoint(x: 24, y: 101))
                }
                .stroke(hex(0x2B2B28), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            )

            Capsule()
                .fill(hex(0x2B2B28))
                .frame(width: 82, height: 25)
                .rotationEffect(.degrees(-2))
                .offset(x: 35, y: 88)
        }
    }

    private var hindLeg: some View {
        Capsule()
            .fill(hex(0x2B2B28))
            .frame(width: 46, height: 25)
            .rotationEffect(.degrees(-12))
            .offset(x: 106, y: 102)
    }

    private var head: some View {
        Ellipse()
            .fill(hex(0xF9F9F5))
            .frame(width: 76, height: 68)
            .overlay(Ellipse().stroke(hex(0x2B2B28), lineWidth: 4))
            .offset(x: 104, y: 32)
    }

    private var ears: some View {
        ZStack {
            Circle()
                .fill(hex(0x2B2B28))
                .frame(width: 27, height: 27)
                .offset(x: 101, y: 23)
            Circle()
                .fill(hex(0x2B2B28))
                .frame(width: 27, height: 27)
                .offset(x: 157, y: 23)
            Circle()
                .fill(hex(0xF9F9F5))
                .frame(width: 13, height: 13)
                .offset(x: 101, y: 23)
            Circle()
                .fill(hex(0xF9F9F5))
                .frame(width: 13, height: 13)
                .offset(x: 157, y: 23)
        }
    }

    private var eyePatches: some View {
        ZStack {
            Capsule()
                .fill(hex(0x2B2B28))
                .frame(width: 24, height: 17)
                .rotationEffect(.degrees(-24))
                .offset(x: 119, y: 54)
            Capsule()
                .fill(hex(0x2B2B28))
                .frame(width: 24, height: 17)
                .rotationEffect(.degrees(22))
                .offset(x: 145, y: 54)
        }
    }

    private var face: some View {
        ZStack {
            Circle()
                .fill(hex(0xF9F9F5))
                .frame(width: 4, height: 4)
                .offset(x: 122, y: 52)
            Circle()
                .fill(hex(0xF9F9F5))
                .frame(width: 4, height: 4)
                .offset(x: 142, y: 52)
            Ellipse()
                .fill(hex(0x2B2B28))
                .frame(width: 9, height: 7)
                .offset(x: 132, y: 64)
            Path { p in
                p.move(to: CGPoint(x: 128, y: 73))
                p.addQuadCurve(to: CGPoint(x: 136, y: 73),
                               control: CGPoint(x: 132, y: 78))
            }
            .stroke(hex(0x2B2B28), lineWidth: 2)
        }
    }

    private var paws: some View {
        ZStack {
            Capsule()
                .fill(hex(0x2B2B28))
                .frame(width: 48, height: 18)
                .rotationEffect(.degrees(-5))
                .offset(x: 58, y: 112)
            Capsule()
                .fill(hex(0x2B2B28))
                .frame(width: 38, height: 18)
                .rotationEffect(.degrees(-18))
                .offset(x: 134, y: 116)
        }
    }

    private var tokenTag: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(hex(0xFFFFFF))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(hex(0x2B2B28), lineWidth: 2))
            .frame(width: 48, height: 24)
            .overlay(
                Text("15%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(hex(0x2B2B28))
            )
            .offset(x: 52, y: 52)
    }

    private var speech: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("15% tokens")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text("need recharge")
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundColor(hex(0x2B2B28))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
