import Foundation

/// The user's own choices for the strength feature, kept in `settings.json` next to the workout data.
///
/// Only the weekly goal so far. A key that is missing or has the wrong type reads as its default and a number outside its range is
/// brought into it, so a damaged or hand-edited file can never produce a value the app cannot show.
public struct StrengthSettings: Codable, Equatable, Sendable {
    /// Workouts per week the user aims for, 1...7 (`WidgetContext.defaultWeeklyGoal` until they choose another number). An active
    /// training plan with its own `daysPerWeek` takes precedence in the widgets; this is the goal without one.
    public var weeklyGoal: Int {
        didSet { weeklyGoal = Self.clamped(weeklyGoal) }
    }

    /// Smallest and largest weekly goal.
    public static let weeklyGoalRange = 1...7

    /// Creates settings; a goal outside 1...7 is brought into it.
    public init(weeklyGoal: Int = WidgetContext.defaultWeeklyGoal) {
        self.weeklyGoal = Self.clamped(weeklyGoal)
    }

    /// `goal` brought into 1...7.
    public static func clamped(_ goal: Int) -> Int {
        min(weeklyGoalRange.upperBound, max(weeklyGoalRange.lowerBound, goal))
    }

    private enum CodingKeys: String, CodingKey {
        case weeklyGoal
    }

    /// Reads settings; each value that is missing or not a number reads as its default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let goal = (try? container.decodeIfPresent(Int.self, forKey: .weeklyGoal)) ?? WidgetContext.defaultWeeklyGoal
        self.init(weeklyGoal: goal)
    }
}
