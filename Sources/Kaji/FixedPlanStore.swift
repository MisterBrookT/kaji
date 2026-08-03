import Foundation
import Combine
import KajiCore

@MainActor
final class FixedPlanStore: ObservableObject {
    @Published private(set) var plans: [FixedDayPlan]
    @Published private(set) var isTodayCompleted: Bool

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var completionDay: String

    private enum Key {
        static let plans = "fixedPlansV1"
        static let completed = "fixedPlanCompletedV2"
        static let completionDay = "fixedPlanCompletionDayV1"
    }

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        if let data = defaults.data(forKey: Key.plans),
           let decoded = try? JSONDecoder().decode([FixedDayPlan].self, from: data) {
            plans = decoded.map { saved in
                var migrated = saved
                if saved.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let defaultPlan = FixedPlanModel.defaults.first(where: {
                          $0.weekday == saved.weekday && $0.title == saved.title
                   }) {
                    migrated.tag = defaultPlan.tag
                } else {
                    migrated.tag = GoalTagLogic.resolve(saved.tag, title: saved.title).rawValue
                }
                return migrated
            }
        } else {
            plans = FixedPlanModel.defaults
        }
        completionDay = Self.dayKey(Date(), calendar: calendar)
        if defaults.string(forKey: Key.completionDay) == completionDay {
            isTodayCompleted = defaults.bool(forKey: Key.completed)
        } else {
            isTodayCompleted = false
            persistCompletion()
        }
    }

    var today: FixedDayPlan {
        refreshDayBoundary()
        return FixedPlanModel.plan(for: calendar.component(.weekday, from: Date()), in: plans)
    }

    func toggleTodayCompletion() {
        refreshDayBoundary()
        isTodayCompleted.toggle()
        persistCompletion()
    }

    func plan(for weekday: Int) -> FixedDayPlan {
        FixedPlanModel.plan(for: weekday, in: plans)
    }

    func update(weekday: Int, title: String? = nil, tag: String? = nil, text: String? = nil) {
        var plan = self.plan(for: weekday)
        if let title { plan.title = title }
        if let tag { plan.tag = tag }
        if let text { plan.items = FixedPlanModel.items(from: text) }
        plans.removeAll { $0.weekday == weekday }
        plans.append(plan)
        plans.sort { $0.weekday < $1.weekday }
        persistPlans()
    }

    func addItem(weekday: Int) -> UUID {
        var plan = self.plan(for: weekday)
        let item = FixedPlanItem(title: "", dose: "")
        plan.items.append(item)
        replace(plan)
        return item.id
    }

    func updateItem(weekday: Int, id: UUID, title: String? = nil, dose: String? = nil) {
        var plan = self.plan(for: weekday)
        guard let index = plan.items.firstIndex(where: { $0.id == id }) else { return }
        if let title { plan.items[index].title = title }
        if let dose { plan.items[index].dose = dose }
        replace(plan)
    }

    func deleteItem(weekday: Int, id: UUID) {
        var plan = self.plan(for: weekday)
        plan.items.removeAll { $0.id == id }
        replace(plan)
    }

    func reset(weekday: Int) {
        guard let plan = FixedPlanModel.defaults.first(where: { $0.weekday == weekday }) else { return }
        plans.removeAll { $0.weekday == weekday }
        plans.append(plan)
        plans.sort { $0.weekday < $1.weekday }
        persistPlans()
    }

    func refreshDayBoundary() {
        let key = Self.dayKey(Date(), calendar: calendar)
        guard key != completionDay else { return }
        completionDay = key
        isTodayCompleted = false
        persistCompletion()
    }

    private func persistPlans() {
        defaults.set(try? JSONEncoder().encode(plans), forKey: Key.plans)
    }

    private func replace(_ plan: FixedDayPlan) {
        plans.removeAll { $0.weekday == plan.weekday }
        plans.append(plan)
        plans.sort { $0.weekday < $1.weekday }
        persistPlans()
    }

    private func persistCompletion() {
        defaults.set(completionDay, forKey: Key.completionDay)
        defaults.set(isTodayCompleted, forKey: Key.completed)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
