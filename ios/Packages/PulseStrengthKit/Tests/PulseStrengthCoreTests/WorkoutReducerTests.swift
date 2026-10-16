import XCTest
@testable import PulseStrengthCore

// MARK: - Fixtures shared by the reducer, factory and fuzz tests

/// Deterministic fixtures (no clock, no randomness) for the reducer test files.
enum RedFix {
    /// The fake "start of the workout".
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// `t0` plus `seconds`.
    static func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    /// A stable UUID built from two numbers.
    static func uuid(_ high: Int, _ low: Int) -> UUID {
        func hex(_ value: Int, _ width: Int) -> String {
            let digits = String(value, radix: 16)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return UUID(uuidString: "00000000-0000-0000-\(hex(high, 4))-\(hex(low, 12))")!
    }

    // MARK: Exercises

    static func exercise(
        _ id: String, _ name: String, _ muscle: MuscleGroup, _ equipment: Equipment,
        tracking: TrackingKind = .weightReps, best: Double = 0, previousSets: [PreviousSet] = [],
        sets: Int = 3, kg: Double, reps: Int, rest: Int, allowsAddedWeight: Bool = false
    ) -> Exercise {
        Exercise(
            id: id, name: name, muscle: muscle, secondary: "", equipment: equipment, tracking: tracking,
            mediaKey: nil, previousBestE1RM: best, previousSets: previousSets,
            defaults: ExerciseDefaults(sets: sets, weightKg: kg, reps: reps, restSeconds: rest),
            cues: [], barKg: 20, isCustom: false, allowsAddedWeight: allowsAddedWeight
        )
    }

    static let bench = exercise("bench", "Barbell bench press", .chest, .barbell, best: 99, kg: 60, reps: 8, rest: 150)
    static let incline = exercise("incline", "Incline dumbbell press", .chest, .dumbbell, best: 38, kg: 24, reps: 10, rest: 90)
    static let ohp = exercise("ohp", "Overhead press", .shoulders, .barbell, best: 58, kg: 40, reps: 8, rest: 120)
    static let lateral = exercise("lateral", "Dumbbell lateral raise", .shoulders, .dumbbell, best: 12.5, kg: 8, reps: 15, rest: 60)
    static let pushdown = exercise("pushdown", "Triceps pushdown", .arms, .cable, best: 43, kg: 30, reps: 12, rest: 60)
    static let crossover = exercise("crossover", "Cable crossover", .chest, .cable, best: 22, kg: 15, reps: 12, rest: 60)
    static let pushup = exercise("pushup", "Push-up", .chest, .bodyweight, tracking: .repsOnly, kg: 0, reps: 12, rest: 60)
    static let plank = exercise("plank", "Plank", .core, .bodyweight, tracking: .duration, kg: 0, reps: 45, rest: 45)
    static let squat = exercise("squat", "Back squat", .legs, .barbell, kg: 60, reps: 6, rest: 180)
    /// A reps-only exercise that carries an added or assisted load.
    static let pullup = exercise("pullup", "Pull-up", .back, .bodyweight, tracking: .repsOnly, kg: 0, reps: 8, rest: 120, allowsAddedWeight: true)

    /// Exercises the fuzz tests draw from.
    static let pool: [Exercise] = [bench, incline, ohp, lateral, pushdown, crossover, pushup, plank, squat, pullup]

    // MARK: Workout states

    typealias SetSpec = (SetType, Double, Int)

    static func normal(_ count: Int, _ kg: Double, _ reps: Int) -> [SetSpec] {
        Array(repeating: (SetType.normal, kg, reps), count: count)
    }

    /// Entry number `n` (1-based) with deterministic ids: entry `uuid(0x100 + n, 0)`, sets `uuid(0x100 + n, i + 1)`.
    static func entry(
        _ n: Int, _ exercise: Exercise, _ sets: [SetSpec], rest: Int,
        group: String? = nil, templateEntry: UUID? = nil
    ) -> WorkoutExercise {
        WorkoutExercise(
            id: uuid(0x100 + n, 0),
            exercise: exercise,
            sets: sets.enumerated().map { offset, spec in
                LoggedSet(id: uuid(0x100 + n, offset + 1), type: spec.0, weightKg: spec.1, reps: spec.2)
            },
            restSeconds: rest,
            supersetGroup: group,
            note: "",
            templateEntryID: templateEntry
        )
    }

    /// The design's workout, nothing logged yet: bench (2 warm-ups + 3 working sets, rest 150), incline, overhead press,
    /// lateral raise + pushdown (superset A, rest 60) and cable crossover.
    static func designState(now: Date = t0) -> WorkoutState {
        let exercises = [
            entry(1, bench, [(.warmup, 50, 8), (.warmup, 70, 5), (.normal, 82.5, 6), (.normal, 82.5, 6), (.normal, 85, 6)], rest: 150),
            entry(2, incline, normal(3, 28, 10), rest: 90),
            entry(3, ohp, normal(3, 45, 8), rest: 120),
            entry(4, lateral, normal(3, 8, 15), rest: 60, group: "A"),
            entry(5, pushdown, normal(3, 30, 12), rest: 60, group: "A"),
            entry(6, crossover, normal(3, 15, 12), rest: 60),
        ]
        return WorkoutState(id: uuid(1, 1), name: "Upper A · Push", exercises: exercises, currentIndex: 0, startedAt: now)
    }

    /// A workout of `exercises` starting at `index`.
    static func state(_ exercises: [WorkoutExercise], index: Int = 0) -> WorkoutState {
        WorkoutState(id: uuid(1, 2), name: "Test", exercises: exercises, currentIndex: index, startedAt: t0)
    }

    // MARK: Ids and actions

    static func ex(_ s: WorkoutState, _ k: Int) -> UUID { s.exercises[k].id }
    static func setID(_ s: WorkoutState, _ k: Int, _ i: Int) -> UUID { s.exercises[k].sets[i].id }

    static func toggle(_ s: WorkoutState, _ k: Int, _ i: Int) -> WorkoutAction {
        .toggleSet(exerciseID: ex(s, k), setID: setID(s, k, i))
    }

    static func log(_ s: WorkoutState, _ k: Int, _ i: Int) -> WorkoutAction {
        .logSet(exerciseID: ex(s, k), setID: setID(s, k, i))
    }

    /// `s` after `action` at `t0 + seconds`.
    static func reduced(_ s: WorkoutState, _ action: WorkoutAction, at seconds: Double = 0) -> WorkoutState {
        var copy = s
        WorkoutReducer.reduce(&copy, action, now: at(seconds))
        return copy
    }

    /// `s` after all `actions`, one second apart, starting at `t0 + start`.
    static func reduced(_ s: WorkoutState, _ actions: [WorkoutAction], start: Double = 0) -> WorkoutState {
        var copy = s
        for (n, action) in actions.enumerated() {
            WorkoutReducer.reduce(&copy, action, now: at(start + Double(n)))
        }
        return copy
    }

    /// True for actions that create new entity ids (their results differ between two runs).
    static func createsNewIDs(_ action: WorkoutAction) -> Bool {
        switch action {
        case .addSet, .addExercises, .replaceExercise: return true
        default: return false
        }
    }

    /// One action of every kind, using the first exercise / set of `s` (random unknown ids when `s` is empty).
    static func sampleActions(for s: WorkoutState) -> [WorkoutAction] {
        let e = s.exercises.first?.id ?? uuid(0xFFFF, 1)
        let st = s.exercises.first?.sets.first?.id ?? uuid(0xFFFF, 2)
        return [
            .toggleSet(exerciseID: e, setID: st), .logSet(exerciseID: e, setID: st), .logNextSet,
            .setWeight(exerciseID: e, setID: st, kg: 55), .setReps(exerciseID: e, setID: st, reps: 7),
            .nudgeNextSet(weightSteps: 1, repsSteps: -1), .setSetType(exerciseID: e, setID: st, type: .drop),
            .setRIR(exerciseID: e, setID: st, rir: 2), .toggleLastSetRIR(2), .addSet(exerciseID: e),
            .deleteSet(exerciseID: e, setID: st), .setNote(exerciseID: e, note: "slow negatives"),
            .goTo(index: 99), .goTo(index: -4), .nextExercise, .previousExercise,
            .addExercises([bench, plank]), .removeExercise(exerciseID: e), .moveExercise(from: 0, to: 2),
            .moveExerciseBy(exerciseID: e, delta: 1), .replaceExercise(exerciseID: e, with: plank),
            .toggleSuperset(exerciseID: e), .setRest(exerciseID: e, seconds: 30),
            .adjustRest(seconds: 15), .skipRest, .setAutoStartRest(false), .setAlertWhenRestEnds(false),
            .pause, .resume, .undo, .updateHeartRate(120), .setUsedWatch(true), .rename("Renamed"), .setWeightUnit(.lb),
            .startTimedSet(SetRef(exerciseID: e, setID: st)), .stopTimedSet, .cancelTimedSet,
        ]
    }
}

typealias RFix = RedFix

// MARK: - Rule 1: purity, revision, no-ops, currentIndex bounds

final class WorkoutReducerRevisionTests: XCTestCase {
    func testUndoWindowIsSixSeconds() {
        XCTAssertEqual(WorkoutReducer.undoWindow, 6)
    }

    func testChangedStateBumpsRevisionByOne() {
        var s = RFix.designState()
        XCTAssertEqual(s.revision, 0)
        WorkoutReducer.reduce(&s, .setNote(exerciseID: RFix.ex(s, 0), note: "x"), now: RFix.at(1))
        XCTAssertEqual(s.revision, 1)
        WorkoutReducer.reduce(&s, .nextExercise, now: RFix.at(2))
        XCTAssertEqual(s.revision, 2)
        WorkoutReducer.reduce(&s, RFix.toggle(s, 0, 0), now: RFix.at(3))
        XCTAssertEqual(s.revision, 3)
    }

    func testRevisionContinuesFromItsCurrentValue() {
        var s = RFix.designState()
        s.revision = 41
        WorkoutReducer.reduce(&s, .rename("Pull day"), now: RFix.at(1))
        XCTAssertEqual(s.revision, 42)
        XCTAssertEqual(s.name, "Pull day")
    }

    func testNoOpActionsKeepStateAndRevision() {
        let s = RFix.designState()
        let e = RFix.ex(s, 0)
        let st = RFix.setID(s, 0, 0)
        let last = RFix.ex(s, 5)
        let noOps: [WorkoutAction] = [
            .goTo(index: 0), .previousExercise, .skipRest, .resume, .undo,
            .adjustRest(seconds: -15), .adjustRest(seconds: 0),
            .setAutoStartRest(true), .setAlertWhenRestEnds(true), .setUsedWatch(false), .rename("Upper A · Push"),
            .setRest(exerciseID: e, seconds: 150), .setWeight(exerciseID: e, setID: st, kg: 50),
            .setWeight(exerciseID: e, setID: st, kg: 50.004), .setWeight(exerciseID: e, setID: st, kg: .nan),
            .setReps(exerciseID: e, setID: st, reps: 8), .setSetType(exerciseID: e, setID: st, type: .warmup),
            .setRIR(exerciseID: e, setID: st, rir: nil), .setNote(exerciseID: e, note: ""),
            .toggleSuperset(exerciseID: last), .moveExercise(from: 1, to: 1), .moveExerciseBy(exerciseID: e, delta: 0),
            .addExercises([]), .toggleLastSetRIR(2), .nudgeNextSet(weightSteps: 0, repsSteps: 0),
            .stopTimedSet, .cancelTimedSet,
            .startTimedSet(SetRef(exerciseID: e, setID: st)),   // bench is not a timed exercise
        ]
        for action in noOps {
            var t = s
            WorkoutReducer.reduce(&t, action, now: RFix.at(5))
            XCTAssertEqual(t, s, "expected a no-op: \(action)")
        }
    }

    func testLogSetOnDoneSetKeepsRevision() {
        let s = RFix.reduced(RFix.designState(), RFix.toggle(RFix.designState(), 0, 0), at: 1)
        let again = RFix.reduced(s, RFix.log(s, 0, 0), at: 2)
        XCTAssertEqual(again, s)
        XCTAssertEqual(again.revision, 1)
    }

    func testUnknownIDsAreNoOps() {
        let s = RFix.designState()
        let ghost = RFix.uuid(0xDEAD, 1)
        let ghostSet = RFix.uuid(0xDEAD, 2)
        let e = RFix.ex(s, 1)
        let actions: [WorkoutAction] = [
            .toggleSet(exerciseID: ghost, setID: ghostSet), .logSet(exerciseID: ghost, setID: ghostSet),
            .toggleSet(exerciseID: e, setID: ghostSet), .logSet(exerciseID: e, setID: ghostSet),
            .setWeight(exerciseID: ghost, setID: ghostSet, kg: 10), .setWeight(exerciseID: e, setID: ghostSet, kg: 10),
            .setReps(exerciseID: ghost, setID: ghostSet, reps: 3), .setReps(exerciseID: e, setID: ghostSet, reps: 3),
            .setSetType(exerciseID: ghost, setID: ghostSet, type: .drop), .setSetType(exerciseID: e, setID: ghostSet, type: .drop),
            .setRIR(exerciseID: ghost, setID: ghostSet, rir: 1), .setRIR(exerciseID: e, setID: ghostSet, rir: 1),
            .addSet(exerciseID: ghost), .deleteSet(exerciseID: ghost, setID: ghostSet), .deleteSet(exerciseID: e, setID: ghostSet),
            .setNote(exerciseID: ghost, note: "x"), .removeExercise(exerciseID: ghost),
            .moveExerciseBy(exerciseID: ghost, delta: 1), .replaceExercise(exerciseID: ghost, with: RFix.plank),
            .toggleSuperset(exerciseID: ghost), .setRest(exerciseID: ghost, seconds: 10),
            .startTimedSet(SetRef(exerciseID: ghost, setID: ghostSet)), .startTimedSet(SetRef(exerciseID: e, setID: ghostSet)),
        ]
        for action in actions {
            var t = s
            WorkoutReducer.reduce(&t, action, now: RFix.at(5))
            XCTAssertEqual(t, s, "expected a no-op: \(action)")
        }
    }

    func testOutOfRangeIndexesAreNoOps() {
        let s = RFix.designState()
        let actions: [WorkoutAction] = [
            .moveExercise(from: -1, to: 2), .moveExercise(from: 6, to: 0), .moveExercise(from: 0, to: 6),
            .moveExercise(from: 0, to: -1), .moveExerciseBy(exerciseID: RFix.ex(s, 0), delta: -1),
            .moveExerciseBy(exerciseID: RFix.ex(s, 5), delta: 1), .moveExerciseBy(exerciseID: RFix.ex(s, 2), delta: 9),
            .moveExerciseBy(exerciseID: RFix.ex(s, 2), delta: Int.max),
        ]
        for action in actions {
            var t = s
            WorkoutReducer.reduce(&t, action, now: RFix.at(5))
            XCTAssertEqual(t, s, "expected a no-op: \(action)")
        }
    }

    func testReducingTheSameInputTwiceGivesTheSameState() {
        let s = RFix.designState()
        for action in RFix.sampleActions(for: s) where !RFix.createsNewIDs(action) {
            XCTAssertEqual(RFix.reduced(s, action, at: 3), RFix.reduced(s, action, at: 3), "\(action)")
        }
    }

    func testNewEntitiesGetFreshIDs() {
        let s = RFix.designState()
        let added = RFix.reduced(s, .addSet(exerciseID: RFix.ex(s, 1)))
        let newSet = added.exercises[1].sets.last!
        XCTAssertFalse(s.exercises.flatMap { $0.sets }.contains { $0.id == newSet.id })
        let more = RFix.reduced(s, .addExercises([RFix.plank, RFix.plank]))
        let ids = more.exercises.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCurrentIndexStaysInBoundsAfterEveryAction() {
        let starts: [WorkoutState] = [
            RFix.designState(),
            WorkoutState(name: "Empty", startedAt: RFix.t0),
            RFix.state([RFix.entry(1, RFix.plank, RFix.normal(1, 0, 45), rest: 45)]),
        ]
        for start in starts {
            for index in [-7, 0, 2, 5, 99] {
                var s = start
                s.currentIndex = index
                // each action alone
                for action in RFix.sampleActions(for: s) {
                    let after = RFix.reduced(s, action, at: 2)
                    assertInBounds(after, "\(action) from index \(index)")
                }
                // all actions in sequence
                var chained = s
                for (n, action) in RFix.sampleActions(for: s).enumerated() {
                    WorkoutReducer.reduce(&chained, action, now: RFix.at(Double(n)))
                    assertInBounds(chained, "chained \(action) from index \(index)")
                }
            }
        }
    }

    func testCurrentIndexIsZeroForEmptyWorkout() {
        var s = WorkoutState(name: "Empty", currentIndex: 3, startedAt: RFix.t0)
        WorkoutReducer.reduce(&s, .nextExercise, now: RFix.at(1))
        XCTAssertEqual(s.currentIndex, 0)
        WorkoutReducer.reduce(&s, .goTo(index: 5), now: RFix.at(2))
        XCTAssertEqual(s.currentIndex, 0)
    }

    func testOutOfRangeIncomingIndexIsRepairedEvenForHeartRate() {
        var s = RFix.designState()
        s.currentIndex = 42
        WorkoutReducer.reduce(&s, .updateHeartRate(100), now: RFix.at(1))
        XCTAssertEqual(s.currentIndex, 5)
        XCTAssertEqual(s.revision, 0)
    }

    private func assertInBounds(_ s: WorkoutState, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        if s.exercises.isEmpty {
            XCTAssertEqual(s.currentIndex, 0, message, file: file, line: line)
        } else {
            XCTAssertTrue((0..<s.exercises.count).contains(s.currentIndex), "\(message): \(s.currentIndex)", file: file, line: line)
        }
    }
}

// MARK: - Rule 2: logging

final class WorkoutReducerLoggingTests: XCTestCase {
    func testBenchLoggingFlowWithRestLengths60And150() {
        var s = RFix.designState()
        // set index, logged at (seconds), expected rest seconds: warm-ups rest 40 % of 150 s, working sets the full 150 s.
        let steps: [(Int, Double, Int)] = [(0, 10, 60), (1, 100, 60), (2, 200, 150), (3, 400, 150), (4, 600, 150)]
        for (n, step) in steps.enumerated() {
            s = RFix.reduced(s, RFix.toggle(s, 0, step.0), at: step.1)
            XCTAssertTrue(s.exercises[0].sets[step.0].isDone)
            XCTAssertEqual(s.lastLogged, SetRef(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, step.0)))
            XCTAssertEqual(s.rest?.totalSeconds, step.2)
            XCTAssertEqual(s.rest?.endsAt, RFix.at(step.1 + Double(step.2)))
            XCTAssertNil(s.rest?.frozenRemaining)
            XCTAssertEqual(s.currentIndex, 0)
            XCTAssertEqual(s.revision, n + 1)
        }
        XCTAssertTrue(s.exercises[0].isComplete)
        XCTAssertEqual(WorkoutTargets.nextPending(in: s), SetTarget(exerciseIndex: 1, setIndex: 0))
        // The remaining exercises are untouched.
        XCTAssertEqual(s.exercises[1...].flatMap { $0.sets }.filter { $0.isDone }.count, 0)
    }

    func testWarmupRestFactorTable() {
        // rest -> warm-up rest: max(30, round(rest * 0.4 / 5) * 5); a rest of 0 (Off) means no rest after any set type (rule 2),
        // so the warm-up of an Off exercise starts no timer either (it used to start the 30 s minimum).
        let table: [(Int, Int)] = [(45, 30), (60, 30), (75, 30), (90, 35), (100, 40), (120, 50), (150, 60), (180, 70), (0, 0)]
        for (rest, expected) in table {
            let entry = RFix.entry(1, RFix.bench, [(.warmup, 40, 8), (.normal, 80, 5)], rest: rest)
            let s = RFix.state([entry])
            let warm = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 0)
            if expected > 0 {
                XCTAssertEqual(warm.rest?.totalSeconds, expected, "warm-up after rest \(rest)")
            } else {
                XCTAssertNil(warm.rest, "rest Off starts no timer after a warm-up either")
            }
            let work = RFix.reduced(s, RFix.toggle(s, 0, 1), at: 0)
            if rest > 0 {
                XCTAssertEqual(work.rest?.totalSeconds, rest, "working set after rest \(rest)")
            } else {
                XCTAssertNil(work.rest, "rest Off starts no timer after a working set")
            }
        }
    }

    /// Rule 2: an exercise rest of 0 (Off) means no rest after a set of ANY type; a warm-up used to start its 30 s minimum.
    func testRestOffMeansNoRestForAnySetType() {
        let types: [SetType] = [.normal, .warmup, .drop, .failure]
        for type in types {
            let entry = RFix.entry(1, RFix.bench, [(type, 40, 8), (.normal, 80, 5)], rest: 0)
            let s = RFix.state([entry])
            for action in [RFix.toggle(s, 0, 0), RFix.log(s, 0, 0), WorkoutAction.logNextSet] {
                let logged = RFix.reduced(s, action, at: 5)
                XCTAssertTrue(logged.exercises[0].sets[0].isDone, "\(type) \(action)")
                XCTAssertNil(logged.rest, "no timer after a \(type) set of an exercise whose rest is Off (\(action))")
            }
        }
    }

    func testLoggingAWarmupOfAnOffExerciseEndsARestThatWasRunning() {
        // A running rest from the previous exercise is replaced by "no rest", like after a working set of an Off exercise.
        let first = RFix.entry(1, RFix.bench, RFix.normal(1, 80, 5), rest: 90)
        let off = RFix.entry(2, RFix.incline, [(.warmup, 10, 10), (.normal, 20, 10)], rest: 0)
        var s = RFix.state([first, off])
        s = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 1)
        XCTAssertEqual(s.rest?.totalSeconds, 90)
        s = RFix.reduced(s, RFix.toggle(s, 1, 0), at: 2)
        XCTAssertNil(s.rest)
        XCTAssertEqual(s.lastLogged, SetRef(exerciseID: RFix.ex(s, 1), setID: RFix.setID(s, 1, 0)))
    }

    func testTurningTheTimerOffDuringTheWorkoutAlsoSilencesWarmups() {
        let s = RFix.state([RFix.entry(1, RFix.bench, [(.warmup, 40, 8), (.warmup, 60, 5), (.normal, 80, 5)], rest: 150)])
        let before = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 1)
        XCTAssertEqual(before.rest?.totalSeconds, 60)
        var off = RFix.reduced(s, .setRest(exerciseID: RFix.ex(s, 0), seconds: 0), at: 1)
        off = RFix.reduced(off, RFix.toggle(off, 0, 0), at: 2)
        XCTAssertNil(off.rest)
        // Turning it back on restores the warm-up rule.
        var on = RFix.reduced(off, .setRest(exerciseID: RFix.ex(off, 0), seconds: 100), at: 3)
        on = RFix.reduced(on, RFix.toggle(on, 0, 1), at: 4)
        XCTAssertEqual(on.rest?.totalSeconds, 40)
    }

    func testAWarmupOfAnOffExerciseInASupersetStartsNoRestEither() {
        let a = RFix.entry(1, RFix.lateral, [(.warmup, 4, 15), (.normal, 8, 15)], rest: 0, group: "A")
        let b = RFix.entry(2, RFix.pushdown, [(.warmup, 15, 12), (.normal, 30, 12)], rest: 0, group: "A")
        var s = RFix.state([a, b])
        s = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 1)
        XCTAssertEqual(s.currentIndex, 1, "the superset still moves on to its partner")
        XCTAssertNil(s.rest)
        s = RFix.reduced(s, RFix.toggle(s, 1, 0), at: 2)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertNil(s.rest, "end of the round: still no rest, the timer is Off")
    }

    func testDropAndFailureSetsUseTheFullRest() {
        let entry = RFix.entry(1, RFix.bench, [(.drop, 60, 8), (.failure, 60, 8)], rest: 150)
        let s = RFix.state([entry])
        XCTAssertEqual(RFix.reduced(s, RFix.toggle(s, 0, 0)).rest?.totalSeconds, 150)
        XCTAssertEqual(RFix.reduced(s, RFix.toggle(s, 0, 1)).rest?.totalSeconds, 150)
    }

    func testTogglingADoneSetMakesItPendingKeepingRirAndRest() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 10)
        s = RFix.reduced(s, .toggleLastSetRIR(3), at: 11)
        let restBefore = s.rest
        let lastBefore = s.lastLogged
        XCTAssertEqual(s.exercises[0].sets[2].rir, 3)
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 20)
        XCTAssertFalse(s.exercises[0].sets[2].isDone)
        XCTAssertEqual(s.exercises[0].sets[2].rir, 3)
        XCTAssertEqual(s.rest, restBefore)
        XCTAssertEqual(s.lastLogged, lastBefore)
        // and toggling again logs it again with a new rest
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 30)
        XCTAssertTrue(s.exercises[0].sets[2].isDone)
        XCTAssertEqual(s.rest?.endsAt, RFix.at(180))
    }

    func testAutoStartRestOffClearsAnyRest() {
        var s = RFix.designState()
        s.settings.autoStartRest = false
        s.rest = RestState(endsAt: RFix.at(500), totalSeconds: 90)
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 10)
        XCTAssertNil(s.rest)
        XCTAssertTrue(s.exercises[0].sets[2].isDone)
    }

    func testRestOffForAnExerciseStartsNoTimer() {
        var s = RFix.designState()
        s = RFix.reduced(s, .setRest(exerciseID: RFix.ex(s, 0), seconds: 0))
        s.rest = RestState(endsAt: RFix.at(500), totalSeconds: 90)
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 10)
        XCTAssertNil(s.rest)
    }

    func testLoggingWhilePausedStartsAFrozenRest() {
        var s = RFix.designState()
        s = RFix.reduced(s, .pause, at: 5)
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 10)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(160), totalSeconds: 150, frozenRemaining: 150))
        XCTAssertEqual(s.restRemaining(now: RFix.at(9_999)), 150)
    }

    func testLogSetIsIdempotent() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.log(s, 0, 2), at: 10)
        XCTAssertTrue(s.exercises[0].sets[2].isDone)
        XCTAssertEqual(s.rest?.totalSeconds, 150)
        let again = RFix.reduced(s, RFix.log(s, 0, 2), at: 99)
        XCTAssertEqual(again, s)
    }

    func testLogSetOnAPendingSetMatchesToggle() {
        let s = RFix.designState()
        XCTAssertEqual(RFix.reduced(s, RFix.log(s, 3, 1), at: 7), RFix.reduced(s, RFix.toggle(s, 3, 1), at: 7))
    }

    func testLogNextSetMovesToTheNextPendingExerciseAndLogsIt() {
        var s = RFix.designState()
        for i in 0..<5 { s = RFix.reduced(s, RFix.log(s, 0, i), at: Double(i)) }
        XCTAssertEqual(s.currentIndex, 0)
        s = RFix.reduced(s, .logNextSet, at: 50)
        XCTAssertEqual(s.currentIndex, 1)
        XCTAssertTrue(s.exercises[1].sets[0].isDone)
        XCTAssertEqual(s.lastLogged, SetRef(exerciseID: RFix.ex(s, 1), setID: RFix.setID(s, 1, 0)))
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(140), totalSeconds: 90))
    }

    func testLogNextSetWrapsToEarlierExercises() {
        var s = RFix.designState()
        s.currentIndex = 5
        for i in 0..<3 { s = RFix.reduced(s, RFix.log(s, 5, i), at: Double(i)) }
        s = RFix.reduced(s, .logNextSet, at: 10)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertTrue(s.exercises[0].sets[0].isDone)
        XCTAssertEqual(s.rest?.totalSeconds, 60)   // a warm-up of a 150 s exercise
    }

    func testLogNextSetWithNothingPendingIsANoOp() {
        var s = RFix.designState()
        for k in 0..<s.exercises.count {
            for i in 0..<s.exercises[k].sets.count { s.exercises[k].sets[i].isDone = true }
        }
        XCTAssertNil(WorkoutTargets.nextPending(in: s))
        XCTAssertEqual(RFix.reduced(s, .logNextSet), s)
        XCTAssertEqual(RFix.reduced(s, .nudgeNextSet(weightSteps: 1, repsSteps: 1)), s)
    }

    func testNextPendingOrder() {
        var s = RFix.designState()
        s.currentIndex = 2
        XCTAssertEqual(WorkoutTargets.nextPending(in: s), SetTarget(exerciseIndex: 2, setIndex: 0))
        // current exercise done -> the following exercises first
        for i in 0..<3 { s.exercises[2].sets[i].isDone = true }
        XCTAssertEqual(WorkoutTargets.nextPending(in: s), SetTarget(exerciseIndex: 3, setIndex: 0))
        // following exercises done too -> earlier ones
        for k in 3..<6 { for i in 0..<3 { s.exercises[k].sets[i].isDone = true } }
        XCTAssertEqual(WorkoutTargets.nextPending(in: s), SetTarget(exerciseIndex: 0, setIndex: 0))
        // first pending set within an exercise, not the first set
        s.exercises[0].sets[0].isDone = true
        s.exercises[0].sets[1].isDone = true
        XCTAssertEqual(WorkoutTargets.nextPending(in: s), SetTarget(exerciseIndex: 0, setIndex: 2))
        // earlier exercises are searched in order
        s.exercises[0].sets[2].isDone = true
        s.exercises[0].sets[3].isDone = true
        s.exercises[0].sets[4].isDone = true
        XCTAssertEqual(WorkoutTargets.nextPending(in: s), SetTarget(exerciseIndex: 1, setIndex: 0))
    }

    func testNextPendingEdgeCases() {
        XCTAssertNil(WorkoutTargets.nextPending(in: WorkoutState(name: "E", startedAt: RFix.t0)))
        var s = RFix.designState()
        s.currentIndex = 99   // treated as the last exercise
        s.exercises[5].sets[0].isDone = true
        XCTAssertEqual(WorkoutTargets.nextPending(in: s), SetTarget(exerciseIndex: 5, setIndex: 1))
        let noSets = RFix.state([RFix.entry(1, RFix.plank, [], rest: 45)])
        XCTAssertNil(WorkoutTargets.nextPending(in: noSets))
    }

    func testSupersetARoundTrip() {
        var s = RFix.designState()
        s.currentIndex = 3
        s.rest = RestState(endsAt: RFix.at(500), totalSeconds: 90)   // an older rest that is still running
        // first leg (lateral raise): no rest, jump forward to the pushdown
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 10)
        XCTAssertEqual(s.currentIndex, 4)
        XCTAssertNil(s.rest)
        XCTAssertEqual(s.lastLogged, SetRef(exerciseID: RFix.ex(s, 3), setID: RFix.setID(s, 3, 0)))
        // last leg (pushdown): rest starts, jump back to the first leg
        s = RFix.reduced(s, RFix.toggle(s, 4, 0), at: 20)
        XCTAssertEqual(s.currentIndex, 3)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(80), totalSeconds: 60))
        XCTAssertEqual(s.lastLogged, SetRef(exerciseID: RFix.ex(s, 4), setID: RFix.setID(s, 4, 0)))
        // the next round, driven by the Watch button
        s = RFix.reduced(s, .logNextSet, at: 90)
        XCTAssertEqual(s.exercises[3].sets[1].isDone, true)
        XCTAssertEqual(s.currentIndex, 4)
        XCTAssertNil(s.rest)
        s = RFix.reduced(s, .logNextSet, at: 100)
        XCTAssertEqual(s.exercises[4].sets[1].isDone, true)
        XCTAssertEqual(s.currentIndex, 3)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(160), totalSeconds: 60))
    }

    func testSupersetLegsWithAutoStartOffNeverStartARest() {
        var s = RFix.designState()
        s.settings.autoStartRest = false
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 1)
        s = RFix.reduced(s, RFix.toggle(s, 4, 0), at: 2)
        XCTAssertNil(s.rest)
        XCTAssertEqual(s.currentIndex, 3)
    }

    func testThreeLegGroupAdvancesThroughTheLegs() {
        let legs = [
            RFix.entry(1, RFix.lateral, RFix.normal(2, 8, 15), rest: 60, group: "A"),
            RFix.entry(2, RFix.pushdown, RFix.normal(2, 30, 12), rest: 60, group: "A"),
            RFix.entry(3, RFix.crossover, RFix.normal(2, 15, 12), rest: 75, group: "A"),
        ]
        var s = RFix.state(legs)
        s = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 1)
        XCTAssertEqual(s.currentIndex, 1); XCTAssertNil(s.rest)
        s = RFix.reduced(s, RFix.toggle(s, 1, 0), at: 2)
        XCTAssertEqual(s.currentIndex, 2); XCTAssertNil(s.rest)
        s = RFix.reduced(s, RFix.toggle(s, 2, 0), at: 3)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(78), totalSeconds: 75))   // the last leg's own rest
    }

    func testLoggingASetOfAnotherExerciseDoesNotMoveTheCurrentIndex() {
        var s = RFix.designState()
        s.currentIndex = 1
        s = RFix.reduced(s, RFix.toggle(s, 2, 0), at: 5)   // ohp, not in a superset
        XCTAssertEqual(s.currentIndex, 1)
        XCTAssertEqual(s.rest?.totalSeconds, 120)
    }

    func testSupersetJumpIsToTheNextMemberEvenWhenTheGroupIsNotContiguous() {
        let legs = [
            RFix.entry(1, RFix.lateral, RFix.normal(2, 8, 15), rest: 60, group: "A"),
            RFix.entry(2, RFix.incline, RFix.normal(2, 20, 10), rest: 90),
            RFix.entry(3, RFix.pushdown, RFix.normal(2, 30, 12), rest: 60, group: "A"),
        ]
        var s = RFix.state(legs)
        s = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 1)
        XCTAssertEqual(s.currentIndex, 2, "the next member by order, not the exercise at index + 1")
        XCTAssertNil(s.rest)
        s = RFix.reduced(s, RFix.toggle(s, 2, 0), at: 2)
        XCTAssertEqual(s.currentIndex, 0, "after the last member the first one is current again")
        XCTAssertEqual(s.rest?.totalSeconds, 60)
    }
}

// MARK: - Rules 3 and 4: set values, nudges, types, RIR, notes

final class WorkoutReducerSetEditTests: XCTestCase {
    func testSetWeightClampsAndRoundsToHundredths() {
        let s = RFix.designState()
        let e = RFix.ex(s, 0)
        let id = RFix.setID(s, 0, 2)
        func weight(_ kg: Double) -> Double {
            RFix.reduced(s, .setWeight(exerciseID: e, setID: id, kg: kg)).exercises[0].sets[2].weightKg
        }
        XCTAssertEqual(weight(-5), 0)
        XCTAssertEqual(weight(0), 0)
        XCTAssertEqual(weight(82.504), 82.5, accuracy: 1e-9)
        XCTAssertEqual(weight(82.506), 82.51, accuracy: 1e-9)
        XCTAssertEqual(weight(100), 100)
        XCTAssertEqual(weight(.infinity), 82.5)     // not representable: ignored
        XCTAssertEqual(weight(.nan), 82.5)          // ignored
        XCTAssertEqual(weight(-.infinity), 0)       // clamped like any negative value
    }

    func testSetRepsClampsTo0Through999() {
        let s = RFix.designState()
        let e = RFix.ex(s, 0)
        let id = RFix.setID(s, 0, 2)
        func reps(_ n: Int) -> Int { RFix.reduced(s, .setReps(exerciseID: e, setID: id, reps: n)).exercises[0].sets[2].reps }
        XCTAssertEqual(reps(-3), 0)
        XCTAssertEqual(reps(0), 0)
        XCTAssertEqual(reps(12), 12)
        XCTAssertEqual(reps(999), 999)
        XCTAssertEqual(reps(1000), 999)
        XCTAssertEqual(reps(Int.max), 999)
        XCTAssertEqual(reps(Int.min), 0)
    }

    func testEditingValuesDoesNotChangeTheDoneFlag() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 1)
        s = RFix.reduced(s, .setWeight(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 2), kg: 90), at: 2)
        s = RFix.reduced(s, .setReps(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 2), reps: 4), at: 3)
        XCTAssertTrue(s.exercises[0].sets[2].isDone)
        let pending = RFix.reduced(s, .setWeight(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 3), kg: 91))
        XCTAssertFalse(pending.exercises[0].sets[3].isDone)
        XCTAssertEqual(pending.rest, s.rest)
    }

    func testNudgeEditsTheNextPendingSetWithTheExerciseSteps() {
        var s = RFix.designState()
        // bench is a barbell: 2.5 kg steps; the next pending set is the first warm-up (50 x 8)
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: 1, repsSteps: 2))
        XCTAssertEqual(s.exercises[0].sets[0].weightKg, 52.5)
        XCTAssertEqual(s.exercises[0].sets[0].reps, 10)
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: -3, repsSteps: -1))
        XCTAssertEqual(s.exercises[0].sets[0].weightKg, 45)
        XCTAssertEqual(s.exercises[0].sets[0].reps, 9)
        XCTAssertEqual(s.exercises[0].sets[1].weightKg, 70)   // other sets untouched
        XCTAssertEqual(s.currentIndex, 0)
    }

    func testNudgeUsesDumbbellBodyweightAndDurationSteps() {
        let dumbbell = RFix.designState()
        var d = dumbbell
        d.currentIndex = 1                                   // incline: dumbbell, 2 kg steps
        d = RFix.reduced(d, .nudgeNextSet(weightSteps: 2, repsSteps: 1))
        XCTAssertEqual(d.exercises[1].sets[0].weightKg, 32)
        XCTAssertEqual(d.exercises[1].sets[0].reps, 11)

        var bw = RFix.state([RFix.entry(1, RFix.pushup, RFix.normal(2, 0, 12), rest: 60)])
        bw = RFix.reduced(bw, .nudgeNextSet(weightSteps: 4, repsSteps: -2))   // no weight for repsOnly
        XCTAssertEqual(bw.exercises[0].sets[0].weightKg, 0)
        XCTAssertEqual(bw.exercises[0].sets[0].reps, 10)

        var timed = RFix.state([RFix.entry(1, RFix.plank, RFix.normal(2, 0, 45), rest: 45)])
        timed = RFix.reduced(timed, .nudgeNextSet(weightSteps: 1, repsSteps: 3))   // seconds move in 5 s steps
        XCTAssertEqual(timed.exercises[0].sets[0].weightKg, 0)
        XCTAssertEqual(timed.exercises[0].sets[0].reps, 60)
    }

    func testNudgeClampsAtTheBounds() {
        var s = RFix.designState()
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: -100, repsSteps: -100))
        XCTAssertEqual(s.exercises[0].sets[0].weightKg, 0)
        XCTAssertEqual(s.exercises[0].sets[0].reps, 0)
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: Int.max, repsSteps: Int.max))
        XCTAssertEqual(s.exercises[0].sets[0].reps, 999)
        XCTAssertTrue(s.exercises[0].sets[0].weightKg.isFinite)
    }

    func testNudgeFollowsTheNextPendingSetAcrossExercises() {
        var s = RFix.designState()
        for i in 0..<5 { s.exercises[0].sets[i].isDone = true }   // current exercise complete
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: 1, repsSteps: 0))
        XCTAssertEqual(s.exercises[1].sets[0].weightKg, 30)
        XCTAssertEqual(s.currentIndex, 0)                          // nudging does not navigate
    }

    func testSetSetTypeChangesOnlyTheType() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 1)
        let rest = s.rest
        s = RFix.reduced(s, .setSetType(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 2), type: .failure), at: 2)
        XCTAssertEqual(s.exercises[0].sets[2].type, .failure)
        XCTAssertTrue(s.exercises[0].sets[2].isDone)
        XCTAssertEqual(s.rest, rest)
        s = RFix.reduced(s, .setSetType(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 0), type: .normal), at: 3)
        XCTAssertEqual(s.exercises[0].sets[0].type, .normal)
    }

    func testExplicitRIRClampsAndClears() {
        var s = RFix.designState()
        let e = RFix.ex(s, 0)
        let id = RFix.setID(s, 0, 2)
        func set(_ rir: Int?) { s = RFix.reduced(s, .setRIR(exerciseID: e, setID: id, rir: rir)) }
        set(2); XCTAssertEqual(s.exercises[0].sets[2].rir, 2)
        set(9); XCTAssertEqual(s.exercises[0].sets[2].rir, 4)
        set(-3); XCTAssertEqual(s.exercises[0].sets[2].rir, 0)
        set(nil); XCTAssertNil(s.exercises[0].sets[2].rir)
        set(2); set(2)   // explicit set does not toggle
        XCTAssertEqual(s.exercises[0].sets[2].rir, 2)
    }

    func testToggleLastSetRIRAppliesToTheLastLoggedSetAndSameValueClears() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 1)
        s = RFix.reduced(s, .toggleLastSetRIR(2), at: 2)
        XCTAssertEqual(s.exercises[0].sets[2].rir, 2)
        s = RFix.reduced(s, .toggleLastSetRIR(2), at: 3)
        XCTAssertNil(s.exercises[0].sets[2].rir)
        s = RFix.reduced(s, .toggleLastSetRIR(3), at: 4)
        s = RFix.reduced(s, .toggleLastSetRIR(1), at: 5)
        XCTAssertEqual(s.exercises[0].sets[2].rir, 1)
        s = RFix.reduced(s, .toggleLastSetRIR(9), at: 6)      // clamped to 4 ("4+")
        XCTAssertEqual(s.exercises[0].sets[2].rir, 4)
        s = RFix.reduced(s, .toggleLastSetRIR(4), at: 7)
        XCTAssertNil(s.exercises[0].sets[2].rir)
        // the next logged set becomes the target
        s = RFix.reduced(s, RFix.toggle(s, 0, 3), at: 8)
        s = RFix.reduced(s, .toggleLastSetRIR(0), at: 9)
        XCTAssertEqual(s.exercises[0].sets[3].rir, 0)
        XCTAssertNil(s.exercises[0].sets[2].rir)
    }

    func testToggleLastSetRIRWithoutALoggedSetIsANoOp() {
        let s = RFix.designState()
        XCTAssertEqual(RFix.reduced(s, .toggleLastSetRIR(2)), s)
    }

    func testSetNoteStoresTheText() {
        var s = RFix.designState()
        s = RFix.reduced(s, .setNote(exerciseID: RFix.ex(s, 2), note: "Belt on, pause at the chest"))
        XCTAssertEqual(s.exercises[2].note, "Belt on, pause at the chest")
        XCTAssertEqual(s.exercises[1].note, "")
        s = RFix.reduced(s, .setNote(exerciseID: RFix.ex(s, 2), note: ""))
        XCTAssertEqual(s.exercises[2].note, "")
    }
}

// MARK: - Rule 5: add / delete set

final class WorkoutReducerSetListTests: XCTestCase {
    func testAddSetCopiesTheLastSetAsAPendingNormalSet() {
        var s = RFix.designState()
        s.exercises[2].sets[2].type = .failure
        s.exercises[2].sets[2].isDone = true
        s.exercises[2].sets[2].rir = 1
        s.exercises[2].sets[2].weightKg = 47.5
        s.exercises[2].sets[2].reps = 7
        s = RFix.reduced(s, .addSet(exerciseID: RFix.ex(s, 2)))
        XCTAssertEqual(s.exercises[2].sets.count, 4)
        let added = s.exercises[2].sets[3]
        XCTAssertEqual(added.type, .normal)
        XCTAssertEqual(added.weightKg, 47.5)
        XCTAssertEqual(added.reps, 7)
        XCTAssertFalse(added.isDone)
        XCTAssertNil(added.rir)
        XCTAssertEqual(s.revision, 1)
    }

    func testAddSetWithoutSetsUsesTheExerciseDefaults() {
        var s = RFix.designState()
        s.exercises[0].sets = []
        s = RFix.reduced(s, .addSet(exerciseID: RFix.ex(s, 0)))
        XCTAssertEqual(s.exercises[0].sets.count, 1)
        XCTAssertEqual(s.exercises[0].sets[0].weightKg, 60)    // bench defaults: 60 kg x 8
        XCTAssertEqual(s.exercises[0].sets[0].reps, 8)
        XCTAssertEqual(s.exercises[0].sets[0].type, .normal)
    }

    func testDeleteSetRemovesItAndCreatesAnUndoEntry() {
        var s = RFix.designState()
        let removed = s.exercises[1].sets[1]
        s = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 1), setID: removed.id), at: 100)
        XCTAssertEqual(s.exercises[1].sets.count, 2)
        XCTAssertFalse(s.exercises[1].sets.contains { $0.id == removed.id })
        XCTAssertEqual(s.undo?.title, "Set deleted")
        XCTAssertEqual(s.undo?.expiresAt, RFix.at(106))
        XCTAssertEqual(s.undo?.payload, .set(exerciseID: RFix.ex(s, 1), index: 1, set: removed))
        XCTAssertEqual(s.revision, 1)
    }

    func testDeleteSetClearsLastLoggedOnlyWhenItPointedAtThatSet() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 1)
        let other = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 3)), at: 2)
        XCTAssertNotNil(other.lastLogged)
        let same = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 2)), at: 2)
        XCTAssertNil(same.lastLogged)
    }

    func testDeletingTheLastSetLeavesAnExerciseWithoutSets() {
        var s = RFix.state([RFix.entry(1, RFix.plank, RFix.normal(1, 0, 45), rest: 45)])
        s = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 0)))
        XCTAssertTrue(s.exercises[0].sets.isEmpty)
        XCTAssertFalse(s.exercises[0].isComplete)
        XCTAssertNil(WorkoutTargets.nextPending(in: s))
    }
}

// MARK: - Rule 6: remove exercise and undo

final class WorkoutReducerRemoveUndoTests: XCTestCase {
    func testRemoveExerciseCreatesAnUndoEntry() {
        var s = RFix.designState()
        let removed = s.exercises[1]
        s = RFix.reduced(s, .removeExercise(exerciseID: removed.id), at: 50)
        XCTAssertEqual(s.exercises.count, 5)
        XCTAssertFalse(s.exercises.contains { $0.id == removed.id })
        XCTAssertEqual(s.undo?.title, "Removed Incline dumbbell press")
        XCTAssertEqual(s.undo?.expiresAt, RFix.at(56))
        XCTAssertEqual(s.undo?.payload, .exercise(index: 1, exercise: removed))
    }

    func testCurrentIndexShiftsDownWhenAnEarlierExerciseIsRemoved() {
        var s = RFix.designState()
        s.currentIndex = 3
        let lateralID = RFix.ex(s, 3)
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 1)))
        XCTAssertEqual(s.currentIndex, 2)
        XCTAssertEqual(s.currentExercise?.id, lateralID)
    }

    func testRemovingTheCurrentOrLaterExerciseKeepsTheIndexThenClamps() {
        var s = RFix.designState()
        s.currentIndex = 2
        var a = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 2)))
        XCTAssertEqual(a.currentIndex, 2)
        XCTAssertEqual(a.currentExercise?.exercise.id, "lateral")
        a = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 4)))
        XCTAssertEqual(a.currentIndex, 2)
        s.currentIndex = 5
        let b = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 5)))
        XCTAssertEqual(b.currentIndex, 4)
    }

    func testRemovingTheOnlyExerciseEmptiesTheWorkout() {
        var s = RFix.state([RFix.entry(1, RFix.plank, RFix.normal(1, 0, 45), rest: 45)])
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 0)))
        XCTAssertTrue(s.exercises.isEmpty)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertNotNil(s.undo)
    }

    func testLastLoggedIsClearedOnlyWhenItPointedAtTheRemovedExercise() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 2, 0), at: 1)
        let keep = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 1)), at: 2)
        XCTAssertNotNil(keep.lastLogged)
        let clear = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 2)), at: 2)
        XCTAssertNil(clear.lastLogged)
    }

    func testRemovingOneOfTwoSupersetMembersReleasesTheOther() {
        var s = RFix.designState()
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 3)))
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, [nil, nil, nil, nil, nil])
    }

    func testRemovingTheMiddleOfAThreeMemberSupersetKeepsTheGroup() {
        let legs = [
            RFix.entry(1, RFix.bench, RFix.normal(2, 80, 5), rest: 150),
            RFix.entry(2, RFix.lateral, RFix.normal(2, 8, 15), rest: 60, group: "A"),
            RFix.entry(3, RFix.pushdown, RFix.normal(2, 30, 12), rest: 60, group: "A"),
            RFix.entry(4, RFix.crossover, RFix.normal(2, 15, 12), rest: 60, group: "A"),
        ]
        var s = RFix.state(legs)
        let removed = s.exercises[2]
        s = RFix.reduced(s, .removeExercise(exerciseID: removed.id), at: 10)
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, [nil, "A", "A"])
        // the group still works: first leg jumps forward, last leg jumps back
        let first = RFix.reduced(s, RFix.toggle(s, 1, 0), at: 11)
        XCTAssertEqual(first.currentIndex, 2)
        XCTAssertNil(first.rest)
        let last = RFix.reduced(first, RFix.toggle(first, 2, 0), at: 12)
        XCTAssertEqual(last.currentIndex, 1)
        XCTAssertNotNil(last.rest)
        // undo puts the middle leg back into the group
        let restored = RFix.reduced(s, .undo, at: 12)
        XCTAssertEqual(restored.exercises.map { $0.supersetGroup }, [nil, "A", "A", "A"])
        XCTAssertEqual(restored.exercises[2].id, removed.id)
    }

    func testRemovingTheFirstOrLastOfAThreeMemberSupersetKeepsTheGroup() {
        let legs = [
            RFix.entry(1, RFix.lateral, RFix.normal(2, 8, 15), rest: 60, group: "A"),
            RFix.entry(2, RFix.pushdown, RFix.normal(2, 30, 12), rest: 60, group: "A"),
            RFix.entry(3, RFix.crossover, RFix.normal(2, 15, 12), rest: 60, group: "A"),
        ]
        let s = RFix.state(legs)
        XCTAssertEqual(RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 0))).exercises.map { $0.supersetGroup }, ["A", "A"])
        XCTAssertEqual(RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 2))).exercises.map { $0.supersetGroup }, ["A", "A"])
    }

    func testUndoInsideTheWindowRestoresTheExerciseAtItsIndex() {
        var s = RFix.designState()
        s.currentIndex = 4
        let removed = s.exercises[1]
        s = RFix.reduced(s, .removeExercise(exerciseID: removed.id), at: 100)
        XCTAssertEqual(s.currentIndex, 3)
        s = RFix.reduced(s, .undo, at: 103)
        XCTAssertEqual(s.exercises.count, 6)
        XCTAssertEqual(s.exercises[1], removed)
        XCTAssertEqual(s.currentIndex, 1)      // the restored exercise becomes the current one
        XCTAssertNil(s.undo)
    }

    func testUndoExactlyAtTheEndOfTheWindowStillRestores() {
        var s = RFix.designState()
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 5)), at: 100)
        s = RFix.reduced(s, .undo, at: 106)
        XCTAssertEqual(s.exercises.count, 6)
        XCTAssertEqual(s.currentIndex, 5)
        XCTAssertNil(s.undo)
    }

    func testUndoAfterTheWindowDoesNotRestoreButClearsTheEntry() {
        var s = RFix.designState()
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 1)), at: 100)
        s = RFix.reduced(s, .undo, at: 106.5)
        XCTAssertEqual(s.exercises.count, 5)
        XCTAssertNil(s.undo)
        // a second undo does nothing
        let again = RFix.reduced(s, .undo, at: 107)
        XCTAssertEqual(again, s)
    }

    func testUndoRestoresADeletedSetAtItsIndexInsideTheWindow() {
        var s = RFix.designState()
        let original = s.exercises[1].sets
        s = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 1), setID: RFix.setID(s, 1, 1)), at: 10)
        s = RFix.reduced(s, .undo, at: 15)
        XCTAssertEqual(s.exercises[1].sets, original)
        XCTAssertNil(s.undo)
    }

    func testUndoAfterTheWindowDoesNotRestoreADeletedSet() {
        var s = RFix.designState()
        s = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 1), setID: RFix.setID(s, 1, 1)), at: 10)
        s = RFix.reduced(s, .undo, at: 17)
        XCTAssertEqual(s.exercises[1].sets.count, 2)
        XCTAssertNil(s.undo)
    }

    func testOnlyTheLastDestructiveEditCanBeUndone() {
        var s = RFix.designState()
        let removed = s.exercises[2]
        s = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 1), setID: RFix.setID(s, 1, 0)), at: 1)
        s = RFix.reduced(s, .removeExercise(exerciseID: removed.id), at: 2)
        s = RFix.reduced(s, .undo, at: 3)
        XCTAssertEqual(s.exercises[2], removed)
        XCTAssertEqual(s.exercises[1].sets.count, 2)   // the set deletion is gone for good
        XCTAssertNil(s.undo)
    }

    func testUndoWithoutAnEntryIsANoOp() {
        let s = RFix.designState()
        XCTAssertEqual(RFix.reduced(s, .undo), s)
    }

    func testUndoNeverCreatesDuplicatesOrALoneSupersetMember() {
        // pair A: remove one leg (the other leaves the group), undo -> no single-member group is created
        var s = RFix.designState()
        let removed = s.exercises[3]
        s = RFix.reduced(s, .removeExercise(exerciseID: removed.id), at: 1)
        s = RFix.reduced(s, .undo, at: 2)
        XCTAssertEqual(s.exercises[3].id, removed.id)
        XCTAssertNil(s.exercises[3].supersetGroup)
        XCTAssertNil(s.exercises[4].supersetGroup)
        // the entry cannot be applied twice
        var dupe = RFix.designState()
        let first = dupe.exercises[0]
        dupe.undo = UndoEntry(payload: .exercise(index: 0, exercise: first), title: "x", expiresAt: RFix.at(100))
        dupe = RFix.reduced(dupe, .undo, at: 1)
        XCTAssertEqual(dupe.exercises.count, 6)
        XCTAssertNil(dupe.undo)
    }
}

// MARK: - Rule 7: order, replace, add, rest per exercise

final class WorkoutReducerListEditTests: XCTestCase {
    func testMoveExerciseReordersAndTheCurrentExerciseKeepsItsPlace() {
        var s = RFix.designState()
        s.currentIndex = 2
        let ohpID = RFix.ex(s, 2)
        s = RFix.reduced(s, .moveExercise(from: 2, to: 0))
        XCTAssertEqual(s.exercises.map { $0.exercise.id }, ["ohp", "bench", "incline", "lateral", "pushdown", "crossover"])
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.currentExercise?.id, ohpID)

        // moving another exercise across the current one shifts the index
        s.currentIndex = 1                        // bench
        s = RFix.reduced(s, .moveExercise(from: 0, to: 4))
        XCTAssertEqual(s.exercises.map { $0.exercise.id }, ["bench", "incline", "lateral", "pushdown", "ohp", "crossover"])
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.currentExercise?.exercise.id, "bench")
    }

    func testMoveExerciseByStepsUpAndDown() {
        var s = RFix.designState()
        s.currentIndex = 1
        s = RFix.reduced(s, .moveExerciseBy(exerciseID: RFix.ex(s, 1), delta: 1))
        XCTAssertEqual(s.exercises.map { $0.exercise.id }, ["bench", "ohp", "incline", "lateral", "pushdown", "crossover"])
        XCTAssertEqual(s.currentIndex, 2)
        s = RFix.reduced(s, .moveExerciseBy(exerciseID: RFix.ex(s, 4), delta: -1))
        XCTAssertEqual(s.exercises.map { $0.exercise.id }, ["bench", "ohp", "incline", "pushdown", "lateral", "crossover"])
        XCTAssertEqual(s.currentIndex, 2)
        // bench would land between the two exercises of the superset: it goes behind them
        s = RFix.reduced(s, .moveExerciseBy(exerciseID: RFix.ex(s, 0), delta: 3))
        XCTAssertEqual(s.exercises.map { $0.exercise.id }, ["ohp", "incline", "pushdown", "lateral", "bench", "crossover"])
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, [nil, nil, "A", "A", nil, nil])
        XCTAssertEqual(s.currentExercise?.exercise.id, "incline")
    }

    func testReplaceExerciseKeepsTheEntryIDAndSupersetGroup() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 1)     // log a lateral raise set
        s.exercises[3].note = "slow"
        let oldID = RFix.ex(s, 3)
        s = RFix.reduced(s, .replaceExercise(exerciseID: oldID, with: RFix.pushup), at: 2)
        let replaced = s.exercises[3]
        XCTAssertEqual(replaced.id, oldID)
        XCTAssertEqual(replaced.supersetGroup, "A")
        XCTAssertEqual(replaced.exercise.id, "pushup")
        XCTAssertEqual(replaced.sets.count, 3)
        XCTAssertTrue(replaced.sets.allSatisfy { !$0.isDone && $0.type == .normal && $0.rir == nil && $0.reps == 12 && $0.weightKg == 0 })
        XCTAssertEqual(replaced.restSeconds, 60)
        XCTAssertEqual(replaced.note, "")
        XCTAssertNil(s.lastLogged)       // it pointed at a set of the replaced exercise
        XCTAssertEqual(s.exercises[4].supersetGroup, "A")
    }

    func testReplaceExerciseKeepsLastLoggedOfOtherExercisesAndTheTemplateLink() {
        var s = RFix.designState()
        let template = RFix.uuid(0x7E, 1)
        s.exercises[1].templateEntryID = template
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 1)
        let last = s.lastLogged
        s = RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 1), with: RFix.squat), at: 2)
        XCTAssertEqual(s.lastLogged, last)
        XCTAssertEqual(s.exercises[1].templateEntryID, template)
        XCTAssertEqual(s.exercises[1].restSeconds, 180)
    }

    func testReplaceExerciseDropsAnUndoEntryForASetOfTheReplacedExercise() {
        var s = RFix.designState()
        s = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 1), setID: RFix.setID(s, 1, 0)), at: 1)
        s = RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 1), with: RFix.squat), at: 2)
        XCTAssertNil(s.undo)
        // an undo entry for another exercise survives
        var t = RFix.designState()
        t = RFix.reduced(t, .deleteSet(exerciseID: RFix.ex(t, 2), setID: RFix.setID(t, 2, 0)), at: 1)
        t = RFix.reduced(t, .replaceExercise(exerciseID: RFix.ex(t, 1), with: RFix.squat), at: 2)
        XCTAssertNotNil(t.undo)
    }

    // MARK: Replace exercise leaves an undo when something would be lost

    func testReplacingAnExerciseWithLoggedSetsLeavesAnUndoThatSwapsTheOriginalBack() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 1)
        s.exercises[3].note = "slow"
        let original = s.exercises[3]
        s = RFix.reduced(s, .replaceExercise(exerciseID: original.id, with: RFix.pushup), at: 2)
        XCTAssertEqual(s.exercises[3].exercise.id, "pushup")
        XCTAssertEqual(s.undo?.title, "Replaced " + original.exercise.name)
        XCTAssertEqual(s.undo?.expiresAt, RFix.t0.addingTimeInterval(2 + WorkoutReducer.undoWindow))

        s = RFix.reduced(s, .undo, at: 3)
        XCTAssertEqual(s.exercises[3], original, "the logged set, its values and the note are back")
        XCTAssertTrue(s.exercises[3].sets[0].isDone)
        XCTAssertEqual(s.currentIndex, 3)
        XCTAssertNil(s.undo)
    }

    func testTheReplaceUndoFollowsTheCurrentSupersetGroup() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 1)
        XCTAssertEqual(s.exercises[3].supersetGroup, "A")
        XCTAssertEqual(s.exercises[4].supersetGroup, "A")
        s = RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 3), with: RFix.pushup), at: 2)
        // the partner leaves the group, so the replacement is released from it as well
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 4)), at: 3)
        XCTAssertNil(s.exercises[3].supersetGroup)
        s = RFix.reduced(s, .undo, at: 4)
        XCTAssertEqual(s.exercises[3].exercise.id, "lateral", "the original is back")
        XCTAssertNil(s.exercises[3].supersetGroup, "it does not rejoin a group its partner left")
        let groups = Dictionary(grouping: s.exercises.compactMap { $0.supersetGroup }, by: { $0 })
        XCTAssertTrue(groups.values.allSatisfy { $0.count > 1 }, "a group never has a single member")
    }

    func testTheReplaceUndoDoesNotThrowAwayWorkDoneOnTheReplacement() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 1)
        s = RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 3), with: RFix.pushup), at: 2)
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 3)             // a set of the replacement is logged
        let before = s.exercises
        s = RFix.reduced(s, .undo, at: 4)
        XCTAssertEqual(s.exercises, before, "the logged set of the replacement is kept")
        XCTAssertNil(s.undo, "the undo is spent")
    }

    func testTheReplaceUndoExpires() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 1)
        let replacement = RFix.ex(s, 3)
        s = RFix.reduced(s, .replaceExercise(exerciseID: replacement, with: RFix.pushup), at: 2)
        s = RFix.reduced(s, .undo, at: 2 + WorkoutReducer.undoWindow + 1)
        XCTAssertEqual(s.exercises[3].exercise.id, "pushup", "too late: the replacement stays")
        XCTAssertNil(s.undo)
    }

    func testReplacingAnUntouchedExerciseLeavesAnotherUndoAlone() {
        var s = RFix.designState()
        s = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 2), setID: RFix.setID(s, 2, 0)), at: 1)
        let pending = s.undo
        XCTAssertNotNil(pending)
        s = RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 1), with: RFix.squat), at: 2)
        XCTAssertEqual(s.undo, pending, "nothing was logged on the replaced exercise, so nothing was lost")
    }

    func testTheReplaceUndoDoesNothingWhenTheEntryIsGone() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 1)
        let id = RFix.ex(s, 3)
        s = RFix.reduced(s, .replaceExercise(exerciseID: id, with: RFix.pushup), at: 2)
        s.exercises.remove(at: 3)
        let before = s.exercises
        s = RFix.reduced(s, .undo, at: 3)
        XCTAssertEqual(s.exercises, before)
        XCTAssertNil(s.undo)
    }

    func testTheReplacePayloadSurvivesPersistence() throws {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 1)
        s = RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 3), with: RFix.pushup), at: 2)
        let data = try StrengthJSON.makeEncoder().encode(s)
        let decoded = try StrengthJSON.makeDecoder().decode(WorkoutState.self, from: data)
        XCTAssertEqual(decoded, s)
        guard case .replaced = decoded.undo?.payload else { return XCTFail("the replaced payload was not kept") }
    }

    func testAddExercisesAppendsEntriesWithDefaultSetsAndRest() {
        var s = RFix.designState()
        s.currentIndex = 2
        s = RFix.reduced(s, .addExercises([RFix.plank, RFix.squat, RFix.plank]))
        XCTAssertEqual(s.exercises.count, 9)
        XCTAssertEqual(s.currentIndex, 2)
        let plank = s.exercises[6]
        XCTAssertEqual(plank.exercise.id, "plank")
        XCTAssertEqual(plank.sets.count, 3)
        XCTAssertTrue(plank.sets.allSatisfy { !$0.isDone && $0.reps == 45 && $0.weightKg == 0 && $0.type == .normal })
        XCTAssertEqual(plank.restSeconds, 45)
        XCTAssertNil(plank.supersetGroup)
        XCTAssertNil(plank.templateEntryID)
        XCTAssertEqual(plank.note, "")
        XCTAssertEqual(s.exercises[7].sets.first?.weightKg, 60)
        XCTAssertEqual(s.exercises[7].restSeconds, 180)
        XCTAssertEqual(Set(s.exercises.map { $0.id }).count, 9)   // the same exercise twice gets two entries
    }

    func testAddExercisesToAnEmptyWorkoutSelectsTheFirst() {
        var s = WorkoutState(name: "Empty", currentIndex: 4, startedAt: RFix.t0)
        s = RFix.reduced(s, .addExercises([RFix.bench, RFix.incline]))
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.exercises.count, 2)
    }

    func testSetRestSetsSecondsAndClampsNegativeToZero() {
        var s = RFix.designState()
        s = RFix.reduced(s, .setRest(exerciseID: RFix.ex(s, 1), seconds: 105))
        XCTAssertEqual(s.exercises[1].restSeconds, 105)
        s = RFix.reduced(s, .setRest(exerciseID: RFix.ex(s, 1), seconds: -20))
        XCTAssertEqual(s.exercises[1].restSeconds, 0)
        s = RFix.reduced(s, .setRest(exerciseID: RFix.ex(s, 1), seconds: 0))
        XCTAssertEqual(s.exercises[1].restSeconds, 0)
        XCTAssertEqual(s.exercises[0].restSeconds, 150)
    }
}

// MARK: - Rule 8: supersets

final class WorkoutReducerSupersetTests: XCTestCase {
    func testJoiningTheNextExerciseUsesTheFirstUnusedLetter() {
        var s = RFix.designState()                  // letter A is taken by lateral + pushdown
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 1)))
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, [nil, "B", "B", "A", "A", nil])
    }

    func testJoiningAnExerciseThatIsNextToAGroupTakesThatGroup() {
        var s = RFix.designState()
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 2)))   // ohp joins the lateral's group
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, [nil, nil, "A", "A", "A", nil])
    }

    func testLeavingAGroupOfThreeFromTheEndKeepsTheOthers() {
        var s = RFix.designState()
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 2)))      // ohp joins lateral + pushdown
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 4)))      // pushdown leaves
        let expected: [String?] = [nil, nil, "A", "A", nil, nil]
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, expected)
    }

    func testLeavingFromTheMiddleOfAGroupKeepsEveryGroupTogether() {
        var s = RFix.designState()
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 2)))      // A: ohp, lateral, pushdown
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 3)))      // lateral leaves the middle
        // ohp and pushdown would be apart: with a member on each side nobody keeps the letter
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, [nil, nil, nil, nil, nil, nil])

        // A group of four splits into the members before and after the one that leaves
        var four = RFix.state((1...6).map { n in
            RFix.entry(n, n.isMultiple(of: 2) ? RFix.lateral : RFix.pushdown, RFix.normal(1, 10, 10), rest: 60, group: n <= 4 ? "A" : nil)
        })
        four = RFix.reduced(four, .toggleSuperset(exerciseID: RFix.ex(four, 1)))   // the second of four leaves
        XCTAssertEqual(four.exercises.map { $0.supersetGroup }, [nil, nil, "B", "B", nil, nil])
        var five = RFix.state((1...6).map { n in
            RFix.entry(n, n.isMultiple(of: 2) ? RFix.lateral : RFix.pushdown, RFix.normal(1, 10, 10), rest: 60, group: n <= 5 ? "A" : nil)
        })
        five = RFix.reduced(five, .toggleSuperset(exerciseID: RFix.ex(five, 2)))   // the middle of five leaves
        XCTAssertEqual(five.exercises.map { $0.supersetGroup }, ["A", "A", nil, "B", "B", nil])
    }

    func testLeavingAGroupOfTwoReleasesBothMembers() {
        let s = RFix.designState()
        let first = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 3)))
        XCTAssertEqual(first.exercises.map { $0.supersetGroup }, [nil, nil, nil, nil, nil, nil])
        let second = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 4)))
        XCTAssertEqual(second.exercises.map { $0.supersetGroup }, [nil, nil, nil, nil, nil, nil])
    }

    func testTheLastExerciseCannotJoinANextOne() {
        let s = RFix.designState()
        XCTAssertEqual(RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 5))), s)
    }

    func testLetterIsReusedAfterTheGroupIsDissolved() {
        var s = RFix.designState()
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 3)))     // dissolve A
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 0)))     // bench + incline
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, ["A", "A", nil, nil, nil, nil])
    }

    func testASixthSupersetGetsItsOwnLetterAndTheLettersContinueAfterZ() {
        // 40 pairs, each its own superset: the letters run A...Z, AA, AB, ... and never repeat
        var s = RFix.state((0..<80).map { n in
            RFix.entry(n + 1, n.isMultiple(of: 2) ? RFix.lateral : RFix.pushdown, RFix.normal(1, 10, 10), rest: 60)
        })
        for pair in 0..<40 { s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, pair * 2))) }
        let groups = s.exercises.compactMap { $0.supersetGroup }
        XCTAssertEqual(groups.count, 80)
        XCTAssertEqual(Set(groups).count, 40, "every pair has its own group")
        XCTAssertEqual(s.exercises[0].supersetGroup, "A")
        XCTAssertEqual(s.exercises[10].supersetGroup, "F", "the sixth superset does not merge with the fifth")
        XCTAssertEqual(s.exercises[50].supersetGroup, "Z")
        XCTAssertEqual(s.exercises[52].supersetGroup, "AA")
        XCTAssertEqual(s.exercises[54].supersetGroup, "AB")
        XCTAssertEqual(s.exercises[78].supersetGroup, "AN")
        for pair in 0..<40 { XCTAssertEqual(s.exercises[pair * 2].supersetGroup, s.exercises[pair * 2 + 1].supersetGroup) }
    }

    func testGroupNamesFollowTheSpreadsheetColumns() {
        XCTAssertEqual((24..<30).map { WorkoutReducer.groupName(at: $0) }, ["Y", "Z", "AA", "AB", "AC", "AD"])
        XCTAssertEqual(WorkoutReducer.groupName(at: 0), "A")
        XCTAssertEqual(WorkoutReducer.groupName(at: 25), "Z")
        XCTAssertEqual(WorkoutReducer.groupName(at: 26), "AA")
        XCTAssertEqual(WorkoutReducer.groupName(at: 51), "AZ")
        XCTAssertEqual(WorkoutReducer.groupName(at: 52), "BA")
        XCTAssertEqual(WorkoutReducer.groupName(at: 701), "ZZ")
        XCTAssertEqual(WorkoutReducer.groupName(at: 702), "AAA")
    }

    func testTheFirstUnusedLetterIsTaken() {
        var s = RFix.state((0..<8).map { n in
            RFix.entry(n + 1, n.isMultiple(of: 2) ? RFix.lateral : RFix.pushdown, RFix.normal(1, 10, 10), rest: 60,
                       group: n < 4 ? (n < 2 ? "A" : "C") : nil)
        })
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 4)))
        XCTAssertEqual(s.exercises[4].supersetGroup, "B", "B is free")
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 6)))
        XCTAssertEqual(s.exercises[6].supersetGroup, "D", "A, B and C are taken")
    }

    func testSupersetsCreatedWithTheToggleDriveLogging() {
        var s = RFix.state([
            RFix.entry(1, RFix.lateral, RFix.normal(2, 8, 15), rest: 60),
            RFix.entry(2, RFix.pushdown, RFix.normal(2, 30, 12), rest: 60),
        ])
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 0)))
        s = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 1)
        XCTAssertEqual(s.currentIndex, 1)
        XCTAssertNil(s.rest)
    }
}

// MARK: - Rule 9: rest timer

final class WorkoutReducerRestTests: XCTestCase {
    private func resting(endsAt: Double, total: Int) -> WorkoutState {
        var s = RFix.designState()
        s.rest = RestState(endsAt: RFix.at(endsAt), totalSeconds: total)
        return s
    }

    func testAdjustRestStartsARestWhenNoneRuns() {
        let s = RFix.reduced(RFix.designState(), .adjustRest(seconds: 15), at: 100)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(115), totalSeconds: 15))
        // and a non-positive request without a rest does nothing
        XCTAssertEqual(RFix.reduced(RFix.designState(), .adjustRest(seconds: -15), at: 100), RFix.designState())
        XCTAssertEqual(RFix.reduced(RFix.designState(), .adjustRest(seconds: 0), at: 100), RFix.designState())
    }

    func testAdjustRestMovesTheEndAndTheTotal() {
        var s = resting(endsAt: 200, total: 90)
        s = RFix.reduced(s, .adjustRest(seconds: 15), at: 150)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(215), totalSeconds: 105))
        s = RFix.reduced(s, .adjustRest(seconds: -15), at: 150)
        s = RFix.reduced(s, .adjustRest(seconds: -15), at: 150)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(185), totalSeconds: 75))
    }

    func testAdjustRestNeverEndsBeforeNowAndKeepsAtLeastFiveSeconds() {
        var s = resting(endsAt: 160, total: 20)
        s = RFix.reduced(s, .adjustRest(seconds: -15), at: 150)       // 10 s left -> ends now
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(150), totalSeconds: 5))
        s = RFix.reduced(s, .adjustRest(seconds: -15), at: 150)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(150), totalSeconds: 5))
    }

    func testAdjustRestOnAFinishedRestRestartsFromNow() {
        var s = resting(endsAt: 100, total: 60)                    // finished 50 s ago
        s = RFix.reduced(s, .adjustRest(seconds: 15), at: 150)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(165), totalSeconds: 75))
    }

    func testAdjustRestWhilePausedAdjustsTheFrozenRemainingTime() {
        var s = resting(endsAt: 250, total: 150)
        s = RFix.reduced(s, .pause, at: 130)                          // 120 s frozen
        s = RFix.reduced(s, .adjustRest(seconds: 15), at: 200)
        XCTAssertEqual(s.rest?.frozenRemaining, 135)
        XCTAssertEqual(s.rest?.totalSeconds, 165)
        XCTAssertEqual(s.rest?.endsAt, RFix.at(250))                  // untouched while frozen
        s = RFix.reduced(s, .adjustRest(seconds: -200), at: 210)
        XCTAssertEqual(s.rest?.frozenRemaining, 0)                 // never negative
        XCTAssertEqual(s.rest?.totalSeconds, 5)
        // a rest started with the plus button while paused is frozen too
        var empty = RFix.reduced(RFix.designState(), .pause, at: 5)
        empty = RFix.reduced(empty, .adjustRest(seconds: 30), at: 6)
        XCTAssertEqual(empty.rest, RestState(endsAt: RFix.at(36), totalSeconds: 30, frozenRemaining: 30))
    }

    func testSkipRestClearsTheRest() {
        var s = resting(endsAt: 200, total: 90)
        s = RFix.reduced(s, .skipRest, at: 150)
        XCTAssertNil(s.rest)
        XCTAssertEqual(s.revision, 1)
        XCTAssertEqual(RFix.reduced(s, .skipRest), s)                 // nothing to skip
    }

    func testRestSettingFlagsAreStored() {
        var s = RFix.designState()
        s = RFix.reduced(s, .setAutoStartRest(false))
        XCTAssertFalse(s.settings.autoStartRest)
        XCTAssertTrue(s.settings.alertWhenRestEnds)
        s = RFix.reduced(s, .setAlertWhenRestEnds(false))
        XCTAssertFalse(s.settings.alertWhenRestEnds)
        s = RFix.reduced(s, .setAutoStartRest(true))
        XCTAssertTrue(s.settings.autoStartRest)
        XCTAssertEqual(s.revision, 3)
    }
}

// MARK: - Rule 10: pause and resume

final class WorkoutReducerPauseTests: XCTestCase {
    func testPauseFreezesTheRunningRest() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 100)               // 150 s rest, ends 250
        s = RFix.reduced(s, .pause, at: 130)
        XCTAssertEqual(s.pausedAt, RFix.at(130))
        XCTAssertEqual(s.rest?.frozenRemaining, 120)
        XCTAssertEqual(s.restRemaining(now: RFix.at(5_000)), 120)
        XCTAssertTrue(s.isPaused)
    }

    func testResumeAddsThePauseToTheTotalAndThawsTheRest() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 100)
        s = RFix.reduced(s, .pause, at: 130)
        s = RFix.reduced(s, .resume, at: 330)
        XCTAssertNil(s.pausedAt)
        XCTAssertEqual(s.pausedTotal, 200)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(450), totalSeconds: 150))
        XCTAssertEqual(s.restRemaining(now: RFix.at(400)), 50)
        XCTAssertFalse(s.isPaused)
    }

    func testElapsedTimeExcludesPauses() {
        var s = RFix.designState()
        s = RFix.reduced(s, .pause, at: 100)
        XCTAssertEqual(s.elapsedSeconds(now: RFix.at(200)), 100)
        s = RFix.reduced(s, .resume, at: 300)
        XCTAssertEqual(s.elapsedSeconds(now: RFix.at(400)), 200)
        s = RFix.reduced(s, .pause, at: 400)
        s = RFix.reduced(s, .resume, at: 450)
        XCTAssertEqual(s.pausedTotal, 250)
        XCTAssertEqual(s.elapsedSeconds(now: RFix.at(500)), 250)
    }

    func testPauseWithoutRestOnlySetsThePauseTime() {
        let s = RFix.reduced(RFix.designState(), .pause, at: 50)
        XCTAssertEqual(s.pausedAt, RFix.at(50))
        XCTAssertNil(s.rest)
        XCTAssertNil(RFix.reduced(s, .resume, at: 60).rest)
    }

    func testPausingTwiceOrResumingWhileRunningIsANoOp() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 100)
        XCTAssertEqual(RFix.reduced(s, .resume, at: 120), s)
        let paused = RFix.reduced(s, .pause, at: 130)
        XCTAssertEqual(RFix.reduced(paused, .pause, at: 140), paused)
    }

    func testResumeOfAFinishedFrozenRestEndsRightNow() {
        var s = RFix.designState()
        s.rest = RestState(endsAt: RFix.at(100), totalSeconds: 60)    // already over
        s = RFix.reduced(s, .pause, at: 150)
        XCTAssertEqual(s.rest?.frozenRemaining, 0)
        s = RFix.reduced(s, .resume, at: 160)
        XCTAssertEqual(s.rest?.endsAt, RFix.at(160))
        XCTAssertNil(s.rest?.frozenRemaining)
        XCTAssertEqual(s.restRemaining(now: RFix.at(160)), 0)
    }

    func testResumeNeverMovesTheClockBackwards() {
        var s = RFix.designState()
        s = RFix.reduced(s, .pause, at: 100)
        s = RFix.reduced(s, .resume, at: 90)            // clock skew
        XCTAssertEqual(s.pausedTotal, 0)
        XCTAssertNil(s.pausedAt)
    }

    func testPauseAndResumeKeepTheFrozenInvariant() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 10)
        s = RFix.reduced(s, .pause, at: 20)
        XCTAssertNotNil(s.rest?.frozenRemaining)
        s = RFix.reduced(s, RFix.toggle(s, 0, 3), at: 30)               // new rest while paused
        XCTAssertNotNil(s.rest?.frozenRemaining)
        s = RFix.reduced(s, .resume, at: 40)
        XCTAssertNil(s.rest?.frozenRemaining)
        XCTAssertEqual(s.rest?.endsAt, RFix.at(190))
    }
}

// MARK: - Rule 11: navigation, flags, heart rate

final class WorkoutReducerMiscTests: XCTestCase {
    func testGoToNextAndPreviousClamp() {
        var s = RFix.designState()
        s = RFix.reduced(s, .goTo(index: 3))
        XCTAssertEqual(s.currentIndex, 3)
        s = RFix.reduced(s, .goTo(index: 99))
        XCTAssertEqual(s.currentIndex, 5)
        s = RFix.reduced(s, .nextExercise)
        XCTAssertEqual(s.currentIndex, 5)
        s = RFix.reduced(s, .goTo(index: -2))
        XCTAssertEqual(s.currentIndex, 0)
        s = RFix.reduced(s, .previousExercise)
        XCTAssertEqual(s.currentIndex, 0)
        s = RFix.reduced(s, .nextExercise)
        s = RFix.reduced(s, .nextExercise)
        XCTAssertEqual(s.currentIndex, 2)
        s = RFix.reduced(s, .previousExercise)
        XCTAssertEqual(s.currentIndex, 1)
    }

    func testNavigationDoesNotTouchTheRest() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 1)
        let rest = s.rest
        s = RFix.reduced(s, .nextExercise, at: 2)
        XCTAssertEqual(s.rest, rest)
    }

    func testFlagsAndNameAreSet() {
        var s = RFix.designState()
        s = RFix.reduced(s, .setUsedWatch(true))
        XCTAssertTrue(s.usedWatch)
        s = RFix.reduced(s, .setUsedWatch(false))
        XCTAssertFalse(s.usedWatch)
        s = RFix.reduced(s, .rename("Push day"))
        XCTAssertEqual(s.name, "Push day")
        XCTAssertEqual(s.revision, 3)
    }

    func testUpdateHeartRateStoresSamplesWithoutBumpingTheRevision() {
        var s = RFix.designState()
        s.revision = 7
        s = RFix.reduced(s, .updateHeartRate(120), at: 1)
        XCTAssertEqual(s.heartRate, 120)
        XCTAssertEqual(s.heartRateSum, 120)
        XCTAssertEqual(s.heartRateCount, 1)
        s = RFix.reduced(s, .updateHeartRate(130), at: 2)
        XCTAssertEqual(s.heartRate, 130)
        XCTAssertEqual(s.heartRateSum, 250)
        XCTAssertEqual(s.heartRateCount, 2)
        XCTAssertEqual(s.averageHeartRate, 125)
        XCTAssertEqual(s.revision, 7)
        // the next real change bumps by exactly one
        s = RFix.reduced(s, .rename("x"), at: 3)
        XCTAssertEqual(s.revision, 8)
    }

    func testHeartRateRangeAndNilHandling() {
        var s = RFix.designState()
        s = RFix.reduced(s, .updateHeartRate(30))
        s = RFix.reduced(s, .updateHeartRate(240))
        XCTAssertEqual(s.heartRateCount, 2)
        XCTAssertEqual(s.heartRateSum, 270)
        s = RFix.reduced(s, .updateHeartRate(29))       // shown, but not averaged
        XCTAssertEqual(s.heartRate, 29)
        s = RFix.reduced(s, .updateHeartRate(241))
        XCTAssertEqual(s.heartRate, 241)
        s = RFix.reduced(s, .updateHeartRate(0))
        XCTAssertEqual(s.heartRateCount, 2)
        XCTAssertEqual(s.heartRateSum, 270)
        s = RFix.reduced(s, .updateHeartRate(nil))      // sensor lost
        XCTAssertNil(s.heartRate)
        XCTAssertEqual(s.heartRateCount, 2)
        XCTAssertEqual(s.revision, 0)
    }

    func testHeartRateChangesNothingElse() {
        var s = RFix.designState()
        s = RFix.reduced(s, RFix.toggle(s, 0, 2), at: 1)
        var expected = s
        expected.heartRate = 140
        expected.heartRateSum = 140
        expected.heartRateCount = 1
        XCTAssertEqual(RFix.reduced(s, .updateHeartRate(140), at: 50), expected)
    }
}
