import XCTest
@testable import PulseStrengthCore

// MARK: - The live record rules, one case per kind and per "no record"

final class LiveRecordRuleTests: XCTestCase {
    typealias Spec = (type: SetType, kg: Double, reps: Int, done: Bool)

    /// An exercise whose earlier sessions are `previous` (non-warm-up sets raise the best estimate and the marks).
    private func exercise(
        _ tracking: TrackingKind, allowsAddedWeight: Bool = false, previous: [(SetType, Double, Int)]
    ) -> Exercise {
        var marks = RecordMarks()
        var best = 0.0
        for set in previous {
            marks.add(weightKg: set.1, reps: set.2, type: set.0, tracking: tracking, carriesLoad: tracking == .repsOnly && allowsAddedWeight)
            if tracking == .weightReps, set.0 != .warmup, let estimate = Estimated1RM.estimate(weightKg: set.1, reps: set.2) {
                best = max(best, estimate)
            }
        }
        var result = RedFix.exercise(
            "x", "Exercise", .chest, .barbell, tracking: tracking, best: best, kg: 0, reps: 5, rest: 60, allowsAddedWeight: allowsAddedWeight
        )
        result.previousRecords = marks
        return result
    }

    private func kinds(_ exercise: Exercise, _ sets: [Spec]) -> [PRKind?] {
        var entry = RedFix.entry(1, exercise, sets.map { ($0.type, $0.kg, $0.reps) }, rest: 60)
        for (index, set) in sets.enumerated() { entry.sets[index].isDone = set.done }
        return PresenterSupport.analyse(entry).sets.map { $0.kind }
    }

    private func normal(_ kg: Double, _ reps: Int, done: Bool = true) -> Spec { (.normal, kg, reps, done) }

    // The earlier session of the weight table: 100 x 5 (estimate 116.67) and 60 x 12 (84).
    private var lifter: Exercise { exercise(.weightReps, previous: [(.normal, 100, 5), (.normal, 60, 12)]) }

    func testAnEstimateRecord() {
        XCTAssertEqual(kinds(lifter, [normal(100, 6)]), [.estimated1RM], "100 x 6 is 120")
    }

    func testTheEstimateComesBeforeTheOtherKinds() {
        // 105 x 5 is both the heaviest weight and an estimate of 122.5
        XCTAssertEqual(kinds(lifter, [normal(105, 5)]), [.estimated1RM])
    }

    func testTheHeaviestWeightWhateverTheReps() {
        // 110 x 1 is 113.67, below the estimate of 116.67, but 10 kg heavier than any set
        XCTAssertEqual(kinds(lifter, [normal(110, 1)]), [.heaviest])
    }

    func testARepRecordForARepRange() {
        // 70 x 10: no estimate record (93.3), not the heaviest, but more than the 60 kg of the best 10 reps
        XCTAssertEqual(kinds(lifter, [normal(70, 10)]), [.repRecord(reps: 10)])
        // 100 x 5 again changes nothing; 61 x 12 beats the 60 kg of the best 12 reps
        XCTAssertEqual(kinds(lifter, [normal(100, 5)]), [nil])
        XCTAssertEqual(kinds(lifter, [normal(61, 12)]), [.repRecord(reps: 12)])
    }

    func testSetsAboveTheEstimateCapUseTheOpenEndedBucket() {
        let withLongSets = exercise(.weightReps, previous: [(.normal, 100, 5), (.normal, 60, 15)])
        // 70 x 15: no estimate, not the heaviest, but more than the 60 kg lifted for 13 or more reps
        XCTAssertEqual(kinds(withLongSets, [normal(70, 15)]), [.repRecord(reps: 13)])
        XCTAssertEqual(kinds(withLongSets, [normal(70, 30)]), [.repRecord(reps: 13)], "13 or more reps share one record")
        XCTAssertEqual(kinds(withLongSets, [normal(59, 15)]), [nil])
        // 20 kg x 100 reps beats nothing
        XCTAssertEqual(kinds(withLongSets, [normal(20, 100)]), [nil])
    }

    func testARecordNeedsItsOwnEarlierValue() {
        // the earlier session reached 12 reps at most: 20 reps at any weight has no record of its own to beat
        XCTAssertEqual(kinds(lifter, [normal(50, 20)]), [nil])
        // and there is no estimate for 50 x 20
        XCTAssertNil(Estimated1RM.estimate(weightKg: 50, reps: 20))
    }

    func testTheFirstSessionOfAnExerciseIsNeverFlagged() {
        let first = exercise(.weightReps, previous: [])
        XCTAssertEqual(kinds(first, [normal(100, 5), normal(110, 5), normal(120, 1)]), [nil, nil, nil])
        let firstRepsOnly = exercise(.repsOnly, previous: [])
        XCTAssertEqual(kinds(firstRepsOnly, [normal(0, 30)]), [nil])
        let firstTimed = exercise(.duration, previous: [])
        XCTAssertEqual(kinds(firstTimed, [normal(0, 300)]), [nil])
    }

    func testTheMarginIsHalfASetTenthOfAKilogramOfFifty() {
        let reference = exercise(.weightReps, previous: [(.normal, 100, 6)])      // 120
        XCTAssertEqual(kinds(reference, [normal(100.04, 6)]), [nil], "120.048 is within the margin of 120.05")
        XCTAssertEqual(kinds(reference, [normal(100.06, 6)]), [.estimated1RM], "120.072 clears it")
        // the same margin separates the weights of the other kinds
        let heavy = exercise(.weightReps, previous: [(.normal, 100, 1)])           // 103.33
        XCTAssertEqual(kinds(heavy, [normal(100.04, 1)]), [nil])
        XCTAssertEqual(kinds(heavy, [normal(100.06, 1)]), [.estimated1RM])
    }

    func testWarmUpsAreNeverRecords() {
        XCTAssertEqual(kinds(lifter, [(.warmup, 200, 5, true), (.warmup, 300, 1, true)]), [nil, nil])
        // and they do not raise what the next set has to beat
        XCTAssertEqual(kinds(lifter, [(.warmup, 200, 5, true), normal(100, 6)]), [nil, .estimated1RM])
    }

    func testPendingSetsAreNeverRecords() {
        XCTAssertEqual(kinds(lifter, [normal(200, 5, done: false)]), [nil])
        // a pending set does not raise the running best either
        XCTAssertEqual(kinds(lifter, [normal(200, 5, done: false), normal(100, 6)]), [nil, .estimated1RM])
    }

    func testTheRunningBestRisesWithEveryLoggedSet() {
        XCTAssertEqual(kinds(lifter, [normal(100, 6), normal(100, 6), normal(100, 7)]), [.estimated1RM, nil, .estimated1RM])
        XCTAssertEqual(kinds(lifter, [normal(110, 1), normal(110, 1), normal(111, 1)]), [.heaviest, nil, .heaviest])
        // a rep record is raised by the sets of the same workout too
        XCTAssertEqual(kinds(lifter, [normal(70, 10), normal(70, 10), normal(72, 10)]), [.repRecord(reps: 10), nil, .repRecord(reps: 10)])
    }

    func testDropAndFailureSetsCount() {
        XCTAssertEqual(kinds(lifter, [(.drop, 110, 1, true)]), [.heaviest])
        XCTAssertEqual(kinds(lifter, [(.failure, 100, 6, true)]), [.estimated1RM])
    }

    func testHugeAndBrokenWeightsNeverTrapOrMakeUpAnEstimate() {
        XCTAssertEqual(kinds(lifter, [normal(1_000_000, 1)]), [.estimated1RM])
        XCTAssertEqual(kinds(lifter, [normal(Double.greatestFiniteMagnitude, 12)]), [.heaviest], "no estimate that overflows")
        XCTAssertEqual(kinds(lifter, [normal(.infinity, 5), normal(.nan, 5), normal(-.infinity, 5)]), [nil, nil, nil])
        XCTAssertEqual(kinds(lifter, [normal(100, 0), normal(0, 5), normal(-5, 5)]), [nil, nil, nil])
        XCTAssertEqual(kinds(lifter, [normal(100, Int.max)]), [nil], "no estimate for absurd reps, and nothing to beat at 13 or more")
        let infiniteBest = exercise(.weightReps, previous: [(.normal, 100, 5)])
        var broken = infiniteBest
        broken.previousBestE1RM = .infinity
        XCTAssertEqual(kinds(broken, [normal(100, 6)]), [nil], "a best that is not finite cannot be beaten")
    }

    // MARK: Reps only and timed

    func testMostRepsWithoutALoad() {
        let pushups = exercise(.repsOnly, previous: [(.normal, 0, 15), (.normal, 0, 12)])
        XCTAssertEqual(kinds(pushups, [normal(0, 16)]), [.reps])
        XCTAssertEqual(kinds(pushups, [normal(0, 15)]), [nil], "equal is not more")
        XCTAssertEqual(kinds(pushups, [normal(0, 16), normal(0, 16), normal(0, 17)]), [.reps, nil, .reps])
        XCTAssertEqual(kinds(pushups, [(.warmup, 0, 40, true)]), [nil])
        XCTAssertEqual(kinds(pushups, [normal(0, 40, done: false)]), [nil])
    }

    func testLongestHold() {
        let planks = exercise(.duration, previous: [(.normal, 0, 60), (.normal, 0, 45)])
        XCTAssertEqual(kinds(planks, [normal(0, 61)]), [.duration])
        XCTAssertEqual(kinds(planks, [normal(0, 60)]), [nil])
        XCTAssertEqual(kinds(planks, [normal(0, 10_800)]), [.duration])
        XCTAssertEqual(kinds(planks, [normal(0, 90), normal(0, 90)]), [.duration, nil])
    }

    func testAnAddedLoadRecordHasNoEstimate() {
        let pullups = exercise(.repsOnly, allowsAddedWeight: true, previous: [(.normal, 10, 8), (.normal, 0, 14)])
        XCTAssertEqual(kinds(pullups, [normal(15, 8)]), [.heaviest], "+15 kg is the heaviest added load")
        XCTAssertEqual(kinds(pullups, [normal(10, 8)]), [nil], "the same load for the same reps is no record")
        XCTAssertEqual(kinds(pullups, [normal(10, 9)]), [.repRecord(reps: 9)], "+10 kg for 9 reps beats the bodyweight 14 that held that range")
        XCTAssertEqual(kinds(pullups, [normal(12, 6)]), [.heaviest])
        XCTAssertEqual(kinds(pullups, [normal(0, 15)]), [.reps], "bodyweight reps are their own record")
        XCTAssertEqual(kinds(pullups, [normal(0, 14)]), [nil])
        let rows = PresenterSupport.analyse(RedFix.entry(1, pullups, [(.normal, 15, 8)], rest: 60)).sets
        XCTAssertEqual(rows.map { $0.e1RM }, [0], "an added load never has an estimate")
    }

    func testAnAssistedLoadGetsHeavierTowardsBodyweight() {
        let assisted = exercise(.repsOnly, allowsAddedWeight: true, previous: [(.normal, -20, 8)])
        XCTAssertEqual(kinds(assisted, [normal(-15, 8)]), [.heaviest], "-15 is heavier than -20")
        XCTAssertEqual(kinds(assisted, [normal(-25, 8)]), [nil])
        XCTAssertEqual(kinds(assisted, [normal(-20, 8)]), [nil])
        XCTAssertEqual(kinds(assisted, [normal(-20, 10)]), [nil], "10 reps at the same assistance has no record of its own")
    }

    func testBodyweightIsAHeavierLoadThanAnyAssistance() {
        let assisted = exercise(.repsOnly, allowsAddedWeight: true, previous: [(.normal, -30, 8)])
        XCTAssertEqual(kinds(assisted, [normal(0, 12)]), [.heaviest], "going from assisted to bodyweight is a record")
        let progressed = exercise(.repsOnly, allowsAddedWeight: true, previous: [(.normal, -30, 8), (.normal, 0, 8)])
        XCTAssertEqual(kinds(progressed, [normal(-10, 8)]), [nil], "a step back to an assisted load is none")
        XCTAssertEqual(kinds(progressed, [normal(0, 9)]), [.reps], "more bodyweight reps")
        XCTAssertEqual(kinds(progressed, [normal(5, 8)]), [.heaviest])
    }

    func testBodyweightOnlyExercisesKeepNoLoadMarks() {
        let pushups = exercise(.repsOnly, previous: [(.normal, 0, 15)])
        XCTAssertNil(pushups.previousRecords.heaviestKg)
        XCTAssertTrue(pushups.previousRecords.repRecords.isEmpty)
        XCTAssertEqual(kinds(pushups, [normal(0, 16)]), [.reps])
    }

    // MARK: The kind of the record of the summary

    func testTheSummaryNamesTheKindAndTheValueBeforeTheWorkout() throws {
        let cases: [(Exercise, [Spec], PRKind, Double)] = [
            (lifter, [normal(100, 6)], .estimated1RM, 100 * (1 + 5.0 / 30)),
            (lifter, [normal(110, 1)], .heaviest, 100),
            (lifter, [normal(70, 10)], .repRecord(reps: 10), 60),
            (exercise(.repsOnly, previous: [(.normal, 0, 15)]), [normal(0, 18)], .reps, 15),
            (exercise(.duration, previous: [(.normal, 0, 60)]), [normal(0, 75)], .duration, 60),
        ]
        for (exercise, sets, kind, previous) in cases {
            var entry = RedFix.entry(1, exercise, sets.map { ($0.type, $0.kg, $0.reps) }, rest: 60)
            for index in sets.indices { entry.sets[index].isDone = true }
            let state = RedFix.state([entry])
            let summary = SummaryBuilder.build(from: state, finishedAt: RedFix.at(600))
            let record = try XCTUnwrap(summary.personalRecords.first, "\(kind)")
            XCTAssertEqual(record.kind, kind)
            XCTAssertEqual(record.previousBest, previous, accuracy: 1e-9, "\(kind)")
            XCTAssertEqual(record.weightKg, sets[0].kg)
            XCTAssertEqual(record.reps, sets[0].reps)
            XCTAssertEqual(summary.exercises[0].sets.map { $0.prKind }, [kind])
            XCTAssertTrue(summary.exercises[0].isPersonalRecord)
        }
    }

    func testOnePersonalRecordPerExerciseTheHighestKindThenTheLargestValue() throws {
        // 110 x 1 is the heaviest weight, 100 x 6 an estimate record: the summary keeps the estimate
        var entry = RedFix.entry(1, lifter, [(.normal, 110, 1), (.normal, 100, 6)], rest: 60)
        for index in entry.sets.indices { entry.sets[index].isDone = true }
        let summary = SummaryBuilder.build(from: RedFix.state([entry]), finishedAt: RedFix.at(600))
        XCTAssertEqual(summary.exercises[0].sets.map { $0.prKind }, [.heaviest, .estimated1RM])
        XCTAssertEqual(summary.personalRecords.count, 1)
        XCTAssertEqual(summary.personalRecords[0].kind, .estimated1RM)
        XCTAssertEqual(summary.personalRecords[0].weightKg, 100)

        // two sets of one kind: the larger value wins
        var two = RedFix.entry(1, lifter, [(.normal, 110, 1), (.normal, 115, 1)], rest: 60)
        for index in two.sets.indices { two.sets[index].isDone = true }
        let best = SummaryBuilder.build(from: RedFix.state([two]), finishedAt: RedFix.at(600))
        XCTAssertEqual(best.personalRecords.map { $0.weightKg }, [115])
    }
}

// MARK: - The presenter and the summary agree

final class RecordAgreementTests: XCTestCase {
    private func randomExercise(_ rng: inout RedLCG, taken: inout Set<String>) -> Exercise {
        // each exercise at most once per workout: the summary keeps one record per exercise id
        let base = rng.pick([RedFix.bench, RedFix.incline, RedFix.pullup, RedFix.pushup, RedFix.plank, RedFix.squat, RedFix.lateral]
            .filter { !taken.contains($0.id) })
        taken.insert(base.id)
        var exercise = base
        var marks = RecordMarks()
        var best = 0.0
        if rng.chance(85) {
            for _ in 0..<rng.int(1...5) {
                let type = rng.pick([SetType.normal, .normal, .warmup, .drop, .failure])
                let weight = randomWeight(for: base, &rng)
                let reps = base.tracking == .duration ? rng.int(10...200) : rng.int(1...20)
                marks.add(weightKg: weight, reps: reps, type: type, tracking: base.tracking, carriesLoad: base.carriesLoad)
                if base.tracking == .weightReps, type != .warmup, let estimate = Estimated1RM.estimate(weightKg: weight, reps: reps) {
                    best = max(best, estimate)
                }
            }
        }
        exercise.previousBestE1RM = best
        exercise.previousRecords = marks
        return exercise
    }

    private func randomWeight(for exercise: Exercise, _ rng: inout RedLCG) -> Double {
        switch exercise.tracking {
        case .weightReps: return Double(rng.int(10...200)) / 2
        case .repsOnly: return exercise.allowsAddedWeight ? rng.pick([-20, -10, 0, 0, 5, 10, 20]) : 0
        case .duration: return 0
        }
    }

    private func randomState(seed: UInt64) -> WorkoutState {
        var rng = RedLCG(seed: seed)
        var taken = Set<String>()
        let entries = (0..<rng.int(1...4)).map { n -> WorkoutExercise in
            let exercise = randomExercise(&rng, taken: &taken)
            let sets = (0..<rng.int(1...7)).map { _ -> RedFix.SetSpec in
                let reps = exercise.tracking == .duration ? rng.int(5...240) : rng.pick([0, 1, 3, 5, 8, 10, 12, 13, 15, 20, 40])
                return (rng.pick([SetType.normal, .normal, .normal, .warmup, .drop, .failure]), randomWeight(for: exercise, &rng), reps)
            }
            var entry = RedFix.entry(n + 1, exercise, sets, rest: 60)
            for index in entry.sets.indices { entry.sets[index].isDone = rng.chance(75) }
            return entry
        }
        return RedFix.state(entries)
    }

    func testTheScreenAndTheSavedWorkoutFlagTheSameSetsWithTheSameKind() {
        var flagged = Set<String>()
        for seed in 1...300 as ClosedRange<UInt64> {
            let state = randomState(seed: seed)
            let summary = SummaryBuilder.build(from: state, finishedAt: RedFix.at(3_600))
            var summaryIndex = 0
            for (k, entry) in state.exercises.enumerated() {
                var shown = state
                shown.currentIndex = k
                let rows = WorkoutPresenter.present(shown, now: RedFix.at(10), recovery: DemoRecovery.provider).card?.rows ?? []
                XCTAssertEqual(rows.count, entry.sets.count, "seed \(seed)")
                let rowKinds = rows.enumerated().filter { entry.sets[$0.offset].isDone }.map { $0.element.prKind }
                guard entry.doneCount > 0 else { continue }
                let saved = summary.exercises[summaryIndex]
                summaryIndex += 1
                XCTAssertEqual(saved.sets.map { $0.prKind }, rowKinds, "seed \(seed) exercise \(k)")
                XCTAssertEqual(saved.isPersonalRecord, rowKinds.contains { $0 != nil }, "seed \(seed)")
                XCTAssertEqual(rows.map { $0.isPersonalRecord }, rows.map { $0.prKind != nil }, "seed \(seed)")
                for (row, set) in zip(rows, entry.sets) where !set.isDone {
                    XCTAssertNil(row.prKind, "a pending set is no record, seed \(seed)")
                }
                for (row, set) in zip(rows, entry.sets) where set.type == .warmup {
                    XCTAssertNil(row.prKind, "a warm-up is no record, seed \(seed)")
                }
                let records = summary.personalRecords.filter { $0.exerciseID == entry.exercise.id }
                if let top = rowKinds.compactMap({ $0 }).max(by: { $0.rank < $1.rank }) {
                    flagged.insert("\(top)")
                    XCTAssertEqual(records.count, 1, "seed \(seed)")
                    XCTAssertEqual(records.first?.kind.rank, top.rank, "seed \(seed)")
                } else {
                    XCTAssertTrue(records.isEmpty, "seed \(seed)")
                }
            }
            XCTAssertEqual(summaryIndex, summary.exercises.count, "seed \(seed)")
        }
        // the random workouts really reached every kind of record
        for kind in ["estimated1RM", "heaviest", "reps", "duration"] {
            XCTAssertTrue(flagged.contains(kind), "no \(kind) in 300 random workouts: \(flagged)")
        }
        XCTAssertTrue(flagged.contains { $0.hasPrefix("repRecord") }, "\(flagged)")
    }
}

// MARK: - The record rows of the exercise screen

final class RecordRowsTests: XCTestCase {
    private typealias F = SvcDataFix

    private func rows(_ data: StrengthData, _ id: String, format: DisplayFormat = .metric) -> [String: ExerciseRecordRow] {
        Dictionary(uniqueKeysWithValues: data.history(for: id, now: F.now, format: format).records.map { ($0.id, $0) })
    }

    func testAWeightExerciseListsTheHeaviestWeightAndTheRepMaxesItReached() throws {
        var data = StrengthData()
        data.history = [
            F.workout(1, finishedAt: F.daysAgo(20), [F.entry("bench", [F.work(100, 3), F.work(90, 5)], n: 1)]),
            F.workout(2, finishedAt: F.daysAgo(10), [F.entry("bench", [F.work(80, 9)], n: 2)]),
        ]
        let history = data.history(for: "bench", now: F.now)
        XCTAssertEqual(history.records.map { $0.id }, ["e1rm", "bestSet", "heaviest", "rm3", "rm5", "rm8", "repsAtWeight", "bestVolume"])
        let byID = rows(data, "bench")
        XCTAssertEqual(byID["heaviest"]?.label, "Heaviest weight")
        XCTAssertEqual(byID["heaviest"]?.value, "100 kg")
        XCTAssertEqual(byID["heaviest"]?.date, F.daysAgo(20))
        XCTAssertEqual(byID["rm3"]?.label, "Best 3RM")
        XCTAssertEqual(byID["rm3"]?.value, "100 kg")
        XCTAssertEqual(byID["rm5"]?.value, "90 kg")
        XCTAssertEqual(byID["rm8"]?.value, "80 kg", "the heaviest weight for at least 8 reps: 80 x 9")
        XCTAssertEqual(byID["rm8"]?.date, F.daysAgo(10))
    }

    func testARepMaxIsOnlyListedWhenItWasReached() {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(100, 4)], n: 1)])]
        XCTAssertEqual(data.history(for: "bench", now: F.now).records.map { $0.id }, ["e1rm", "bestSet", "heaviest", "rm3", "repsAtWeight", "bestVolume"])
    }

    func testTheRowsFollowTheUnitAndTheLocale() {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(100, 5)], n: 1)])]
        let pounds = rows(data, "bench", format: DisplayFormat(unit: .lb, locale: Locale(identifier: "en_US")))
        XCTAssertEqual(pounds["heaviest"]?.value, "220.5 lb")
        XCTAssertEqual(pounds["rm5"]?.value, "220.5 lb")
        let german = rows(data, "bench", format: DisplayFormat(unit: .kg, locale: Locale(identifier: "de_DE")))
        XCTAssertEqual(german["heaviest"]?.value, "100 kg")
        var decimal = StrengthData()
        decimal.history = [F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(82.5, 5)], n: 1)])]
        XCTAssertEqual(rows(decimal, "bench", format: DisplayFormat(unit: .kg, locale: Locale(identifier: "de_DE")))["heaviest"]?.value, "82,5 kg")
    }

    func testAWarmUpIsNoHeaviestWeight() {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.warmup(150, 5), F.work(80, 5)], n: 1)])]
        XCTAssertEqual(rows(data, "bench")["heaviest"]?.value, "80 kg")
    }

    func testAnExerciseWithOnlyLongSetsStillShowsItsHeaviestWeight() {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(2), [F.entry("lateral", [F.work(8, 15), F.work(8, 17)], n: 1)])]
        let history = data.history(for: "lateral", now: F.now)
        XCTAssertEqual(history.bestE1RM, 0, "no estimate above 12 reps")
        XCTAssertTrue(history.e1RMSeries.isEmpty)
        XCTAssertNil(history.bestSetText)
        XCTAssertEqual(rows(data, "lateral")["heaviest"]?.value, "8 kg")
        XCTAssertNil(rows(data, "lateral")["e1rm"], "no estimated 1RM row without an estimate")
    }

    func testARepsOnlyExerciseListsTheMostRepsAndTheHeaviestAddedLoad() {
        var data = StrengthData()
        data.history = [
            F.workout(1, finishedAt: F.daysAgo(12), [F.entry("pullup", [F.work(0, 10), F.work(10, 6)], n: 1)]),
            F.workout(2, finishedAt: F.daysAgo(3), [F.entry("pullup", [F.work(0, 12), F.work(-20, 8)], n: 2)]),
        ]
        let byID = rows(data, "pullup")
        XCTAssertEqual(byID["mostReps"]?.value, "12")
        XCTAssertEqual(byID["mostReps"]?.date, F.daysAgo(3))
        XCTAssertEqual(byID["heaviest"]?.label, "Heaviest added weight")
        XCTAssertEqual(byID["heaviest"]?.value, "+10 kg")
        XCTAssertEqual(byID["heaviest"]?.date, F.daysAgo(12))
        XCTAssertEqual(byID["rm5"]?.value, "+10 kg", "the heaviest load for at least 5 reps")
        XCTAssertNil(byID["rm8"], "12 bodyweight reps are heavier than the assisted 8 and are no added load")
        XCTAssertEqual(byID["rm3"]?.value, "+10 kg")
    }

    func testAnAssistedLoadIsShownWithAMinus() {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(3), [F.entry("pullup", [F.work(-30, 8), F.work(-40, 10)], n: 1)])]
        let byID = rows(data, "pullup")
        XCTAssertEqual(byID["heaviest"]?.value, "\u{2212}30 kg")
        XCTAssertEqual(byID["rm8"]?.value, "\u{2212}30 kg")
        XCTAssertEqual(byID["rm5"]?.value, "\u{2212}30 kg")
        XCTAssertNil(byID["mostReps"], "no set without a load")
    }

    func testTheMostRepsRowCountsTheSetsWithoutALoadLikeTheRecordRule() throws {
        var data = StrengthData()
        data.history = [
            F.workout(1, finishedAt: F.daysAgo(5), [F.entry("pullup", [F.work(0, 10), F.work(10, 12)], n: 1)]),
        ]
        XCTAssertEqual(rows(data, "pullup")["mostReps"]?.value, "10", "the 12 reps with +10 kg are a load, not bodyweight reps")
        let history = data.history(for: "pullup", now: F.now)
        XCTAssertEqual(history.bestSetText, "10 reps")
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "pullup")).previousRecords.bestReps, 10)
    }

    func testBodyweightOnlyPullUpsListNoAddedWeight() {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(3), [F.entry("pullup", [F.work(0, 8), F.work(0, 10)], n: 1)])]
        let byID = rows(data, "pullup")
        XCTAssertEqual(byID["mostReps"]?.value, "10")
        XCTAssertNil(byID["heaviest"])
        XCTAssertNil(byID["rm8"])
    }

    func testATieIsDatedWithTheEarliestSession() {
        var data = StrengthData()
        data.history = [
            F.workout(1, finishedAt: F.daysAgo(20), [F.entry("bench", [F.work(100, 3)], n: 1), F.entry("pullup", [F.work(0, 10)], n: 3), F.entry("plank", [F.work(0, 60)], n: 5)]),
            F.workout(2, finishedAt: F.daysAgo(10), [F.entry("bench", [F.work(100, 3)], n: 2), F.entry("pullup", [F.work(0, 10)], n: 4), F.entry("plank", [F.work(0, 60)], n: 6)]),
        ]
        let bench = rows(data, "bench")
        XCTAssertEqual(bench["heaviest"]?.date, F.daysAgo(20))
        XCTAssertEqual(bench["rm3"]?.date, F.daysAgo(20))
        XCTAssertEqual(rows(data, "pullup")["mostReps"]?.date, F.daysAgo(10), "the newest session wins a tie of the most reps in a set")
        XCTAssertEqual(rows(data, "plank")["longest"]?.date, F.daysAgo(10), "and of the longest set")
    }

    func testATimedExerciseListsTheLongestHold() {
        var data = StrengthData()
        data.history = [
            F.workout(1, finishedAt: F.daysAgo(8), [F.entry("plank", [F.work(0, 45), F.work(0, 70)], n: 1)]),
            F.workout(2, finishedAt: F.daysAgo(1), [F.entry("plank", [F.work(0, 60)], n: 2)]),
        ]
        let byID = rows(data, "plank")
        XCTAssertEqual(byID["longest"]?.value, "70 s")
        XCTAssertEqual(byID["longest"]?.date, F.daysAgo(8))
    }

    func testAStoredMarkOfAnUnreadableWorkoutIsListed() {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(80, 5)], n: 1)])]
        data.personalBests["bench"] = PersonalBest(
            exerciseID: "bench", estimated1RM: 0, weightKg: 0, reps: 0, date: F.daysAgo(90), heaviestKg: 120, repRecords: [1: 120]
        )
        let byID = rows(data, "bench")
        XCTAssertEqual(byID["heaviest"]?.value, "120 kg")
        XCTAssertEqual(byID["heaviest"]?.date, F.daysAgo(90))
    }
}
