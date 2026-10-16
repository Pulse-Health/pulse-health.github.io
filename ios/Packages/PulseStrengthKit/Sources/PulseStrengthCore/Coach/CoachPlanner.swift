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

/// Puts the engine's answers where the screens need them. Pure: the caller passes the history in.
public enum CoachPlanner {
    /// The hub card's "Next time" lines: the first `limit` exercises of `template` that have something to aim for.
    ///
    /// When none has, a single "Log RIR" hint is returned for the first exercise that lacks effort data, so the lines nudge
    /// without nagging. Exercises that appear twice are listed once.
    public static func nextTime(
        for template: WorkoutTemplate,
        exercise: (String) -> Exercise?,
        history: (String) -> ExerciseHistory,
        audience: AudienceProfile = .unknown,
        config: CoachConfig = CoachConfig(),
        now: Date,
        limit: Int = 3
    ) -> [NextTimeItem] {
        var seen = Set<String>()
        var targets: [NextTimeItem] = []
        var hint: NextTimeItem?
        for entry in template.entries {
            let id = entry.exercise.id
            guard seen.insert(id).inserted else { continue }
            let current = exercise(id) ?? entry.exercise
            let recommendation = ProgressionEngine.recommend(
                for: current, history: history(id), audience: audience, config: config, now: now
            )
            guard let line = TemplateWriter.line(for: recommendation) else { continue }
            let item = NextTimeItem(exerciseName: current.name, recommendation: recommendation, line: line)
            if recommendation.verdict.hasTarget {
                if targets.count < max(0, limit) { targets.append(item) }
            } else if hint == nil {
                hint = item
            }
        }
        if targets.isEmpty, let hint { return [hint] }
        return targets
    }

    /// The suggestion for one exercise of the running workout, or nil when there is nothing useful to show.
    ///
    /// Shown only before the first set is logged. A target is shown only when applying it would change something; the "Log RIR"
    /// hint is shown without actions. Apply changes the pending `.normal` sets only (warm-ups, drop sets and failure sets keep
    /// what the person entered).
    public static func suggestion(
        for entry: WorkoutExercise,
        history: ExerciseHistory,
        audience: AudienceProfile = .unknown,
        config: CoachConfig = CoachConfig(),
        now: Date
    ) -> WorkoutSuggestion? {
        guard entry.exercise.tracksWeight, entry.doneCount == 0 else { return nil }
        let recommendation = ProgressionEngine.recommend(
            for: entry.exercise, history: history, audience: audience, config: config, now: now
        )
        guard let line = TemplateWriter.line(for: recommendation) else { return nil }

        guard recommendation.verdict.hasTarget,
              let weight = recommendation.targetWeightKg, let reps = recommendation.targetReps
        else {
            return WorkoutSuggestion(recommendation: recommendation, line: line, actions: [])
        }

        var actions: [WorkoutAction] = []
        for set in entry.sets where !set.isDone && set.type == .normal {
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
