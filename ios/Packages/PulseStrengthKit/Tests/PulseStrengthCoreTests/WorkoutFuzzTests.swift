import XCTest
@testable import PulseStrengthCore

/// Seeded linear congruential generator (Knuth's MMIX constants): deterministic, no real randomness.
struct RedLCG {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }

    /// A value in `range` (inclusive).
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// True `percent` times out of 100.
    mutating func chance(_ percent: Int) -> Bool { int(0...99) < percent }

    mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
}

/// Draws random but plausible actions for a state: mostly valid ids, sometimes unknown or mismatched ones.
struct RedActionGenerator {
    var rng: RedLCG
    private var ghosts = 0
    /// Index of the last drawn action kind (for reproducibility checks).
    private(set) var lastKind = 0

    init(seed: UInt64) { rng = RedLCG(seed: seed) }

    private mutating func ghostID() -> UUID {
        ghosts += 1
        return RedFix.uuid(0xDEAD, ghosts)
    }

    private mutating func exerciseID(_ s: WorkoutState) -> UUID {
        if s.exercises.isEmpty || rng.chance(8) { return ghostID() }
        return s.exercises[rng.int(0...(s.exercises.count - 1))].id
    }

    private mutating func target(_ s: WorkoutState) -> (UUID, UUID) {
        let roll = rng.int(0...99)
        let withSets = s.exercises.filter { !$0.sets.isEmpty }
        if roll < 88, !withSets.isEmpty {
            let entry = withSets[rng.int(0...(withSets.count - 1))]
            return (entry.id, entry.sets[rng.int(0...(entry.sets.count - 1))].id)
        }
        if roll < 94, !s.exercises.isEmpty {
            return (s.exercises[rng.int(0...(s.exercises.count - 1))].id, ghostID())
        }
        return (ghostID(), ghostID())
    }

    /// A pending set of a timed (duration) exercise when the workout has one, else any target.
    private mutating func timedTarget(_ s: WorkoutState) -> (UUID, UUID) {
        let timed = s.exercises.filter { $0.exercise.tracking == .duration && $0.sets.contains { !$0.isDone } }
        guard !timed.isEmpty, rng.chance(85) else { return target(s) }
        let entry = timed[rng.int(0...(timed.count - 1))]
        let pending = entry.sets.filter { !$0.isDone }
        return (entry.id, pending[rng.int(0...(pending.count - 1))].id)
    }

    private mutating func weight() -> Double {
        rng.pick([-5, 0, 0.004, 22.5, 47.5, 82.505, 100, 250.25, -250, -1_000, .nan, .infinity, -.infinity, 1e300])
    }

    private mutating func exercises() -> [Exercise] {
        (0..<rng.int(0...3)).map { _ in rng.pick(RedFix.pool) }
    }

    mutating func next(for s: WorkoutState) -> WorkoutAction {
        // Keep the workout from shrinking to nothing or growing without bound.
        if s.exercises.count < 2, rng.chance(50) {
            lastKind = 28
            return .addExercises(exercises())
        }
        if s.exercises.count > 9, rng.chance(30) {
            lastKind = 29
            return .removeExercise(exerciseID: exerciseID(s))
        }
        // Right after a removal / deletion the user is likely to tap "Undo".
        if s.undo != nil, rng.chance(30) {
            lastKind = 43
            return .undo
        }
        let kind = rng.int(0...52)
        lastKind = kind
        let count = s.exercises.count
        switch kind {
        case 0...5:
            let (e, st) = target(s); return .toggleSet(exerciseID: e, setID: st)
        case 6...9:
            let (e, st) = target(s); return .logSet(exerciseID: e, setID: st)
        case 10...13:
            return .logNextSet
        case 14:
            let (e, st) = target(s); return .setWeight(exerciseID: e, setID: st, kg: weight())
        case 15:
            let (e, st) = target(s)
            return .setReps(exerciseID: e, setID: st, reps: rng.pick([-50, 0, 1, 8, 12, 45, 999, 1_200, Int.max, Int.min]))
        case 16...17:
            return .nudgeNextSet(weightSteps: rng.pick([-3, -1, 0, 1, 2, 5, 100_000, Int.min, Int.max]),
                                 repsSteps: rng.pick([-5, -1, 0, 1, 3, 100_000, Int.min, Int.max]))
        case 18:
            let (e, st) = target(s); return .setSetType(exerciseID: e, setID: st, type: rng.pick(SetType.allCases))
        case 19:
            let (e, st) = target(s); return .setRIR(exerciseID: e, setID: st, rir: rng.pick([nil, -2, 0, 1, 2, 3, 4, 9]))
        case 20...21:
            return .toggleLastSetRIR(rng.pick([-1, 0, 1, 2, 3, 4, 7]))
        case 22:
            return .addSet(exerciseID: exerciseID(s))
        case 23:
            let (e, st) = target(s); return .deleteSet(exerciseID: e, setID: st)
        case 24:
            return .setNote(exerciseID: exerciseID(s), note: rng.pick(["", "slow", "belt on"]))
        case 25:
            return .goTo(index: rng.int(-3...(count + 3)))
        case 26:
            return .nextExercise
        case 27:
            return .previousExercise
        case 28:
            return .addExercises(exercises())
        case 29:
            return .removeExercise(exerciseID: exerciseID(s))
        case 30:
            return .moveExercise(from: rng.int(-2...(count + 1)), to: rng.int(-2...(count + 1)))
        case 31:
            return .moveExerciseBy(exerciseID: exerciseID(s), delta: rng.pick([-3, -1, 0, 1, 1, 2, 7, Int.max, Int.min]))
        case 32:
            return .replaceExercise(exerciseID: exerciseID(s), with: rng.pick(RedFix.pool))
        case 33...34:
            return .toggleSuperset(exerciseID: exerciseID(s))
        case 35:
            return .setRest(exerciseID: exerciseID(s), seconds: rng.pick([-30, 0, 30, 45, 60, 90, 150, 600, Int.max, Int.min]))
        case 36...37:
            return .adjustRest(seconds: rng.pick([-3_600, -15, -15, 15, 15, 30, 3_600, Int.max, Int.min]))
        case 38:
            return .skipRest
        case 39:
            return .setAutoStartRest(rng.chance(70))
        case 40:
            return .setAlertWhenRestEnds(rng.chance(50))
        case 41:
            return .pause
        case 42:
            return .resume
        case 43...44:
            return .undo
        case 45:
            return .updateHeartRate(rng.pick([nil, -1, 0, 29, 30, 95, 128, 180, 240, 241, 400]))
        case 46:
            return .setUsedWatch(rng.chance(50))
        case 48:
            return .setWeightUnit(rng.pick(WeightUnit.allCases))
        case 49...50:
            let (e, st) = timedTarget(s); return .startTimedSet(SetRef(exerciseID: e, setID: st))
        case 51:
            return .stopTimedSet
        case 52:
            return .cancelTimedSet
        default:
            return .rename(rng.pick(["", "Push", "Upper A · Push"]))
        }
    }
}

final class WorkoutFuzzTests: XCTestCase {
    private static let stepsPerRun = 2_000

    // MARK: Fixtures

    private func fixtures() -> [(String, WorkoutState)] {
        let supersetHeavy = RedFix.state([
            RedFix.entry(1, RedFix.lateral, RedFix.normal(3, 8, 15), rest: 60, group: "A"),
            RedFix.entry(2, RedFix.pushdown, RedFix.normal(3, 30, 12), rest: 60, group: "A"),
            RedFix.entry(3, RedFix.bench, RedFix.normal(3, 80, 5), rest: 150, group: "B"),
            RedFix.entry(4, RedFix.ohp, RedFix.normal(3, 45, 8), rest: 120, group: "B"),
            RedFix.entry(5, RedFix.incline, RedFix.normal(3, 28, 10), rest: 90, group: "B"),
            RedFix.entry(6, RedFix.crossover, RedFix.normal(2, 15, 12), rest: 60),
            RedFix.entry(7, RedFix.pushup, RedFix.normal(2, 0, 12), rest: 60),
            RedFix.entry(8, RedFix.plank, RedFix.normal(2, 0, 45), rest: 45),
        ])
        var pausedWithRest = RedFix.designState()
        pausedWithRest.pausedAt = RedFix.at(30)
        pausedWithRest.pausedTotal = 10
        pausedWithRest.rest = RestState(endsAt: RedFix.at(100), totalSeconds: 90, frozenRemaining: 70)
        var halfDone = RedFix.designState()
        for i in 0..<5 { halfDone.exercises[0].sets[i].isDone = true }
        halfDone.currentIndex = 1
        let timedAndLoads = RedFix.state([
            RedFix.entry(1, RedFix.plank, RedFix.normal(3, 0, 45), rest: 45),
            RedFix.entry(2, RedFix.pullup, RedFix.normal(3, 0, 8), rest: 120),
            RedFix.entry(3, RedFix.plank, RedFix.normal(2, 0, 30), rest: 30, group: "A"),
            RedFix.entry(4, RedFix.pushup, RedFix.normal(2, 0, 12), rest: 30, group: "A"),
            RedFix.entry(5, RedFix.squat, [(.warmup, 40, 8), (.drop, 80, 6), (.drop, 60, 8), (.normal, 80, 6)], rest: 120),
        ])
        var timing = timedAndLoads
        WorkoutReducer.reduce(&timing, .startTimedSet(SetRef(exerciseID: timing.exercises[0].id, setID: timing.exercises[0].sets[0].id)), now: RedFix.t0)
        WorkoutReducer.reduce(&timing, .pause, now: RedFix.at(10))
        return [
            ("design", RedFix.designState()),
            ("empty", WorkoutState(id: RedFix.uuid(1, 3), name: "Empty", startedAt: RedFix.t0)),
            ("single plank set", RedFix.state([RedFix.entry(1, RedFix.plank, RedFix.normal(1, 0, 45), rest: 45)])),
            ("supersets", supersetHeavy),
            ("paused with rest", pausedWithRest),
            ("half done", halfDone),
            ("timed sets and loads", timedAndLoads),
            ("timed set running, paused", timing),
        ]
    }

    // MARK: Runs

    /// Aggregated numbers of one run, used to show that the generator reached the interesting code.
    private struct RunStats {
        var changed = 0
        var undoRestored = 0
        var restsStarted = 0
        var supersetJumps = 0
        var emptied = 0
        var timersStarted = 0
        var timersStopped = 0
        var kinds: [Int] = []
    }

    @discardableResult
    private func run(
        _ label: String, from start: WorkoutState, seed: UInt64, steps: Int, checksGroups: Bool = true
    ) -> (WorkoutState, RunStats) {
        var generator = RedActionGenerator(seed: seed)
        var state = start
        var stats = RunStats()
        var now = RedFix.t0
        for step in 1...steps {
            // Time moves in whole seconds; mostly short gaps so the 6 s undo window is hit from both sides.
            if generator.rng.chance(5) {
                now = now.addingTimeInterval(300)
            } else if !generator.rng.chance(10) {
                now = now.addingTimeInterval(Double(generator.rng.int(1...9)))
            }
            let before = state
            let action = generator.next(for: before)
            stats.kinds.append(generator.lastKind)
            WorkoutReducer.reduce(&state, action, now: now)
            let context = "[\(label) seed \(seed) step \(step)] \(action)"
            checkInvariants(state, before: before, action: action, now: now, checksGroups: checksGroups, context: context)

            // The same input must give the same output (apart from freshly generated ids).
            if !RedFix.createsNewIDs(action) {
                var again = before
                WorkoutReducer.reduce(&again, action, now: now)
                XCTAssertEqual(again, state, "not deterministic \(context)")
            }

            var withoutRevision = state
            withoutRevision.revision = before.revision
            if withoutRevision != before { stats.changed += 1 }
            if case .undo = action {
                let beforeCount = before.exercises.count + before.exercises.reduce(0) { $0 + $1.sets.count }
                let afterCount = state.exercises.count + state.exercises.reduce(0) { $0 + $1.sets.count }
                if afterCount > beforeCount { stats.undoRestored += 1 }
            }
            if let rest = state.rest, rest != before.rest { stats.restsStarted += 1 }
            if case .toggleSet = action, before.currentIndex != state.currentIndex { stats.supersetJumps += 1 }
            if state.exercises.isEmpty { stats.emptied += 1 }
            if before.timedSet == nil, state.timedSet != nil { stats.timersStarted += 1 }
            if case .stopTimedSet = action, before.timedSet != nil, state.timedSet == nil { stats.timersStopped += 1 }
        }
        return (state, stats)
    }

    func testRandomActionsKeepTheInvariants() {
        var total = RunStats()
        for (n, fixture) in fixtures().enumerated() {
            let (label, start) = fixture
            let (_, stats) = run(label, from: start, seed: 0xC0FFEE + UInt64(n) * 7_919, steps: Self.stepsPerRun)
            total.changed += stats.changed
            total.undoRestored += stats.undoRestored
            total.restsStarted += stats.restsStarted
            total.supersetJumps += stats.supersetJumps
            total.emptied += stats.emptied
            total.timersStarted += stats.timersStarted
            total.timersStopped += stats.timersStopped
            XCTAssertGreaterThan(stats.changed, Self.stepsPerRun / 4, "too few effective actions in \(label)")
        }
        // The runs must really have exercised these paths.
        XCTAssertGreaterThan(total.undoRestored, 5)
        XCTAssertGreaterThan(total.restsStarted, 100)
        XCTAssertGreaterThan(total.supersetJumps, 20)
        XCTAssertGreaterThan(total.emptied, 0)
        XCTAssertGreaterThan(total.timersStarted, 20, "timed sets were started")
        XCTAssertGreaterThan(total.timersStopped, 5, "and stopped (logged)")
    }

    func testRandomActionsWithSeveralSeedsOnTheDesignWorkout() {
        for seed in [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64] {
            run("design", from: RedFix.designState(), seed: seed, steps: 500)
        }
    }

    /// States that a replay, an undo or a build that predates the rules can produce: superset members that are apart, a lone member,
    /// a timed set whose set is gone, a rest together with a timed set, an index out of range. The reducer takes any of them.
    func testRandomActionsFromStatesThatBrokeTheRulesNeverTrapAndStayDeterministic() {
        var apart = RedFix.state([
            RedFix.entry(1, RedFix.lateral, RedFix.normal(2, 8, 15), rest: 60, group: "A"),
            RedFix.entry(2, RedFix.plank, RedFix.normal(2, 0, 45), rest: 45),
            RedFix.entry(3, RedFix.pushdown, RedFix.normal(2, 30, 12), rest: 60, group: "A"),
            RedFix.entry(4, RedFix.bench, RedFix.normal(2, 80, 5), rest: 90, group: "B"),
            RedFix.entry(5, RedFix.pullup, RedFix.normal(2, -20, 8), rest: 90, group: "A"),
        ])
        apart.currentIndex = 17
        var dangling = apart
        dangling.timedSet = TimedSetState(
            setRef: SetRef(exerciseID: RedFix.uuid(0xBEEF, 1), setID: RedFix.uuid(0xBEEF, 2)), startedAt: RedFix.t0, targetSeconds: -5
        )
        dangling.rest = RestState(endsAt: RedFix.at(60), totalSeconds: 60)
        var wrongKind = apart
        wrongKind.timedSet = TimedSetState(
            setRef: SetRef(exerciseID: wrongKind.exercises[3].id, setID: wrongKind.exercises[3].sets[0].id),
            startedAt: RedFix.at(1_000), targetSeconds: 99_999, frozenElapsed: -4
        )
        for (n, start) in [apart, dangling, wrongKind].enumerated() {
            for seed in 1...6 as ClosedRange<UInt64> {
                var generator = RedActionGenerator(seed: seed * 31 + UInt64(n))
                var state = start
                var now = RedFix.t0
                for _ in 0..<600 {
                    now = now.addingTimeInterval(Double(generator.rng.int(0...9)))
                    let before = state
                    let action = generator.next(for: before)
                    WorkoutReducer.reduce(&state, action, now: now)
                    if state.exercises.isEmpty {
                        XCTAssertEqual(state.currentIndex, 0)
                    } else {
                        XCTAssertTrue((0..<state.exercises.count).contains(state.currentIndex), "\(action)")
                    }
                    if !RedFix.createsNewIDs(action) {
                        var again = before
                        WorkoutReducer.reduce(&again, action, now: now)
                        XCTAssertEqual(again, state, "not deterministic: \(action)")
                    }
                }
            }
        }
    }

    func testTheGeneratorIsReproducible() {
        let first = run("design", from: RedFix.designState(), seed: 424_242, steps: 400)
        let second = run("design", from: RedFix.designState(), seed: 424_242, steps: 400)
        XCTAssertEqual(first.1.kinds, second.1.kinds)
        XCTAssertEqual(first.1.changed, second.1.changed)
        XCTAssertEqual(first.0.exercises.map { $0.exercise.id }, second.0.exercises.map { $0.exercise.id })
        XCTAssertEqual(first.0.exercises.map { $0.sets.count }, second.0.exercises.map { $0.sets.count })
        XCTAssertEqual(first.0.revision, second.0.revision)
        XCTAssertEqual(first.0.currentIndex, second.0.currentIndex)
    }

    func testTheGeneratorCoversEveryActionKind() {
        var generator = RedActionGenerator(seed: 99)
        let state = RedFix.designState()
        var seen = Set<Int>()
        for _ in 0..<5_000 {
            _ = generator.next(for: state)
            seen.insert(generator.lastKind)
        }
        XCTAssertEqual(seen, Set(0...52))
    }

    func testLCGIsDeterministicAndStaysInRange() {
        var a = RedLCG(seed: 5)
        var b = RedLCG(seed: 5)
        for _ in 0..<1_000 {
            let value = a.int(-3...4)
            XCTAssertEqual(value, b.int(-3...4))
            XCTAssertTrue((-3...4).contains(value))
        }
        var c = RedLCG(seed: 1)
        var d = RedLCG(seed: 2)
        XCTAssertNotEqual(c.int(0...1_000_000), d.int(0...1_000_000))
    }

    // MARK: Invariants

    private func checkInvariants(
        _ s: WorkoutState, before b: WorkoutState, action: WorkoutAction, now: Date, checksGroups: Bool, context: String
    ) {
        // currentIndex within bounds (0 when empty)
        if s.exercises.isEmpty {
            XCTAssertEqual(s.currentIndex, 0, "index of an empty workout \(context)")
        } else {
            XCTAssertTrue((0..<s.exercises.count).contains(s.currentIndex), "index \(s.currentIndex) out of bounds \(context)")
        }

        // no duplicate ids
        let exerciseIDs = s.exercises.map { $0.id }
        XCTAssertEqual(Set(exerciseIDs).count, exerciseIDs.count, "duplicate exercise ids \(context)")
        let setIDs = s.exercises.flatMap { $0.sets.map { $0.id } }
        XCTAssertEqual(Set(setIDs).count, setIDs.count, "duplicate set ids \(context)")

        // a superset group never has a single member
        var groupSizes: [String: Int] = [:]
        for entry in s.exercises {
            if let group = entry.supersetGroup { groupSizes[group, default: 0] += 1 }
        }
        for (group, size) in groupSizes {
            XCTAssertGreaterThanOrEqual(size, 2, "single member superset \(group) \(context)")
        }

        // rest totals >= 0 or nil; frozen exactly while paused
        if let rest = s.rest {
            XCTAssertGreaterThanOrEqual(rest.totalSeconds, 0, "negative rest total \(context)")
            if let frozen = rest.frozenRemaining {
                XCTAssertGreaterThanOrEqual(frozen, 0, "negative frozen rest \(context)")
            }
            XCTAssertEqual(rest.frozenRemaining != nil, s.pausedAt != nil, "frozen iff paused \(context)")
        }
        for entry in s.exercises {
            XCTAssertGreaterThanOrEqual(entry.restSeconds, 0, "negative exercise rest \(context)")
        }

        // revision never decreases and moves by exactly one for a real change (never for heart rate)
        var withoutRevision = s
        withoutRevision.revision = b.revision
        let changed = withoutRevision != b
        var isHeartRate = false
        if case .updateHeartRate = action { isHeartRate = true }
        XCTAssertGreaterThanOrEqual(s.revision, b.revision, "revision decreased \(context)")
        XCTAssertEqual(s.revision, b.revision + (changed && !isHeartRate ? 1 : 0), "revision rule \(context)")

        // lastLogged always resolves to an existing set
        if let ref = s.lastLogged {
            let found = s.exercises.first { $0.id == ref.exerciseID }?.sets.contains { $0.id == ref.setID } ?? false
            XCTAssertTrue(found, "dangling lastLogged \(context)")
        }

        // set values stay in their ranges: weights of 0 or more (down to -300 for an exercise with an added or assisted load),
        // reps up to 999 (seconds up to 10,800 for a timed exercise)
        for entry in s.exercises {
            let lowest = entry.exercise.carriesLoad ? WorkoutReducer.minimumWeightKg : 0
            let mostReps = entry.exercise.tracking == .duration ? WorkoutReducer.maximumDurationSeconds : WorkoutReducer.maximumReps
            for set in entry.sets {
                XCTAssertTrue(
                    set.weightKg.isFinite && set.weightKg >= lowest && set.weightKg <= WorkoutReducer.maximumWeightKg,
                    "bad weight \(set.weightKg) \(context)"
                )
                XCTAssertFalse(set.weightKg == 0 && set.weightKg.sign == .minus, "negative zero \(context)")
                XCTAssertTrue((0...mostReps).contains(set.reps), "bad reps \(set.reps) \(context)")
                if let rir = set.rir { XCTAssertTrue((0...4).contains(rir), "bad rir \(rir) \(context)") }
            }
        }

        // the members of a superset are next to each other
        if checksGroups {
            for group in Set(s.exercises.compactMap { $0.supersetGroup }) {
                let members = s.exercises.indices.filter { s.exercises[$0].supersetGroup == group }
                if let first = members.first, let last = members.last {
                    XCTAssertEqual(last - first, members.count - 1, "superset \(group) is split \(context)")
                }
            }
        }

        // a timed set: a pending set of a timed exercise, never together with a rest, frozen exactly while paused
        if let timed = s.timedSet {
            let found = s.exercises.first { $0.id == timed.setRef.exerciseID }
            let set = found?.sets.first { $0.id == timed.setRef.setID }
            XCTAssertNotNil(set, "dangling timed set \(context)")
            XCTAssertEqual(found?.exercise.tracking, .duration, "timed set of an exercise that is not timed \(context)")
            XCTAssertEqual(set?.isDone, false, "timed set of a logged set \(context)")
            XCTAssertEqual(timed.targetSeconds, set?.reps, "target does not follow the set \(context)")
            XCTAssertNil(s.rest, "a rest runs while a timed set does \(context)")
            XCTAssertEqual(timed.frozenElapsed != nil, s.pausedAt != nil, "timed set frozen iff paused \(context)")
            if let frozen = timed.frozenElapsed { XCTAssertGreaterThanOrEqual(frozen, 0, context) }
        }

        // pause bookkeeping
        XCTAssertGreaterThanOrEqual(s.pausedTotal, b.pausedTotal, "pausedTotal decreased \(context)")
        XCTAssertGreaterThanOrEqual(s.pausedTotal, 0, context)

        // heart-rate totals only grow, by at most one sample per update, and only for updates
        XCTAssertGreaterThanOrEqual(s.heartRateCount, b.heartRateCount, context)
        XCTAssertLessThanOrEqual(s.heartRateCount, b.heartRateCount + (isHeartRate ? 1 : 0), "heart rate count \(context)")
        if !isHeartRate {
            XCTAssertEqual(s.heartRateSum, b.heartRateSum, context)
            XCTAssertEqual(s.heartRate, b.heartRate, context)
        }

        // the next pending set, when there is one, is pending; when there is none, everything is logged
        if let target = WorkoutTargets.nextPending(in: s) {
            XCTAssertFalse(s.exercises[target.exerciseIndex].sets[target.setIndex].isDone, "next pending is done \(context)")
        } else {
            XCTAssertTrue(s.exercises.allSatisfy { $0.sets.allSatisfy { $0.isDone } }, "pending set not found \(context)")
        }

        // pause freezes the remaining rest, resume thaws it from `now`, undo respects the window and always clears the entry
        switch action {
        case .pause:
            if b.pausedAt == nil, let rest = b.rest {
                XCTAssertEqual(s.pausedAt, now, context)
                XCTAssertEqual(s.rest?.frozenRemaining, max(0, rest.endsAt.timeIntervalSince(now)), "pause freeze \(context)")
            }
        case .resume:
            if b.pausedAt != nil, let frozen = b.rest?.frozenRemaining {
                XCTAssertNil(s.pausedAt, context)
                XCTAssertEqual(s.rest?.endsAt, now.addingTimeInterval(max(0, frozen)), "resume thaw \(context)")
            }
        case .startTimedSet:
            if b.timedSet != nil { XCTAssertEqual(s.timedSet, b.timedSet, "a second timed set replaced the first \(context)") }
        case .stopTimedSet:
            XCTAssertNil(s.timedSet, "stop keeps the timed set \(context)")
            if let timed = b.timedSet, let logged = s.lastLogged, logged == timed.setRef {
                let set = s.exercises.first { $0.id == logged.exerciseID }?.sets.first { $0.id == logged.setID }
                XCTAssertEqual(set?.isDone, true, "stop did not log \(context)")
            }
        case .cancelTimedSet:
            XCTAssertNil(s.timedSet, "cancel keeps the timed set \(context)")
            XCTAssertEqual(s.exercises, b.exercises, "cancel changed the sets \(context)")
        case let .setWeightUnit(unit):
            XCTAssertEqual(s.settings.weightUnit, unit, "unit not set \(context)")
            XCTAssertEqual(s.exercises, b.exercises, "a unit change touched the exercises (weights stay in kilograms) \(context)")
        case .undo:
            XCTAssertNil(s.undo, "undo keeps its entry \(context)")
            if let entry = b.undo, now > entry.expiresAt {
                XCTAssertEqual(s.exercises, b.exercises, "undo outside the window restored something \(context)")
            }
        default:
            break
        }

        // an undo entry always expires after it was created within the window
        if let undo = s.undo, undo.expiresAt != b.undo?.expiresAt {
            XCTAssertTrue(undo.title == "Set deleted" || undo.title.hasPrefix("Removed ") || undo.title.hasPrefix("Replaced "), "undo title \(context)")
        }
    }
}
