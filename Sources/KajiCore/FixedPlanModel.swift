import Foundation

public struct FixedPlanItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var dose: String

    public init(id: UUID = UUID(), title: String, dose: String) {
        self.id = id
        self.title = title
        self.dose = dose
    }
}

public struct FixedDayPlan: Codable, Equatable, Identifiable, Sendable {
    public var weekday: Int
    public var title: String
    public var tag: String
    public var items: [FixedPlanItem]

    public var id: Int { weekday }

    public init(weekday: Int, title: String, tag: String = "", items: [FixedPlanItem]) {
        self.weekday = weekday
        self.title = title
        self.tag = tag
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case weekday, title, tag, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekday = try container.decode(Int.self, forKey: .weekday)
        title = try container.decode(String.self, forKey: .title)
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
        items = try container.decode([FixedPlanItem].self, forKey: .items)
    }
}

public enum FixedPlanModel {
    public static let morning = [
        FixedPlanItem(title: "猫牛式", dose: "6–8 次"),
        FixedPlanItem(title: "侧向儿童式", dose: "每侧 30 秒"),
        FixedPlanItem(title: "半跪髋屈肌拉伸", dose: "每侧 30 秒"),
        FixedPlanItem(title: "门框胸肌拉伸", dose: "每侧 30 秒"),
        FixedPlanItem(title: "臀桥", dose: "10–12 次"),
    ]

    public static let defaults: [FixedDayPlan] = [
        day(2, "全身拉伸＋核心", morning + [
            e("门框胸肌拉伸", "每侧 30–45 秒 × 2"),
            e("侧向儿童式", "每侧 30–45 秒 × 2"),
            e("开书式胸椎旋转", "每侧 6–8 次 × 2"),
            e("横臂肩后侧拉伸", "每侧 30–45 秒 × 2"),
            e("Figure-4 臀部拉伸", "每侧 30–45 秒 × 2"),
            e("腘绳肌拉伸", "每侧 30–45 秒 × 2"),
            e("靠墙小腿拉伸", "每侧 30–45 秒 × 2"),
            e("十字仰卧起坐", "10–15 次 × 1"),
            e("核心保持系列", "每项 30 秒 × 1"),
            e("侧支撑抬臀", "每侧 30 秒 × 1"),
        ]),
        day(3, "完全休息", [e("休息", "不训练；正常走路即可")]),
        day(4, "上肢力量", morning + [
            e("哑铃地板卧推", "3 × 8–12"),
            e("单臂哑铃划船", "3 × 8–12／侧"),
            e("哑铃侧平举", "3 × 12–20"),
            e("站姿二头弯举", "2 × 10–15"),
            e("过头三头伸展", "2 × 10–15"),
        ]),
        day(5, "楼梯心肺", morning + [
            e("平地轻松走", "5 分钟"),
            e("持续爬楼", "15–30 分钟；强度 5–6/10"),
            e("平地慢走", "3–5 分钟"),
        ]),
        day(6, "恢复拉伸＋核心", morning + [
            e("半跪髋屈肌拉伸", "每侧 30–45 秒 × 2"),
            e("Figure-4 臀部拉伸", "每侧 30–45 秒 × 2"),
            e("腘绳肌拉伸", "每侧 30–45 秒 × 2"),
            e("靠墙小腿拉伸", "每侧 30–45 秒 × 2"),
            e("开书式胸椎旋转", "每侧 6–8 次 × 2"),
            e("侧向儿童式", "每侧 30–45 秒 × 2"),
            e("门框胸肌拉伸", "每侧 30–45 秒 × 2"),
            e("横臂肩后侧拉伸", "每侧 30–45 秒 × 2"),
            e("十字仰卧起坐", "10–15 次 × 1"),
            e("核心保持系列", "每项 30 秒 × 1"),
            e("侧支撑抬臀", "每侧 30 秒 × 1"),
        ]),
        day(7, "下肢力量", morning + [
            e("哑铃罗马尼亚硬拉", "3 × 8–12"),
            e("反向弓步", "3 × 8–12／侧"),
            e("哑铃髋推", "3 × 10–15"),
        ]),
        day(1, "上肢肌耐力＋核心", morning + [
            e("上斜俯卧撑", "12–20 次 × 3 轮"),
            e("轻重量单臂哑铃划船", "15–20 次／侧 × 3 轮"),
            e("Suitcase March", "每侧 30–45 秒 × 3 轮"),
            e("十字仰卧起坐", "10–15 次 × 1"),
            e("核心保持系列", "每项 30 秒 × 1"),
            e("侧支撑抬臀", "每侧 30 秒 × 1"),
        ]),
    ].sorted { $0.weekday < $1.weekday }

    public static func plan(for weekday: Int, in plans: [FixedDayPlan]) -> FixedDayPlan {
        plans.first(where: { $0.weekday == weekday })
            ?? defaults.first(where: { $0.weekday == weekday })
            ?? defaults[0]
    }

    public static func text(for plan: FixedDayPlan) -> String {
        plan.items.map { "\($0.title) | \($0.dose)" }.joined(separator: "\n")
    }

    public static func items(from text: String) -> [FixedPlanItem] {
        text.split(separator: "\n").compactMap { raw in
            let parts = raw.split(separator: "|", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let title = parts.first, !title.isEmpty else { return nil }
            return FixedPlanItem(title: title, dose: parts.count > 1 ? parts[1] : "")
        }
    }

    private static func e(_ title: String, _ dose: String) -> FixedPlanItem {
        FixedPlanItem(title: title, dose: dose)
    }

    private static func day(_ weekday: Int, _ title: String, _ items: [FixedPlanItem]) -> FixedDayPlan {
        FixedDayPlan(weekday: weekday, title: title, tag: GoalTag.health.rawValue, items: items)
    }
}
