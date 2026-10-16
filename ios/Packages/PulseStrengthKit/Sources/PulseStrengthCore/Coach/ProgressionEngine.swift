import Foundation

/// Decides, from the sets a person actually performed, what to do with a lift next time.
///
/// A pure function: the same history, audience, configuration and date always give the same `Recommendation`. It reads only
/// **performed** sets (the planned target is not stored in the history, and "update template" overwrites it with the performed
/// values), counts only working sets (warm-ups and drop sets are ignored; a "to failure" set always counts as reps in reserve 0,
/// whatever value is stored with it), and judges effort from the optional reps-in-reserve value. It never raises the weight without
/// effort data.
///
/// The history is sorted newest first and de-duplicated by session id before anything is judged, so the caller's order does not
/// matter. Sessions dated more than a day after `now` (a clock error) are ignored. The sessions that count as "the last two" must
/// lie within `CoachConfig.breakDays` of each other: a clean session after a long layoff is a restart, not a second data point.
///
/// The thresholds live in `CoachConfig` and have not been signed off by a qualified coach.
public enum ProgressionEngine {
    /// Bump when a rule changes; stamped into every `Recommendation` so an evaluation can tell which engine produced it.
    public static let version = 1

    /// Sets outside these bounds are treated as data errors and ignored (a damaged file or a bad import), so no arithmetic can
    /// overflow and no target prints as "0 kg". 999 is the most reps the workout reducer stores, so Apply can always reach a target.
    private static let minimumKg = 0.5
    private static let plausibleKg = 2_000.0
    private static let plausibleReps = 999

    /// A session dated more than this far after `now` is a clock error and is ignored.
    private static let clockSkewAllowance: TimeInterval = 86_400

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

        guard config.isValid else {
            return make(.insufficientData, [.invalidConfiguration])
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

        let prepared = prepare(history.sessions, config, now: now)
        let flags: [ReasonCode] = prepared.excluded > 0 ? [.suspectSetExcluded] : []
        guard prepared.sessions.count >= max(2, config.minimumSessions) else {
            return make(.insufficientData, flags + [.tooFewSessions], sessions: prepared.sessions.count)
        }
        // Two sessions whose best lifts are far apart cannot be told from a typo in one of them: say nothing.
        guard !prepared.unresolvedJump else {
            return make(.insufficientData, [.suspectSetExcluded], sessions: prepared.sessions.count)
        }
        let latest = prepared.sessions[0]
        let increment = config.increment(for: exercise)

        // The sessions that count as "recent": the newest ones with no gap longer than the break between them.
        var recent = 1
        while recent < prepared.sessions.count,
              gapDays(prepared.sessions[recent].date, prepared.sessions[recent - 1].date) <= Double(config.breakDays) {
            recent += 1
        }
        let sessions = Array(prepared.sessions.prefix(recent))
        let count = sessions.count

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

        // 1. A long break: do not progress from old numbers. A date that is not a number counts as a break too.
        let daysSince = gapDays(latest.date, now)
        if !daysSince.isFinite || daysSince > Double(config.breakDays) {
            return hold([.returningAfterBreak])
        }
        // The newest session is the first one back after a layoff: it cannot be one of two comparable sessions.
        guard count >= max(2, config.minimumSessions) else {
            return hold([.awaitingSecondCleanSession])
        }
        let previous = sessions[1]

        // 2. Many increases in a row: a lighter week, but only for someone who is actually working hard.
        if config.lighterWeekAfterIncreases > 0,
           let effort = latest.meanRIR, latest.coverage >= config.effortCoverage, effort < config.lighterWeekMaximumRIR {
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
        guard effort >= config.progressMinimumRIR, latest.comfortableShare >= config.comfortableSetShare - 1e-9 else {
            return hold([.moderateEffort])
        }
        guard isSame(latest.load, previous.load),
              let earlier = previous.meanRIR, previous.coverage >= config.effortCoverage,
              earlier >= config.progressMinimumRIR,
              previous.comfortableShare >= config.comfortableSetShare - 1e-9,
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
        /// Share of the sets at `load` with at least `progressMinimumRIR` reps in reserve (a set without a value does not count).
        var comfortableShare: Double
    }

    /// Days from `earlier` to `later` (negative when `later` is first; NaN for a date that is not a number).
    private static func gapDays(_ earlier: Date, _ later: Date) -> Double {
        later.timeIntervalSince(earlier) / 86_400
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
                && set.weightKg.isFinite && set.weightKg >= minimumKg && set.weightKg <= plausibleKg
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
    /// entered as 16).
    ///
    /// A set is dropped when its estimated 1RM is more than `suspectRatio` times the median of the last six session bests **and**
    /// more than that times the best of the next older session, so a lifter who really is getting stronger every session (each step
    /// small, the median lagging behind) is not mistaken for a typo. Three recent sessions are needed to know what "typical" is. With
    /// exactly two, nothing can be dropped, so two sessions whose bests are further apart than `suspectRatio` are reported as an
    /// `unresolvedJump` and the engine stays silent.
    private static func prepare(
        _ input: [ExerciseSession], _ config: CoachConfig, now: Date
    ) -> (sessions: [Summary], excluded: Int, unresolvedJump: Bool) {
        // Newest first whatever the caller's order, ties keep their order, a repeated session id counts once, and a session dated in
        // the future (a clock error) does not exist.
        let indexed = input.enumerated().filter { _, session in
            session.date.timeIntervalSinceReferenceDate.isFinite
                && !(session.date.timeIntervalSince(now) > clockSkewAllowance)
        }
        let ordered = indexed.sorted { lhs, rhs in
            if lhs.element.date != rhs.element.date { return lhs.element.date > rhs.element.date }
            return lhs.offset < rhs.offset
        }
        var seen = Set<UUID>()
        let sessions = ordered.map { $0.element }.filter { seen.insert($0.id).inserted }

        let working = sessions.map { workingSets($0) }
        let bests: [Double] = working.map { sets in
            sets.filter { $0.reps <= config.maximumRepsForReference }.map { e1RM($0) }.max() ?? 0
        }
        let typicalBests = bests.prefix(6).filter { $0 > 0 }
        let reference: Double? = typicalBests.count >= 3 ? median(Array(typicalBests)) : nil

        var unresolved = false
        if typicalBests.count == 2, let high = typicalBests.max(), let low = typicalBests.min(), high > config.suspectRatio * low {
            unresolved = true
        }

        var excluded = 0
        var result: [Summary] = []
        for (index, sets) in working.enumerated() {
            var kept = sets
            if let reference, reference > 0 {
                let older = index + 1 < bests.count ? bests[index + 1] : 0
                kept = sets.filter { set in
                    let value = e1RM(set)
                    let farAboveTypical = value > config.suspectRatio * reference
                    let jumpedFromOlder = older <= 0 || value > config.suspectRatio * older
                    return !(farAboveTypical && jumpedFromOlder)
                }
                excluded += sets.count - kept.count
            }
            if let summary = summarise(kept, date: sessions[index].date, config: config) {
                result.append(summary)
            }
        }
        return (result, excluded, unresolved)
    }

    private static func summarise(_ sets: [CompletedSet], date: Date, config: CoachConfig) -> Summary? {
        guard let load = sets.map({ $0.weightKg }).max() else { return nil }
        let atLoad = sets.filter { $0.weightKg >= load - sameWeightTolerance }
        let totalReps = atLoad.reduce(0.0) { $0 + Double($1.reps) }
        let mean = totalReps / Double(atLoad.count)
        // A set marked "to failure" is at reps in reserve 0 whatever value was stored before it was re-marked.
        let efforts: [Int] = atLoad.compactMap { set in
            if set.type == .failure { return 0 }
            return set.rir.map { min(4, max(0, $0)) }
        }
        let comfortable = efforts.filter { Double($0) >= config.progressMinimumRIR }.count
        return Summary(
            date: date,
            load: load,
            meanReps: mean,
            typicalReps: max(1, Int(min(mean.rounded(), Double(plausibleReps)))),
            coverage: Double(efforts.count) / Double(atLoad.count),
            meanRIR: efforts.isEmpty ? nil : Double(efforts.reduce(0, +)) / Double(efforts.count),
            comfortableShare: Double(comfortable) / Double(atLoad.count)
        )
    }
}
