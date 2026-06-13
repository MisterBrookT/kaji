import SwiftUI
import CoreGraphics

// MARK: - SVGPath
//
// A minimal SVG path-data ("d" attribute) parser that builds a CGPath. Just
// enough to render the brand logos we ship (OpenAI / Gemini) from the exact
// same path strings the design preview uses — so the gauge and the HTML mock
// stay pixel-faithful.
//
// Supports: M m  L l  H h  V v  C c  S s  Q q  T t  A a  Z z
// Arcs (A/a) are converted to cubic Béziers (the OpenAI mark needs them).
// All logos author in a 24×24 viewBox; `path(in:)` consumers scale to fit.
enum SVGPath {
    /// Parse SVG path data into a CGPath in the path's own coordinate space
    /// (here, a 24×24 box). Unknown/garbage input yields an empty path rather
    /// than crashing.
    static func cgPath(from d: String) -> CGPath {
        let path = CGMutablePath()
        var t = Scanner(d)

        var cur = CGPoint.zero          // current point
        var startPt = CGPoint.zero      // subpath start (for Z)
        var prevCtrl: CGPoint? = nil    // last cubic/quad control (for S/T)
        var prevCmd: Character = " "

        func n() -> CGFloat { CGFloat(t.number() ?? 0) }
        func flag() -> Bool { (t.number() ?? 0) != 0 }

        while let cmd = t.command() {
            let rel = cmd.isLowercase
            switch cmd {
            case "M", "m":
                var p = CGPoint(x: n(), y: n())
                if rel { p.x += cur.x; p.y += cur.y }
                path.move(to: p); cur = p; startPt = p
                // Extra coordinate pairs after a moveto are implicit linetos.
                while t.peekIsNumber() {
                    var q = CGPoint(x: n(), y: n())
                    if rel { q.x += cur.x; q.y += cur.y }
                    path.addLine(to: q); cur = q
                }
            case "L", "l":
                while t.peekIsNumber() {
                    var p = CGPoint(x: n(), y: n())
                    if rel { p.x += cur.x; p.y += cur.y }
                    path.addLine(to: p); cur = p
                }
            case "H", "h":
                while t.peekIsNumber() {
                    var x = n(); if rel { x += cur.x }
                    cur.x = x; path.addLine(to: cur)
                }
            case "V", "v":
                while t.peekIsNumber() {
                    var y = n(); if rel { y += cur.y }
                    cur.y = y; path.addLine(to: cur)
                }
            case "C", "c":
                while t.peekIsNumber() {
                    var c1 = CGPoint(x: n(), y: n())
                    var c2 = CGPoint(x: n(), y: n())
                    var p  = CGPoint(x: n(), y: n())
                    if rel {
                        c1.x += cur.x; c1.y += cur.y
                        c2.x += cur.x; c2.y += cur.y
                        p.x  += cur.x; p.y  += cur.y
                    }
                    path.addCurve(to: p, control1: c1, control2: c2)
                    prevCtrl = c2; cur = p
                }
            case "S", "s":
                while t.peekIsNumber() {
                    var c2 = CGPoint(x: n(), y: n())
                    var p  = CGPoint(x: n(), y: n())
                    if rel { c2.x += cur.x; c2.y += cur.y; p.x += cur.x; p.y += cur.y }
                    let c1: CGPoint
                    if "CcSs".contains(prevCmd), let pc = prevCtrl {
                        c1 = CGPoint(x: 2 * cur.x - pc.x, y: 2 * cur.y - pc.y) // reflect
                    } else { c1 = cur }
                    path.addCurve(to: p, control1: c1, control2: c2)
                    prevCtrl = c2; cur = p
                }
            case "Q", "q":
                while t.peekIsNumber() {
                    var c = CGPoint(x: n(), y: n())
                    var p = CGPoint(x: n(), y: n())
                    if rel { c.x += cur.x; c.y += cur.y; p.x += cur.x; p.y += cur.y }
                    path.addQuadCurve(to: p, control: c)
                    prevCtrl = c; cur = p
                }
            case "T", "t":
                while t.peekIsNumber() {
                    var p = CGPoint(x: n(), y: n())
                    if rel { p.x += cur.x; p.y += cur.y }
                    let c: CGPoint
                    if "QqTt".contains(prevCmd), let pc = prevCtrl {
                        c = CGPoint(x: 2 * cur.x - pc.x, y: 2 * cur.y - pc.y)
                    } else { c = cur }
                    path.addQuadCurve(to: p, control: c)
                    prevCtrl = c; cur = p
                }
            case "A", "a":
                while t.peekIsNumber() {
                    let rx = n(), ry = n(), rot = n()
                    let large = flag(), sweep = flag()
                    var p = CGPoint(x: n(), y: n())
                    if rel { p.x += cur.x; p.y += cur.y }
                    appendArc(to: path, from: cur, to: p, rx: rx, ry: ry,
                              xRotDeg: rot, largeArc: large, sweep: sweep)
                    cur = p; prevCtrl = nil
                }
            case "Z", "z":
                path.closeSubpath(); cur = startPt; prevCtrl = nil
            default:
                break
            }
            prevCmd = cmd
        }
        return path
    }

    // MARK: Arc → cubic Béziers (endpoint to center parameterization, W3C impl notes)
    private static func appendArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint,
                                  rx rxIn: CGFloat, ry ryIn: CGFloat, xRotDeg: CGFloat,
                                  largeArc: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }

        let phi = xRotDeg * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        // Step 1: compute (x1', y1')
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p =  cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Correct out-of-range radii.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }

        // Step 2: compute center (cx', cy')
        let rx2 = rx * rx, ry2 = ry * ry, x1p2 = x1p * x1p, y1p2 = y1p * y1p
        var num = rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2
        let den = rx2 * y1p2 + ry2 * x1p2
        if num < 0 { num = 0 }
        var coef = den == 0 ? 0 : sqrt(num / den)
        if largeArc == sweep { coef = -coef }
        let cxp =  coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx

        // Step 3: center (cx, cy)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        // Step 4: angles
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(min(max(dot / len, -1), 1))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var dTheta = angle(ux, uy, vx, vy)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        // Split into segments of <= 90°, each a cubic Bézier.
        let segs = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / CGFloat(segs)
        let tParam = 4.0 / 3.0 * tan(delta / 4)
        var ang = theta1
        for _ in 0..<segs {
            let cosA = cos(ang), sinA = sin(ang)
            let cosB = cos(ang + delta), sinB = sin(ang + delta)
            // Points on the unit-ish ellipse, then rotate + translate.
            func pt(_ ca: CGFloat, _ sa: CGFloat) -> CGPoint {
                let ex = rx * ca, ey = ry * sa
                return CGPoint(x: cosPhi * ex - sinPhi * ey + cx,
                               y: sinPhi * ex + cosPhi * ey + cy)
            }
            func deriv(_ ca: CGFloat, _ sa: CGFloat) -> CGPoint {
                let ex = -rx * sa, ey = ry * ca
                return CGPoint(x: cosPhi * ex - sinPhi * ey,
                               y: sinPhi * ex + cosPhi * ey)
            }
            let e1 = pt(cosA, sinA), e2 = pt(cosB, sinB)
            let d1 = deriv(cosA, sinA), d2 = deriv(cosB, sinB)
            let c1 = CGPoint(x: e1.x + tParam * d1.x, y: e1.y + tParam * d1.y)
            let c2 = CGPoint(x: e2.x - tParam * d2.x, y: e2.y - tParam * d2.y)
            path.addCurve(to: e2, control1: c1, control2: c2)
            ang += delta
        }
    }

    // MARK: - Number/command scanner
    private struct Scanner {
        private let chars: [Character]
        private var i = 0
        init(_ s: String) { chars = Array(s) }

        private mutating func skipSep() {
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { i += 1 }
                else { break }
            }
        }

        private static let cmds = Set("MmLlHhVvCcSsQqTtAaZz")

        mutating func command() -> Character? {
            skipSep()
            guard i < chars.count else { return nil }
            let c = chars[i]
            if Scanner.cmds.contains(c) { i += 1; return c }
            return nil // a number where a command is expected -> caller loop handled it
        }

        mutating func peekIsNumber() -> Bool {
            skipSep()
            guard i < chars.count else { return false }
            let c = chars[i]
            return c.isNumber || c == "-" || c == "+" || c == "."
        }

        /// Scan one SVG number (sign, int/frac, exponent). Stops at a second '.'
        /// or a '-'/'+' that begins the next number.
        mutating func number() -> Double? {
            skipSep()
            guard i < chars.count else { return nil }
            let start = i
            var seenDot = false
            var seenDigit = false
            if chars[i] == "-" || chars[i] == "+" { i += 1 }
            while i < chars.count {
                let c = chars[i]
                if c.isNumber { seenDigit = true; i += 1 }
                else if c == "." {
                    if seenDot { break }
                    seenDot = true; i += 1
                }
                else if (c == "e" || c == "E"), seenDigit {
                    i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
                }
                else { break }
            }
            guard i > start else { return nil }
            return Double(String(chars[start..<i]))
        }
    }
}
