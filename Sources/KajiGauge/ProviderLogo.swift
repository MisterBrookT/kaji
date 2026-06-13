import SwiftUI

// MARK: - ProviderLogo
//
// The center brand mark of each ring. These are the SAME vector logos the
// design preview uses, so the native gauge stays faithful to the approved mock:
//   - Claude  → a radial burst of tapered lines (stroked).
//   - OpenAI  → the official simple-icons knot (filled path, needs SVG arcs).
//   - Gemini  → the four-point spark (filled path).
// Anything else falls back to its Unicode mark from `Providers`.
//
// All paths author in a 24×24 box; the shapes scale to whatever frame we give.
struct ProviderLogo: View {
    let key: String
    let color: Color
    var size: CGFloat = 18

    var body: some View {
        Group {
            switch key {
            case "claude":
                ClaudeBurst()
                    .stroke(color, style: StrokeStyle(lineWidth: size * (2.1 / 24),
                                                      lineCap: .round))
            case "codex", "openai":
                VectorLogo(pathData: BrandPaths.openai).fill(color)
            case "gemini":
                VectorLogo(pathData: BrandPaths.gemini).fill(color)
            default:
                Text(Providers.mark(for: key))
                    .font(.system(size: size))
                    .foregroundColor(color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Claude burst
//
// 12 radial lines from a small inner radius outward, alternating length — the
// signature Anthropic/Claude mark. Stroked, not filled.
struct ClaudeBurst: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = min(rect.width, rect.height) / 24
        let cx = rect.midX, cy = rect.midY
        let n = 12
        let inner: CGFloat = 2.6
        for i in 0..<n {
            let a = (CGFloat(i) / CGFloat(n)) * (.pi * 2) - .pi / 2
            let outer: CGFloat = 11.2 - (i % 2 == 1 ? 2.1 : 0)
            p.move(to: CGPoint(x: cx + cos(a) * inner * s, y: cy + sin(a) * inner * s))
            p.addLine(to: CGPoint(x: cx + cos(a) * outer * s, y: cy + sin(a) * outer * s))
        }
        return p
    }
}

// MARK: - VectorLogo
//
// Renders an SVG path (24×24 viewBox) scaled + centered into the frame. Filled.
struct VectorLogo: Shape {
    let pathData: String

    func path(in rect: CGRect) -> Path {
        let cg = SVGPath.cgPath(from: pathData)
        let s = min(rect.width, rect.height) / 24
        let tx = rect.minX + (rect.width - 24 * s) / 2
        let ty = rect.minY + (rect.height - 24 * s) / 2
        var t = CGAffineTransform(scaleX: s, y: s)
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
        if let scaled = cg.copy(using: &t) { return Path(scaled) }
        return Path(cg)
    }
}

// MARK: - Brand path data
//
// Verbatim from the design preview (and upstream simple-icons) so the native
// gauge and the HTML mock render the identical mark.
enum BrandPaths {
    // OpenAI / Codex — simple-icons "openai" knot.
    static let openai = "M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.1419.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z"

    // Gemini — four-point spark.
    static let gemini = "M12 0C12 6.6 6.6 12 0 12C6.6 12 12 17.4 12 24C12 17.4 17.4 12 24 12C17.4 12 12 6.6 12 0Z"
}
