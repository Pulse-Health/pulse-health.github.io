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
    /// The sessions of one workout (by name) when at least `minimum` of them exist, else the whole history.
    ///
    /// The same lift is often trained in two workouts with different schemes (heavy and light days, upper A and B). Judged together,
    /// the engine would compare a heavy day with a light day and never see two sessions of the same kind. Names are compared without
    /// case and surrounding spaces; a name nobody has used leaves the history unchanged.
    func scoped(toWorkoutNamed name: String?, minimum: Int = 2) -> ExerciseHistory {
        guard let name else { return self }
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return self }
        let matching = sessions.filter {
            $0.workoutName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted
        }
        guard matching.count >= minimum else { return self }
        var scoped = self
        scoped.sessions = matching
        return scoped
    }
}

/// Puts the engine's answers where the screens need them. Pure: the caller passes the history in.
public enum CoachPlanner {
    /// The hub card's "Next time" lines: the first `limit` exercises of `template` that have something to aim for.
    ///
    /// Each exercise is judged on the sessions of this template (see `ExerciseHistory.scoped(toWorkoutNamed:)`). When none has a
    /// target, a single "Log RIR" hint is returned for the first exercise that lacks effort data, so the lines nudge without
    /// nagging. Exercises that appear twice are listed once. A `limit` of zero or less returns nothing.
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
                for: current, history: history(id).scoped(toWorkoutNamed: template.name),
                audience: audience, config: config, now: now
            )
            guard let line = TemplateWriter.line(for: recommendation, config: config) else { continue }
            let item = NextTimeItem(exerciseName: current.name, recommendation: recommendation, line: line)
            if recommendation.verdict.hasTarget {
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

    /// The suggestion for one exercise of the running workout, or nil when there is nothing useful to show.
    ///
    /// Shown only before the first set is logged, and judged on the sessions of the same workout (`workoutName`) when there are at
    /// least two. A target is shown only when applying it would change something; the "Log RIR" hint is shown without actions.
    ///
    /// Apply changes the **top group** of the pending `.normal` sets: the sets at the heaviest pending weight. Lighter back-off sets,
    /// pyramids and ramps keep what the person planned, and warm-ups, drop sets and failure sets are never touched.
    public static func suggestion(
        for entry: WorkoutExercise,
        history: ExerciseHistory,
        workoutName: String? = nil,
        audience: AudienceProfile = .unknown,
        config: CoachConfig = CoachConfig(),
        now: Date
    ) -> WorkoutSuggestion? {
        guard entry.exercise.tracksWeight, entry.doneCount == 0 else { return nil }
        let recommendation = ProgressionEngine.recommend(
            for: entry.exercise, history: history.scoped(toWorkoutNamed: workoutName),
            audience: audience, config: config, now: now
        )
        guard let line = TemplateWriter.line(for: recommendation, config: config) else { return nil }

        guard recommendation.verdict.hasTarget,
              let weight = recommendation.targetWeightKg, let reps = recommendation.targetReps
        else {
            return WorkoutSuggestion(recommendation: recommendation, line: line, actions: [])
        }

        let pending = entry.sets.filter { !$0.isDone && $0.type == .normal }
        let topWeight = pending.map { $0.weightKg }.max() ?? 0
        var actions: [WorkoutAction] = []
        for set in pending where abs(set.weightKg - topWeight) <= 0.005 {
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
}
