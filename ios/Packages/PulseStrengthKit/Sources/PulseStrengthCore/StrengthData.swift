import Foundation

// MARK: - Pure data

/// Everything the strength feature remembers between workouts, with the rules that change and read it.
///
/// A plain value type: the stores and tests drive it directly, nothing here touches disk or the clock.
public struct StrengthData: Equatable, Sendable {
    /// Saved workout templates, in the order they are shown.
    public var templates: [WorkoutTemplate]
    /// Finished workouts, newest first.
    public var history: [CompletedWorkout]
    /// Exercises the user created.
    public var customExercises: [Exercise]
    /// Best estimated 1RM per exercise id.
    public var personalBests: [String: PersonalBest]
    /// Training plans (rotations of templates), in the order they are shown.
    public var plans: [WorkoutPlan]

    /// Creates the data from its collections.
    public init(
        templates: [WorkoutTemplate] = [],
        history: [CompletedWorkout] = [],
        customExercises: [Exercise] = [],
        personalBests: [String: PersonalBest] = [:],
        plans: [WorkoutPlan] = []
    ) {
        self.templates = templates
        self.history = history
        self.customExercises = customExercises
        self.personalBests = personalBests
        self.plans = plans
    }

    /// True when there are neither templates nor finished workouts (the condition for seeding demo data).
    public var isEmpty: Bool { templates.isEmpty && history.isEmpty }

    /// The template with the given id.
    public func template(id: UUID) -> WorkoutTemplate? {
        templates.first { $0.id == id }
    }

    /// The plan the hub follows, if any.
    public var activePlan: WorkoutPlan? {
        plans.first { $0.isActive }
    }

    /// The workout to recommend next: the next one of the active plan, or without an active plan (or when none of its
    /// templates exists) the one after the most recently performed template.
    public func nextTemplate() -> WorkoutTemplate? {
        if let plan = activePlan, let next = plan.nextWorkout(in: templates) { return next }
        return TemplateRotation.next(in: templates)
    }
}

// MARK: - Exercises with remembered results

public extension StrengthData {
    /// The built-in library plus the custom exercises, each with `previousBestE1RM` and `previousSets` taken from the user's results.
    ///
    /// An exercise with no personal best or history keeps the values it already carries (the library's demo values).
    /// A custom exercise whose id equals a built-in id is ignored.
    func exercises() -> [Exercise] {
        let memory = exerciseMemory()
        return allExercises().map { overlay($0, memory: memory) }
    }

    /// One exercise (built-in first, then custom) with the remembered results overlaid; nil for an unknown id.
    func exercise(id: String) -> Exercise? {
        let base = ExerciseLibrary.exercise(id: id) ?? customExercises.first { $0.id == id }
        guard let base else { return nil }
        return overlay(base, memory: exerciseMemory(only: id))
    }

    /// `exercise` with the remembered best e1RM and last sets of the same exercise id applied (anything remembered wins).
    func overlay(_ exercise: Exercise) -> Exercise {
        overlay(exercise, memory: exerciseMemory(only: exercise.id))
    }
}

/// What the history says about one exercise: its latest sets and its best estimated 1RM.
private struct ExerciseMemory {
    var lastDate: Date
    var lastSets: [PreviousSet]
    var bestE1RM: Double
}

private extension StrengthData {
    func allExercises() -> [Exercise] {
        let builtInIDs = Set(ExerciseLibrary.builtIn.map { $0.id })
        var seen = builtInIDs
        var result = ExerciseLibrary.builtIn
        for custom in customExercises where seen.insert(custom.id).inserted {
            result.append(custom)
        }
        return result
    }

    func overlay(_ exercise: Exercise, memory: [String: ExerciseMemory]) -> Exercise {
        var result = exercise
        let remembered = memory[exercise.id]
        let best = max(personalBests[exercise.id]?.estimated1RM ?? 0, remembered?.bestE1RM ?? 0)
        if best > 0 { result.previousBestE1RM = best }
        if let sets = remembered?.lastSets, !sets.isEmpty { result.previousSets = sets }
        return result
    }

    /// One pass over the history (optionally for a single exercise id): latest sets and best e1RM per exercise.
    func exerciseMemory(only id: String? = nil) -> [String: ExerciseMemory] {
        var memory: [String: ExerciseMemory] = [:]
        for workout in history {
            var setsByExercise: [String: [CompletedSet]] = [:]
            var bestByExercise: [String: Double] = [:]
            var order: [String] = []
            for entry in workout.exercises {
                if let id, entry.exerciseID != id { continue }
                if setsByExercise[entry.exerciseID] == nil { order.append(entry.exerciseID) }
                setsByExercise[entry.exerciseID, default: []].append(contentsOf: entry.sets)
                bestByExercise[entry.exerciseID] = max(bestByExercise[entry.exerciseID] ?? 0, StrengthData.bestE1RM(of: entry))
            }
            for exerciseID in order {
                let sets = setsByExercise[exerciseID] ?? []
                var item = memory[exerciseID] ?? ExerciseMemory(lastDate: .distantPast, lastSets: [], bestE1RM: 0)
                item.bestE1RM = max(item.bestE1RM, bestByExercise[exerciseID] ?? 0)
                if !sets.isEmpty, (item.lastSets.isEmpty || workout.finishedAt > item.lastDate) {
                    item.lastDate = workout.finishedAt
                    item.lastSets = sets.map { PreviousSet(weightKg: $0.weightKg, reps: $0.reps) }
                }
                memory[exerciseID] = item
            }
        }
        return memory
    }

    /// The e1RM recorded on the entry, or (when none was recorded) the best Epley estimate of its non-warm-up sets.
    static func bestE1RM(of entry: CompletedExercise) -> Double {
        if entry.bestE1RM > 0 { return entry.bestE1RM }
        return bestSet(in: entry.sets, tracking: entry.tracking)?.e1RM ?? 0
    }

    /// The non-warm-up set with the highest Epley estimate (the first one on a tie); nil without a weight-tracking set.
    static func bestSet(in sets: [CompletedSet], tracking: TrackingKind) -> (e1RM: Double, weightKg: Double, reps: Int)? {
        guard tracking == .weightReps else { return nil }
        var best: (e1RM: Double, weightKg: Double, reps: Int)?
        for set in sets where set.type != .warmup {
            let value = Estimated1RM.epley(weightKg: set.weightKg, reps: set.reps)
            if value > 0, value > (best?.e1RM ?? 0) { best = (value, set.weightKg, set.reps) }
        }
        return best
    }
}

// MARK: - Changes

public extension StrengthData {
    /// Adds (or replaces, by id) a custom exercise. An id that belongs to a built-in exercise is ignored.
    mutating func addCustomExercise(_ exercise: Exercise) {
        guard ExerciseLibrary.exercise(id: exercise.id) == nil else { return }
        var stored = exercise
        stored.isCustom = true
        if let index = customExercises.firstIndex(where: { $0.id == stored.id }) {
            customExercises[index] = stored
        } else {
            customExercises.append(stored)
        }
    }

    /// Inserts a template, or replaces the one with the same id (keeping its position).
    mutating func saveTemplate(_ template: WorkoutTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
    }

    /// Adds a plan, or replaces the one with the same id (keeping its position). A plan that is saved active deactivates the others.
    mutating func savePlan(_ plan: WorkoutPlan) {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
        if plan.isActive { activatePlan(id: plan.id) }
    }

    /// Makes the plan the only active one. Does nothing for an unknown id.
    mutating func activatePlan(id: UUID) {
        guard plans.contains(where: { $0.id == id }) else { return }
        for index in plans.indices { plans[index].isActive = plans[index].id == id }
    }

    /// Removes a plan. Its workouts stay saved as templates.
    mutating func deletePlan(id: UUID) {
        plans.removeAll { $0.id == id }
    }

    /// Passes over the next workout of a plan without doing it.
    mutating func skipNextWorkout(planID: UUID) {
        guard let index = plans.firstIndex(where: { $0.id == planID }) else { return }
        plans[index].skip(in: templates)
    }

    /// Adds the plans, templates and exercises of an import bundle (see `PlanBundle`).
    ///
    /// * A template with a known id is replaced by the imported one but keeps its `lastPerformed`; a new one is appended.
    /// * A plan with a known id is replaced but keeps its place in the rotation and whether it is active; a new plan becomes the
    ///   active one (the user has just chosen to import it).
    /// * Exercises: the bundle's custom exercises and the custom exercises the templates use are added (never over a built-in id).
    @discardableResult
    mutating func importBundle(_ bundle: PlanBundle) -> PlanImportSummary {
        let bundle = bundle.sanitized()
        var customCount = 0
        var customs = bundle.customExercises
        for template in bundle.templates {
            for entry in template.entries where entry.exercise.isCustom && !customs.contains(where: { $0.id == entry.exercise.id }) {
                customs.append(entry.exercise)
            }
        }
        for exercise in customs {
            if !customExercises.contains(where: { $0.id == exercise.id }) { customCount += 1 }
            addCustomExercise(exercise)
        }
        for template in bundle.templates {
            var incoming = template
            incoming.lastPerformed = self.template(id: template.id)?.lastPerformed
            saveTemplate(incoming)
        }
        for plan in bundle.plans {
            var incoming = plan
            if let existing = plans.first(where: { $0.id == plan.id }) {
                incoming.isActive = existing.isActive
                incoming.nextIndex = incoming.templateIDs.isEmpty ? 0 : min(existing.nextIndex, incoming.templateIDs.count - 1)
                savePlan(incoming)
            } else {
                incoming.isActive = true
                savePlan(incoming)
            }
        }
        return PlanImportSummary(plans: bundle.plans.count, templates: bundle.templates.count, customExercises: customCount)
    }

    /// Records a finished workout.
    ///
    /// * History: inserted newest first (a workout with the same id is replaced).
    /// * Personal bests: raised for every exercise whose best estimated 1RM beats the stored one.
    /// * Templates: the workout's template gets `lastPerformed`; `updateTemplate` (when given) replaces the stored template with the same id
    ///   (or is added) and also gets `lastPerformed`.
    /// * Plans: every plan that contains the workout's template moves on to the workout after it (once per workout: recording the same
    ///   workout id again does not advance the rotation again).
    mutating func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) {
        let isNewWorkout = !history.contains { $0.id == completed.id }
        history.removeAll { $0.id == completed.id }
        let index = history.firstIndex { $0.finishedAt <= completed.finishedAt } ?? history.endIndex
        history.insert(completed, at: index)

        for entry in completed.exercises {
            let value = StrengthData.bestE1RM(of: entry)
            guard value > 0, value > (personalBests[entry.exerciseID]?.estimated1RM ?? 0) else { continue }
            let set = StrengthData.bestSet(in: entry.sets, tracking: entry.tracking)
            personalBests[entry.exerciseID] = PersonalBest(
                exerciseID: entry.exerciseID,
                estimated1RM: value,
                weightKg: set?.weightKg ?? 0,
                reps: set?.reps ?? 0,
                date: completed.finishedAt
            )
        }

        if let id = completed.templateID, let position = templates.firstIndex(where: { $0.id == id }) {
            templates[position].lastPerformed = Self.later(templates[position].lastPerformed, completed.finishedAt)
        }
        if var updated = updateTemplate {
            updated.lastPerformed = Self.later(updated.lastPerformed, completed.finishedAt)
            saveTemplate(updated)
        }
        if isNewWorkout, let id = completed.templateID {
            for index in plans.indices { plans[index].advance(after: id) }
        }
    }

    /// Fills an empty store (no templates, no history) with the demo templates, history and personal bests; true when it did.
    @discardableResult
    mutating func seedDemoDataIfEmpty(now: Date) -> Bool {
        guard isEmpty else { return false }
        let demo = StrengthData.demo(now: now)
        templates = demo.templates
        history = demo.history
        if personalBests.isEmpty { personalBests = demo.personalBests }
        return true
    }

    /// The demo data for `now` (see `SampleData`): three templates, five finished workouts and the matching personal bests.
    static func demo(now: Date) -> StrengthData {
        StrengthData(
            templates: SampleData.templates(now: now),
            history: SampleData.history(now: now),
            customExercises: [],
            personalBests: SampleData.personalBests(now: now)
        )
    }

    private static func later(_ existing: Date?, _ candidate: Date) -> Date {
        guard let existing else { return candidate }
        return max(existing, candidate)
    }
}

// MARK: - Exercise history

public extension StrengthData {
    /// The sessions, e1RM trend, records and 30-day totals behind the exercise detail screen.
    func history(for exerciseID: String, now: Date) -> ExerciseHistory {
        let sessions = exerciseSessions(for: exerciseID)
        let tracking = sessions.first?.tracking ?? ExerciseLibrary.exercise(id: exerciseID)?.tracking
            ?? customExercises.first { $0.id == exerciseID }?.tracking ?? .weightReps

        // Oldest first for the trend.
        let series = sessions.reversed().compactMap { item -> E1RMPoint? in
            item.e1RM > 0 ? E1RMPoint(date: item.session.date, value: item.e1RM) : nil
        }

        var bestValue = 0.0
        var bestWeight = 0.0
        var bestReps = 0
        var bestDate: Date?
        for item in sessions.reversed() {
            guard let set = StrengthData.bestSet(in: item.session.sets, tracking: tracking), set.e1RM > bestValue else { continue }
            bestValue = set.e1RM
            bestWeight = set.weightKg
            bestReps = set.reps
            bestDate = item.session.date
        }
        let seriesBest = series.map { $0.value }.max() ?? 0
        bestValue = max(bestValue, seriesBest)
        if let stored = personalBests[exerciseID], stored.estimated1RM > bestValue + 1e-9 {
            bestValue = stored.estimated1RM
            bestWeight = stored.weightKg
            bestReps = stored.reps
            bestDate = stored.date
        }

        let threshold = now.addingTimeInterval(-30 * 86_400)
        let recent = sessions.filter { $0.session.date >= threshold }
        let volume = recent.reduce(0.0) { $0 + $1.volumeKg }

        var bestSetText: String?
        switch tracking {
        case .weightReps:
            if bestValue > 0, bestReps > 0 { bestSetText = NumberText.kg(bestWeight) + " kg × " + String(bestReps) }
        case .repsOnly:
            if let top = StrengthData.topSet(in: sessions, by: { $0.reps }) {
                bestSetText = String(top.value) + (top.value == 1 ? " rep" : " reps")
                bestDate = top.date
            }
        case .duration:
            if let top = StrengthData.topSet(in: sessions, by: { $0.reps }) {
                bestSetText = String(top.value) + " s"
                bestDate = top.date
            }
        }

        return ExerciseHistory(
            exerciseID: exerciseID,
            sessions: sessions.map { $0.session },
            e1RMSeries: Array(series),
            bestE1RM: tracking == .weightReps ? bestValue : 0,
            bestSetText: bestSetText,
            bestSetDate: bestSetText == nil ? nil : bestDate,
            volumeLast30Days: volume,
            sessionsLast30Days: recent.count,
            records: records(for: tracking, sessions: sessions, bestE1RM: bestValue, bestDate: bestDate, bestSetText: bestSetText)
        )
    }
}

private struct SessionItem {
    var session: ExerciseSession
    var tracking: TrackingKind
    var e1RM: Double
    var volumeKg: Double
}

private extension StrengthData {
    /// Every workout that contains the exercise, newest first (entries of one workout are merged into one session).
    func exerciseSessions(for exerciseID: String) -> [SessionItem] {
        var items: [(offset: Int, item: SessionItem)] = []
        for (offset, workout) in self.history.enumerated() {
            let entries = workout.exercises.filter { $0.exerciseID == exerciseID && !$0.sets.isEmpty }
            guard let first = entries.first else { continue }
            let sets = entries.flatMap { $0.sets }
            let volume = first.tracking == .weightReps
                ? sets.reduce(0.0) { $0 + ($1.type == .warmup ? 0 : $1.weightKg * Double($1.reps)) }
                : 0
            let session = ExerciseSession(
                id: workout.id,
                date: workout.finishedAt,
                workoutName: workout.name,
                sets: sets,
                isPersonalRecord: entries.contains { $0.isPersonalRecord }
            )
            let e1RM = entries.map { StrengthData.bestE1RM(of: $0) }.max() ?? 0
            items.append((offset, SessionItem(session: session, tracking: first.tracking, e1RM: e1RM, volumeKg: volume)))
        }
        items.sort { lhs, rhs in
            if lhs.item.session.date != rhs.item.session.date { return lhs.item.session.date > rhs.item.session.date }
            return lhs.offset < rhs.offset
        }
        return items.map { $0.item }
    }

    /// The set with the highest `value` (the newest session wins a tie), with the session date.
    static func topSet(in sessions: [SessionItem], by value: (CompletedSet) -> Int) -> (value: Int, date: Date)? {
        var best: (value: Int, date: Date)?
        for item in sessions {
            for set in item.session.sets where set.type != .warmup {
                let candidate = value(set)
                if candidate > 0, candidate > (best?.value ?? 0) { best = (candidate, item.session.date) }
            }
        }
        return best
    }

    func records(
        for tracking: TrackingKind,
        sessions: [SessionItem],
        bestE1RM: Double,
        bestDate: Date?,
        bestSetText: String?
    ) -> [ExerciseRecordRow] {
        guard !sessions.isEmpty else { return [] }
        var rows: [ExerciseRecordRow] = []

        // Best session by a numeric measure (the newest session wins a tie).
        func bestSession(_ measure: (SessionItem) -> Double) -> (value: Double, date: Date)? {
            var best: (value: Double, date: Date)?
            for item in sessions {
                let value = measure(item)
                if value > 0, value > (best?.value ?? 0) { best = (value, item.session.date) }
            }
            return best
        }

        switch tracking {
        case .weightReps:
            if bestE1RM > 0 {
                rows.append(ExerciseRecordRow(id: "e1rm", label: "Estimated 1RM", value: NumberText.thousands(bestE1RM) + " kg", date: bestDate))
            }
            if let text = bestSetText {
                rows.append(ExerciseRecordRow(id: "bestSet", label: "Best set", value: text, date: bestDate))
            }
            if let common = commonWorkingWeight(in: sessions) {
                var most = 0
                var mostDate: Date?
                for item in sessions {
                    for set in item.session.sets where set.type != .warmup && set.weightKg == common && set.reps > most {
                        most = set.reps
                        mostDate = item.session.date
                    }
                }
                if most > 0 {
                    rows.append(ExerciseRecordRow(id: "repsAtWeight", label: "Most reps at " + NumberText.kg(common) + " kg", value: String(most), date: mostDate))
                }
            }
            if let top = bestSession({ $0.volumeKg }) {
                rows.append(ExerciseRecordRow(id: "bestVolume", label: "Best session volume", value: NumberText.thousands(top.value) + " kg", date: top.date))
            }
        case .repsOnly:
            if let top = StrengthData.topSet(in: sessions, by: { $0.reps }) {
                rows.append(ExerciseRecordRow(id: "mostReps", label: "Most reps in a set", value: String(top.value), date: top.date))
            }
            if let top = bestSession({ item in Double(item.session.sets.reduce(0) { $0 + ($1.type == .warmup ? 0 : $1.reps) }) }) {
                rows.append(ExerciseRecordRow(id: "bestSessionReps", label: "Best session reps", value: NumberText.thousands(top.value), date: top.date))
            }
        case .duration:
            if let top = StrengthData.topSet(in: sessions, by: { $0.reps }) {
                rows.append(ExerciseRecordRow(id: "longest", label: "Longest set", value: String(top.value) + " s", date: top.date))
            }
            if let top = bestSession({ item in Double(item.session.sets.reduce(0) { $0 + ($1.type == .warmup ? 0 : $1.reps) }) }) {
                rows.append(ExerciseRecordRow(id: "bestSessionTime", label: "Best session time", value: NumberText.clock(seconds: Int(top.value)), date: top.date))
            }
        }
        return rows
    }

    /// The working (non-warm-up, weight above zero) weight used in the most sets; the heavier one on a tie.
    func commonWorkingWeight(in sessions: [SessionItem]) -> Double? {
        var counts: [Double: Int] = [:]
        for item in sessions {
            for set in item.session.sets where set.type != .warmup && set.weightKg > 0 {
                counts[set.weightKg, default: 0] += 1
            }
        }
        var best: (weight: Double, count: Int)?
        for (weight, count) in counts {
            if let current = best, count < current.count || (count == current.count && weight < current.weight) { continue }
            best = (weight, count)
        }
        return best?.weight
    }
}

// MARK: - Model (data + persistence)

/// A `StrengthData` bound to a `FileStrengthPersistence`: loads on creation, saves what a change touched, caches the exercise overlay.
///
/// `StrengthStore` wraps this class with Combine publishing; the class itself is platform neutral so it runs (and is tested) everywhere.
@MainActor
public final class StrengthDataModel: WorkoutDataProviding {
    /// The current data.
    public private(set) var data: StrengthData
    /// The first error of the last save that failed; nil when the last save wrote every file it was asked to write.
    public private(set) var lastPersistenceError: Error?

    private let persistence: FileStrengthPersistence?
    private var cache: (list: [Exercise], byID: [String: Exercise])?

    /// Loads `persistence` (when given); with `seedDemoData` an empty store is filled with the demo data for `now`.
    public init(persistence: FileStrengthPersistence?, seedDemoData: Bool = false, now: Date = Date()) {
        self.persistence = persistence
        self.data = StrengthData()
        loadFromDisk()
        if seedDemoData, data.seedDemoDataIfEmpty(now: now) {
            persist(templates: true, history: true, customExercises: false, personalBests: true)
        }
    }

    /// The built-in and custom exercises with the user's previous results overlaid (cached until the next change).
    public var exercises: [Exercise] { overlayCache().list }

    /// One exercise by id (built-in or custom) with the user's previous results overlaid.
    public func exercise(id: String) -> Exercise? { overlayCache().byID[id] }

    /// One template by id.
    public func template(id: UUID) -> WorkoutTemplate? { data.template(id: id) }

    /// Adds a custom exercise and saves the custom exercises.
    public func addCustomExercise(_ exercise: Exercise) {
        let before = data.customExercises
        data.addCustomExercise(exercise)
        guard data.customExercises != before else { return }
        cache = nil
        persist(templates: false, history: false, customExercises: true, personalBests: false)
    }

    /// Adds or replaces a template and saves the templates.
    public func saveTemplate(_ template: WorkoutTemplate) {
        data.saveTemplate(template)
        persist(templates: true, history: false, customExercises: false, personalBests: false)
    }

    /// The workout to recommend next (see `StrengthData.nextTemplate`).
    public func nextTemplate() -> WorkoutTemplate? { data.nextTemplate() }

    /// Adds or replaces a plan and saves the plans.
    public func savePlan(_ plan: WorkoutPlan) {
        data.savePlan(plan)
        persist(templates: false, history: false, customExercises: false, personalBests: false, plans: true)
    }

    /// Makes a plan the active one and saves the plans.
    public func activatePlan(id: UUID) {
        data.activatePlan(id: id)
        persist(templates: false, history: false, customExercises: false, personalBests: false, plans: true)
    }

    /// Removes a plan (its templates stay) and saves the plans.
    public func deletePlan(id: UUID) {
        data.deletePlan(id: id)
        persist(templates: false, history: false, customExercises: false, personalBests: false, plans: true)
    }

    /// Passes over the next workout of a plan and saves the plans.
    public func skipNextWorkout(planID: UUID) {
        data.skipNextWorkout(planID: planID)
        persist(templates: false, history: false, customExercises: false, personalBests: false, plans: true)
    }

    /// Imports a plan file (see `PlanBundle`). Nothing changes when the file cannot be read.
    public func importPlan(from fileData: Data) -> Result<PlanImportSummary, PlanImportError> {
        let bundle: PlanBundle
        do {
            bundle = try PlanBundle.decode(from: fileData)
        } catch let error as PlanImportError {
            return .failure(error)
        } catch {
            return .failure(.unreadable)
        }
        let summary = data.importBundle(bundle)
        cache = nil
        persist(templates: true, history: false, customExercises: true, personalBests: false, plans: true)
        return .success(summary)
    }

    /// Records a finished workout (history, personal bests, template) and saves what changed.
    ///
    /// The data changes in memory in every case. The result is `.failure` when the workout could not be written to the history
    /// file, which is the only place the workout's sets are kept; the other files are derived (the personal bests are re-read from
    /// the history) or secondary (the template), so failing to write them is reported through `lastPersistenceError` only.
    /// Every file is rewritten in full by its next save, so unsaved data is saved then.
    @discardableResult
    public func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) -> Result<Void, Error> {
        data.record(completed, updateTemplate: updateTemplate)
        cache = nil
        if let historyError = persist(templates: true, history: true, customExercises: false, personalBests: true, plans: true) {
            return .failure(historyError)
        }
        return .success(())
    }

    /// The history of one exercise as shown on its detail screen.
    public func history(for exerciseID: String, now: Date) -> ExerciseHistory {
        data.history(for: exerciseID, now: now)
    }

    /// Re-reads everything from disk (no-op without persistence).
    public func reload() {
        guard persistence != nil else { return }
        loadFromDisk()
    }

    private func loadFromDisk() {
        guard let persistence else { return }
        data = StrengthData(
            templates: persistence.loadTemplates(),
            history: persistence.loadHistory(),
            customExercises: persistence.loadCustomExercises(),
            personalBests: persistence.loadPersonalBests(),
            plans: persistence.loadPlans()
        )
        cache = nil
    }

    private func overlayCache() -> (list: [Exercise], byID: [String: Exercise]) {
        if let cache { return cache }
        let list = data.exercises()
        var byID: [String: Exercise] = [:]
        for exercise in list { byID[exercise.id] = exercise }
        cache = (list, byID)
        return (list, byID)
    }

    /// Writes the requested files, attempting every one even when an earlier one fails.
    ///
    /// Sets `lastPersistenceError` to the first error (nil when every requested file was written) and returns the error of the
    /// history file, nil when it was written or not requested.
    @discardableResult
    private func persist(templates: Bool, history: Bool, customExercises: Bool, personalBests: Bool, plans: Bool = false) -> Error? {
        guard let persistence else {
            lastPersistenceError = nil
            return nil
        }
        var firstError: Error?
        var historyError: Error?
        func attempt(_ write: () throws -> Void) -> Error? {
            do {
                try write()
                return nil
            } catch {
                if firstError == nil { firstError = error }
                return error
            }
        }
        if templates { _ = attempt { try persistence.saveTemplates(data.templates) } }
        if history { historyError = attempt { try persistence.saveHistory(data.history) } }
        if customExercises { _ = attempt { try persistence.saveCustomExercises(data.customExercises) } }
        if personalBests { _ = attempt { try persistence.savePersonalBests(data.personalBests) } }
        if plans { _ = attempt { try persistence.savePlans(data.plans) } }
        lastPersistenceError = firstError
        return historyError
    }
}
