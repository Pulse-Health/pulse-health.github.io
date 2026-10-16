import Foundation

// MARK: - Template update prompt

/// When the app offers to update a template after a workout that differs from it.
public enum TemplateUpdatePrompt: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// Whenever anything in the workout differs from the template (exercises, sets, weights, reps, rest).
    case whenChanged
    /// Only when exercises were added, removed or reordered (`TemplateDiff`).
    case structureOnly
    /// Never.
    case never

    public var id: String { rawValue }
}

// MARK: - Preferences

/// What the user has chosen for their workouts, saved as `preferences.json` and applied to every new workout.
///
/// Reading is forgiving so that a file written by another version loads: every field is optional in the file and falls back to its
/// default, and an unknown value of `weightUnit` or `askToUpdateTemplate` (a case a newer version added) reads as the default.
/// The two counts are kept in range by the properties themselves, whoever sets them.
public struct StrengthPreferences: Codable, Equatable, Sendable {
    /// The unit weights are shown and typed in (storage stays kilograms). Created from the device's region the first time, then stored.
    public var weightUnit: WeightUnit
    /// Start the rest timer when a set is logged (`WorkoutSettings.autoStartRest` of every new workout).
    public var autoStartRest: Bool
    /// Notify when a rest ends (`WorkoutSettings.alertWhenRestEnds` of every new workout).
    public var alertWhenRestEnds: Bool
    /// Play a sound when a rest ends.
    public var soundWhenRestEnds: Bool
    /// Haptic feedback on taps and when a rest ends.
    public var hapticsEnabled: Bool
    /// Workouts per week the user aims for, 1...14 (`weeklyGoalRange`).
    public var weeklyGoalSessions: Int {
        didSet { weeklyGoalSessions = Self.clampedGoal(weeklyGoalSessions) }
    }
    /// Keep the screen on during a workout.
    public var keepScreenAwake: Bool
    /// Save finished workouts to Apple Health.
    public var saveWorkoutsToHealth: Bool
    /// Estimate the calories of a workout (for Health and the summary).
    public var estimateCalories: Bool
    /// When to offer updating the template a workout was started from.
    public var askToUpdateTemplate: TemplateUpdatePrompt
    /// Rest in seconds for a new custom exercise, 0...`WorkoutReducer.maximumRestSeconds` (0 = timer off).
    public var defaultRestSeconds: Int {
        didSet { defaultRestSeconds = Self.clampedRest(defaultRestSeconds) }
    }

    /// The range `weeklyGoalSessions` is kept in.
    public static let weeklyGoalRange = 1...14

    /// The rest of a new custom exercise before the user chooses another (90 seconds).
    public static let standardRestSeconds = 90

    /// Creates preferences; the defaults are the ones of a new install in kilograms (`init(locale:)` picks the unit by region).
    public init(
        weightUnit: WeightUnit = .kg,
        autoStartRest: Bool = true,
        alertWhenRestEnds: Bool = true,
        soundWhenRestEnds: Bool = true,
        hapticsEnabled: Bool = true,
        weeklyGoalSessions: Int = 4,
        keepScreenAwake: Bool = true,
        saveWorkoutsToHealth: Bool = true,
        estimateCalories: Bool = true,
        askToUpdateTemplate: TemplateUpdatePrompt = .whenChanged,
        defaultRestSeconds: Int = StrengthPreferences.standardRestSeconds
    ) {
        self.weightUnit = weightUnit
        self.autoStartRest = autoStartRest
        self.alertWhenRestEnds = alertWhenRestEnds
        self.soundWhenRestEnds = soundWhenRestEnds
        self.hapticsEnabled = hapticsEnabled
        self.weeklyGoalSessions = Self.clampedGoal(weeklyGoalSessions)
        self.keepScreenAwake = keepScreenAwake
        self.saveWorkoutsToHealth = saveWorkoutsToHealth
        self.estimateCalories = estimateCalories
        self.askToUpdateTemplate = askToUpdateTemplate
        self.defaultRestSeconds = Self.clampedRest(defaultRestSeconds)
    }

    /// The defaults of a new install for a user with `locale`: `WeightUnit.defaultFor(locale:)` as the unit, everything else as in `init`.
    public init(locale: Locale) {
        self.init(weightUnit: WeightUnit.defaultFor(locale: locale))
    }

    private static func clampedGoal(_ value: Int) -> Int {
        max(weeklyGoalRange.lowerBound, min(value, weeklyGoalRange.upperBound))
    }

    private static func clampedRest(_ value: Int) -> Int {
        max(0, min(value, WorkoutReducer.maximumRestSeconds))
    }

    private enum CodingKeys: String, CodingKey {
        case weightUnit, autoStartRest, alertWhenRestEnds, soundWhenRestEnds, hapticsEnabled, weeklyGoalSessions
        case keepScreenAwake, saveWorkoutsToHealth, estimateCalories, askToUpdateTemplate, defaultRestSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StrengthPreferences()
        self.init(
            weightUnit: (try? container.decodeIfPresent(WeightUnit.self, forKey: .weightUnit)) ?? defaults.weightUnit,
            autoStartRest: try container.decodeIfPresent(Bool.self, forKey: .autoStartRest) ?? defaults.autoStartRest,
            alertWhenRestEnds: try container.decodeIfPresent(Bool.self, forKey: .alertWhenRestEnds) ?? defaults.alertWhenRestEnds,
            soundWhenRestEnds: try container.decodeIfPresent(Bool.self, forKey: .soundWhenRestEnds) ?? defaults.soundWhenRestEnds,
            hapticsEnabled: try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? defaults.hapticsEnabled,
            weeklyGoalSessions: try container.decodeIfPresent(Int.self, forKey: .weeklyGoalSessions) ?? defaults.weeklyGoalSessions,
            keepScreenAwake: try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? defaults.keepScreenAwake,
            saveWorkoutsToHealth: try container.decodeIfPresent(Bool.self, forKey: .saveWorkoutsToHealth) ?? defaults.saveWorkoutsToHealth,
            estimateCalories: try container.decodeIfPresent(Bool.self, forKey: .estimateCalories) ?? defaults.estimateCalories,
            askToUpdateTemplate: (try? container.decodeIfPresent(TemplateUpdatePrompt.self, forKey: .askToUpdateTemplate))
                ?? defaults.askToUpdateTemplate,
            defaultRestSeconds: try container.decodeIfPresent(Int.self, forKey: .defaultRestSeconds) ?? defaults.defaultRestSeconds
        )
    }
}
