import Foundation

#if canImport(Combine) || PULSE_COMBINE_SHIM
#if canImport(Combine)
import Combine
#endif

/// The observable store behind the SwiftUI screens: templates, history, custom exercises and personal bests.
///
/// A thin Combine wrapper around `StrengthDataModel` (which holds `StrengthData` and the persistence): every change is
/// forwarded to the model and the published copies are refreshed.
@MainActor
public final class StrengthStore: ObservableObject {
    /// Saved workout templates.
    @Published public private(set) var templates: [WorkoutTemplate] = []
    /// Finished workouts, newest first.
    @Published public private(set) var history: [CompletedWorkout] = []
    /// Exercises the user created.
    @Published public private(set) var customExercises: [Exercise] = []
    /// Best estimated 1RM per exercise id.
    @Published public private(set) var personalBests: [String: PersonalBest] = [:]
    /// The user's body weight over time, newest first.
    @Published public private(set) var bodyWeights: [BodyWeightEntry] = []
    /// How often the app asks the user to update their weight.
    @Published public private(set) var weighIn = WeighInPreferences()

    private let model: StrengthDataModel

    /// Loads the saved data from `persistence` (nil keeps everything in memory); `seedDemoData` fills an empty store with demo data.
    public init(persistence: FileStrengthPersistence?, seedDemoData: Bool = false) {
        model = StrengthDataModel(persistence: persistence, seedDemoData: seedDemoData)
        publish()
    }

    /// The built-in and custom exercises with `previousBestE1RM` / `previousSets` overlaid from personal bests and history.
    public var exercises: [Exercise] { model.exercises }

    /// One exercise (built-in or custom) with the previous results overlaid; nil for an unknown id.
    public func exercise(id: String) -> Exercise? { model.exercise(id: id) }

    /// Adds a custom exercise and saves it.
    public func addCustomExercise(_ exercise: Exercise) {
        model.addCustomExercise(exercise)
        publish()
    }

    /// Adds a template, or replaces the one with the same id, and saves it.
    public func saveTemplate(_ template: WorkoutTemplate) {
        model.saveTemplate(template)
        publish()
    }

    /// Records a finished workout: history (newest first), personal bests, the template's `lastPerformed`, and `updateTemplate` when given.
    ///
    /// The store changes in every case; the result is `.failure` when the workout could not be written to the history file.
    @discardableResult
    public func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) -> Result<Void, Error> {
        let result = model.record(completed, updateTemplate: updateTemplate)
        publish()
        return result
    }

    /// The sessions, trend, records and 30-day totals of one exercise, relative to `now`.
    public func history(for exerciseID: String, now: Date) -> ExerciseHistory {
        model.history(for: exerciseID, now: now)
    }

    /// The newest weigh-in.
    public var latestBodyWeight: BodyWeightEntry? { bodyWeights.first }

    /// True when the app should ask the user for a weight now (the reminder is on and the interval since the latest weigh-in is over).
    public func isWeighInDue(now: Date, calendar: Calendar = .current) -> Bool {
        model.data.isWeighInDue(now: now, calendar: calendar)
    }

    /// Stores a body weight (kg, rounded to 0.1) and saves it. nil when `kg` is not a plausible body weight.
    @discardableResult
    public func recordBodyWeight(kg: Double, date: Date = Date()) -> BodyWeightEntry? {
        let entry = model.recordBodyWeight(kg: kg, date: date)
        publish()
        return entry
    }

    /// Removes a weigh-in; false when there is none with that id.
    @discardableResult
    public func deleteBodyWeight(id: UUID) -> Bool {
        let removed = model.deleteBodyWeight(id: id)
        publish()
        return removed
    }

    /// Replaces the weigh-in reminder preferences and saves them.
    public func setWeighInPreferences(_ preferences: WeighInPreferences) {
        model.setWeighInPreferences(preferences)
        publish()
    }

    /// Re-reads everything from disk.
    public func reload() {
        model.reload()
        publish()
    }

    /// Copies the model's data into the published properties that actually changed.
    private func publish() {
        let data = model.data
        if templates != data.templates { templates = data.templates }
        if history != data.history { history = data.history }
        if customExercises != data.customExercises { customExercises = data.customExercises }
        if personalBests != data.personalBests { personalBests = data.personalBests }
        if bodyWeights != data.bodyWeights { bodyWeights = data.bodyWeights }
        if weighIn != data.weighIn { weighIn = data.weighIn }
    }
}

#endif
