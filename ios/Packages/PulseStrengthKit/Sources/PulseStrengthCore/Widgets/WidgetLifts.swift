import Foundation

/// The lifts the user trains most, their estimated-1RM trends, plateaus and strength ratio
/// (widgets/SPEC.md section 2: lifts, plateaus, strengthRatio).
enum WidgetLifts {
    /// How far back a lift has to have been trained to be listed.
    static let windowDays = 90
    /// Most lifts listed.
    static let maximumLifts = 8
    /// Most sessions in a lift's trend.
    static let maximumPoints = 6
    /// Plateaus listed.
    static let maximumPlateaus = 4
    /// The tip on the first lift that went flat.
    static let plateauTip = "Try 3 × 8 at about 90% for two weeks."

    /// One day of one lift: its best estimated 1RM of a workout (rounded to 0.1) and the day that workout belongs to.
    struct Session {
        var date: Date
        var day: Int
        var value: Double
    }

    /// A listed lift with every session of the history, oldest first (the block uses them all, the trend only the last few).
    struct Series {
        var trend: LiftTrend
        var sessions: [Session]
    }

    // MARK: Lifts

    /// Up to 8 weight-tracking exercises that were trained in the last 90 days, most workouts first (then the most recent, then the
    /// smaller id).
    ///
    /// A session is a workout with at least one set of the exercise that has an estimate above zero; its value is the greatest
    /// `CompletedExercise.bestE1RM` of the exercise in that workout, or, when that is 0, the best Epley estimate of its non-warm-up
    /// sets. `points` are the last 6 sessions of the whole history, oldest first, rounded to 0.1. `bestE1RM` is the best of those
    /// points; `prIndex` marks it when it is later than the first point and beat every earlier one. `sessionCount` counts the sessions
    /// of the last 90 days (a day count from `now`, no upper bound).
    static func lifts(_ history: WidgetHistory) -> [Series] {
        var byExercise: [String: (name: String, sessions: [Session])] = [:]
        // Oldest first; a tie keeps the older position of the history (which is newest first).
        let ordered = history.entries.enumerated().sorted { lhs, rhs in
            lhs.element.workout.finishedAt != rhs.element.workout.finishedAt
                ? lhs.element.workout.finishedAt < rhs.element.workout.finishedAt
                : lhs.offset > rhs.offset
        }
        for (_, entry) in ordered {
            var seen = Set<String>()
            for exercise in entry.workout.exercises where exercise.tracking == .weightReps {
                // The same exercise twice in one workout is one session.
                guard seen.insert(exercise.exerciseID).inserted else { continue }
                let value = sessionValue(of: exercise.exerciseID, in: entry.workout)
                guard value > 0 else { continue }
                var item = byExercise[exercise.exerciseID] ?? (exercise.name, [])
                item.name = exercise.name
                item.sessions.append(Session(date: entry.workout.finishedAt, day: entry.day, value: WidgetText.tenth(value)))
                byExercise[exercise.exerciseID] = item
            }
        }

        let cutoff = history.now.addingTimeInterval(-Double(windowDays) * 86_400)
        let ranked = byExercise.compactMap { id, item -> (id: String, name: String, sessions: [Session], recent: Int)? in
            let recent = item.sessions.filter { $0.date >= cutoff }.count
            return recent > 0 ? (id, item.name, item.sessions, recent) : nil
        }.sorted { lhs, rhs in
            if lhs.recent != rhs.recent { return lhs.recent > rhs.recent }
            if let left = lhs.sessions.last?.date, let right = rhs.sessions.last?.date, left != right { return left > right }
            return lhs.id < rhs.id
        }
        return ranked.prefix(maximumLifts).map { item in
            Series(trend: trend(id: item.id, name: item.name, sessions: item.sessions, recent: item.recent), sessions: item.sessions)
        }
    }

    /// The value of one lift in one workout: the greatest recorded `bestE1RM` of the exercise, else the best Epley estimate of its
    /// non-warm-up sets.
    private static func sessionValue(of exerciseID: String, in workout: CompletedWorkout) -> Double {
        let entries = workout.exercises.filter { $0.exerciseID == exerciseID }
        let recorded = entries.map { $0.bestE1RM }.max() ?? 0
        guard recorded <= 0 else { return recorded }
        var best = 0.0
        for entry in entries {
            for set in entry.sets where set.type != .warmup {
                best = max(best, Estimated1RM.epley(weightKg: set.weightKg, reps: set.reps))
            }
        }
        return best
    }

    private static func trend(id: String, name: String, sessions: [Session], recent: Int) -> LiftTrend {
        let points = sessions.suffix(maximumPoints).map { TrendPoint(date: $0.date, value: $0.value) }
        let values = points.map { $0.value }
        let best = values.max() ?? 0
        let firstBest = values.firstIndex(of: best)
        return LiftTrend(
            exerciseID: id,
            name: name,
            points: points,
            currentE1RM: values.last ?? 0,
            bestE1RM: best,
            prIndex: firstBest.flatMap { $0 > 0 ? $0 : nil },
            sessionCount: recent,
            deltaKg: values.count > 1 ? WidgetText.tenth(values[values.count - 1] - values[values.count - 2]) : 0
        )
    }

    // MARK: Plateaus

    /// The first 4 lifts with at least 3 points, each as rising, flat or falling.
    ///
    /// `p` is the latest point that set a new best (strictly above every earlier point; the first point counts) and `flatSessions` is
    /// `count - p`. With 3 or more of them and the last point within 3 % of the best the lift is flat; with 2 or more and the last
    /// point more than 3 % below the best it is falling; otherwise it is rising. The first flat lift carries the tip.
    static func plateaus(_ lifts: [Series]) -> [PlateauFlag] {
        var flags: [PlateauFlag] = []
        var tipGiven = false
        for lift in lifts.map({ $0.trend }) where lift.points.count >= 3 {
            guard flags.count < maximumPlateaus else { break }
            let values = lift.points.map { $0.value }
            let best = values.max() ?? 0
            var latestBest = 0
            var runningBest = -Double.infinity
            for (index, value) in values.enumerated() where value > runningBest {
                runningBest = value
                latestBest = index
            }
            let flatSessions = values.count - latestBest
            let last = values[values.count - 1]
            let status: TrendStatus
            if flatSessions >= 3 && last >= 0.97 * best {
                status = .flat
            } else if flatSessions >= 2 && last < 0.97 * best {
                status = .falling
            } else {
                status = .rising
            }
            var tip: String?
            if status == .flat && !tipGiven {
                tip = plateauTip
                tipGiven = true
            }
            flags.append(PlateauFlag(exerciseID: lift.exerciseID, name: lift.name, status: status, flatSessions: flatSessions, tip: tip))
        }
        return flags
    }

    // MARK: Strength ratio

    /// The main lifts and the bodyweight multiple the app suggests as a goal for each.
    private static let goalRatios: [String: Double] = ["bench": 1.5, "squat": 2.0, "deadlift": 2.5, "ohp": 1.0]

    /// The first listed lift that is bench press, squat, deadlift or overhead press against `bodyweightKg` (nil when unknown or not
    /// above zero): the best estimated 1RM, the ratio to the body weight rounded to 0.01 and the goal ratio of that lift.
    static func strengthRatio(_ lifts: [Series], bodyweightKg: Double?) -> StrengthRatio? {
        guard let lift = lifts.map({ $0.trend }).first(where: { goalRatios[$0.exerciseID] != nil }) else { return nil }
        let weight = bodyweightKg.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return StrengthRatio(
            exerciseID: lift.exerciseID,
            exerciseName: lift.name,
            estimated1RM: lift.bestE1RM,
            bodyweightKg: weight,
            ratio: weight.map { WidgetText.hundredth(lift.bestE1RM / $0) },
            goalRatio: goalRatios[lift.exerciseID] ?? 1.5
        )
    }
}
