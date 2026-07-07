import AppKit
import SwiftUI

struct BreakOverlayView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var workSession: WorkSessionController
    @ObservedObject var petCatalog: PetCatalogStore
    @ObservedObject var dailyGoals: DailyGoalStore

    let isPrimary: Bool
    let onStartBreak: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var t: KajiTheme { .resolve(scheme, prefs.menubarStyle) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                if isPrimary {
                    petMark(in: geo.size)
                    VStack(spacing: 14) {
                        Spacer()
                        VStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundColor(t.cream)
                            Text(subtitle)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(t.mute)
                                .multilineTextAlignment(.center)
                        }
                        Text(clock)
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundColor(t.cream)
                            .monospacedDigit()
                        pendingGoalStrip
                        HStack(spacing: 12) {
                            actionButton(workSession.phase == .breaking ? "Breaking" : "Start Break",
                                         filled: true,
                                         action: onStartBreak)
                            if prefs.allowBreakSkip {
                                actionButton("Skip", filled: false, action: onSkip)
                            }
                        }
                        Text("Skip today \(workSession.skipCountToday)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(t.ash)
                    }
                    .frame(width: min(560, geo.size.width - 48))
                    .padding(.bottom, max(28, geo.safeAreaInsets.bottom + 24))
                }
            }
        }
    }

    private var title: String {
        switch workSession.phase {
        case .working:
            return "Break"
        case .breakDue:
            return "该休息了"
        case .breaking:
            return "休息中"
        }
    }

    private var subtitle: String {
        let petName = petCatalog.displayName(for: prefs.petId)
        switch workSession.phase {
        case .working:
            return petName
        case .breakDue:
            return "\(petName) 拦住你。站起来，走两分钟。"
        case .breaking:
            return "别切回工作。结束后自动放行。"
        }
    }

    private var clock: String {
        workSession.phase == .breaking ? workSession.breakClock : "\(prefs.breakMinutes):00"
    }

    @ViewBuilder
    private func petMark(in size: CGSize) -> some View {
        let width = min(size.width * 0.78, size.height * 0.92, 760)
        ZStack {
            Ellipse()
                .fill(t.panel.opacity(0.36))
                .frame(width: width * 0.72, height: width * 0.15)
                .blur(radius: 16)
                .offset(y: width * 0.22)
            NaviBreakPandaImage()
                .frame(width: width, height: width * 0.62)
                .shadow(color: t.gold.opacity(0.16), radius: 38, x: 0, y: 24)
        }
        .accessibilityLabel(Text("Navi Panda blocks work"))
    }

    private var pendingGoalStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没做")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(t.mute)
            if dailyGoals.pendingGoals.isEmpty {
                Text("今天目标都完成了")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(t.cream)
            } else {
                ForEach(dailyGoals.pendingGoals.prefix(3)) { goal in
                    HStack(spacing: 8) {
                        Circle().fill(t.gold).frame(width: 6, height: 6)
                        Text(goal.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(t.cream)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.panel.opacity(0.72)))
    }

    private var background: some View {
        LinearGradient(colors: [t.bgTop.opacity(0.98), t.bg.opacity(0.98)],
                       startPoint: .topTrailing,
                       endPoint: .bottomLeading)
            .overlay(t.gold.opacity(0.08))
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(filled ? t.bg : t.cream)
                .frame(width: 148, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(filled ? t.gold : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(filled ? Color.clear : t.track, lineWidth: 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct NaviBreakPandaImage: View {
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "navi-panda", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            PandaMark(accent: .green, ink: .white, mute: .gray)
        }
    }
}

private struct PixelShibaMark: View {
    let accent: Color
    let ink: Color
    let mute: Color

    var body: some View {
        ZStack {
            ear(x: -18)
            ear(x: 18)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.96))
                .frame(width: 48, height: 42)
                .offset(y: 5)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(ink.opacity(0.92))
                .frame(width: 28, height: 18)
                .offset(y: 14)
            eye(x: -10)
            eye(x: 10)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(.black.opacity(0.72))
                .frame(width: 5, height: 4)
                .offset(y: 14)
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.black.opacity(0.46))
                    .frame(width: 8, height: 3)
                    .rotationEffect(.degrees(12))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.black.opacity(0.46))
                    .frame(width: 8, height: 3)
                    .rotationEffect(.degrees(-12))
            }
            .offset(y: 21)
            Circle()
                .fill(ink.opacity(0.55))
                .frame(width: 6, height: 6)
                .offset(x: -18, y: 12)
            Circle()
                .fill(ink.opacity(0.55))
                .frame(width: 6, height: 6)
                .offset(x: 18, y: 12)
        }
    }

    private func ear(x: CGFloat) -> some View {
        Triangle()
            .fill(accent)
            .frame(width: 18, height: 22)
            .rotationEffect(.degrees(x < 0 ? -22 : 22))
            .offset(x: x, y: -14)
    }

    private func eye(x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.black.opacity(0.72))
            .frame(width: 6, height: 8)
            .offset(x: x, y: 4)
            .overlay(
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 2, height: 2)
                    .offset(x: x + 1, y: 1)
            )
    }
}

private struct PandaMark: View {
    let accent: Color
    let ink: Color
    let mute: Color

    var body: some View {
        ZStack {
            Circle().fill(ink).frame(width: 52, height: 48).offset(y: 4)
            Circle().fill(mute).frame(width: 18, height: 18).offset(x: -20, y: -13)
            Circle().fill(mute).frame(width: 18, height: 18).offset(x: 20, y: -13)
            Circle().fill(mute).frame(width: 14, height: 18).offset(x: -11, y: 3)
            Circle().fill(mute).frame(width: 14, height: 18).offset(x: 11, y: 3)
            Circle().fill(.black.opacity(0.72)).frame(width: 5, height: 5).offset(x: -10, y: 4)
            Circle().fill(.black.opacity(0.72)).frame(width: 5, height: 5).offset(x: 10, y: 4)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 8, height: 5)
                .offset(y: 13)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
