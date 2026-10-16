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
    /// The user's body weight over time, newest first (see `BodyWeight.swift`).
    public var bodyWeights: [BodyWeightEntry]
    /// How often the app asks the user to update their weight.
    public var weighIn: WeighInPreferences
    /// The user's workout preferences (unit, rest timer, goal, ...), see `StrengthPreferences`.
    public var preferences: StrengthPreferences
    /// True while `history` is known to lack workouts that could not be read from disk. The personal bests may then be the only
    /// trace of those workouts, so `recomputePersonalBests()` only raises them and never lowers or drops one.
    public var historyIsIncomplete: Bool
    /// True when the demo data was seeded into this store in this process (previews and UI tests): the built-in exercises then
    /// carry the invented previous results of `DemoPreviousResults` until the user's own history replaces them. Never stored; a
    /// real user's store is always false, so the previous column and the record baseline come from real history only.
    public var usesDemoPreviousResults: Bool

    /// Creates the data from its collections.
    public init(
        templates: [WorkoutTemplate] = [],
        history: [CompletedWorkout] = [],
        customExercises: [Exercise] = [],
        personalBests: [String: PersonalBest] = [:],
        bodyWeights: [BodyWeightEntry] = [],
        weighIn: WeighInPreferences = WeighInPreferences(),
        preferences: StrengthPreferences = StrengthPreferences(),
        historyIsIncomplete: Bool = false,
        usesDemoPreviousResults: Bool = false
    ) {
        self.templates = templates
        self.history = history
        self.customExercises = customExercises
        self.personalBests = personalBests
        self.bodyWeights = bodyWeights
        self.weighIn = weighIn
        self.preferences = preferences
        self.historyIsIncomplete = historyIsIncomplete
        self.usesDemoPreviousResults = usesDemoPreviousResults
    }

    /// True when there are neither templates nor finished workouts (the condition for seeding demo data).
    public var isEmpty: Bool { templates.isEmpty && history.isEmpty }

    /// The template with the given id.
    public func template(id: UUID) -> WorkoutTemplate? {
        templates.first { $0.id == id }
    }
}

// MARK: - Exercises with remembered results

public extension StrengthData {
    /// The built-in library plus the custom exercises, each with `previousBestE1RM` and `previousSets` taken from the user's results.
    ///
    /// An exercise with no personal best or history has none (0 and no sets), except in a demo store (`usesDemoPreviousResults`),
    /// where it keeps the invented demo values. A custom exercise whose id equals a built-in id is ignored.
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

    /// `exercise` with the remembered best e1RM and last sets of the same exercise id applied (anything remembered wins). In a demo
    /// store an exercise with nothing remembered gets the demo numbers of its id; otherwise it keeps what it carries.
    func overlay(_ exercise: Exercise) -> Exercise {
        overlay(exercise, memory: exerciseMemory(only: exercise.id))
    }
}

/// What the history says about one exercise: its latest sets, its best estimated 1RM and its record marks.
private struct ExerciseMemory {
    var lastDate: Date
    var lastSets: [PreviousSet]
    var bestE1RM: Double
    var marks: RecordMarks
}

private extension StrengthData {
    func allExercises() -> [Exercise] {
        var seen = Set(ExerciseLibrary.builtIn.map { $0.id })
        var result = ExerciseLibrary.builtIn
        for custom in customExercises where seen.insert(custom.id).inserted {
            result.append(custom)
        }
        return result
    }

    func overlay(_ exercise: Exercise, memory: [String: ExerciseMemory]) -> Exercise {
        var result = usesDemoPreviousResults ? DemoPreviousResults.applying(to: exercise) : exercise
        let remembered = memory[exercise.id]
        let stored = personalBests[exercise.id]?.withoutUnreliableEstimate
        let best = max(stored?.estimated1RM ?? 0, remembered?.bestE1RM ?? 0)
        if best > 0 { result.previousBestE1RM = best }
        if let sets = remembered?.lastSets, !sets.isEmpty { result.previousSets = sets }
        var marks = stored?.marks ?? RecordMarks()
        if let remembered { marks.merge(remembered.marks) }
        if !marks.isEmpty { result.previousRecords = marks }
        return result
    }

    /// One pass over the history (optionally for a single exercise id): latest sets, best e1RM and record marks per exercise.
    ///
    /// The latest sets are those of the exercise's most recent workout, and of ONE entry of it: when the exercise appears twice in that
    /// workout, the first entry that has sets (an exercise that appears twice has its occurrences matched to the same previous sets, see
    /// `PresenterSupport.matchedPreviousSets`). The bests and marks come from every entry of every workout.
    func exerciseMemory(only id: String? = nil) -> [String: ExerciseMemory] {
        var memory: [String: ExerciseMemory] = [:]
        for workout in history {
            var firstSets: [String: [CompletedSet]] = [:]
            var bestByExercise: [String: Double] = [:]
            var marksByExercise: [String: RecordMarks] = [:]
            for entry in workout.exercises {
                if let id, entry.exerciseID != id { continue }
                if !entry.sets.isEmpty, firstSets[entry.exerciseID] == nil { firstSets[entry.exerciseID] = entry.sets }
                bestByExercise[entry.exerciseID] = max(bestByExercise[entry.exerciseID] ?? 0, StrengthData.bestE1RM(of: entry))
                var marks = marksByExercise[entry.exerciseID] ?? RecordMarks()
                marks.merge(RecordMarks(entry: entry))
                marksByExercise[entry.exerciseID] = marks
            }
            for (exerciseID, best) in bestByExercise {
                var item = memory[exerciseID] ?? ExerciseMemory(lastDate: .distantPast, lastSets: [], bestE1RM: 0, marks: RecordMarks())
                item.bestE1RM = max(item.bestE1RM, best)
                item.marks.merge(marksByExercise[exerciseID] ?? RecordMarks())
                if let sets = firstSets[exerciseID], item.lastSets.isEmpty || workout.finishedAt > item.lastDate {
                    item.lastDate = workout.finishedAt
                    item.lastSets = sets.map { PreviousSet(weightKg: $0.weightKg, reps: $0.reps, type: $0.type == .normal ? nil : $0.type, rir: $0.rir) }
                }
                memory[exerciseID] = item
            }
        }
        return memory
    }

    /// The best estimated 1RM of the entry: the best estimate (`Estimated1RM.estimate`, sets of 1...12 reps) of its non-warm-up sets,
    /// or, when the entry recorded one, that value.
    ///
    /// A value recorded before the 12-rep cap that came from a set of more reps (20 kg x 100 reps was "estimated" at 87 kg) is no
    /// estimate any more and gives way to what the sets say.
    static func bestE1RM(of entry: CompletedExercise) -> Double {
        let derived = bestSet(in: entry.sets, tracking: entry.tracking)?.e1RM ?? 0
        guard entry.bestE1RM > 0 else { return derived }
        if entry.tracking == .weightReps, derived < entry.bestE1RM, entry.sets.contains(where: { set in
            set.type != .warmup && set.reps > Estimated1RM.maximumReliableReps
                && Estimated1RM.epley(weightKg: set.weightKg, reps: set.reps) == entry.bestE1RM
        }) {
            return derived
        }
        return entry.bestE1RM
    }

    /// The non-warm-up set with the highest estimate (`Estimated1RM.estimate`; the first one on a tie); nil without a weight-tracking
    /// set that has one.
    static func bestSet(in sets: [CompletedSet], tracking: TrackingKind) -> (e1RM: Double, weightKg: Double, reps: Int)? {
        guard tracking == .weightReps else { return nil }
        var best: (e1RM: Double, weightKg: Double, reps: Int)?
        for set in sets where set.type != .warmup {
            guard let value = Estimated1RM.estimate(weightKg: set.weightKg, reps: set.reps) else { continue }
            if value > (best?.e1RM ?? 0) { best = (value, set.weightKg, set.reps) }
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

    /// Records a finished workout.
    ///
    /// * History: inserted newest first (a workout with the same id is replaced).
    /// * Personal bests: raised for every exercise whose best estimated 1RM beats the stored one, and for every mark (heaviest weight,
    ///   rep records, most reps, longest hold) the workout raises. The result is the same as `recomputePersonalBests()` over the new
    ///   history; a workout that replaced an earlier one with the same id recomputes them, because the earlier version may have held
    ///   a best the new one does not reach.
    /// * Templates: the workout's template gets `lastPerformed`; `updateTemplate` (when given) replaces the stored template with the same id
    ///   (or is added) and also gets `lastPerformed`.
    mutating func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) {
        let replaced = history.contains { $0.id == completed.id }
        history.removeAll { $0.id == completed.id }
        let index = history.firstIndex { $0.finishedAt <= completed.finishedAt } ?? history.endIndex
        history.insert(completed, at: index)

        if replaced {
            recomputePersonalBests()
        } else {
            for entry in completed.exercises {
                StrengthData.raiseBest(&personalBests, with: entry, at: completed.finishedAt)
            }
        }

        if let id = completed.templateID, let position = templates.firstIndex(where: { $0.id == id }) {
            templates[position].lastPerformed = Self.later(templates[position].lastPerformed, completed.finishedAt)
        }
        if var updated = updateTemplate {
            updated.lastPerformed = Self.later(updated.lastPerformed, completed.finishedAt)
            saveTemplate(updated)
        }
    }

    /// The personal bests as a pure function of the complete history: for every exercise the best estimated 1RM of any workout
    /// (the e1RM recorded on the entry, or the best estimate of its non-warm-up sets of 1...12 reps), with the set, reps and date that
    /// reached it, and the marks of `RecordMarks` over all its non-warm-up sets (heaviest weight, rep records, most reps, longest
    /// hold). The earliest workout wins a tie, an exercise without an estimate has the date of its earliest workout with a mark, and
    /// bests of exercises without history (or without a single set that counts) do not exist.
    func recomputedPersonalBests() -> [String: PersonalBest] {
        // Oldest first; workouts with the same finish time keep the order in which they were recorded (the newer one is listed first).
        let ordered = history.enumerated().sorted { lhs, rhs in
            lhs.element.finishedAt != rhs.element.finishedAt ? lhs.element.finishedAt < rhs.element.finishedAt : lhs.offset > rhs.offset
        }
        var bests: [String: PersonalBest] = [:]
        for item in ordered {
            for entry in item.element.exercises {
                StrengthData.raiseBest(&bests, with: entry, at: item.element.finishedAt)
            }
        }
        return bests
    }

    /// Replaces the personal bests with `recomputedPersonalBests()`: a best can go down when the workout that set it was changed or deleted.
    ///
    /// While `historyIsIncomplete` the stored bests are kept and only raised by the recomputed ones (a better value, or an exercise
    /// that has none yet), because a best that the readable history does not explain may belong to a workout that could not be read.
    mutating func recomputePersonalBests() {
        let recomputed = recomputedPersonalBests()
        guard historyIsIncomplete else {
            personalBests = recomputed
            return
        }
        for (id, candidate) in recomputed {
            personalBests[id] = personalBests[id]?.raised(by: candidate) ?? candidate
        }
    }

    /// The best estimated 1RM and the record marks per exercise id among the workouts older than the one at `index` of the (newest
    /// first) history: what a workout at that position had to beat.
    internal func baselines(inWorkoutsOlderThanIndex index: Int) -> [String: (e1RM: Double, marks: RecordMarks)] {
        var baselines: [String: (e1RM: Double, marks: RecordMarks)] = [:]
        for workout in history.dropFirst(index + 1) {
            for entry in workout.exercises {
                var item = baselines[entry.exerciseID] ?? (0, RecordMarks())
                item.e1RM = max(item.e1RM, StrengthData.bestE1RM(of: entry))
                item.marks.merge(RecordMarks(entry: entry))
                baselines[entry.exerciseID] = item
            }
        }
        return baselines
    }

    /// Raises the best of the exercise of `entry` (finished at `date`) with what the entry reached (see `PersonalBest.raised(by:)`).
    fileprivate static func raiseBest(_ bests: inout [String: PersonalBest], with entry: CompletedExercise, at date: Date) {
        let estimate = bestE1RM(of: entry)
        let value = estimate.isFinite && estimate > 0 ? estimate : 0
        let marks = RecordMarks(entry: entry)
        guard value > 0 || !marks.isEmpty else { return }
        let set = value > 0 ? bestSet(in: entry.sets, tracking: entry.tracking) : nil
        let candidate = PersonalBest(
            exerciseID: entry.exerciseID,
            estimated1RM: value,
            weightKg: set?.weightKg ?? 0,
            reps: set?.reps ?? 0,
            date: date,
            heaviestKg: marks.heaviestKg,
            repRecords: marks.repRecords,
            bestReps: marks.bestReps,
            bestSeconds: marks.bestSeconds
        )
        bests[entry.exerciseID] = bests[entry.exerciseID]?.raised(by: candidate) ?? candidate
    }

    /// Fills an empty store (no templates, no history) with the demo templates, history and personal bests and switches on the demo
    /// previous results (`usesDemoPreviousResults`); true when it did. Only previews and UI tests seed.
    @discardableResult
    mutating func seedDemoDataIfEmpty(now: Date) -> Bool {
        guard isEmpty else { return false }
        let demo = StrengthData.demo(now: now)
        templates = demo.templates
        history = demo.history
        if personalBests.isEmpty { personalBests = demo.personalBests }
        usesDemoPreviousResults = true
        return true
    }

    /// The demo data for `now` (see `SampleData`): three templates, five finished workouts and the matching personal bests, with
    /// the demo previous results switched on.
    static func demo(now: Date) -> StrengthData {
        StrengthData(
            templates: SampleData.templates(now: now),
            history: SampleData.history(now: now),
            customExercises: [],
            personalBests: SampleData.personalBests(now: now),
            usesDemoPreviousResults: true
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
    ///
    /// The texts in it ("85 kg × 5", the record rows) are written in the unit and with the separators of `format` (default: kilograms,
    /// en_US); the numbers (`bestE1RM`, `volumeLast30Days`, the sets) stay in kilograms.
    func history(for exerciseID: String, now: Date, format: DisplayFormat = .metric) -> ExerciseHistory {
        let formatter = format.formatter
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
        if let stored = personalBests[exerciseID]?.withoutUnreliableEstimate, stored.estimated1RM > bestValue + 1e-9 {
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
            if bestValue > 0, bestReps > 0 { bestSetText = String(format: "%@ × %ld", formatter.textWithUnit(kg: bestWeight), bestReps) }
        case .repsOnly:
            if let top = StrengthData.topSet(in: sessions, by: { $0.bodyweightReps }) {
                bestSetText = String(top.value) + (top.value == 1 ? " rep" : " reps")
                bestDate = top.date
            }
        case .duration:
            if let top = StrengthData.topSet(in: sessions, by: { $0.reps }) {
                bestSetText = String(top.value) + " s"
                bestDate = top.date
            }
        }

        let marks = datedMarks(of: sessions, stored: personalBests[exerciseID])
        return ExerciseHistory(
            exerciseID: exerciseID,
            sessions: sessions.map { $0.session },
            e1RMSeries: Array(series),
            bestE1RM: tracking == .weightReps ? bestValue : 0,
            bestSetText: bestSetText,
            bestSetDate: bestSetText == nil ? nil : bestDate,
            volumeLast30Days: volume,
            sessionsLast30Days: recent.count,
            records: records(
                for: tracking, sessions: sessions, bestE1RM: bestValue, bestDate: bestDate, bestSetText: bestSetText, marks: marks, formatter: formatter
            ) + bodyWeightRecords(
                for: exerciseID, tracking: tracking, sessions: sessions,
                bestE1RM: tracking == .weightReps ? bestValue : 0, bestDate: bestDate, formatter: formatter
            ),
            previousSets: exerciseMemory(only: exerciseID)[exerciseID]?.lastSets ?? []
        )
    }
}

private extension CompletedSet {
    /// The reps of a set of a reps-only exercise without an added or assisted load (what `RecordMarks.bestReps` counts); 0 for a loaded set.
    var bodyweightReps: Int { abs(weightKg) < 0.005 ? reps : 0 }
}

private struct SessionItem {
    var session: ExerciseSession
    var tracking: TrackingKind
    var carriesLoad: Bool
    var e1RM: Double
    var volumeKg: Double
}

/// Record marks with the date each was reached.
private struct DatedMarks {
    var marks = RecordMarks()
    var heaviestDate: Date?
    var repDates: [Int: Date] = [:]
    var repsDate: Date?
    var secondsDate: Date?

    /// Raises every mark that `other` (reached at `date`) beats; the date of a mark only changes when it is beaten, so feeding the
    /// sessions oldest first dates each mark with the earliest session that reached it.
    mutating func raise(with other: RecordMarks, at date: Date) {
        if let heaviest = other.heaviestKg, heaviest > marks.heaviestKg ?? -.infinity {
            marks.heaviestKg = heaviest
            heaviestDate = date
        }
        for (reps, weight) in other.repRecords where weight > marks.repRecords[reps] ?? -.infinity {
            marks.repRecords[reps] = weight
            repDates[reps] = date
        }
        if other.bestReps > marks.bestReps {
            marks.bestReps = other.bestReps
            repsDate = date
        }
        if other.bestSeconds > marks.bestSeconds {
            marks.bestSeconds = other.bestSeconds
            secondsDate = date
        }
    }
}

private extension StrengthData {
    /// Every workout that contains the exercise, newest first (entries of one workout are merged into one session).
    func exerciseSessions(for exerciseID: String) -> [SessionItem] {
        var items: [(offset: Int, item: SessionItem)] = []
        for (offset, workout) in self.history.enumerated() {
            let entries = workout.exercises.filter { $0.exerciseID == exerciseID && !$0.sets.isEmpty }
            guard let first = entries.first else { continue }
            let sets = entries.flatMap { $0.sets }
            // Weight x reps; a reps-only exercise counts its added loads only (bodyweight and assisted sets add nothing).
            let volume = first.tracking == .duration
                ? 0
                : sets.reduce(0.0) { $0 + ($1.type == .warmup ? 0 : max(0, $1.weightKg) * Double($1.reps)) }
            let session = ExerciseSession(
                id: workout.id,
                date: workout.finishedAt,
                workoutName: workout.name,
                sets: sets,
                isPersonalRecord: entries.contains { $0.isPersonalRecord }
            )
            let e1RM = entries.map { StrengthData.bestE1RM(of: $0) }.max() ?? 0
            items.append((offset, SessionItem(session: session, tracking: first.tracking, carriesLoad: first.carriesLoad, e1RM: e1RM, volumeKg: volume)))
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
        bestSetText: String?,
        marks: DatedMarks,
        formatter: WeightFormatter
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
                rows.append(ExerciseRecordRow(id: "e1rm", label: "Estimated 1RM", value: formatter.volumeWithUnit(kg: bestE1RM), date: bestDate))
            }
            if let text = bestSetText {
                rows.append(ExerciseRecordRow(id: "bestSet", label: "Best set", value: text, date: bestDate))
            }
            rows.append(contentsOf: loadRows(marks, label: "Heaviest weight", format: { formatter.textWithUnit(kg: $0) }))
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
                    rows.append(ExerciseRecordRow(
                        id: "repsAtWeight", label: String(format: "Most reps at %@", formatter.textWithUnit(kg: common)), value: String(most), date: mostDate
                    ))
                }
            }
            if let top = bestSession({ $0.volumeKg }) {
                rows.append(ExerciseRecordRow(id: "bestVolume", label: "Best session volume", value: formatter.volumeWithUnit(kg: top.value), date: top.date))
            }
        case .repsOnly:
            var most = StrengthData.topSet(in: sessions, by: { $0.bodyweightReps })
            if marks.marks.bestReps > (most?.value ?? 0), let date = marks.repsDate { most = (marks.marks.bestReps, date) }
            if let top = most {
                rows.append(ExerciseRecordRow(id: "mostReps", label: "Most reps in a set", value: String(top.value), date: top.date))
            }
            rows.append(contentsOf: loadRows(marks, label: "Heaviest added weight", format: { formatter.signedText(kg: $0) + " " + formatter.unit.symbol }))
            if let top = bestSession({ item in Double(item.session.sets.reduce(0) { $0 + ($1.type == .warmup ? 0 : $1.reps) }) }) {
                rows.append(ExerciseRecordRow(id: "bestSessionReps", label: "Best session reps", value: NumberText.thousands(top.value), date: top.date))
            }
        case .duration:
            var longest = StrengthData.topSet(in: sessions, by: { $0.reps })
            if marks.marks.bestSeconds > (longest?.value ?? 0), let date = marks.secondsDate { longest = (marks.marks.bestSeconds, date) }
            if let top = longest {
                rows.append(ExerciseRecordRow(id: "longest", label: "Longest set", value: String(top.value) + " s", date: top.date))
            }
            if let top = bestSession({ item in Double(item.session.sets.reduce(0) { $0 + ($1.type == .warmup ? 0 : $1.reps) }) }) {
                rows.append(ExerciseRecordRow(id: "bestSessionTime", label: "Best session time", value: NumberText.clock(seconds: Int(top.value)), date: top.date))
            }
        }
        return rows
    }

    /// The rows of the load marks: the heaviest weight ("heaviest") and the best 3, 5 and 8 rep maxes ("rm3", "rm5", "rm8": the
    /// heaviest weight for at least that many reps), each only when achieved. A mark of 0 (bodyweight, as a reps-only exercise that
    /// carries a load counts it) is no load worth a row. `format` writes a weight with its unit.
    func loadRows(_ marks: DatedMarks, label heaviestLabel: String, format: (Double) -> String) -> [ExerciseRecordRow] {
        var rows: [ExerciseRecordRow] = []
        if let heaviest = marks.marks.heaviestKg, heaviest != 0 {
            rows.append(ExerciseRecordRow(id: "heaviest", label: heaviestLabel, value: format(heaviest), date: marks.heaviestDate))
        }
        for reps in [3, 5, 8] {
            guard let weight = marks.marks.repRecords[reps], weight != 0 else { continue }
            rows.append(ExerciseRecordRow(
                id: "rm\(reps)", label: String(format: "Best %ldRM", reps), value: format(weight), date: marks.repDates[reps]
            ))
        }
        return rows
    }

    /// The record marks over all sessions with the date of the earliest session that reached each, raised by the stored personal best
    /// (`stored`, dated with its own date) where that is higher: it can hold a mark of workouts that cannot be read any more.
    func datedMarks(of sessions: [SessionItem], stored: PersonalBest?) -> DatedMarks {
        var dated = DatedMarks()
        for item in sessions.reversed() {
            dated.raise(with: RecordMarks(sets: item.session.sets, tracking: item.tracking, carriesLoad: item.carriesLoad), at: item.session.date)
        }
        if let stored { dated.raise(with: stored.marks, at: stored.date) }
        return dated
    }

    /// The record rows that need the user's body weight (none without a weigh-in):
    /// * barbell lifts: "Relative strength", the best estimated 1RM as a multiple of the body weight on the day it was set;
    /// * push-ups, chest dips and pull-ups (`BodyweightLoad`): "Best session load (est.)", the working reps times the share of the
    ///   body weight one rep moves times the body weight of that session (the session with the most wins; the newest on a tie).
    func bodyWeightRecords(
        for exerciseID: String,
        tracking: TrackingKind,
        sessions: [SessionItem],
        bestE1RM: Double,
        bestDate: Date?,
        formatter: WeightFormatter
    ) -> [ExerciseRecordRow] {
        guard !bodyWeights.isEmpty else { return [] }
        switch tracking {
        case .weightReps:
            let exercise = ExerciseLibrary.exercise(id: exerciseID) ?? customExercises.first { $0.id == exerciseID }
            guard bestE1RM > 0, exercise?.equipment == .barbell,
                  let weight = bodyWeightKg(at: bestDate ?? sessions.first?.session.date ?? Date()), weight > 0
            else { return [] }
            return [ExerciseRecordRow(
                id: "relativeStrength",
                label: "Relative strength",
                value: String(format: "%@ bodyweight", BodyWeightRules.multipleText(bestE1RM / weight, locale: formatter.locale)),
                date: bestDate
            )]
        case .repsOnly:
            guard let factor = BodyweightLoad.factor(exerciseID: exerciseID) else { return [] }
            var best: (load: Double, date: Date)?
            for item in sessions {
                guard let weight = bodyWeightKg(at: item.session.date) else { continue }
                let reps = item.session.sets.reduce(0) { $0 + ($1.type == .warmup ? 0 : $1.reps) }
                let load = Double(reps) * factor * weight
                if load > (best?.load ?? 0) { best = (load, item.session.date) }
            }
            guard let best else { return [] }
            return [ExerciseRecordRow(
                id: "bodyweightLoad",
                label: "Best session load (est.)",
                value: formatter.volumeWithUnit(kg: best.load),
                date: best.date
            )]
        case .duration:
            return []
        }
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
///
/// Every mutating call changes the data in memory first and then writes the files it touched (and only those). A write that fails
/// keeps the in-memory change and is reported: through the returned `Result` and through `lastPersistenceError`. A file whose write
/// failed is written again by the next save of anything. Writing several files is not transactional; the order is chosen so that a
/// failure in the middle loses nothing: the history first (the only copy of the sets), then the custom exercises, the personal bests
/// (derived from the history) and the templates.
@MainActor
public final class StrengthDataModel: WorkoutDataProviding {
    /// The current data.
    public internal(set) var data: StrengthData
    /// The first error of the last save that failed; nil when the last save wrote every file it was asked to write.
    public private(set) var lastPersistenceError: Error?
    /// The problems found while loading the files that the user has not acknowledged yet (see `PersistenceIssue`).
    public private(set) var persistenceIssues: [PersistenceIssue] = []

    let persistence: FileStrengthPersistence?
    var cache: (list: [Exercise], byID: [String: Exercise])?
    private var unsavedFiles: PersistTargets = []
    /// The locale whose region picks the weight unit of preferences that are created (a first launch, a reset); nil means kilograms.
    let deviceLocale: Locale?
    /// True once `preferences.json` exists (written, or found at load). Until then the next save of anything writes it, so the
    /// unit picked from the region at the first launch is kept even if the region changes later. Loading writes nothing.
    private var preferencesStored = false

    /// Loads `persistence` (when given); with `seedDemoData` an empty store is filled with the demo data for `now` and shows the
    /// demo previous results (`StrengthData.usesDemoPreviousResults`). The app seeds only in previews and UI tests.
    ///
    /// Demo data is only written to a data directory that has no data files at all and no load issues: files that exist but
    /// could not be read are never seeded over.
    ///
    /// Without a saved `preferences.json` the preferences are the defaults of a new install, with the weight unit that `deviceLocale`
    /// calls for (the app passes `Locale.current`; nil, the default of tests and previews, means kilograms). A directory that holds
    /// templates, history or other data of an older build keeps kilograms whatever the region.
    public init(persistence: FileStrengthPersistence?, seedDemoData: Bool = false, now: Date = Date(), deviceLocale: Locale? = nil) {
        self.persistence = persistence
        self.deviceLocale = deviceLocale
        self.data = StrengthData(preferences: StrengthDataModel.newInstallPreferences(deviceLocale))
        loadFromDisk()
        let mayWrite = persistence.map { !$0.hasDataFiles && persistenceIssues.isEmpty } ?? true
        if seedDemoData, mayWrite, data.seedDemoDataIfEmpty(now: now) {
            persist(templates: true, history: true, customExercises: false, personalBests: true)
        }
    }

    /// The built-in and custom exercises with the user's previous results overlaid (cached until the next change).
    public var exercises: [Exercise] { overlayCache().list }

    /// One exercise by id (built-in or custom) with the user's previous results overlaid.
    public func exercise(id: String) -> Exercise? { overlayCache().byID[id] }

    /// One template by id.
    public func template(id: UUID) -> WorkoutTemplate? { data.template(id: id) }

    /// Adds a custom exercise (or replaces the one with the same id) and saves the custom exercises. `.failure` when the id belongs
    /// to a built-in exercise (nothing changes) or when the file could not be written (the exercise is added in memory).
    @discardableResult
    public func addCustomExercise(_ exercise: Exercise) -> Result<Void, Error> {
        guard ExerciseLibrary.exercise(id: exercise.id) == nil else { return .failure(StrengthStoreError.reservedExerciseID) }
        let before = data.customExercises
        data.addCustomExercise(exercise)
        guard data.customExercises != before else { return .success(()) }
        return commit(customExercises: true, exercises: true)
    }

    /// Adds or replaces a template and saves the templates. A template with a known id keeps its position, a new one is appended.
    /// `.failure` when the file could not be written (the template is saved in memory).
    @discardableResult
    public func saveTemplate(_ template: WorkoutTemplate) -> Result<Void, Error> {
        data.saveTemplate(template)
        return commit(templates: true)
    }

    /// Records a finished workout (history, personal bests, template) and saves what changed.
    ///
    /// The data changes in memory in every case. The result is `.failure` when the workout could not be written to the history
    /// file, which is the only place the workout's sets are kept; the other files are derived (the personal bests can be recomputed
    /// from the history) or secondary (the template), so failing to write them is reported through `lastPersistenceError` only.
    /// The templates and the personal bests are written only when the workout changed them.
    @discardableResult
    public func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) -> Result<Void, Error> {
        let templatesBefore = data.templates
        let bestsBefore = data.personalBests
        data.record(completed, updateTemplate: updateTemplate)
        cache = nil
        let failures = persist(
            templates: data.templates != templatesBefore,
            history: true,
            customExercises: false,
            personalBests: data.personalBests != bestsBefore
        )
        if let failure = failures.first(where: { $0.target == .history }) { return .failure(failure.error) }
        return .success(())
    }

    /// The history of one exercise as shown on its detail screen, with its texts in the unit of the preferences and the separators of
    /// `locale` (default: en_US).
    public func history(for exerciseID: String, now: Date, locale: Locale = DisplayFormat.metric.locale) -> ExerciseHistory {
        data.history(for: exerciseID, now: now, format: DisplayFormat(unit: data.preferences.weightUnit, locale: locale))
    }

    /// Stores a body weight (kg, rounded to 0.1) and saves the weigh-ins. nil, and nothing saved, when `kg` is not a plausible body weight.
    @discardableResult
    public func recordBodyWeight(kg: Double, date: Date) -> BodyWeightEntry? {
        guard let entry = data.recordBodyWeight(kg: kg, date: date) else { return nil }
        persist(templates: false, history: false, customExercises: false, personalBests: false, bodyWeights: true)
        return entry
    }

    /// Adds the body weights read from Apple Health that are not here yet (see `StrengthData.mergeHealthBodyWeights`) and saves
    /// them; returns how many were added.
    @discardableResult
    public func importHealthBodyWeights(_ samples: [HealthBodyWeightSample]) -> Int {
        let added = data.mergeHealthBodyWeights(samples)
        if added > 0 {
            persist(templates: false, history: false, customExercises: false, personalBests: false, bodyWeights: true)
        }
        return added
    }

    /// Removes a weigh-in that was entered here and saves the weigh-ins; false when there is none with that id
    /// or when it was read from Apple Health (those cannot be deleted here).
    @discardableResult
    public func deleteBodyWeight(id: UUID) -> Bool {
        guard data.deleteBodyWeight(id: id) else { return false }
        persist(templates: false, history: false, customExercises: false, personalBests: false, bodyWeights: true)
        return true
    }

    /// The user's workout preferences.
    public var preferences: StrengthPreferences { data.preferences }

    /// Replaces the workout preferences and saves them. `.failure` when the file could not be written (the preferences change in
    /// memory anyway). The counts are kept in range by `StrengthPreferences` itself.
    @discardableResult
    public func updatePreferences(_ preferences: StrengthPreferences) -> Result<Void, Error> {
        guard data.preferences != preferences || !preferencesStored else { return .success(()) }
        data.preferences = preferences
        return commit(preferences: true)
    }

    /// Replaces the weigh-in reminder preferences and saves them.
    public func setWeighInPreferences(_ preferences: WeighInPreferences) {
        guard data.weighIn != preferences else { return }
        data.weighIn = preferences
        persist(templates: false, history: false, customExercises: false, personalBests: false, weighIn: true)
    }

    /// Re-reads everything from disk (no-op without persistence).
    public func reload() {
        guard persistence != nil else { return }
        loadFromDisk()
    }

    /// Forgets the load issues the user has seen (`persistenceIssues` becomes empty). The backups of damaged files stay on disk.
    /// From then on the personal bests follow the history again, also after a history that had unreadable workouts.
    public func acknowledgePersistenceIssues() {
        persistence?.clearLoadIssues()
        persistenceIssues = []
        data.historyIsIncomplete = false
    }

    /// Takes over the issues the persistence found since the last call, such as those of the active-workout file that the
    /// workout engine reads on its own. Issues the user has not acknowledged stay, also when a later read of the file was clean
    /// (the file was rewritten since); a newer issue of the same file replaces the older one.
    public func refreshPersistenceIssues() {
        guard let persistence else { return }
        var byFile: [String: PersistenceIssue] = [:]
        for issue in persistenceIssues { byFile[issue.fileName] = issue }
        for issue in persistence.loadIssues { byFile[issue.fileName] = issue }
        persistenceIssues = byFile.values.sorted { $0.fileName < $1.fileName }
    }

    private func loadFromDisk() {
        guard let persistence else { return }
        persistence.rescanSchema()
        let bestsFileExisted = persistence.hasPersonalBestsFile
        let historyWasIncomplete = data.historyIsIncomplete
        let wasDemo = data.usesDemoPreviousResults
        // A file that exists but cannot be read counts as stored: it is left alone until the user saves new preferences (the
        // original is copied first, see `FileStrengthPersistence.write`).
        preferencesStored = persistence.hasPreferencesFile
        let preferences = persistence.loadPreferences() ?? preferencesWithoutFile(of: persistence)
        data = StrengthData(
            templates: persistence.loadTemplates(),
            history: persistence.loadHistory(),
            customExercises: persistence.loadCustomExercises(),
            personalBests: persistence.loadPersonalBests(),
            bodyWeights: persistence.loadBodyWeights(),
            weighIn: persistence.loadWeighInPreferences(),
            preferences: preferences,
            historyIsIncomplete: historyWasIncomplete,
            usesDemoPreviousResults: wasDemo
        )
        cache = nil
        refreshPersistenceIssues()
        repairDerivedData(bestsFileExisted: bestsFileExisted)
    }

    /// Fixes what is derived from the files just read: the personal bests are recomputed from the history when their file is
    /// missing, or damaged while the history is whole (a damaged history keeps the bests as they were read: they may be the only
    /// trace of a workout that could not be read); template copies of built-in exercises take over the current library.
    ///
    /// Only a missing bests file is written back. A damaged file stays as it is until the next legitimate save of it.
    private func repairDerivedData(bestsFileExisted: Bool) {
        let damaged = Set((persistence?.loadIssues ?? []).map { $0.fileName })
        let bestsDamaged = damaged.contains(FileStrengthPersistence.FileName.personalBests)
        let historyDamaged = damaged.contains(FileStrengthPersistence.FileName.history)
        if historyDamaged { data.historyIsIncomplete = true }
        if !data.history.isEmpty, !bestsFileExisted || (bestsDamaged && !historyDamaged) {
            data.recomputePersonalBests()
            if !bestsFileExisted, persistence?.canWrite == true {
                persist(templates: false, history: false, customExercises: false, personalBests: true)
            }
        }
        refreshTemplateExercises()
    }

    /// The preferences when `preferences.json` could not be loaded. A directory that already holds the user's data without a
    /// preferences file was written by a build that only knew kilograms: that user keeps kilograms (the region must not convert
    /// their history on the upgrade) and can choose pounds in the settings. Only a directory without such data is a new install.
    private func preferencesWithoutFile(of persistence: FileStrengthPersistence) -> StrengthPreferences {
        if !persistence.hasPreferencesFile, persistence.hasUserDataFilesBesidesPreferences { return StrengthPreferences() }
        return StrengthDataModel.newInstallPreferences(deviceLocale)
    }

    /// The preferences of a new install: the defaults with the unit that `deviceLocale` calls for (kilograms without a locale).
    private static func newInstallPreferences(_ deviceLocale: Locale?) -> StrengthPreferences {
        deviceLocale.map { StrengthPreferences(locale: $0) } ?? StrengthPreferences()
    }

    func overlayCache() -> (list: [Exercise], byID: [String: Exercise]) {
        if let cache { return cache }
        let list = data.exercises()
        var byID: [String: Exercise] = [:]
        for exercise in list { byID[exercise.id] = exercise }
        cache = (list, byID)
        return (list, byID)
    }

    /// The files `persist` can write.
    struct PersistTargets: OptionSet {
        let rawValue: Int
        static let templates = PersistTargets(rawValue: 1)
        static let history = PersistTargets(rawValue: 2)
        static let customExercises = PersistTargets(rawValue: 4)
        static let personalBests = PersistTargets(rawValue: 8)
        static let bodyWeights = PersistTargets(rawValue: 16)
        static let weighIn = PersistTargets(rawValue: 32)
        static let preferences = PersistTargets(rawValue: 64)
    }

    /// A file that `persist` could not write, and why.
    struct PersistFailure {
        let target: PersistTargets
        let error: Error
    }

    /// Writes the files a change touched, then the files an earlier save could not write. Every file is attempted even when an
    /// earlier one fails.
    ///
    /// Sets `lastPersistenceError` to the first error (nil when every file was written) and returns every failure, in write order.
    @discardableResult
    func persist(
        templates: Bool,
        history: Bool,
        customExercises: Bool,
        personalBests: Bool,
        bodyWeights: Bool = false,
        weighIn: Bool = false,
        preferences: Bool = false
    ) -> [PersistFailure] {
        guard let persistence else {
            lastPersistenceError = nil
            return []
        }
        var pending = unsavedFiles
        if templates { pending.insert(.templates) }
        if history { pending.insert(.history) }
        if customExercises { pending.insert(.customExercises) }
        if personalBests { pending.insert(.personalBests) }
        if bodyWeights { pending.insert(.bodyWeights) }
        if weighIn { pending.insert(.weighIn) }
        // The first save of anything also writes the preferences that were created at the first launch.
        if preferences || !preferencesStored { pending.insert(.preferences) }
        unsavedFiles = []

        var failures: [PersistFailure] = []
        func attempt(_ target: PersistTargets, _ write: () throws -> Void) {
            guard pending.contains(target) else { return }
            do {
                try write()
            } catch {
                failures.append(PersistFailure(target: target, error: error))
                unsavedFiles.insert(target)
            }
        }
        attempt(.history) { try persistence.saveHistory(data.history) }
        attempt(.customExercises) { try persistence.saveCustomExercises(data.customExercises) }
        attempt(.personalBests) { try persistence.savePersonalBests(data.personalBests) }
        attempt(.templates) { try persistence.saveTemplates(data.templates) }
        attempt(.bodyWeights) { try persistence.saveBodyWeights(data.bodyWeights) }
        attempt(.weighIn) { try persistence.saveWeighInPreferences(data.weighIn) }
        attempt(.preferences) {
            try persistence.savePreferences(data.preferences)
            preferencesStored = true
        }
        lastPersistenceError = failures.first?.error
        return failures
    }

    /// Saves the files a management change touched and reports the outcome: `.failure` with the first error among the files this
    /// change asked to write. A file that an earlier save left unwritten is retried too, but its error only reaches
    /// `lastPersistenceError`, so the result says whether this change was saved. `exercises` drops the cached exercise overlay.
    func commit(
        templates: Bool = false,
        history: Bool = false,
        customExercises: Bool = false,
        personalBests: Bool = false,
        bodyWeights: Bool = false,
        weighIn: Bool = false,
        preferences: Bool = false,
        exercises: Bool = false
    ) -> Result<Void, Error> {
        if exercises || history || personalBests { cache = nil }
        var requested: PersistTargets = []
        if templates { requested.insert(.templates) }
        if history { requested.insert(.history) }
        if customExercises { requested.insert(.customExercises) }
        if personalBests { requested.insert(.personalBests) }
        if bodyWeights { requested.insert(.bodyWeights) }
        if weighIn { requested.insert(.weighIn) }
        if preferences { requested.insert(.preferences) }
        let failures = persist(
            templates: templates,
            history: history,
            customExercises: customExercises,
            personalBests: personalBests,
            bodyWeights: bodyWeights,
            weighIn: weighIn,
            preferences: preferences
        )
        if let failure = failures.first(where: { requested.contains($0.target) }) { return .failure(failure.error) }
        return .success(())
    }

    /// Removes every data file of the persistence after the whole data was reset (`FileStrengthPersistence.deleteAll()`) and forgets
    /// the writes that were still pending: there is nothing left to write. When the removal fails (or is refused), every file counts
    /// as unwritten, so the next save of anything writes the emptied data again.
    func removeAllFiles() -> Result<Void, Error> {
        cache = nil
        guard let persistence else {
            unsavedFiles = []
            lastPersistenceError = nil
            return .success(())
        }
        do {
            try persistence.deleteAll()
            unsavedFiles = []
            preferencesStored = false
            lastPersistenceError = nil
            return .success(())
        } catch {
            unsavedFiles = [.templates, .history, .customExercises, .personalBests, .bodyWeights, .weighIn, .preferences]
            lastPersistenceError = error
            return .failure(error)
        }
    }
}
