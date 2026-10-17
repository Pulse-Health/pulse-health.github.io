import XCTest
@testable import PulseStrengthCore

final class SummaryBuilderTests: XCTestCase {
    /// A finished session of the design's workout:
    /// bench W 50x8, W 70x5, 82.5x6 (RIR 3), 82.5x6 (RIR 2), 85x6 (RIR 1) = a personal record (102 > 99);
    /// incline 28x10 (RIR 4) and 28x10 (third set pending); lateral 8x15 and pushdown 30x12 (one set each, superset).
    /// Heart rate samples 120, 130, 140 and one out-of-range sample (20).
    private func session() -> WorkoutState {
        var state = PresFix.freshUpperA()
        var clock = 100.0
        func apply(_ action: WorkoutAction) {
            WorkoutReducer.reduce(&state, action, now: PresFix.at(clock))
            clock += 10
        }
        // Bench: five sets in order, with RIR on the working sets.
        for _ in 0..<2 { apply(.logNextSet) }
        apply(.logNextSet); apply(.toggleLastSetRIR(3))
        apply(.logNextSet); apply(.toggleLastSetRIR(2))
        apply(.logNextSet); apply(.toggleLastSetRIR(1))
        // Incline: two of three sets.
        apply(.logNextSet); apply(.toggleLastSetRIR(4))
        apply(.logNextSet)
        // Skip overhead press; superset lateral + pushdown, one round.
        apply(.goTo(index: 3))
        apply(.logNextSet)
        apply(.logNextSet)
        for bpm in [120, 130, 140, 20] { apply(.updateHeartRate(bpm)) }
        return state
    }

    private func build(_ state: WorkoutState, finishedAt seconds: Double = 3725) -> CompletedWorkout {
        SummaryBuilder.build(from: state, finishedAt: PresFix.at(seconds))
    }

    // MARK: Totals

    func testIdentityAndTiming() {
        let state = session()
        let summary = build(state)
        XCTAssertEqual(summary.id, state.id)
        XCTAssertEqual(summary.name, "Upper A · Push")
        XCTAssertEqual(summary.templateID, PresFix.upperA().id)
        XCTAssertEqual(summary.startedAt, PresFix.t0)
        XCTAssertEqual(summary.finishedAt, PresFix.at(3725))
        XCTAssertEqual(summary.durationSeconds, 3725)
    }

    func testVolumeAndSetCounts() {
        let summary = build(session())
        // 82.5x6 + 82.5x6 + 85x6 + 28x10 + 28x10 + 8x15 + 30x12 = 495 + 495 + 510 + 280 + 280 + 120 + 360
        XCTAssertEqual(summary.volumeKg, 2540, accuracy: 0.0001)
        XCTAssertEqual(summary.loggedSets, 9)   // warm-ups included
    }

    func testVolumeMatchesThePresenterTotals() {
        let state = session()
        XCTAssertEqual(build(state).volumeKg, PresFix.present(state, at: 3725).totals.volumeKg, accuracy: 0.0001)
        XCTAssertEqual(build(state).loggedSets, PresFix.present(state, at: 3725).totals.loggedSets)
    }

    func testOnlyLoggedSetsAreKeptAndExercisesWithoutLoggedSetsAreLeftOut() {
        let summary = build(session())
        XCTAssertEqual(summary.exercises.map { $0.exerciseID }, ["bench", "incline", "lateral", "pushdown"])
        XCTAssertEqual(summary.exercises.map { $0.sets.count }, [5, 2, 1, 1])
        let bench = summary.exercises[0]
        XCTAssertEqual(bench.sets.map { $0.type }, [.warmup, .warmup, .normal, .normal, .normal])
        XCTAssertEqual(bench.sets.map { $0.weightKg }, [50, 70, 82.5, 82.5, 85])
        XCTAssertEqual(bench.sets.map { $0.reps }, [8, 5, 6, 6, 6])
        XCTAssertEqual(bench.sets.map { $0.rir }, [nil, nil, 3, 2, 1])
    }

    func testCompletedExerciseFieldsComeFromTheWorkoutEntry() {
        let state = session()
        let summary = build(state)
        let bench = summary.exercises[0]
        XCTAssertEqual(bench.id, state.exercises[0].id)
        XCTAssertEqual(bench.name, "Barbell bench press")
        XCTAssertEqual(bench.muscle, .chest)
        XCTAssertEqual(bench.mediaKey, "bench")
        XCTAssertEqual(bench.tracking, .weightReps)
    }

    func testNoPendingSetIsKept() {
        // The third incline set was never logged.
        let incline = build(session()).exercises[1]
        XCTAssertEqual(incline.sets.count, 2)
    }

    func testLoggingAPendingSetIsNeededToAppear() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(3, 80, 5))
        XCTAssertTrue(build(state).exercises.isEmpty)
        state = PresFix.marking(state, exercise: 0, done: [1])
        let summary = build(state)
        XCTAssertEqual(summary.exercises.count, 1)
        XCTAssertEqual(summary.loggedSets, 1)
    }

    // MARK: Personal records

    func testPersonalRecordList() throws {
        let summary = build(session())
        XCTAssertEqual(summary.personalRecords.count, 1)
        let record = try XCTUnwrap(summary.personalRecords.first)
        XCTAssertEqual(record.exerciseID, "bench")
        XCTAssertEqual(record.exerciseName, "Barbell bench press")
        XCTAssertEqual(record.weightKg, 85)
        XCTAssertEqual(record.reps, 6)
        XCTAssertEqual(record.estimated1RM, 102, accuracy: 0.0001)
        XCTAssertEqual(record.previousBest, 99)
        XCTAssertEqual(summary.exercises.map { $0.isPersonalRecord }, [true, false, false, false])
    }

    func testBestE1RMOfEachExercise() {
        let summary = build(session())
        XCTAssertEqual(summary.exercises[0].bestE1RM, 102, accuracy: 0.0001)
        XCTAssertEqual(summary.exercises[1].bestE1RM, 28 * (1 + 10.0 / 30), accuracy: 0.0001)
        XCTAssertEqual(summary.exercises[2].bestE1RM, 0, accuracy: 0.0001)    // 8 x 15: above the 12-rep cap, no estimate
    }

    func testWarmUpsNeverSetTheBestE1RM() {
        let state = PresFix.marking(
            PresFix.single(PresFix.lib("bench", best: 0), [(.warmup, 200, 5), (.normal, 80, 5)]), exercise: 0, done: [0, 1]
        )
        XCTAssertEqual(build(state).exercises[0].bestE1RM, 80 * (1 + 5.0 / 30), accuracy: 0.0001)
    }

    func testNoPersonalRecordWithoutHistoryButTheBestIsStillReported() {
        let state = PresFix.marking(
            PresFix.single(PresFix.lib("bench", best: 0), [(.normal, 100, 5), (.normal, 110, 5)]), exercise: 0, done: [0, 1]
        )
        let summary = build(state)
        XCTAssertTrue(summary.personalRecords.isEmpty)
        XCTAssertFalse(summary.exercises[0].isPersonalRecord)
        XCTAssertEqual(summary.exercises[0].bestE1RM, 110 * (1 + 5.0 / 30), accuracy: 0.0001)
    }

    func testNoPersonalRecordWhenTheBestOnlyMatchesTheBaseline() {
        let state = PresFix.marking(PresFix.single(PresFix.lib("bench"), [(.normal, 82.5, 6)]), exercise: 0, done: [0])
        let summary = build(state)
        XCTAssertTrue(summary.personalRecords.isEmpty)
        XCTAssertFalse(summary.exercises[0].isPersonalRecord)
    }

    func testPersonalRecordUsesTheRunningBaselineLikeThePresenter() throws {
        // 85 x 5 (99.17) then 85 x 6 (102) against 80: both are records, the best set is the second.
        let state = PresFix.marking(
            PresFix.single(PresFix.lib("bench", best: 80), [(.normal, 85, 5), (.normal, 85, 6)]), exercise: 0, done: [0, 1]
        )
        let record = try XCTUnwrap(build(state).personalRecords.first)
        XCTAssertEqual(record.reps, 6)
        XCTAssertEqual(record.estimated1RM, 102, accuracy: 0.0001)
        XCTAssertEqual(record.previousBest, 80)
        let view = PresFix.present(state, at: 10)
        XCTAssertEqual(try XCTUnwrap(view.card).rows.map { $0.isPersonalRecord }, [true, true])
    }

    func testRecordBestSetIsTheHighestEstimateNotTheLastSet() throws {
        let state = PresFix.marking(
            PresFix.single(PresFix.lib("bench", best: 80), [(.normal, 85, 6), (.normal, 85, 3)]), exercise: 0, done: [0, 1]
        )
        let record = try XCTUnwrap(build(state).personalRecords.first)
        XCTAssertEqual(record.reps, 6)
        XCTAssertEqual(record.weightKg, 85)
    }

    func testRecordsListFollowsTheWorkoutOrder() {
        let a = PresFix.entry(1, PresFix.lib("incline", best: 20), PresFix.normal(1, 28, 10))
        let b = PresFix.entry(2, PresFix.lib("bench", best: 50), PresFix.normal(1, 80, 5))
        var state = PresFix.workout([a, b])
        state = PresFix.marking(state, exercise: 0, done: [0])
        state = PresFix.marking(state, exercise: 1, done: [0])
        XCTAssertEqual(build(state).personalRecords.map { $0.exerciseID }, ["incline", "bench"])
    }

    func testTheSameExerciseTwiceYieldsOneRecordWithTheBestEstimate() {
        let a = PresFix.entry(1, PresFix.lib("bench", best: 80), PresFix.normal(1, 85, 5))
        let b = PresFix.entry(2, PresFix.lib("bench", best: 80), PresFix.normal(1, 90, 5))
        var state = PresFix.workout([a, b])
        state = PresFix.marking(state, exercise: 0, done: [0])
        state = PresFix.marking(state, exercise: 1, done: [0])
        let summary = build(state)
        XCTAssertEqual(summary.exercises.count, 2)
        XCTAssertEqual(summary.personalRecords.count, 1)
        XCTAssertEqual(summary.personalRecords[0].weightKg, 90)
    }

    func testBodyweightAndDurationExercisesHaveNoEstimate() {
        let pushup = PresFix.entry(1, PresFix.lib("pushup"), PresFix.normal(2, 0, 12))
        let plank = PresFix.entry(2, PresFix.lib("plank"), PresFix.normal(1, 0, 60))
        var state = PresFix.workout([pushup, plank])
        state = PresFix.marking(state, exercise: 0, done: [0, 1])
        state = PresFix.marking(state, exercise: 1, done: [0])
        let summary = build(state)
        XCTAssertEqual(summary.exercises.map { $0.bestE1RM }, [0, 0])
        XCTAssertEqual(summary.exercises.map { $0.isPersonalRecord }, [false, false])
        XCTAssertEqual(summary.exercises.map { $0.tracking }, [.repsOnly, .duration])
        XCTAssertEqual(summary.volumeKg, 0)
        XCTAssertEqual(summary.loggedSets, 3)
        XCTAssertEqual(summary.exercises[1].sets.map { $0.reps }, [60])
    }

    // MARK: Muscle sets

    func testMuscleSetsAreSortedBySetsThenName() {
        let summary = build(session())
        // Non-warm-up logged sets: chest 3 + 2, shoulders (lateral) 1, arms (pushdown) 1.
        XCTAssertEqual(summary.muscleSets.map { $0.muscle }, [.chest, .arms, .shoulders])
        XCTAssertEqual(summary.muscleSets.map { $0.sets }, [5, 1, 1])
    }

    func testMuscleSetsOmitZerosAndWarmUps() {
        let warmUpOnly = PresFix.marking(PresFix.single(PresFix.lib("squat"), [(.warmup, 40, 10), (.normal, 80, 5)]), exercise: 0, done: [0])
        XCTAssertTrue(build(warmUpOnly).muscleSets.isEmpty)
        XCTAssertEqual(build(warmUpOnly).loggedSets, 1)
    }

    func testMuscleSetsCountEveryTrackingKind() {
        let plank = PresFix.entry(1, PresFix.lib("plank"), PresFix.normal(2, 0, 45))
        let pushup = PresFix.entry(2, PresFix.lib("pushup"), PresFix.normal(2, 0, 12))
        let squat = PresFix.entry(3, PresFix.lib("squat"), PresFix.normal(3, 80, 5))
        var state = PresFix.workout([plank, pushup, squat])
        state = PresFix.marking(state, exercise: 0, done: [0, 1])
        state = PresFix.marking(state, exercise: 1, done: [0, 1])
        state = PresFix.marking(state, exercise: 2, done: [0, 1, 2])
        let sets = build(state).muscleSets
        // Legs 3, then chest and core with 2 each (alphabetical).
        XCTAssertEqual(sets.map { $0.muscle }, [.legs, .chest, .core])
        XCTAssertEqual(sets.map { $0.sets }, [3, 2, 2])
    }

    func testMuscleSetsAllSixGroupsTieBreakByName() {
        var entries: [WorkoutExercise] = []
        let ids = ["bench", "pullup", "ohp", "curl", "squat", "plank"]
        for (n, id) in ids.enumerated() { entries.append(PresFix.entry(n + 1, PresFix.lib(id), PresFix.normal(1, 20, 5))) }
        var state = PresFix.workout(entries)
        for k in 0..<entries.count { state = PresFix.marking(state, exercise: k, done: [0]) }
        XCTAssertEqual(build(state).muscleSets.map { $0.muscle.rawValue }, ["Arms", "Back", "Chest", "Core", "Legs", "Shoulders"])
    }

    // MARK: RIR and heart rate

    func testAverageRIR() throws {
        // Recorded on logged sets: 3, 2, 1 (bench) and 4 (incline).
        XCTAssertEqual(try XCTUnwrap(build(session()).averageRIR), 2.5, accuracy: 0.0001)
    }

    func testAverageRIRIgnoresUnrecordedAndUnloggedSets() throws {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(4, 80, 5))
        state = PresFix.marking(state, exercise: 0, done: [0, 1, 2])
        state.exercises[0].sets[0].rir = 1
        state.exercises[0].sets[1].rir = 2
        state.exercises[0].sets[3].rir = 4   // pending: ignored
        XCTAssertEqual(try XCTUnwrap(build(state).averageRIR), 1.5, accuracy: 0.0001)
    }

    func testAverageRIRIsNilWithoutRecordedValues() {
        let state = PresFix.marking(PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80, 5)), exercise: 0, done: [0, 1])
        XCTAssertNil(build(state).averageRIR)
    }

    func testAverageHeartRate() {
        // 120, 130, 140 count; 20 is out of range for the reducer.
        XCTAssertEqual(build(session()).averageHeartRate, 130)
    }

    func testAverageHeartRateIsNilWithoutSamples() {
        XCTAssertNil(build(PresFix.goldenState()).averageHeartRate)
    }

    // MARK: Duration

    func testDurationOfAWorkoutWithoutPauses() {
        XCTAssertEqual(build(session(), finishedAt: 600).durationSeconds, 600)
        XCTAssertEqual(build(session(), finishedAt: 0).durationSeconds, 0)
        XCTAssertEqual(build(session(), finishedAt: -10).durationSeconds, 0)
    }

    func testDurationExcludesPausedTime() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .pause, at: 1000)
        state = PresFix.reduced(state, .resume, at: 1400)   // 400 s paused
        XCTAssertEqual(build(state, finishedAt: 2000).durationSeconds, 1600)
    }

    func testDurationOfAWorkoutFinishedWhilePausedStopsAtThePause() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, .pause, at: 1000)
        XCTAssertEqual(build(state, finishedAt: 5000).durationSeconds, 1000)
    }

    func testDurationIgnoresAnEarlierFinishedAtOfTheState() {
        var state = PresFix.freshUpperA()
        state.finishedAt = PresFix.at(50)
        XCTAssertEqual(build(state, finishedAt: 700).durationSeconds, 700)
    }

    // MARK: Empty and degenerate workouts

    func testEmptyWorkoutSummary() {
        let state = WorkoutFactory.makeEmpty(name: "Workout", now: PresFix.t0)
        let summary = build(state, finishedAt: 90)
        XCTAssertEqual(summary.name, "Workout")
        XCTAssertNil(summary.templateID)
        XCTAssertEqual(summary.durationSeconds, 90)
        XCTAssertEqual(summary.volumeKg, 0)
        XCTAssertEqual(summary.loggedSets, 0)
        XCTAssertNil(summary.averageHeartRate)
        XCTAssertNil(summary.averageRIR)
        XCTAssertTrue(summary.exercises.isEmpty)
        XCTAssertTrue(summary.personalRecords.isEmpty)
        XCTAssertTrue(summary.muscleSets.isEmpty)
    }

    func testNothingLoggedSummary() {
        let summary = build(PresFix.freshUpperA(), finishedAt: 30)
        XCTAssertEqual(summary.loggedSets, 0)
        XCTAssertTrue(summary.exercises.isEmpty)
        XCTAssertEqual(summary.volumeKg, 0)
    }

    func testEverythingLogged() {
        let state = PresFix.loggedEverything(PresFix.freshUpperA())
        let summary = build(state, finishedAt: 600)
        XCTAssertEqual(summary.exercises.count, 6)
        XCTAssertEqual(summary.loggedSets, 20)
        XCTAssertEqual(summary.exercises.map { $0.sets.count }, [5, 3, 3, 3, 3, 3])
        // bench 85 x 6 = 102 beats 99; incline 28 x 10 = 37.3 < 38; ohp 45 x 8 = 57 < 58; lateral 8 x 15 = 12 < 12.5;
        // pushdown 30 x 12 = 42 < 43; crossover 15 x 12 = 21 < 22.
        XCTAssertEqual(summary.personalRecords.map { $0.exerciseID }, ["bench"])
    }

    func testSummaryIsCodableAndStable() throws {
        let state = session()
        let summary = build(state)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(summary)
        XCTAssertEqual(try decoder.decode(CompletedWorkout.self, from: data), summary)
        // Building twice from the same state gives the same summary.
        XCTAssertEqual(build(state), summary)
    }

    func testSummaryHasUniqueIdentifiersForLists() {
        let summary = build(PresFix.loggedEverything(PresFix.freshUpperA()))
        XCTAssertEqual(Set(summary.exercises.map { $0.id }).count, summary.exercises.count)
        XCTAssertEqual(Set(summary.personalRecords.map { $0.id }).count, summary.personalRecords.count)
        XCTAssertEqual(Set(summary.muscleSets.map { $0.id }).count, summary.muscleSets.count)
    }
}

// MARK: - Fuzz: summary invariants

final class SummaryFuzzTests: XCTestCase {
    func testSummaryAgreesWithThePresenterUnderRandomPlay() {
        for seed in 1...10 {
            var rng = PresLCG(seed: UInt64(seed) &+ 500)
            var state = WorkoutFactory.makeWorkout(from: PresFix.upperA(), now: PresFix.t0)
            var clock = 0.0
            for step in 0..<120 {
                clock += Double(rng.below(30))
                let exercise = state.exercises.isEmpty ? nil : state.exercises[rng.below(state.exercises.count)]
                let set = exercise.flatMap { $0.sets.isEmpty ? nil : $0.sets[rng.below($0.sets.count)] }
                let action: WorkoutAction
                switch rng.below(8) {
                case 0, 1, 2: action = .logNextSet
                case 3: action = exercise.flatMap { e in set.map { .toggleSet(exerciseID: e.id, setID: $0.id) } } ?? .skipRest
                case 4: action = .toggleLastSetRIR(rng.below(5))
                case 5: action = .updateHeartRate(60 + rng.below(100))
                case 6: action = exercise.flatMap { e in set.map { .setWeight(exerciseID: e.id, setID: $0.id, kg: Double(rng.below(240)) / 2) } } ?? .skipRest
                default: action = .goTo(index: rng.below(6))
                }
                WorkoutReducer.reduce(&state, action, now: PresFix.at(clock))

                let summary = SummaryBuilder.build(from: state, finishedAt: PresFix.at(clock + 1))
                let view = PresFix.present(state, at: clock + 1)
                let context = "seed \(seed) step \(step)"
                XCTAssertEqual(summary.loggedSets, view.totals.loggedSets, context)
                XCTAssertEqual(summary.volumeKg, view.totals.volumeKg, accuracy: 0.0001, context)
                XCTAssertEqual(summary.exercises.map { $0.sets.count }.reduce(0, +), summary.loggedSets, context)
                XCTAssertEqual(summary.muscleSets.map { $0.sets }, summary.muscleSets.map { $0.sets }.sorted(by: >), context)
                XCTAssertTrue(summary.muscleSets.allSatisfy { $0.sets > 0 }, context)
                XCTAssertEqual(summary.exercises.filter { $0.isPersonalRecord }.count, summary.personalRecords.count, context)
                XCTAssertEqual(summary.averageHeartRate, state.averageHeartRate, context)
                for exercise in summary.exercises {
                    XCTAssertFalse(exercise.sets.isEmpty, context)
                    if exercise.isPersonalRecord { XCTAssertGreaterThan(exercise.bestE1RM, 0, context) }
                }
                for record in summary.personalRecords {
                    XCTAssertGreaterThan(record.estimated1RM, record.previousBest, context)
                }
            }
        }
    }
}
