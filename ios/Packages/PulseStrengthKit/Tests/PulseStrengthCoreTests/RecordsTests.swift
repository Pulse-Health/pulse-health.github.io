import XCTest
@testable import PulseStrengthCore

// MARK: - The estimate helper

final class EstimateHelperTests: XCTestCase {
    func testTheEstimateExistsForOneToTwelveRepsOnly() throws {
        XCTAssertEqual(Estimated1RM.maximumReliableReps, 12)
        XCTAssertEqual(try XCTUnwrap(Estimated1RM.estimate(weightKg: 100, reps: 1)), 100 * (1 + 1.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Estimated1RM.estimate(weightKg: 100, reps: 12)), 140, accuracy: 1e-9)
        XCTAssertNil(Estimated1RM.estimate(weightKg: 100, reps: 13))
        XCTAssertNil(Estimated1RM.estimate(weightKg: 20, reps: 100), "20 kg x 100 reps is not an 87 kg lifter")
        XCTAssertEqual(Estimated1RM.epley(weightKg: 20, reps: 100), 20 * (1 + 100.0 / 30), accuracy: 1e-9, "the formula alone still computes")
    }

    func testNoEstimateWithoutAWeightOrReps() {
        XCTAssertNil(Estimated1RM.estimate(weightKg: 0, reps: 5))
        XCTAssertNil(Estimated1RM.estimate(weightKg: -20, reps: 5))
        XCTAssertNil(Estimated1RM.estimate(weightKg: 80, reps: 0))
        XCTAssertNil(Estimated1RM.estimate(weightKg: 80, reps: -3))
        XCTAssertNil(Estimated1RM.estimate(weightKg: .nan, reps: 5))
        XCTAssertNil(Estimated1RM.estimate(weightKg: .infinity, reps: 5))
        XCTAssertNil(Estimated1RM.estimate(weightKg: Double.greatestFiniteMagnitude, reps: 12), "an estimate that overflows is none")
    }

    func testEveryCallerTreatsMoreThanTwelveRepsAsNoEstimate() throws {
        typealias F = SvcDataFix
        // The history: the set of 100 reps is no best set and no estimate, in the chart or in the bests.
        let longSet = F.work(20, 100)
        var data = StrengthData()
        data.record(F.workout(1, finishedAt: F.daysAgo(3), [F.entry("bench", [longSet, F.work(60, 8)], n: 1)]), updateTemplate: nil)
        var history = data.history(for: "bench", now: F.now)
        XCTAssertEqual(history.bestSetText, "60 kg × 8")
        XCTAssertEqual(history.bestE1RM, 60 * (1 + 8.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(data.personalBests["bench"]?.weightKg, 60)

        var onlyLong = StrengthData()
        onlyLong.record(F.workout(2, finishedAt: F.daysAgo(3), [F.entry("bench", [longSet], n: 2)]), updateTemplate: nil)
        history = onlyLong.history(for: "bench", now: F.now)
        XCTAssertNil(history.bestSetText)
        XCTAssertEqual(history.bestE1RM, 0)
        XCTAssertTrue(history.e1RMSeries.isEmpty)
        XCTAssertEqual(onlyLong.personalBests["bench"]?.estimated1RM, 0)
        XCTAssertEqual(onlyLong.exercise(id: "bench")?.previousBestE1RM, 0)

        // An estimate that an older build recorded from the 100 reps (87) is dropped too.
        var old = StrengthData()
        old.history = [F.workout(3, finishedAt: F.daysAgo(3), [F.entry("bench", [longSet], best: 20 * (1 + 100.0 / 30), n: 3)])]
        XCTAssertEqual(old.exercise(id: "bench")?.previousBestE1RM, 0)
        XCTAssertEqual(old.recomputedPersonalBests()["bench"]?.estimated1RM, 0)

        // The summary and the screen: 20 kg x 100 reps is no record against a best of 50.
        let state = PresFix.marking(PresFix.single(PresFix.lib("bench", best: 50), [(.normal, 20, 100)]), exercise: 0, done: [0])
        let summary = SummaryBuilder.build(from: state, finishedAt: PresFix.at(60))
        XCTAssertEqual(summary.exercises[0].bestE1RM, 0)
        XCTAssertTrue(summary.personalRecords.isEmpty)
        let card = try XCTUnwrap(PresFix.present(state).card)
        XCTAssertEqual(card.rows.map { $0.isPersonalRecord }, [false])
        XCTAssertNil(card.coachTip, "no tip is made of a set above the cap")
    }

    func testTheTipNeedsASetThatCanBeAnEstimate() throws {
        let underTheCap = PresFix.single(PresFix.lib("bench", best: 99), [(.normal, 70, 12)])
        XCTAssertNotNil(try XCTUnwrap(PresFix.present(underTheCap).card).coachTip)
        let aboveTheCap = PresFix.single(PresFix.lib("bench", best: 99), [(.normal, 70, 13)])
        XCTAssertNil(try XCTUnwrap(PresFix.present(aboveTheCap).card).coachTip)
    }
}

// MARK: - Record marks

final class RecordMarksTests: XCTestCase {
    private func marks(_ tracking: TrackingKind, carriesLoad: Bool = false, _ sets: [(SetType, Double, Int)]) -> RecordMarks {
        var result = RecordMarks()
        for set in sets { result.add(weightKg: set.1, reps: set.2, type: set.0, tracking: tracking, carriesLoad: carriesLoad) }
        return result
    }

    func testAWeightSetRaisesTheHeaviestAndEveryRepRecordUpToItsReps() {
        let result = marks(.weightReps, [(.normal, 100, 5)])
        XCTAssertEqual(result.heaviestKg, 100)
        XCTAssertEqual(result.repRecords, [1: 100, 2: 100, 3: 100, 4: 100, 5: 100], "the heaviest weight lifted for AT LEAST that many reps")
        XCTAssertEqual(result.bestReps, 0)
        XCTAssertEqual(result.bestSeconds, 0)
    }

    func testALighterSetWithMoreRepsRaisesTheHigherKeysOnly() {
        let result = marks(.weightReps, [(.normal, 100, 5), (.normal, 80, 8)])
        XCTAssertEqual(result.repRecords, [1: 100, 2: 100, 3: 100, 4: 100, 5: 100, 6: 80, 7: 80, 8: 80])
        XCTAssertEqual(result.heaviestKg, 100)
    }

    func testRepsAboveTwelveShareTheOpenEndedKey() {
        let result = marks(.weightReps, [(.normal, 60, 20)])
        XCTAssertEqual(Set(result.repRecords.keys), Set(1...13), "keys 1...12 and 13 for \"13 or more\"")
        XCTAssertEqual(RecordMarks.openEndedReps, 13)
        XCTAssertEqual(RecordMarks.bucket(forReps: 12), 12)
        XCTAssertEqual(RecordMarks.bucket(forReps: 13), 13)
        XCTAssertEqual(RecordMarks.bucket(forReps: 999), 13)
        XCTAssertEqual(result.repRecords[13], 60)
    }

    func testWarmUpsAndEmptySetsCountForNothing() {
        XCTAssertTrue(marks(.weightReps, [(.warmup, 200, 5), (.normal, 80, 0), (.normal, 0, 8), (.normal, -5, 8)]).isEmpty)
        XCTAssertTrue(marks(.weightReps, [(.normal, .nan, 5), (.normal, .infinity, 5)]).isEmpty)
        XCTAssertTrue(marks(.duration, [(.warmup, 0, 60), (.normal, 0, 0)]).isEmpty)
    }

    func testDropSetsAndFailureSetsCount() {
        let result = marks(.weightReps, [(.drop, 60, 10), (.failure, 70, 6)])
        XCTAssertEqual(result.heaviestKg, 70)
        XCTAssertEqual(result.repRecords[10], 60)
        XCTAssertEqual(result.repRecords[6], 70)
    }

    func testRepsOnlySetsWithoutALoadRaiseTheMostReps() {
        let result = marks(.repsOnly, [(.normal, 0, 12), (.normal, 0, 15), (.normal, 0, 9)])
        XCTAssertEqual(result.bestReps, 15)
        XCTAssertNil(result.heaviestKg)
        XCTAssertTrue(result.repRecords.isEmpty)
    }

    func testRepsOnlySetsWithALoadRaiseTheLoadMarksWithTheSignedWeight() {
        let result = marks(.repsOnly, [(.normal, 10, 8), (.normal, -20, 12), (.normal, 0, 6)])
        XCTAssertEqual(result.heaviestKg, 10)
        XCTAssertEqual(result.repRecords[8], 10)
        XCTAssertEqual(result.repRecords[12], -20, "an assisted load is a negative weight")
        XCTAssertEqual(result.bestReps, 6, "bodyweight sets still count for the most reps")
    }

    func testBodyweightSetsOfAnExerciseThatCarriesALoadAlsoCountAsALoadOfZero() {
        let result = marks(.repsOnly, carriesLoad: true, [(.normal, -20, 8), (.normal, 0, 12)])
        XCTAssertEqual(result.heaviestKg, 0, "bodyweight is heavier than any assistance")
        XCTAssertEqual(result.repRecords[8], 0)
        XCTAssertEqual(result.repRecords[12], 0)
        XCTAssertEqual(result.bestReps, 12)
    }

    func testAnEntryOfALoadCarryingExerciseKnowsIt() {
        func entry(_ id: String, _ tracking: TrackingKind) -> CompletedExercise {
            CompletedExercise(
                exerciseID: id, name: id, muscle: .back, mediaKey: nil, tracking: tracking,
                sets: [CompletedSet(type: .normal, weightKg: 0, reps: 10)], isPersonalRecord: false, bestE1RM: 0
            )
        }
        XCTAssertTrue(entry("pullup", .repsOnly).carriesLoad)
        XCTAssertTrue(entry("custom-1", .repsOnly).carriesLoad, "a custom reps-only exercise allows an added load")
        XCTAssertFalse(entry("pushup", .repsOnly).carriesLoad)
        XCTAssertFalse(entry("bench", .weightReps).carriesLoad)
        XCTAssertEqual(RecordMarks(entry: entry("pullup", .repsOnly)).heaviestKg, 0)
        XCTAssertNil(RecordMarks(entry: entry("pushup", .repsOnly)).heaviestKg)
    }

    func testTimedSetsRaiseTheLongestHold() {
        XCTAssertEqual(marks(.duration, [(.normal, 0, 45), (.normal, 0, 90), (.normal, 0, 60)]).bestSeconds, 90)
    }

    func testMergingTakesTheHigherOfEveryMark() {
        var a = marks(.weightReps, [(.normal, 100, 5)])
        let b = marks(.weightReps, [(.normal, 90, 8), (.normal, 105, 1)])
        a.merge(b)
        XCTAssertEqual(a.heaviestKg, 105)
        XCTAssertEqual(a.repRecords, [1: 105, 2: 100, 3: 100, 4: 100, 5: 100, 6: 90, 7: 90, 8: 90])
        var empty = RecordMarks()
        empty.merge(a)
        XCTAssertEqual(empty, a)
        a.merge(RecordMarks())
        XCTAssertEqual(a.heaviestKg, 105)
    }

    func testMarksAreMadeFromFinishedEntries() {
        let entry = CompletedExercise(
            exerciseID: "bench", name: "Bench", muscle: .chest, mediaKey: nil, tracking: .weightReps,
            sets: [
                CompletedSet(type: .warmup, weightKg: 50, reps: 8), CompletedSet(type: .normal, weightKg: 80, reps: 6),
                CompletedSet(type: .normal, weightKg: 85, reps: 5),
            ],
            isPersonalRecord: false, bestE1RM: 0
        )
        let result = RecordMarks(entry: entry)
        XCTAssertEqual(result.heaviestKg, 85)
        XCTAssertEqual(result.repRecords, [1: 85, 2: 85, 3: 85, 4: 85, 5: 85, 6: 80])
    }

    // MARK: Coding

    private func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func testTheRepRecordsAreWrittenAsAnObjectKeyedByTheReps() throws {
        let value = RecordMarks(heaviestKg: 100, repRecords: [5: 100, 13: 60], bestReps: 0, bestSeconds: 0)
        XCTAssertEqual(
            try json(value), "{\"bestReps\":0,\"bestSeconds\":0,\"heaviestKg\":100,\"repRecords\":{\"13\":60,\"5\":100}}"
        )
        let decoded = try JSONDecoder().decode(RecordMarks.self, from: Data(try json(value).utf8))
        XCTAssertEqual(decoded, value)
    }

    func testMarksReadWhateverIsMissingOrDamaged() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(RecordMarks.self, from: Data("{}".utf8)), RecordMarks())
        let damaged = "{\"heaviestKg\":80,\"repRecords\":{\"x\":1,\"0\":50,\"-3\":50,\"4\":70}}"
        XCTAssertEqual(try decoder.decode(RecordMarks.self, from: Data(damaged.utf8)), RecordMarks(heaviestKg: 80, repRecords: [4: 70]))
        let wrongType = "{\"repRecords\":[1,2,3],\"bestReps\":4}"
        XCTAssertEqual(try decoder.decode(RecordMarks.self, from: Data(wrongType.utf8)), RecordMarks(bestReps: 4), "derived data: read as not reached")
    }
}

// MARK: - Kinds of record

final class PRKindTests: XCTestCase {
    private let kinds: [PRKind] = [.estimated1RM, .heaviest, .repRecord(reps: 5), .repRecord(reps: 13), .reps, .duration]

    func testEveryKindRoundTripsAsOneString() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for kind in kinds {
            let data = try encoder.encode([kind])
            XCTAssertEqual(try decoder.decode([PRKind].self, from: data), [kind])
        }
        XCTAssertEqual(String(decoding: try encoder.encode([PRKind.estimated1RM, .repRecord(reps: 5), .reps]), as: UTF8.self),
                       "[\"estimated1RM\",\"repRecord:5\",\"reps\"]")
    }

    func testAnUnknownKindIsNotDecodedButTheTypesThatHoldOneReadItAsNone() throws {
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode([PRKind].self, from: Data("[\"fastest\"]".utf8)))
        XCTAssertThrowsError(try decoder.decode([PRKind].self, from: Data("[\"repRecord:0\"]".utf8)))
        XCTAssertThrowsError(try decoder.decode([PRKind].self, from: Data("[\"repRecord:x\"]".utf8)))

        let set = try decoder.decode(CompletedSet.self, from: Data("{\"type\":\"normal\",\"weightKg\":80,\"reps\":5,\"prKind\":\"fastest\"}".utf8))
        XCTAssertNil(set.prKind, "the set loads, without its kind")
        let record = try decoder.decode(
            PersonalRecord.self,
            from: Data("{\"exerciseID\":\"b\",\"exerciseName\":\"B\",\"weightKg\":80,\"reps\":5,\"estimated1RM\":93,\"previousBest\":90,\"kind\":42}".utf8)
        )
        XCTAssertEqual(record.kind, .estimated1RM)
    }

    func testCompletedSetsAndRecordsFromBeforeTheKindsDecode() throws {
        let decoder = JSONDecoder()
        let set = try decoder.decode(CompletedSet.self, from: Data("{\"type\":\"normal\",\"weightKg\":80,\"reps\":5}".utf8))
        XCTAssertEqual(set, CompletedSet(type: .normal, weightKg: 80, reps: 5))
        XCTAssertNil(set.prKind)
        let record = try decoder.decode(
            PersonalRecord.self,
            from: Data("{\"exerciseID\":\"b\",\"exerciseName\":\"B\",\"weightKg\":80,\"reps\":5,\"estimated1RM\":93,\"previousBest\":90}".utf8)
        )
        XCTAssertEqual(record.kind, .estimated1RM, "a record saved before the kinds was an estimated 1RM")
        let kinded = CompletedSet(type: .drop, weightKg: 60, reps: 8, rir: 1, prKind: .repRecord(reps: 8))
        XCTAssertEqual(try decoder.decode(CompletedSet.self, from: try JSONEncoder().encode(kinded)), kinded)
    }

    func testTitles() {
        XCTAssertEqual(kinds.map { $0.shortTitle }, ["Est. 1RM", "Heaviest", "5RM", "13+ reps", "Most reps", "Longest hold"])
        XCTAssertEqual(
            kinds.map { $0.spokenTitle },
            ["estimated one rep max", "heaviest weight", "best 5 rep max", "heaviest weight for 13 or more reps", "most reps in a set", "longest hold"]
        )
    }

    func testTheRankOrdersTheKinds() {
        XCTAssertEqual(kinds.map { $0.rank }, [5, 4, 3, 3, 2, 1])
    }
}

// MARK: - Personal bests

final class PersonalBestMarksTests: XCTestCase {
    private typealias F = SvcDataFix

    func testABestWrittenBeforeTheMarksDecodes() throws {
        let old = "{\"date\":\"2026-10-03T19:30:00.000Z\",\"estimated1RM\":99.17,\"exerciseID\":\"bench\",\"reps\":5,\"weightKg\":85}"
        let decoder = StrengthJSON.makeDecoder()
        let best = try decoder.decode(PersonalBest.self, from: Data(old.utf8))
        XCTAssertEqual(best.estimated1RM, 99.17)
        XCTAssertEqual(best.weightKg, 85)
        XCTAssertEqual(best.reps, 5)
        XCTAssertNil(best.heaviestKg)
        XCTAssertEqual(best.repRecords, [:])
        XCTAssertEqual(best.bestReps, 0)
        XCTAssertEqual(best.bestSeconds, 0)
        XCTAssertTrue(best.marks.isEmpty)
    }

    func testABestRoundTripsWithItsMarks() throws {
        let best = PersonalBest(
            exerciseID: "bench", estimated1RM: 116.5, weightKg: 100, reps: 5, date: F.daysAgo(3),
            heaviestKg: 105, repRecords: [1: 105, 5: 100, 13: 60], bestReps: 0, bestSeconds: 0
        )
        let data = try StrengthJSON.makeEncoder().encode(best)
        XCTAssertEqual(try StrengthJSON.makeDecoder().decode(PersonalBest.self, from: data), best)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"repRecords\":{\"1\":105,\"13\":60,\"5\":100}"), text)
    }

    func testEveryMarkOfABestSurvivesTheRoundTrip() throws {
        let best = PersonalBest(
            exerciseID: "plank", estimated1RM: 0, weightKg: 0, reps: 0, date: F.daysAgo(3),
            heaviestKg: -12.5, repRecords: [4: -12.5], bestReps: 17, bestSeconds: 300
        )
        let decoded = try StrengthJSON.makeDecoder().decode(PersonalBest.self, from: try StrengthJSON.makeEncoder().encode(best))
        XCTAssertEqual(decoded.bestSeconds, 300)
        XCTAssertEqual(decoded.bestReps, 17)
        XCTAssertEqual(decoded.heaviestKg, -12.5)
        XCTAssertEqual(decoded.repRecords, [4: -12.5])
        XCTAssertEqual(decoded, best)
    }

    func testAnEstimateFromMoreThanTwelveRepsIsNoEstimateAnyMore() {
        let inflated = PersonalBest(exerciseID: "bench", estimated1RM: 87, weightKg: 20, reps: 100, date: F.daysAgo(3), heaviestKg: 20)
        let cleaned = inflated.withoutUnreliableEstimate
        XCTAssertEqual(cleaned.estimated1RM, 0)
        XCTAssertEqual(cleaned.weightKg, 0)
        XCTAssertEqual(cleaned.reps, 0)
        XCTAssertEqual(cleaned.heaviestKg, 20, "the marks stay")
        let fine = PersonalBest(exerciseID: "bench", estimated1RM: 100, weightKg: 80, reps: 8, date: F.daysAgo(3))
        XCTAssertEqual(fine.withoutUnreliableEstimate, fine)

        var data = StrengthData()
        data.personalBests["bench"] = inflated
        XCTAssertEqual(data.exercise(id: "bench")?.previousBestE1RM, 0, "the overlay does not take it as the best to beat")
        data.history = [F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(60, 8)], n: 1)])]
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousBestE1RM, 60 * (1 + 8.0 / 30), accuracy: 1e-9)
        // Recording keeps the clean one.
        var recorded = StrengthData()
        recorded.personalBests["bench"] = inflated
        recorded.record(F.workout(2, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(60, 8)], n: 2)]), updateTemplate: nil)
        XCTAssertEqual(try XCTUnwrap(recorded.personalBests["bench"]).estimated1RM, 60 * (1 + 8.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(recorded.personalBests["bench"]?.reps, 8)
    }

    func testTheOverlayCarriesTheMarksOfTheHistoryAndTheStoredBest() throws {
        var data = StrengthData()
        data.history = [
            F.workout(1, finishedAt: F.daysAgo(9), [F.entry("bench", [F.work(100, 3), F.warmup(150, 3)], n: 1)]),
            F.workout(2, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(80, 8)], n: 2)]),
        ]
        var bench = try XCTUnwrap(data.exercise(id: "bench"))
        XCTAssertEqual(bench.previousRecords.heaviestKg, 100)
        XCTAssertEqual(bench.previousRecords.repRecords[3], 100)
        XCTAssertEqual(bench.previousRecords.repRecords[8], 80)
        XCTAssertNil(bench.previousRecords.repRecords[9])
        data.personalBests["bench"] = PersonalBest(exerciseID: "bench", estimated1RM: 0, weightKg: 0, reps: 0, date: F.daysAgo(40), heaviestKg: 120)
        bench = try XCTUnwrap(data.exercise(id: "bench"))
        XCTAssertEqual(bench.previousRecords.heaviestKg, 120, "a stored mark of a workout that cannot be read any more")
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "squat")).previousRecords, RecordMarks(), "an exercise without history has none")
    }

    func testIncrementalRecordingEqualsTheRecomputeForRandomHistories() {
        var rng = RedLCG(seed: 7)
        let ids = ["bench", "pullup", "plank", "squat", "pushup"]
        for run in 0..<40 {
            var incremental = StrengthData()
            var workouts: [CompletedWorkout] = []
            for n in 1...rng.int(3...6) {
                let entries = (0..<rng.int(1...3)).map { k -> CompletedExercise in
                    let id = rng.pick(ids)
                    let library = ExerciseLibrary.exercise(id: id)!
                    let sets = (0..<rng.int(1...4)).map { _ -> CompletedSet in
                        let weight: Double
                        switch library.tracking {
                        case .weightReps: weight = Double(rng.int(20...140)) / (rng.chance(30) ? 2 : 1)
                        case .repsOnly: weight = id == "pullup" ? Double(rng.int(-30...30)) : 0
                        case .duration: weight = 0
                        }
                        let reps = library.tracking == .duration ? rng.int(10...180) : rng.int(0...20)
                        return CompletedSet(type: rng.pick([.normal, .normal, .warmup, .drop, .failure]), weightKg: weight, reps: reps)
                    }
                    return F.entry(id, sets, n: run * 100 + n * 10 + k)
                }
                let workout = F.workout(run * 100 + n, finishedAt: F.daysAgo(Double(rng.int(1...400))), entries)
                workouts.append(workout)
                incremental.record(workout, updateTemplate: nil)
            }
            XCTAssertEqual(incremental.personalBests, incremental.recomputedPersonalBests(), "run \(run)")
            var again = StrengthData(history: workouts)
            again.recomputePersonalBests()
            XCTAssertEqual(again.personalBests, incremental.personalBests, "run \(run): the order of recording does not matter")
        }
    }

    func testRaisingIsTheSameInAnyOrder() {
        let a = PersonalBest(exerciseID: "x", estimated1RM: 100, weightKg: 80, reps: 8, date: F.daysAgo(5), heaviestKg: 80, repRecords: [1: 80, 8: 80])
        let b = PersonalBest(exerciseID: "x", estimated1RM: 100, weightKg: 90, reps: 5, date: F.daysAgo(9), heaviestKg: 90, repRecords: [1: 90, 5: 90])
        let c = PersonalBest(exerciseID: "x", estimated1RM: 0, weightKg: 0, reps: 0, date: F.daysAgo(30), bestReps: 20)
        for order in [[a, b, c], [c, b, a], [b, c, a], [a, c, b]] {
            let result = order.dropFirst().reduce(order[0]) { $0.raised(by: $1) }
            XCTAssertEqual(result.estimated1RM, 100)
            XCTAssertEqual(result.weightKg, 90, "an equal estimate keeps the earlier one")
            XCTAssertEqual(result.date, F.daysAgo(9))
            XCTAssertEqual(result.heaviestKg, 90)
            XCTAssertEqual(result.repRecords, [1: 90, 5: 90, 8: 80])
            XCTAssertEqual(result.bestReps, 20)
        }
    }
}
