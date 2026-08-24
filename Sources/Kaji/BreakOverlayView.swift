import AppKit
import SwiftUI
import KajiCore

struct BreakSkipConfirmation: Equatable {
    private(set) var remainingSeconds: Int?

    var title: String {
        guard let remainingSeconds else { return "Skip" }
        return remainingSeconds > 0 ? "Sure?  \(remainingSeconds)" : "Sure?"
    }

    var isCoolingDown: Bool {
        remainingSeconds.map { $0 > 0 } ?? false
    }

    var isArmed: Bool {
        remainingSeconds != nil
    }

    mutating func request() -> Bool {
        if remainingSeconds == 0 { return true }
        if remainingSeconds == nil { remainingSeconds = 3 }
        return false
    }

    mutating func tick() {
        guard let remainingSeconds, remainingSeconds > 0 else { return }
        self.remainingSeconds = remainingSeconds - 1
    }
}

struct BreakOverlayView: View {
    @ObservedObject var workSession: WorkSessionController
    @ObservedObject var prefs: Prefs

    let scene: BreakSceneID
    let isPrimary: Bool
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false
    @State private var skipConfirmation = BreakSkipConfirmation()
    @State private var skipConfirmationTask: Task<Void, Never>?

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
        .onExitCommand(perform: handleSkip)
        .background(Color.black)
        .task(id: reduceMotion) {
            drifting = false
            guard BreakSceneModel.allowsMotion(reduceMotion: reduceMotion) else { return }
            withAnimation(.easeInOut(duration: 28).repeatForever(autoreverses: true)) {
                drifting = true
            }
        }
        .onDisappear {
            skipConfirmationTask?.cancel()
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

    private var atmosphere: some View {
        WindowRainLayer(isPaused: reduceMotion)
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
            Text(workSession.breakClock)
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .accessibilityLabel("休息倒计时 \(workSession.breakClock)")

            if prefs.allowBreakSkip {
                Button(action: handleSkip) {
                    Text(skipConfirmation.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(skipConfirmation.isArmed ? 0.78 : 0.52))
                        .frame(minWidth: 72, minHeight: 28)
                }
                .buttonStyle(.plain)
                .disabled(skipConfirmation.isCoolingDown)
            }
        }
    }


    private func handleSkip() {
        if skipConfirmation.request() {
            skipConfirmationTask?.cancel()
            onSkip()
            return
        }
        guard skipConfirmation.remainingSeconds == 3 else { return }
        skipConfirmationTask = Task { @MainActor in
            for _ in 0..<3 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                skipConfirmation.tick()
            }
        }
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
