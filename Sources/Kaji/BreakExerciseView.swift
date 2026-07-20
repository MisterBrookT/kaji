import SwiftUI

enum BreakExercise: String, CaseIterable, Identifiable {
    case shoulderRoll
    case neckRelease
    case chestOpen
    case standingTwist
    case squat
    case calfRaise
    case wristReset
    case eyeReset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shoulderRoll: return "肩膀绕环"
        case .neckRelease: return "颈部放松"
        case .chestOpen: return "扩胸伸展"
        case .standingTwist: return "站姿转体"
        case .squat: return "慢速深蹲"
        case .calfRaise: return "提踵"
        case .wristReset: return "手腕重置"
        case .eyeReset: return "20-20-20 护眼"
        }
    }

    var duration: String {
        switch self {
        case .eyeReset: return "20 秒"
        case .squat: return "8 次"
        case .standingTwist: return "左右 6 次"
        case .calfRaise: return "12 次"
        default: return "30 秒"
        }
    }

    var cue: String {
        switch self {
        case .shoulderRoll: return "肩膀向后画大圈，保持呼吸。"
        case .neckRelease: return "耳朵缓慢靠向肩膀，不要耸肩。"
        case .chestOpen: return "双手向后展开，胸口向前。"
        case .standingTwist: return "髋部朝前，上身左右转动。"
        case .squat: return "膝盖朝脚尖方向，慢下慢起。"
        case .calfRaise: return "扶稳桌面，脚跟缓慢抬起落下。"
        case .wristReset: return "手臂伸直，轻拉手掌和手指。"
        case .eyeReset: return "看向 6 米外，让眼睛离开屏幕。"
        }
    }
}

struct BreakExerciseMotionView: View {
    let exercise: BreakExercise
    let accent: Color
    let ink: Color
    let muted: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        if reduceMotion {
            motionCanvas(0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                motionCanvas(sin(seconds * .pi * 1.15))
            }
        }
    }

    private func motionCanvas(_ motion: Double) -> some View {
        Canvas { context, size in
            if exercise == .eyeReset {
                drawEyes(context: &context, size: size, motion: motion)
            } else {
                drawFigure(context: &context, size: size, motion: motion)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawFigure(context: inout GraphicsContext, size: CGSize, motion: Double) {
        let w = size.width
        let h = size.height
        let centerX = w * 0.5
        let cycle = CGFloat((motion + 1) * 0.5)
        var lift: CGFloat = 0
        var headShift: CGFloat = 0
        var shoulderSpread: CGFloat = 0
        var armLift: CGFloat = 0
        var hipTwist: CGFloat = 0
        var kneeBend: CGFloat = 0

        switch exercise {
        case .shoulderRoll:
            armLift = CGFloat(motion) * h * 0.12
            shoulderSpread = cycle * w * 0.06
        case .neckRelease:
            headShift = CGFloat(motion) * w * 0.08
        case .chestOpen:
            shoulderSpread = cycle * w * 0.18
            armLift = -cycle * h * 0.08
        case .standingTwist:
            hipTwist = CGFloat(motion) * w * 0.12
        case .squat:
            kneeBend = cycle * h * 0.16
        case .calfRaise:
            lift = cycle * h * 0.11
        case .wristReset:
            shoulderSpread = w * 0.14
            armLift = CGFloat(motion) * h * 0.05
        case .eyeReset:
            break
        }

        let head = CGPoint(x: centerX + headShift, y: h * 0.18 + kneeBend - lift)
        let neck = CGPoint(x: centerX, y: h * 0.31 + kneeBend - lift)
        let leftShoulder = CGPoint(x: centerX - w * 0.12 - shoulderSpread, y: h * 0.35 + kneeBend - lift)
        let rightShoulder = CGPoint(x: centerX + w * 0.12 + shoulderSpread, y: h * 0.35 + kneeBend - lift)
        let hip = CGPoint(x: centerX + hipTwist * 0.35, y: h * 0.59 + kneeBend - lift)
        let leftHand = CGPoint(x: centerX - w * 0.27 - shoulderSpread, y: h * 0.55 + armLift + kneeBend - lift)
        let rightHand = CGPoint(x: centerX + w * 0.27 + shoulderSpread, y: h * 0.55 - armLift + kneeBend - lift)
        let leftKnee = CGPoint(x: centerX - w * 0.10 - kneeBend * 0.45, y: h * 0.76 + kneeBend * 0.28 - lift)
        let rightKnee = CGPoint(x: centerX + w * 0.10 + kneeBend * 0.45, y: h * 0.76 + kneeBend * 0.28 - lift)
        let leftFoot = CGPoint(x: centerX - w * 0.16, y: h * 0.94)
        let rightFoot = CGPoint(x: centerX + w * 0.16, y: h * 0.94)

        var skeleton = Path()
        skeleton.move(to: neck)
        skeleton.addLine(to: hip)
        skeleton.move(to: leftShoulder)
        skeleton.addLine(to: rightShoulder)
        skeleton.move(to: leftShoulder)
        skeleton.addLine(to: leftHand)
        skeleton.move(to: rightShoulder)
        skeleton.addLine(to: rightHand)
        skeleton.move(to: hip)
        skeleton.addLine(to: leftKnee)
        skeleton.addLine(to: leftFoot)
        skeleton.move(to: hip)
        skeleton.addLine(to: rightKnee)
        skeleton.addLine(to: rightFoot)
        context.stroke(skeleton,
                       with: .color(ink),
                       style: StrokeStyle(lineWidth: max(3, w * 0.035), lineCap: .round, lineJoin: .round))

        let headSize = min(w, h) * 0.20
        context.fill(Path(ellipseIn: CGRect(x: head.x - headSize / 2,
                                            y: head.y - headSize / 2,
                                            width: headSize,
                                            height: headSize)),
                     with: .color(accent))

        for point in [leftHand, rightHand] {
            let radius = max(3, w * 0.03)
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius,
                                                y: point.y - radius,
                                                width: radius * 2,
                                                height: radius * 2)),
                         with: .color(accent))
        }

        if exercise == .shoulderRoll {
            let ringRadius = w * (0.15 + cycle * 0.025)
            let ringRect = CGRect(x: centerX - ringRadius,
                                  y: h * 0.35 - ringRadius,
                                  width: ringRadius * 2,
                                  height: ringRadius * 2)
            context.stroke(Path(ellipseIn: ringRect),
                           with: .color(accent.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 2, dash: [3, 5]))
        }
    }

    private func drawEyes(context: inout GraphicsContext, size: CGSize, motion: Double) {
        let eyeWidth = size.width * 0.30
        let eyeHeight = size.height * 0.34
        let pupilShift = CGFloat(motion) * eyeWidth * 0.20
        for centerX in [size.width * 0.30, size.width * 0.70] {
            let rect = CGRect(x: centerX - eyeWidth / 2,
                              y: size.height * 0.5 - eyeHeight / 2,
                              width: eyeWidth,
                              height: eyeHeight)
            context.stroke(Path(roundedRect: rect, cornerRadius: eyeHeight / 2),
                           with: .color(ink),
                           lineWidth: max(2, size.width * 0.025))
            let pupil = min(eyeWidth, eyeHeight) * 0.34
            context.fill(Path(ellipseIn: CGRect(x: centerX + pupilShift - pupil / 2,
                                                y: size.height * 0.5 - pupil / 2,
                                                width: pupil,
                                                height: pupil)),
                         with: .color(accent))
        }
        var horizon = Path()
        horizon.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.88))
        horizon.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.88))
        context.stroke(horizon,
                       with: .color(muted.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
    }
}
