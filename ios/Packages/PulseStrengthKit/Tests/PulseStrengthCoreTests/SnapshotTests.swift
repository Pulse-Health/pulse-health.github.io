import XCTest
@testable import PulseStrengthCore

final class SnapshotBuilderTests: XCTestCase {
    private func snapshot(_ state: WorkoutState, at seconds: Double = 0) -> WorkoutSnapshot {
        SnapshotBuilder.make(from: state, now: PresFix.at(seconds))
    }

    // MARK: Phases

    func testLoggingPhaseOfAFreshWorkout() throws {
        let state = PresFix.freshUpperA()
        let snap = snapshot(state, at: 5)
        XCTAssertEqual(snap.phase, .logging)
        XCTAssertEqual(snap.workoutID, state.id)
        XCTAssertEqual(snap.workoutName, "Upper A · Push")
        XCTAssertEqual(snap.revision, 0)
        XCTAssertEqual(snap.exerciseName, "Barbell bench press")
        XCTAssertEqual(snap.exerciseIndex, 0)
        XCTAssertEqual(snap.exerciseCount, 6)
        XCTAssertEqual(snap.targetExerciseID, state.exercises[0].id)
        XCTAssertEqual(snap.targetSetID, state.exercises[0].sets[0].id)
        XCTAssertEqual(snap.setLabel, "Warm-up · Set 1 of 5")
        XCTAssertEqual(snap.tracking, .weightReps)
        XCTAssertEqual(snap.weightText, "50")
        XCTAssertEqual(snap.repsText, "8")
        XCTAssertEqual(snap.repsUnit, "reps")
        XCTAssertTrue(snap.showsWeight)
        XCTAssertEqual(snap.nextSetText, "Warm-up · 50 kg × 8")
        XCTAssertNil(snap.restStartedAt)
        XCTAssertNil(snap.restEndsAt)
        XCTAssertEqual(snap.restTotalSeconds, 0)
        XCTAssertNil(snap.restFrozenRemaining)
        XCTAssertNil(snap.heartRate)
        XCTAssertEqual(snap.volumeText, "0")
        XCTAssertEqual(snap.loggedSets, 0)
        XCTAssertEqual(snap.totalSets, 20)
        XCTAssertEqual(snap.nextExerciseName, "Incline dumbbell press")
        XCTAssertFalse(snap.isPaused)
        XCTAssertEqual(snap.elapsedWhenPaused, 0)
        XCTAssertEqual(snap.activeStart, PresFix.t0)
    }

    func testRestingPhaseOfTheOpeningState() throws {
        let state = PresFix.goldenState()
        let snap = snapshot(state, at: 1458)
        XCTAssertEqual(snap.phase, .resting)
        XCTAssertEqual(snap.revision, state.revision)
        // The target is the 4th set of the bench: "Set 4 of 5".
        XCTAssertEqual(snap.targetExerciseID, state.exercises[0].id)
        XCTAssertEqual(snap.targetSetID, state.exercises[0].sets[3].id)
        XCTAssertEqual(snap.setLabel, "Set 4 of 5")
        XCTAssertEqual(snap.weightText, "82.5")
        XCTAssertEqual(snap.repsText, "6")
        XCTAssertEqual(snap.nextSetText, "Set 4 · 82.5 kg × 6")
        XCTAssertEqual(snap.restStartedAt, PresFix.at(1403))
        XCTAssertEqual(snap.restEndsAt, PresFix.at(1553))
        XCTAssertEqual(snap.restTotalSeconds, 150)
        XCTAssertNil(snap.restFrozenRemaining)
        XCTAssertEqual(snap.volumeText, "495")
        XCTAssertEqual(snap.loggedSets, 3)
        XCTAssertEqual(snap.totalSets, 20)
        XCTAssertEqual(snap.exerciseName, "Barbell bench press")
        XCTAssertEqual(snap.nextExerciseName, "Incline dumbbell press")
    }

    func testRestOverPhaseOnceTheCountdownReachedZero() {
        let state = PresFix.goldenState()
        XCTAssertEqual(snapshot(state, at: 1552).phase, .resting)
        XCTAssertEqual(snapshot(state, at: 1552.5).phase, .resting)
        XCTAssertEqual(snapshot(state, at: 1553).phase, .restOver)
        XCTAssertEqual(snapshot(state, at: 4000).phase, .restOver)
        // The rest dates stay available for the "Go" state.
        let over = snapshot(state, at: 4000)
        XCTAssertEqual(over.restEndsAt, PresFix.at(1553))
        XCTAssertEqual(over.setLabel, "Set 4 of 5")
    }

    func testRestingBecomesLoggingAfterSkipRest() {
        let state = PresFix.reduced(PresFix.goldenState(), .skipRest, at: 1459)
        let snap = snapshot(state, at: 1460)
        XCTAssertEqual(snap.phase, .logging)
        XCTAssertNil(snap.restEndsAt)
        XCTAssertNil(snap.restStartedAt)
        XCTAssertEqual(snap.restTotalSeconds, 0)
    }

    func testCompletePhase() {
        let state = PresFix.loggedEverything(PresFix.freshUpperA())
        let snap = snapshot(state, at: 600)
        XCTAssertEqual(snap.phase, .complete)
        XCTAssertNil(snap.targetExerciseID)
        XCTAssertNil(snap.targetSetID)
        XCTAssertEqual(snap.setLabel, "All sets logged")
        XCTAssertEqual(snap.nextSetText, "All sets logged")
        XCTAssertNil(snap.nextExerciseName)
        XCTAssertEqual(snap.loggedSets, 20)
        XCTAssertEqual(snap.totalSets, 20)
        XCTAssertFalse(snap.exerciseName.isEmpty)
    }

    func testCompleteWinsOverARunningRest() {
        var state = PresFix.loggedEverything(PresFix.freshUpperA(), start: 0)
        XCTAssertNotNil(state.rest)
        state.rest = RestState(endsAt: PresFix.at(1000), totalSeconds: 60)
        let snap = snapshot(state, at: 10)
        XCTAssertEqual(snap.phase, .complete)
        XCTAssertEqual(snap.restEndsAt, PresFix.at(1000))
    }

    func testEmptyWorkoutIsCompleteWithoutTargets() {
        let state = WorkoutFactory.makeEmpty(name: "Workout", now: PresFix.t0)
        let snap = snapshot(state, at: 30)
        XCTAssertEqual(snap.phase, .complete)
        XCTAssertNil(snap.targetExerciseID)
        XCTAssertNil(snap.targetSetID)
        XCTAssertEqual(snap.exerciseName, "")
        XCTAssertEqual(snap.exerciseCount, 0)
        XCTAssertEqual(snap.totalSets, 0)
        XCTAssertNil(snap.nextExerciseName)
    }

    // MARK: Set label and next set text

    func testSetLabelCountsPositionAmongAllSetsOfTheExercise() {
        var state = PresFix.freshUpperA()
        let expected = ["Warm-up · Set 1 of 5", "Warm-up · Set 2 of 5", "Set 3 of 5", "Set 4 of 5", "Set 5 of 5"]
        for label in expected {
            XCTAssertEqual(snapshot(state).setLabel, label)
            state = PresFix.reduced(state, .logNextSet, at: 1)
        }
        // Then the incline press starts.
        XCTAssertEqual(snapshot(state).setLabel, "Set 1 of 3")
    }

    func testSetLabelForDropAndFailureSets() {
        let sets: [PresFix.SetSpec] = [(.drop, 60, 8), (.failure, 70, 4)]
        var state = PresFix.single(PresFix.lib("bench"), sets)
        XCTAssertEqual(snapshot(state).setLabel, "Set 1 of 2")
        XCTAssertEqual(snapshot(state).nextSetText, "Set 1 · 60 kg × 8")
        state = PresFix.marking(state, exercise: 0, done: [0])
        XCTAssertEqual(snapshot(state).setLabel, "Set 2 of 2")
    }

    func testSetLabelCountsSetsAddedDuringTheWorkout() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80, 5))
        state = PresFix.reduced(state, .addSet(exerciseID: state.exercises[0].id))
        state = PresFix.marking(state, exercise: 0, done: [0, 1])
        XCTAssertEqual(snapshot(state).setLabel, "Set 3 of 3")
    }

    func testNextSetTextOfRepsOnlyAndDurationExercises() {
        let pushup = PresFix.single(PresFix.lib("pushup"), [(.normal, 0, 12), (.normal, 0, 10)])
        var snap = snapshot(pushup)
        XCTAssertEqual(snap.nextSetText, "Set 1 · 12 reps")
        XCTAssertEqual(snap.weightText, "BW")
        XCTAssertEqual(snap.repsText, "12")
        XCTAssertEqual(snap.repsUnit, "reps")
        XCTAssertFalse(snap.showsWeight)
        XCTAssertEqual(snap.tracking, .repsOnly)

        let plank = PresFix.single(PresFix.lib("plank"), [(.normal, 0, 45)])
        snap = snapshot(plank)
        XCTAssertEqual(snap.nextSetText, "Set 1 · 45 s")
        XCTAssertEqual(snap.weightText, "–")
        XCTAssertEqual(snap.repsText, "45")
        XCTAssertEqual(snap.repsUnit, "sec")
        XCTAssertFalse(snap.showsWeight)
        XCTAssertEqual(snap.tracking, .duration)
    }

    func testWeightTextHasNoTrailingZeros() {
        let state = PresFix.single(PresFix.lib("bench"), [(.normal, 82.5, 6), (.normal, 80, 6), (.normal, 80.25, 6)])
        XCTAssertEqual(snapshot(state).weightText, "82.5")
        XCTAssertEqual(snapshot(PresFix.marking(state, exercise: 0, done: [0])).weightText, "80")
        XCTAssertEqual(snapshot(PresFix.marking(state, exercise: 0, done: [0, 1])).weightText, "80.25")
    }

    func testTargetFollowsNudgesOfTheNextSet() {
        var state = PresFix.goldenState()
        state = PresFix.reduced(state, .nudgeNextSet(weightSteps: 1, repsSteps: -1), at: 1460)
        let snap = snapshot(state, at: 1461)
        XCTAssertEqual(snap.weightText, "85")
        XCTAssertEqual(snap.repsText, "5")
        XCTAssertEqual(snap.nextSetText, "Set 4 · 85 kg × 5")
    }

    // MARK: Target and next exercise

    func testTargetMovesToTheNextExerciseWhenTheCurrentOneIsDone() {
        var state = PresFix.freshUpperA()
        for _ in 0..<5 { state = PresFix.reduced(state, .logNextSet, at: 1) }
        XCTAssertEqual(state.currentIndex, 0)   // not a superset: the current exercise stays
        let snap = snapshot(state, at: 2)
        XCTAssertEqual(snap.targetExerciseID, state.exercises[1].id)
        XCTAssertEqual(snap.exerciseName, "Incline dumbbell press")
        XCTAssertEqual(snap.exerciseIndex, 1)
        XCTAssertEqual(snap.setLabel, "Set 1 of 3")
        XCTAssertEqual(snap.nextSetText, "Set 1 · 28 kg × 10")
        XCTAssertEqual(snap.nextExerciseName, "Overhead press")
    }

    func testTargetStartsAtTheCurrentExercise() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .goTo(index: 2))
        let snap = snapshot(state)
        XCTAssertEqual(snap.exerciseName, "Overhead press")
        XCTAssertEqual(snap.exerciseIndex, 2)
        XCTAssertEqual(snap.targetExerciseID, state.exercises[2].id)
        XCTAssertEqual(snap.setLabel, "Set 1 of 3")
        XCTAssertEqual(snap.nextExerciseName, "Dumbbell lateral raise")
    }

    func testSupersetAlternatesTheTarget() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .goTo(index: 3))
        var snap = snapshot(state)
        XCTAssertEqual(snap.exerciseName, "Dumbbell lateral raise")
        XCTAssertEqual(snap.nextExerciseName, "Triceps pushdown")
        state = PresFix.reduced(state, .logNextSet, at: 10)
        snap = snapshot(state, at: 11)
        XCTAssertEqual(snap.exerciseName, "Triceps pushdown")
        XCTAssertEqual(snap.exerciseIndex, 4)
        XCTAssertEqual(snap.phase, .logging)   // no rest between the members of a superset
        XCTAssertEqual(snap.nextExerciseName, "Cable crossover")
        state = PresFix.reduced(state, .logNextSet, at: 20)
        snap = snapshot(state, at: 21)
        XCTAssertEqual(snap.exerciseName, "Dumbbell lateral raise")
        XCTAssertEqual(snap.setLabel, "Set 2 of 3")
        XCTAssertEqual(snap.phase, .resting)
        XCTAssertEqual(snap.restTotalSeconds, 60)
    }

    func testNextExerciseNameSkipsFinishedExercisesAndHasNoWrapAround() {
        var state = PresFix.freshUpperA()
        // Finish the overhead press and go there: the next exercise with pending sets is the lateral raise.
        state = PresFix.marking(state, exercise: 2, done: [0, 1, 2])
        state = PresFix.marking(state, exercise: 3, done: [0, 1, 2])
        state = PresFix.reduced(state, .goTo(index: 1))
        XCTAssertEqual(snapshot(state).exerciseName, "Incline dumbbell press")
        XCTAssertEqual(snapshot(state).nextExerciseName, "Triceps pushdown")
        // On the last exercise nothing follows, even though earlier exercises are pending.
        state = PresFix.reduced(state, .goTo(index: 5))
        XCTAssertEqual(snapshot(state).exerciseName, "Cable crossover")
        XCTAssertNil(snapshot(state).nextExerciseName)
    }

    func testNextExerciseNameIsNilWhenOnlyTheShownExerciseIsPending() {
        var state = PresFix.freshUpperA()
        for k in 1..<6 { state = PresFix.marking(state, exercise: k, done: Array(0..<state.exercises[k].sets.count)) }
        XCTAssertNil(snapshot(state).nextExerciseName)
        XCTAssertEqual(snapshot(state).exerciseName, "Barbell bench press")
    }

    // MARK: Time and pause

    func testActiveStartMovesWithPausedTime() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .pause, at: 100)
        state = PresFix.reduced(state, .resume, at: 160)
        let snap = snapshot(state, at: 200)
        XCTAssertEqual(snap.activeStart, PresFix.at(60))
        XCTAssertFalse(snap.isPaused)
        XCTAssertEqual(snap.elapsedWhenPaused, 0)
    }

    func testPausedSnapshotFreezesTheClockAndTheRest() {
        var state = PresFix.goldenState()                        // rest ends at t0 + 1553
        state = PresFix.reduced(state, .pause, at: 1423)         // 130 s of rest left
        for seconds in [1424.0, 1500, 9000] {
            let snap = snapshot(state, at: seconds)
            XCTAssertTrue(snap.isPaused)
            XCTAssertEqual(snap.elapsedWhenPaused, 1423)
            XCTAssertEqual(snap.restFrozenRemaining, 130)
            XCTAssertEqual(snap.phase, .resting, "at \(seconds)")
            XCTAssertEqual(snap.restTotalSeconds, 150)
        }
        state = PresFix.reduced(state, .resume, at: 1523)
        let resumed = snapshot(state, at: 1524)
        XCTAssertFalse(resumed.isPaused)
        XCTAssertNil(resumed.restFrozenRemaining)
        XCTAssertEqual(resumed.restEndsAt, PresFix.at(1653))
        XCTAssertEqual(resumed.restStartedAt, PresFix.at(1503))
        XCTAssertEqual(resumed.activeStart, PresFix.at(100))
    }

    func testPausedWithoutRestHasNoFrozenRemaining() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .pause, at: 77.9)
        let snap = snapshot(state, at: 500)
        XCTAssertTrue(snap.isPaused)
        XCTAssertEqual(snap.elapsedWhenPaused, 77)
        XCTAssertNil(snap.restFrozenRemaining)
        XCTAssertEqual(snap.phase, .logging)
    }

    func testPausedWithAnEmptyFrozenRestIsRestOver() {
        var state = PresFix.goldenState()
        state = PresFix.reduced(state, .pause, at: 1560)   // the rest ended at 1553 while the clock still ran
        let snap = snapshot(state, at: 1600)
        XCTAssertEqual(snap.phase, .restOver)
        XCTAssertEqual(snap.restFrozenRemaining, 0)
    }

    func testFrozenRestSecondsRoundUp() {
        var state = PresFix.goldenState()
        state = PresFix.reduced(state, .pause, at: 1500.5)   // 52.5 s left
        XCTAssertEqual(snapshot(state, at: 1600).restFrozenRemaining, 53)
    }

    // MARK: Pass-through values

    func testHeartRateAndVolumeAreCopied() {
        var state = PresFix.loggedEverything(PresFix.freshUpperA())
        state = PresFix.reduced(state, .updateHeartRate(131), at: 700)
        let snap = snapshot(state, at: 701)
        XCTAssertEqual(snap.heartRate, 131)
        // Working sets: bench 495 + 495 + 510, incline 840, ohp 1080, lateral 360, pushdown 1080, crossover 540.
        XCTAssertEqual(snap.volumeText, "5,400")
        XCTAssertEqual(snap.revision, state.revision)
    }

    func testRevisionTracksTheState() {
        var state = PresFix.freshUpperA()
        XCTAssertEqual(snapshot(state).revision, 0)
        state = PresFix.reduced(state, .logNextSet, at: 1)
        XCTAssertEqual(snapshot(state).revision, 1)
        state = PresFix.reduced(state, .updateHeartRate(100), at: 2)
        XCTAssertEqual(snapshot(state).revision, 1)   // heart-rate samples do not bump the revision
    }

    // MARK: Stability (Live Activity de-duplication)

    func testSnapshotIsStableWhileNothingChanges() {
        let logging = PresFix.freshUpperA()
        XCTAssertEqual(snapshot(logging, at: 10), snapshot(logging, at: 500))
        let resting = PresFix.goldenState()
        XCTAssertEqual(snapshot(resting, at: 1460), snapshot(resting, at: 1500))
        var paused = PresFix.goldenState()
        paused = PresFix.reduced(paused, .pause, at: 1423)
        XCTAssertEqual(snapshot(paused, at: 1430), snapshot(paused, at: 3000))
    }

    // MARK: Size and Codable

    private func jsonSize(_ snap: WorkoutSnapshot, iso: Bool) throws -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if iso { encoder.dateEncodingStrategy = .iso8601 }
        return try encoder.encode(snap).count
    }

    /// `snap` without the live context (set dots, moments, superset, plates, coach tip, finish card): the flat part of the content.
    /// The live context has its own budget (`LiveMomentsTests.testTheLargestRealisticSnapshotStaysUnderTheSizeBudget`).
    private func flat(_ snap: WorkoutSnapshot) -> WorkoutSnapshot {
        var copy = snap
        copy.exerciseDoneSets = nil
        copy.exerciseSetCount = nil
        copy.moment = nil
        copy.superset = nil
        copy.plates = nil
        copy.coachTip = nil
        copy.finish = nil
        return copy
    }

    func testLiveActivitySizeSanity() throws {
        var states: [WorkoutState] = [
            PresFix.freshUpperA(),
            PresFix.goldenState(),
            PresFix.reduced(PresFix.goldenState(), .pause, at: 1423),
            PresFix.loggedEverything(PresFix.freshUpperA()),
        ]
        // Worst case: long names everywhere, a heart rate and a long weight text.
        var long = PresFix.single(
            { var e = PresFix.lib("incline"); e.name = String(repeating: "Incline dumbbell press ", count: 3); return e }(),
            [(.warmup, 1234.56, 999)]
        )
        long.name = String(repeating: "Upper A · Push ", count: 4)
        long.heartRate = 187
        long.rest = RestState(endsAt: PresFix.at(100), totalSeconds: 600)
        states.append(long)
        for (index, state) in states.enumerated() {
            let snap = flat(snapshot(state, at: 1458))
            XCTAssertLessThan(try jsonSize(snap, iso: false), 1500, "state \(index)")
            XCTAssertLessThan(try jsonSize(snap, iso: true), 1500, "state \(index) iso")
        }
        XCTAssertLessThan(try jsonSize(flat(snapshot(PresFix.goldenState(), at: 1458)), iso: true), 1000)
        // With the live context the same states stay far below the 4 KB limit of a Live Activity.
        for (index, state) in states.enumerated() {
            XCTAssertLessThan(try jsonSize(snapshot(state, at: 1458), iso: true), 2000, "state \(index) with live context")
        }
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let snap = snapshot(PresFix.goldenState(), at: 1458)
        let data = try JSONEncoder().encode(snap)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSnapshot.self, from: data), snap)
    }
}

// MARK: - Fuzz: snapshot invariants

final class SnapshotFuzzTests: XCTestCase {
    func testInvariantsHoldUnderRandomPlay() throws {
        for seed in 1...12 {
            var rng = PresLCG(seed: UInt64(seed) &+ 900)
            var state = seed % 4 == 0
                ? WorkoutFactory.makeEmpty(name: "Fuzz", now: PresFix.t0)
                : WorkoutFactory.makeWorkout(from: PresFix.upperA(), now: PresFix.t0)
            var clock = 0.0
            for step in 0..<150 {
                clock += Double(rng.below(30)) / 2
                let exercise = state.exercises.isEmpty ? nil : state.exercises[rng.below(state.exercises.count)]
                let set = exercise.flatMap { $0.sets.isEmpty ? nil : $0.sets[rng.below($0.sets.count)] }
                let action: WorkoutAction
                switch rng.below(11) {
                case 0, 1, 2: action = .logNextSet
                case 3: action = exercise.flatMap { e in set.map { .toggleSet(exerciseID: e.id, setID: $0.id) } } ?? .skipRest
                case 4: action = .pause
                case 5: action = .resume
                case 6: action = .adjustRest(seconds: rng.below(2) == 0 ? 15 : -15)
                case 7: action = .goTo(index: rng.below(6))
                case 8: action = .nudgeNextSet(weightSteps: rng.below(5) - 2, repsSteps: rng.below(5) - 2)
                case 9: action = .skipRest
                default: action = .addExercises([PresFix.lib(["pushup", "plank", "squat"][rng.below(3)])])
                }
                WorkoutReducer.reduce(&state, action, now: PresFix.at(clock))

                let now = PresFix.at(clock + Double(rng.below(300)) / 2)
                let snap = SnapshotBuilder.make(from: state, now: now)
                let context = "seed \(seed) step \(step) \(action)"
                let target = WorkoutTargets.nextPending(in: state)

                XCTAssertEqual(snap.phase == .complete, target == nil, context)
                XCTAssertEqual(snap.targetSetID == nil, target == nil, context)
                XCTAssertEqual(snap.targetExerciseID == nil, target == nil, context)
                XCTAssertEqual(snap.workoutID, state.id, context)
                XCTAssertEqual(snap.revision, state.revision, context)
                XCTAssertEqual(snap.exerciseCount, state.exercises.count, context)
                XCTAssertEqual(snap.isPaused, state.isPaused, context)
                XCTAssertEqual(snap.restFrozenRemaining != nil, state.isPaused && state.rest != nil, context)
                XCTAssertEqual(snap.restEndsAt != nil, state.rest != nil, context)
                XCTAssertTrue(snap.restTotalSeconds >= 0, context)
                if snap.phase == .resting || snap.phase == .restOver {
                    XCTAssertNotNil(snap.restEndsAt, context)
                }
                if let target {
                    let entry = state.exercises[target.exerciseIndex]
                    XCTAssertEqual(snap.targetExerciseID, entry.id, context)
                    XCTAssertEqual(snap.targetSetID, entry.sets[target.setIndex].id, context)
                    XCTAssertEqual(snap.exerciseName, entry.exercise.name, context)
                    XCTAssertEqual(snap.exerciseIndex, target.exerciseIndex, context)
                    XCTAssertTrue(snap.setLabel.hasSuffix("of \(entry.sets.count)"), context)
                    XCTAssertEqual(snap.showsWeight, entry.exercise.tracksWeight, context)
                }
                let totals = PresFix.present(state, at: clock).totals
                XCTAssertEqual(snap.loggedSets, totals.loggedSets, context)
                XCTAssertEqual(snap.totalSets, totals.totalSets, context)
                XCTAssertLessThan(try JSONEncoder().encode(snap).count, 1500, context)
            }
        }
    }
}
