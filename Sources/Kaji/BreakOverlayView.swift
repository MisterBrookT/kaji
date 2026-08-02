import AppKit
import SwiftUI
import KajiCore

struct BreakOverlayView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var workSession: WorkSessionController

    let scene: BreakSceneID
    let isPrimary: Bool
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        ZStack {
            sceneBackground
            atmosphere
            readabilityGradient

            if isPrimary {
                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(Color.black)
        .task(id: reduceMotion) {
            drifting = false
            guard BreakSceneModel.allowsMotion(reduceMotion: reduceMotion) else { return }
            withAnimation(.easeInOut(duration: 28).repeatForever(autoreverses: true)) {
                drifting = true
            }
        }
    }

    @ViewBuilder
    private var sceneBackground: some View {
        if let image = BreakSceneImageStore.image(for: scene) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(drifting ? 1.09 : 1.04)
                .offset(x: drifting ? 12 : -8, y: drifting ? -7 : 6)
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else {
            LinearGradient(
                colors: [Color(white: 0.34), Color(white: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var atmosphere: some View {
        switch scene {
        case .windowRain:
            WindowRainLayer(isPaused: reduceMotion)
        case .rainField:
            RainLayer(isPaused: reduceMotion)
        case .mistHill:
            MistLayer(isPaused: reduceMotion)
        case .sunlitMeadow:
            SunlightLayer(isPaused: reduceMotion)
        }
    }

    private var readabilityGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.12), location: 0),
                .init(color: .clear, location: 0.42),
                .init(color: .black.opacity(0.62), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text("休息一下")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text("离开屏幕片刻。")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            Text(workSession.breakClock)
                .font(.system(size: 68, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.top, 4)

            if prefs.allowBreakSkip {
                Button("Skip", action: onSkip)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 22)
                    .frame(height: 38)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
    }
}

private enum BreakSceneImageStore {
    static func image(for scene: BreakSceneID) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: scene.resourceName,
            withExtension: "png"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private struct WindowRainLayer: View {
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: isPaused)) { timeline in
            Canvas { context, size in
                let phase = isPaused ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let travel = size.height + 180

                for index in 0..<22 {
                    let seed = Double((index * 43) % 113) / 113
                    let x = size.width * seed
                    let speed = 16 + Double(index % 6) * 4
                    let startY = (phase * speed + Double(index * 97))
                        .truncatingRemainder(dividingBy: travel) - 100
                    let trailLength = 48 + Double(index % 5) * 21

                    var trail = Path()
                    trail.move(to: CGPoint(x: x, y: startY))
                    for step in 1...8 {
                        let progress = Double(step) / 8
                        let wobble = sin(Double(index) * 1.7 + progress * 5.2) * (2 + Double(index % 3))
                        trail.addLine(
                            to: CGPoint(
                                x: x + wobble,
                                y: startY + trailLength * progress
                            )
                        )
                    }

                    context.stroke(
                        trail,
                        with: .linearGradient(
                            Gradient(colors: [
                                .white.opacity(0.02),
                                .white.opacity(0.13),
                                .white.opacity(0.04)
                            ]),
                            startPoint: CGPoint(x: x, y: startY),
                            endPoint: CGPoint(x: x, y: startY + trailLength)
                        ),
                        lineWidth: index % 4 == 0 ? 1.8 : 1.1
                    )

                    let beadSize = 3.2 + Double(index % 4) * 0.9
                    let beadRect = CGRect(
                        x: x - beadSize / 2,
                        y: startY + trailLength - beadSize / 2,
                        width: beadSize,
                        height: beadSize * 1.35
                    )
                    context.fill(
                        Path(ellipseIn: beadRect),
                        with: .radialGradient(
                            Gradient(colors: [.white.opacity(0.22), .white.opacity(0.03)]),
                            center: CGPoint(x: beadRect.midX - 0.5, y: beadRect.midY - 0.8),
                            startRadius: 0,
                            endRadius: beadSize
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RainLayer: View {
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: isPaused)) { timeline in
            Canvas { context, size in
                let phase = isPaused ? 0 : timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<44 {
                    let seed = Double((index * 37) % 101) / 101
                    let x = size.width * seed
                    let speed = 42 + Double(index % 5) * 9
                    let travel = size.height + 90
                    let y = (phase * speed + Double(index * 73))
                        .truncatingRemainder(dividingBy: travel) - 45
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - 4, y: y + 22))
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.08 + Double(index % 3) * 0.025)),
                        lineWidth: index % 4 == 0 ? 1.2 : 0.7
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MistLayer: View {
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: isPaused)) { timeline in
            GeometryReader { geo in
                let phase = isPaused ? 0 : timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    mistBand(index: 0, phase: phase, size: geo.size)
                    mistBand(index: 1, phase: phase, size: geo.size)
                    mistBand(index: 2, phase: phase, size: geo.size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func mistBand(index: Int, phase: TimeInterval, size: CGSize) -> some View {
        let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
        let travel = size.width * 0.12
        let offset = isPaused ? 0 : sin(phase / (13 + Double(index) * 4)) * travel * direction

        return Ellipse()
            .fill(.white.opacity(0.07 + Double(index) * 0.018))
            .frame(width: size.width * (0.82 + Double(index) * 0.14), height: 150 + CGFloat(index) * 48)
            .blur(radius: 34 + CGFloat(index) * 8)
            .offset(x: offset, y: size.height * (0.02 + Double(index) * 0.18))
    }
}

private struct SunlightLayer: View {
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: isPaused)) { timeline in
            Canvas { context, size in
                let phase = isPaused ? 0 : timeline.date.timeIntervalSinceReferenceDate

                for index in 0..<20 {
                    let seedX = Double((index * 47) % 103) / 103
                    let seedY = Double((index * 71) % 109) / 109
                    let driftX = isPaused ? 0 : sin(phase / 9 + Double(index)) * 9
                    let driftY = isPaused ? 0 : -phase * (1.2 + Double(index % 4) * 0.45)
                    let y = (size.height * seedY + driftY)
                        .truncatingRemainder(dividingBy: size.height + 30)
                    let radius = 1.2 + Double(index % 3) * 0.7
                    let rect = CGRect(
                        x: size.width * seedX + driftX,
                        y: y < -10 ? y + size.height + 30 : y,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(0.11 + Double(index % 3) * 0.035))
                    )
                }

                var ray = Path()
                ray.move(to: CGPoint(x: size.width * 0.58, y: 0))
                ray.addLine(to: CGPoint(x: size.width * 0.82, y: 0))
                ray.addLine(to: CGPoint(x: size.width * 0.62, y: size.height))
                ray.addLine(to: CGPoint(x: size.width * 0.35, y: size.height))
                ray.closeSubpath()
                let pulse = isPaused ? 0.055 : 0.045 + (sin(phase / 7) + 1) * 0.012
                context.fill(
                    ray,
                    with: .linearGradient(
                        Gradient(colors: [.white.opacity(pulse), .white.opacity(0.005)]),
                        startPoint: CGPoint(x: size.width * 0.7, y: 0),
                        endPoint: CGPoint(x: size.width * 0.5, y: size.height)
                    )
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
