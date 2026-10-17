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
    /// Training plans (rotations of templates).
    @Published public private(set) var plans: [WorkoutPlan] = []
    /// The user's body weight over time, newest first.
    @Published public private(set) var bodyWeights: [BodyWeightEntry] = []
    /// How often the app asks the user to update their weight.
    @Published public private(set) var weighIn = WeighInPreferences()
    /// The user's workout preferences (unit, rest timer, goal, ...). New workouts start with them.
    @Published public private(set) var preferences = StrengthPreferences()
    /// The error of the last save that failed (a write that was refused or could not be made); nil when the last save worked. The
    /// change that was being saved stays in memory.
    @Published public private(set) var lastPersistenceError: Error?
    /// Files that could not be read completely the last time the data was loaded, until the user acknowledges them. The readable
    /// part was kept and a copy of every damaged file was made (see `PersistenceIssue`).
    @Published public private(set) var persistenceIssues: [PersistenceIssue] = []

    /// Called after the user's weigh-in was stored (not for weights read from Apple Health). The Health layer saves it to Health.
    public var onBodyWeightSaved: ((BodyWeightEntry) -> Void)?
    /// Called after a weigh-in that was entered here was deleted. The Health layer removes it from Health.
    public var onBodyWeightRemoved: ((BodyWeightEntry) -> Void)?

    private let model: StrengthDataModel

    /// Loads the saved data from `persistence` (nil keeps everything in memory). `seedDemoData` fills an empty store with demo
    /// templates, workouts and personal bests; only previews, the UI tests and tests pass true.
    ///
    /// `deviceLocale` picks the weight unit of the preferences of a first launch (`WeightUnit.defaultFor(locale:)`); the app passes
    /// `Locale.current`. The default, nil, means kilograms, so previews and tests do not depend on the machine's region.
    public init(persistence: FileStrengthPersistence?, seedDemoData: Bool = false, deviceLocale: Locale? = nil) {
        model = StrengthDataModel(persistence: persistence, seedDemoData: seedDemoData, deviceLocale: deviceLocale)
        publish()
    }

    /// The built-in and custom exercises with `previousBestE1RM` / `previousSets` overlaid from personal bests and history.
    public var exercises: [Exercise] { model.exercises }

    /// One exercise (built-in or custom) with the previous results overlaid; nil for an unknown id.
    public func exercise(id: String) -> Exercise? { model.exercise(id: id) }

    /// Adds a custom exercise (or replaces the one with the same id) and saves it. `.failure` when the id belongs to a built-in
    /// exercise, or when the file could not be written (the exercise is added in memory).
    @discardableResult
    public func addCustomExercise(_ exercise: Exercise) -> Result<Void, Error> {
        let result = model.addCustomExercise(exercise)
        publish()
        return result
    }

    /// Adds a template, or replaces the one with the same id, and saves it. A replaced template keeps its position, a new one is
    /// appended: the order of `templates` is the user's order. `.failure` when the file could not be written (the template is saved
    /// in memory).
    @discardableResult
    public func saveTemplate(_ template: WorkoutTemplate) -> Result<Void, Error> {
        let result = model.saveTemplate(template)
        publish()
        return result
    }

    /// The plan the hub follows, if any.
    public var activePlan: WorkoutPlan? { plans.first { $0.isActive } }

    /// The workout to recommend next: the active plan's next workout, else the one after the most recently performed template.
    public var nextTemplate: WorkoutTemplate? { model.nextTemplate() }

    /// Adds a plan, or replaces the one with the same id, and saves it. `.failure` when the file could not be written (the plan is
    /// saved in memory).
    @discardableResult
    public func savePlan(_ plan: WorkoutPlan) -> Result<Void, Error> {
        let result = model.savePlan(plan)
        publish()
        return result
    }

    /// Makes a plan the active one.
    @discardableResult
    public func activatePlan(id: UUID) -> Result<Void, Error> {
        let result = model.activatePlan(id: id)
        publish()
        return result
    }

    /// Removes a plan; its templates stay.
    @discardableResult
    public func deletePlan(id: UUID) -> Result<Void, Error> {
        let result = model.deletePlan(id: id)
        publish()
        return result
    }

    /// Passes over the next workout of a plan.
    @discardableResult
    public func skipNextWorkout(planID: UUID) -> Result<Void, Error> {
        let result = model.skipNextWorkout(planID: planID)
        publish()
        return result
    }

    /// Imports a plan file (see `PlanBundle`): its plan, workouts and new exercises are added, or replaced by the same ids.
    public func importPlan(from fileData: Data) -> Result<PlanImportSummary, PlanImportError> {
        let result = model.importPlan(from: fileData)
        publish()
        return result
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

    // MARK: Managing what is stored

    /// Renames a template (the name is trimmed; `.failure(StrengthStoreError.invalidName)` when it is empty) and saves it.
    @discardableResult
    public func renameTemplate(id: UUID, to name: String) -> Result<Void, Error> {
        let result = model.renameTemplate(id: id, to: name)
        publish()
        return result
    }

    /// Deletes a template and saves the templates. Finished workouts keep their name.
    @discardableResult
    public func deleteTemplate(id: UUID) -> Result<Void, Error> {
        let result = model.deleteTemplate(id: id)
        publish()
        return result
    }

    /// Adds a copy of a template right after the original (new ids, never performed) under `name`, saves it and returns the copy.
    @discardableResult
    public func duplicateTemplate(id: UUID, name: String) -> Result<WorkoutTemplate, Error> {
        let result = model.duplicateTemplate(id: id, name: name)
        publish()
        return result
    }

    /// Moves templates in the list the way SwiftUI's `onMove` describes it, and saves the new order.
    @discardableResult
    public func moveTemplates(fromOffsets source: IndexSet, toOffset destination: Int) -> Result<Void, Error> {
        let result = model.moveTemplates(fromOffsets: source, toOffset: destination)
        publish()
        return result
    }

    /// Orders the templates as `ids` lists them (unknown ids are ignored, unlisted templates follow in their old order) and saves it.
    @discardableResult
    public func setTemplateOrder(_ ids: [UUID]) -> Result<Void, Error> {
        let result = model.setTemplateOrder(ids)
        publish()
        return result
    }

    /// Deletes a finished workout, recomputes the personal bests (a best that the workout set goes away with it) and saves.
    @discardableResult
    public func deleteWorkout(id: UUID) -> Result<Void, Error> {
        let result = model.deleteWorkout(id: id)
        publish()
        return result
    }

    /// Saves an edited finished workout: name, sets (weight, reps, RIR, type), notes. Volume, logged sets, e1RMs, muscle sets and
    /// the personal-record flags are recomputed, and so are the personal bests. See `StrengthData.updateWorkout` for what is kept.
    @discardableResult
    public func updateWorkout(_ workout: CompletedWorkout) -> Result<Void, Error> {
        let result = model.updateWorkout(workout)
        publish()
        return result
    }

    /// Recomputes the personal bests from the whole history.
    @discardableResult
    public func recomputePersonalBests() -> Result<Void, Error> {
        let result = model.recomputePersonalBests()
        publish()
        return result
    }

    /// Deletes a custom exercise and removes it from the templates that contain it; the success value is how many templates lost an
    /// entry, so the screen can warn before it does so. Finished workouts keep the exercise's name.
    @discardableResult
    public func deleteCustomExercise(id: String) -> Result<Int, Error> {
        let result = model.deleteCustomExercise(id: id)
        publish()
        return result
    }

    /// Replaces a custom exercise and refreshes its copies in the templates. Finished workouts keep the old name.
    @discardableResult
    public func updateCustomExercise(_ exercise: Exercise) -> Result<Void, Error> {
        let result = model.updateCustomExercise(exercise)
        publish()
        return result
    }

    // MARK: Sample data, starter templates, reset

    /// True when sample templates or sample workouts from an older build's demo data are stored; the app then offers
    /// `removeSampleData()`.
    public var hasSampleData: Bool { model.hasSampleData }

    /// Deletes exactly the sample templates and sample workouts, recomputes the personal bests from what is left and saves. The
    /// success value says how many templates and workouts went; the user's own data stays (see `StrengthData.removeSampleData`).
    @discardableResult
    public func removeSampleData() -> Result<SampleDataRemoval, Error> {
        let result = model.removeSampleData()
        publish()
        return result
    }

    /// Adds Push, Pull and Legs (`StarterTemplates`) unless they are already stored and saves them; the success value is how many
    /// were added. Their weights are the library defaults, only starting values.
    @discardableResult
    public func addStarterTemplates() -> Result<Int, Error> {
        let result = model.addStarterTemplates()
        publish()
        return result
    }

    /// Erases what `scope` names and saves it; `.all` removes every data file. Only offer it while no workout is running. The
    /// weigh-ins that were saved to Apple Health stay there (`onBodyWeightRemoved` is not called).
    @discardableResult
    public func resetData(_ scope: ResetScope) -> Result<Void, Error> {
        let result = model.resetData(scope)
        publish()
        return result
    }

    // MARK: Recovery

    /// The estimated recovery of every muscle group at `now` from the finished workouts (see `RecoveryEstimator`); `hasData` is
    /// false when there is no workout in the last 21 days.
    public func recoveryEstimates(now: Date = Date()) -> [MuscleGroup: RecoveryEstimate] {
        model.recoveryEstimates(now: now)
    }

    /// The mean recovery of the muscle groups at `now`; nil without a workout in the last 21 days.
    public func readinessPercent(now: Date = Date()) -> Int? {
        model.readinessPercent(now: now)
    }

    /// The estimated recovery as a `RecoveryProvider`, fixed at `now`.
    public func recoveryProvider(now: Date = Date()) -> RecoveryProvider {
        model.recoveryProvider(now: now)
    }

    /// Forgets the load issues the user has seen. The copies of the damaged files stay on disk.
    public func acknowledgePersistenceIssues() {
        model.acknowledgePersistenceIssues()
        publish()
    }

    /// Picks up the issues of files that are read outside the store, such as the active workout. `WorkoutController.restoreFromDisk()`
    /// calls it after restoring.
    public func refreshPersistenceIssues() {
        model.refreshPersistenceIssues()
        publish()
    }

    /// The sessions, trend, records and 30-day totals of one exercise, relative to `now`, with its texts in the unit of the
    /// preferences and the separators of `locale` (default: en_US).
    public func history(for exerciseID: String, now: Date, locale: Locale = DisplayFormat.metric.locale) -> ExerciseHistory {
        model.history(for: exerciseID, now: now, locale: locale)
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
        if let entry { onBodyWeightSaved?(entry) }
        return entry
    }

    /// Adds the body weights read from Apple Health that are not here yet; returns how many were added.
    @discardableResult
    public func importHealthBodyWeights(_ samples: [HealthBodyWeightSample]) -> Int {
        let added = model.importHealthBodyWeights(samples)
        publish()
        return added
    }

    /// Removes a weigh-in that was entered here; false when there is none with that id, or when it was read from Apple Health.
    @discardableResult
    public func deleteBodyWeight(id: UUID) -> Bool {
        let entry = bodyWeights.first { $0.id == id }
        let removed = model.deleteBodyWeight(id: id)
        publish()
        if removed, let entry { onBodyWeightRemoved?(entry) }
        return removed
    }

    /// Replaces the weigh-in reminder preferences and saves them.
    public func setWeighInPreferences(_ preferences: WeighInPreferences) {
        model.setWeighInPreferences(preferences)
        publish()
    }

    /// Replaces the workout preferences and saves them; `.failure` when the file could not be written (they change in memory anyway).
    /// A workout in progress keeps its own settings: use `WorkoutController.updatePreferences(_:)` to bring the unit to it.
    @discardableResult
    public func updatePreferences(_ preferences: StrengthPreferences) -> Result<Void, Error> {
        let result = model.updatePreferences(preferences)
        publish()
        return result
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
        if plans != data.plans { plans = data.plans }
        if bodyWeights != data.bodyWeights { bodyWeights = data.bodyWeights }
        if weighIn != data.weighIn { weighIn = data.weighIn }
        if preferences != data.preferences { preferences = data.preferences }
        if persistenceIssues != model.persistenceIssues { persistenceIssues = model.persistenceIssues }
        if !Self.isSame(lastPersistenceError, model.lastPersistenceError) { lastPersistenceError = model.lastPersistenceError }
    }

    private static func isSame(_ lhs: Error?, _ rhs: Error?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return (lhs as NSError).isEqual(rhs as NSError)
        default: return false
        }
    }
}

#endif
