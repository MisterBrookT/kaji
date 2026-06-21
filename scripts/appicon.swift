import SwiftUI
import AppKit

// Kaji Gauge — app icon.
//
// A sibling of the Kaji helm mark (assets/kaji-logo.svg: an ink ring with ONE
// persimmon spoke). Here the ring becomes the product itself — a concentric
// DUAL-RING gauge — still crossed by the single persimmon helm spoke running
// NE past the rim. Drawn on a deep warm Ember field so the persimmon + gold
// glow: day energy, night luxury, the same palette as the gauge.
//
// Rendered offscreen with ImageRenderer (same proven path as snapshot.swift),
// then packed into AppIcon.icns by scripts/make-icon.sh.

private func hex(_ v: UInt32) -> Color {
    Color(.sRGB,
          red: Double((v >> 16) & 0xFF) / 255,
          green: Double((v >> 8) & 0xFF) / 255,
          blue: Double(v & 0xFF) / 255,
          opacity: 1)
}

struct AppIconView: View {
    // 1024-pt design canvas.
    let s: CGFloat = 1024

    // Palette — white field + brand persimmon / ember gold (user prefers
    // white + orange). The dark Ember ground was swapped for a warm white so
    // the persimmon pops; the gauge geometry is unchanged.
    private let field = hex(0xFFFFFF)      // squircle base
    private let fieldTop = hex(0xFFF6EE)   // faint warm white at the top
    private let edge = hex(0xEADFD3)       // hairline so the squircle reads on white
    private let persimmon = hex(0xF25C05)
    private let gold = hex(0xE0902F)       // warmer/deeper gold so it carries on white
    private let track = hex(0xF0E3D6)      // light warm track behind the inner arc

    var body: some View {
        ZStack {
            // Rounded-rect "squircle" field, Apple-ish 10% margin + ~0.224 radius.
            let inset: CGFloat = 100
            let side = s - inset * 2
            RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                .fill(
                    LinearGradient(colors: [fieldTop, field],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    // Faint warm radial wash behind the gauge for a little depth.
                    RadialGradient(colors: [persimmon.opacity(0.06), .clear],
                                   center: .center, startRadius: 0, endRadius: side * 0.55)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous))
                )
                .overlay(
                    // Hairline edge so the white squircle stays defined against a
                    // white Finder / Applications background.
                    RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                        .stroke(edge, lineWidth: 3)
                )
                .frame(width: side, height: side)

            gauge
            // Knockout: a wider FIELD-colored spoke under the persimmon one, so
            // the handle reads as crossing OVER the wheel (a clean white gap on
            // each side) instead of merging into a same-color blob.
            spokeStroke(color: field, width: 96)
            spokeStroke(color: persimmon, width: 60)
            // Center hub.
            Circle().fill(persimmon).frame(width: 46, height: 46)
        }
        .frame(width: s, height: s)
    }

    // The helm-as-gauge: a full persimmon bezel ring (the wheel) with an inner
    // ember-gold arc inside it (the meter / 7d window) — dual-ring like the
    // product, but clean enough to read at 16pt.
    private var gauge: some View {
        let outer: CGFloat = 540
        let outerLW: CGFloat = 60
        let innerInset: CGFloat = 116
        let innerLW: CGFloat = 38
        return ZStack {
            // Outer persimmon bezel — a full ring, like the kaji helm wheel.
            Circle().stroke(persimmon, style: StrokeStyle(lineWidth: outerLW, lineCap: .round))
            // Inner gold meter — a faint full track with a ~62% arc on top.
            Circle().stroke(track.opacity(0.9),
                            style: StrokeStyle(lineWidth: innerLW, lineCap: .round))
                .padding(innerInset)
            Circle().trim(from: 0, to: 0.62)
                .stroke(gold, style: StrokeStyle(lineWidth: innerLW, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(innerInset)
        }
        .frame(width: outer, height: outer)
    }

    // The single persimmon helm spoke — hub out to NE, past the bezel rim.
    // Matches kaji-logo.svg direction + ~1.45x ring-radius reach (center 64,64
    // -> 104,24 in the 128 logo). The bezel is masked under the spoke so the
    // handle reads as one clean stroke crossing the wheel.
    private func spokeStroke(color: Color, width: CGFloat) -> some View {
        Path { p in
            let c = CGPoint(x: s / 2, y: s / 2)
            let len: CGFloat = 392           // ~1.45 x the 270 bezel radius
            let a = CGFloat.pi / 4           // 45° above horizontal (NE)
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + len * cos(a), y: c.y - len * sin(a)))
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

@MainActor
func renderIcon(to path: String) {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.scale = 1   // view is already 1024pt → 1024px
    guard let img = renderer.nsImage,
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed"); return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) size=\(img.size)")
}

@main
struct IconMain {
    static func main() {
        MainActor.assumeIsolated {
            let out = CommandLine.arguments.dropFirst().first ?? "/tmp/kaji-icon-1024.png"
            renderIcon(to: out)
        }
    }
}
