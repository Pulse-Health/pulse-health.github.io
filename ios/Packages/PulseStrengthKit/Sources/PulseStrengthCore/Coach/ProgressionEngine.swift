import Foundation

/// Decides, from the sets a person actually performed, what to do with a lift next time.
///
/// A pure function: the same history, audience, configuration and date always give the same `Recommendation`. It reads only
/// **performed** sets (the planned target is not stored in the history, and "update template" overwrites it with the performed
/// values), counts only working sets (warm-ups and drop sets are ignored; a "to failure" set counts as reps in reserve 0), and judges
/// effort from the optional reps-in-reserve value. It never raises the weight without effort data.
///
/// The thresholds live in `CoachConfig` and have not been signed off by a qualified coach.
public enum ProgressionEngine {
    /// Bump when a rule changes; stamped into every `Recommendation` so an evaluation can tell which engine produced it.
    public static let version = 1

    /// Sets above these bounds are treated as data errors and ignored (a damaged file or a bad import), so no arithmetic can overflow.
    private static let plausibleKg = 2_000.0
    private static let plausibleReps = 1_000

    /// Two weights closer than this (kg) are the same weight.
    private static let sameWeightTolerance = 0.005

    // MARK: Entry point

    public static func recommend(
        for exercise: Exercise,
        history: ExerciseHistory,
        audience: AudienceProfile = .unknown,
        config: CoachConfig = CoachConfig(),
        now: Date
    ) -> Recommendation {
        func make(
            _ verdict: Verdict, weight: Double? = nil, reps: Int? = nil, _ reasons: [ReasonCode], sessions: Int = 0
        ) -> Recommendation {
            Recommendation(
                exerciseID: exercise.id, verdict: verdict, targetWeightKg: weight, targetReps: reps,
                reasons: reasons, sessionsUsed: sessions
            )
        }

        if audience.avoidMuscles.contains(exercise.muscle) {
            return make(.insufficientData, [.audienceRestricted])
        }
        guard exercise.tracking == .weightReps else {
            return make(.insufficientData, [.unsupportedTracking])
        }
        guard history.exerciseID == exercise.id else {
            return make(.insufficientData, [.tooFewSessions])
        }

        let prepared = prepare(history.sessions, config)
        let sessions = prepared.sessions
        let flags: [ReasonCode] = prepared.excluded > 0 ? [.suspectSetExcluded] : []
        guard sessions.count >= max(2, config.minimumSessions) else {
            return make(.insufficientData, flags + [.tooFewSessions], sessions: sessions.count)
        }

        let count = sessions.count
        let latest = sessions[0]
        let previous = sessions[1]
        let increment = config.increment(for: exercise)

        func hold(_ reasons: [ReasonCode]) -> Recommendation {
            make(.hold, weight: latest.load, reps: latest.typicalReps, flags + reasons, sessions: count)
        }

        /// A bounded reduce, or a hold when even one increment is more than the allowed share of the weight.
        func reduceOrHold(_ reasons: [ReasonCode]) -> Recommendation {
            let share = (latest.load * config.reduceFraction / increment).rounded(.down) * increment
            let amount = max(increment, share)
            let lowered = round2(latest.load - amount)
            if amount / latest.load > config.maximumReduceFraction + 1e-9 || lowered <= 0 {
                return hold(reasons + [.reduceExceedsCap])
            }
            return make(.reduce, weight: lowered, reps: latest.typicalReps, flags + reasons, sessions: count)
        }

        // 1. A long break: do not progress from old numbers.
        let daysSince = now.timeIntervalSince(latest.date) / 86_400
        if daysSince > Double(config.breakDays) {
            return hold([.returningAfterBreak])
        }

        // 2. Many increases in a row: a lighter week.
        if config.lighterWeekAfterIncreases > 0 {
            var streak = 0
            var index = 0
            while index + 1 < count, sessions[index].load > sessions[index + 1].load + sameWeightTolerance {
                streak += 1
                index += 1
            }
            if streak >= config.lighterWeekAfterIncreases {
                return reduceOrHold([.lighterWeekDue])
            }
        }

        // 3. Reps fell at the same weight two sessions in a row.
        if count >= 3 {
            let oldest = sessions[2]
            let sameWeight = isSame(latest.load, previous.load) && isSame(previous.load, oldest.load)
            let fellTwice = latest.meanReps < previous.meanReps - config.repsFallTolerance
                && previous.meanReps < oldest.meanReps - config.repsFallTolerance
            if sameWeight, fellTwice {
                if let effort = latest.meanRIR, latest.coverage >= config.effortCoverage, effort <= config.holdMaximumRIR {
                    return reduceOrHold([.repsFellAtSameLoad])
                }
                if latest.coverage < config.effortCoverage {
                    return hold([.repsFellAtSameLoad, .noRIRRecorded])
                }
                return hold([.repsFellAtSameLoad])
            }
        }

        // 4. Effort of the last session.
        guard let effort = latest.meanRIR, latest.coverage >= config.effortCoverage else {
            return make(.noEffortData, weight: nil, reps: nil, flags + [.noRIRRecorded], sessions: count)
        }
        if effort <= config.holdMaximumRIR {
            return hold([.lastSessionNearFailure])
        }

        // 5. Move up only after two comfortable sessions at the same weight, because RIR is a self-report that can be a rep off.
        guard effort >= config.progressMinimumRIR else {
            return hold([.moderateEffort])
        }
        guard isSame(latest.load, previous.load),
              let earlier = previous.meanRIR, previous.coverage >= config.effortCoverage,
              earlier >= config.progressMinimumRIR,
              latest.meanReps >= previous.meanReps - config.repsFallTolerance
        else {
            return hold([.awaitingSecondCleanSession])
        }

        if increment / latest.load > config.jumpCap(for: audience) + 1e-9 {
            let reps = latest.typicalReps + 1
            if reps > config.maximumTargetReps {
                return hold([.cleanSessionsWithReserve, .stepExceedsCap])
            }
            return make(.addRep, weight: latest.load, reps: reps, flags + [.cleanSessionsWithReserve, .stepExceedsCap], sessions: count)
        }
        return make(
            .progress, weight: round2(latest.load + increment), reps: latest.typicalReps,
            flags + [.cleanSessionsWithReserve], sessions: count
        )
    }

    // MARK: Session summaries

    /// What the engine needs from one session: the weight lifted, the reps and the effort at that weight.
    private struct Summary {
        var date: Date
        /// The heaviest working weight.
        var load: Double
        var meanReps: Double
        /// The mean reps rounded to a whole number, at least 1.
        var typicalReps: Int
        /// Share of the sets at `load` that have a reps-in-reserve value.
        var coverage: Double
        /// Mean reps in reserve over those sets; nil without any.
        var meanRIR: Double?
    }

    private static func isSame(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < sameWeightTolerance
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func workingSets(_ session: ExerciseSession) -> [CompletedSet] {
        session.sets.filter { set in
            (set.type == .normal || set.type == .failure)
                && set.weightKg.isFinite && set.weightKg > 0 && set.weightKg <= plausibleKg
                && set.reps > 0 && set.reps <= plausibleReps
        }
    }

    private static func e1RM(_ set: CompletedSet) -> Double {
        Estimated1RM.epley(weightKg: set.weightKg, reps: set.reps)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// Working-set summaries, newest first, after dropping sets that are far above the lifter's recent best (a typo such as 6 reps
    /// entered as 16). Needs three recent sessions to know what "typical" is; with fewer nothing is dropped.
    private static func prepare(_ sessions: [ExerciseSession], _ config: CoachConfig) -> (sessions: [Summary], excluded: Int) {
        let working = sessions.map { workingSets($0) }

        var typicalBests: [Double] = []
        for sets in working.prefix(6) {
            let best = sets.filter { $0.reps <= config.maximumRepsForReference }.map { e1RM($0) }.max() ?? 0
            if best > 0 { typicalBests.append(best) }
        }
        let reference: Double? = typicalBests.count >= 3 ? median(typicalBests) : nil

        var excluded = 0
        var result: [Summary] = []
        for (index, sets) in working.enumerated() {
            var kept = sets
            if let reference, reference > 0 {
                kept = sets.filter { e1RM($0) <= config.suspectRatio * reference }
                excluded += sets.count - kept.count
            }
            if let summary = summarise(kept, date: sessions[index].date) {
                result.append(summary)
            }
        }
        return (result, excluded)
    }

    private static func summarise(_ sets: [CompletedSet], date: Date) -> Summary? {
        guard let load = sets.map({ $0.weightKg }).max() else { return nil }
        let atLoad = sets.filter { $0.weightKg >= load - sameWeightTolerance }
        let totalReps = atLoad.reduce(0.0) { $0 + Double($1.reps) }
        let mean = totalReps / Double(atLoad.count)
        let efforts: [Int] = atLoad.compactMap { set in
            if let value = set.rir { return min(4, max(0, value)) }
            return set.type == .failure ? 0 : nil
        }
        return Summary(
            date: date,
            load: load,
            meanReps: mean,
            typicalReps: max(1, Int(min(mean.rounded(), Double(plausibleReps)))),
            coverage: Double(efforts.count) / Double(atLoad.count),
            meanRIR: efforts.isEmpty ? nil : Double(efforts.reduce(0, +)) / Double(efforts.count)
        )
    }
}
