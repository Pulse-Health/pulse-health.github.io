import Foundation

/// One line of the hub card: what to aim for next time on one exercise of the template.
public struct NextTimeItem: Identifiable, Equatable, Sendable {
    public var id: String { recommendation.exerciseID }
    public var exerciseName: String
    public var recommendation: Recommendation
    public var line: CoachLine

    public init(exerciseName: String, recommendation: Recommendation, line: CoachLine) {
        self.exerciseName = exerciseName
        self.recommendation = recommendation
        self.line = line
    }
}

/// A suggestion shown on an exercise card of the running workout, with the existing actions that apply it.
public struct WorkoutSuggestion: Equatable, Sendable {
    public var recommendation: Recommendation
    public var line: CoachLine
    /// `setWeight` / `setReps` actions for the pending working sets. Empty when nothing needs to change or the line is only a hint.
    public var actions: [WorkoutAction]

    public init(recommendation: Recommendation, line: CoachLine, actions: [WorkoutAction]) {
        self.recommendation = recommendation
        self.line = line
        self.actions = actions
    }
}

extension ExerciseHistory {
    /// The sessions of one workout (by name) when at least `minimum` of them exist and they are not stale, else the whole history.
    ///
    /// The same lift is often trained in two workouts with different schemes (heavy and light days, upper A and B). Judged together,
    /// the engine would compare a heavy day with a light day and never see two sessions of the same kind. Names are compared without
    /// case and surrounding spaces; a name nobody has used leaves the history unchanged. When the newest session of this workout is
    /// more than `breakDays` older than the newest session of the lift in any workout, the lift has been trained since in another
    /// workout and the whole history is used, so a two-year-old "Chest day" cannot hide last week's training.
    func scoped(toWorkoutNamed name: String?, now: Date, minimum: Int = 2, breakDays: Int = 28) -> ExerciseHistory {
        guard let name else { return self }
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return self }
        let matching = sessions.filter {
            $0.workoutName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted
        }
        guard matching.count >= minimum else { return self }
        // Dates the engine would ignore (not a number, or a day or more ahead of `now`) cannot decide which sessions are the newest.
        func newest(_ rows: [ExerciseSession]) -> Date? {
            rows.map { $0.date }.filter { $0.timeIntervalSinceReferenceDate.isFinite && $0.timeIntervalSince(now) <= 86_400 }.max()
        }
        if let newestOfWorkout = newest(matching), let newestOverall = newest(sessions),
           newestOverall.timeIntervalSince(newestOfWorkout) > (Double(breakDays) + 0.5) * 86_400 {
            return self
        }
        var scoped = self
        scoped.sessions = matching
        return scoped
    }
}

/// Puts the engine's answers where the screens need them. Pure: the caller passes the history in.
public enum CoachPlanner {
    /// The hub card's "Next time" lines: the first `limit` exercises of `template` that have something to aim for.
    ///
    /// Each exercise is judged on the sessions of this template's workout name when there are at least two (see
    /// `ExerciseHistory.scoped`). A line whose weight is far from the weight the template plans for that exercise
    /// (`CoachConfig.maximumPlanDeviation`) is left out. When none has a target, a single "Log RIR" hint is returned for the first
    /// exercise that lacks effort data, so the lines nudge without nagging. Exercises that appear twice are listed once. A `limit`
    /// of zero or less returns nothing.
    public static func nextTime(
        for template: WorkoutTemplate,
        exercise: (String) -> Exercise?,
        history: (String) -> ExerciseHistory,
        audience: AudienceProfile = .unknown,
        config: CoachConfig = CoachConfig(),
        now: Date,
        limit: Int = 3
    ) -> [NextTimeItem] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var targets: [NextTimeItem] = []
        var hint: NextTimeItem?
        for entry in template.entries {
            let id = entry.exercise.id
            guard seen.insert(id).inserted else { continue }
            let current = exercise(id) ?? entry.exercise
            let recommendation = ProgressionEngine.recommend(
                for: current, history: history(id).scoped(toWorkoutNamed: template.name, now: now, breakDays: config.breakDays),
                audience: audience, config: config, now: now
            )
            guard let line = lineFor(recommendation, config: config) else { continue }
            let item = NextTimeItem(exerciseName: current.name, recommendation: recommendation, line: line)
            if recommendation.verdict.hasTarget {
                let planned = entry.plannedSets.filter { $0.type == .normal }.map { $0.weightKg }.max() ?? 0
                guard fitsPlan(recommendation, plannedKg: planned, config: config) else { continue }
                targets.append(item)
                // Enough lines: neither the rest of the template nor a hint is needed.
                if targets.count >= limit { return targets }
            } else if hint == nil {
                hint = item
            }
        }
        if targets.isEmpty, let hint { return [hint] }
        return targets
    }

    /// What the engine says about one exercise of the running workout, whatever the sets look like, or nil for an exercise without a
    /// weight, or when its weight is far from the planned one (see `nextTime`). The card uses it to decide whether the "beat your
    /// best" tip would contradict a coach line that is, or would be, shown.
    public static func recommendation(
        for entry: WorkoutExercise,
        history: ExerciseHistory,
        workoutName: String? = nil,
        audience: AudienceProfile = .unknown,
        config: CoachConfig = CoachConfig(),
        now: Date
    ) -> Recommendation? {
        guard entry.exercise.tracksWeight else { return nil }
        let recommendation = ProgressionEngine.recommend(
            for: entry.exercise, history: history.scoped(toWorkoutNamed: workoutName, now: now, breakDays: config.breakDays),
            audience: audience, config: config, now: now
        )
        let planned = entry.sets.filter { $0.type == .normal || $0.type == .failure }.map { $0.weightKg }.max() ?? 0
        return fitsPlan(recommendation, plannedKg: planned, config: config) ? recommendation : nil
    }

    /// The suggestion for one exercise of the running workout, or nil when there is nothing useful to show.
    ///
    /// Shown only before the first set is logged, and judged on the sessions of the same workout (`workoutName`) when there are at
    /// least two. A target is shown only when applying it would change something and is not far from the plan (see `nextTime`); the
    /// "Log RIR" hint and the note after a long break are shown without actions.
    ///
    /// Apply changes the **top group** of the pending sets: the sets at the heaviest pending weight, counting to-failure sets (the
    /// engine judges the heaviest set) but changing only the `.normal` ones. When the target is lighter than that group, the pending
    /// `.normal` sets between the target and the group move down with it, so that a second tap has nothing left to change. Lighter
    /// back-off sets, pyramids and ramps keep what the person planned, and warm-ups, drop sets and failure sets are never touched.
    public static func suggestion(
        for entry: WorkoutExercise,
        history: ExerciseHistory,
        workoutName: String? = nil,
        audience: AudienceProfile = .unknown,
        config: CoachConfig = CoachConfig(),
        now: Date
    ) -> WorkoutSuggestion? {
        guard entry.doneCount == 0,
              let recommendation = Self.recommendation(
                  for: entry, history: history, workoutName: workoutName, audience: audience, config: config, now: now
              ),
              let line = lineFor(recommendation, config: config)
        else { return nil }

        guard recommendation.verdict.hasTarget,
              let weight = recommendation.targetWeightKg, let reps = recommendation.targetReps
        else {
            return WorkoutSuggestion(recommendation: recommendation, line: line, actions: [])
        }
        // After a long break the person is told what they did last time and to ease back in; the plan is never raised to it.
        if recommendation.reasons.contains(.returningAfterBreak) {
            return WorkoutSuggestion(recommendation: recommendation, line: line, actions: [])
        }

        let pending = entry.sets.filter { !$0.isDone && ($0.type == .normal || $0.type == .failure) }
        let topWeight = pending.map { $0.weightKg }.max() ?? 0
        guard fitsPlan(recommendation, plannedKg: topWeight, config: config) else { return nil }
        // Raising the top group changes only that group; lowering it takes every normal set above the target down with it.
        let floor = min(topWeight, weight) - 0.005
        var actions: [WorkoutAction] = []
        for set in pending where set.type == .normal && set.weightKg >= floor {
            if abs(set.weightKg - weight) > 0.005 {
                actions.append(.setWeight(exerciseID: entry.id, setID: set.id, kg: weight))
            }
            if set.reps != reps {
                actions.append(.setReps(exerciseID: entry.id, setID: set.id, reps: reps))
            }
        }
        // Already matches the plan: nothing to apply, nothing to say.
        if actions.isEmpty { return nil }
        return WorkoutSuggestion(recommendation: recommendation, line: line, actions: actions)
    }

    private static func lineFor(_ recommendation: Recommendation, config: CoachConfig) -> CoachLine? {
        TemplateWriter.line(for: recommendation, config: config)
    }

    /// Whether the recommended weight is close enough to the planned weight to be about the same scheme. A plan of 0 kg (an imported
    /// template that has no weights yet) and a recommendation after a long break are always fine.
    private static func fitsPlan(_ recommendation: Recommendation, plannedKg: Double, config: CoachConfig) -> Bool {
        guard let weight = recommendation.targetWeightKg, plannedKg > 0 else { return true }
        if recommendation.reasons.contains(.returningAfterBreak) { return true }
        // The slack keeps a deviation of exactly the limit on paper (17.2 against 21.5 kg is 20 %) on the same side whatever rounding does.
        return abs(weight - plannedKg) <= config.maximumPlanDeviation * max(weight, plannedKg) * (1 + 1e-9)
    }
}
