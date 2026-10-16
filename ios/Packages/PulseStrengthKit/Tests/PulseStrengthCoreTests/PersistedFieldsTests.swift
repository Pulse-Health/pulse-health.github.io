import Foundation
import XCTest
@testable import PulseStrengthCore

// The additive persisted fields of widgets/SPEC.md section 2: `LoggedSet.doneAt`, `CompletedSet.loggedAt`,
// `WorkoutState.heartRateSeries` and `CompletedWorkout.heartRateSeries`.

// MARK: - LoggedSet.doneAt (reducer)

final class SetDoneTimeTests: XCTestCase {
    private func doneAt(_ s: WorkoutState, _ k: Int, _ i: Int) -> Date? { s.exercises[k].sets[i].doneAt }

    func testLogNextSetStampsTheSetWithTheReducersNow() {
        let s = RFix.reduced(RFix.designState(), .logNextSet, at: 100)
        XCTAssertTrue(s.exercises[0].sets[0].isDone)
        XCTAssertEqual(doneAt(s, 0, 0), RFix.at(100))
        XCTAssertNil(doneAt(s, 0, 1), "a pending set has no time")
    }

    func testLogSetStampsTheNamedSet() {
        let start = RFix.designState()
        let s = RFix.reduced(start, RFix.log(start, 1, 2), at: 250)
        XCTAssertEqual(doneAt(s, 1, 2), RFix.at(250))
        XCTAssertNil(doneAt(s, 0, 0))
    }

    func testToggleSetStampsAPendingSetAndClearsALoggedOne() {
        var s = RFix.designState()
        let toggle = RFix.toggle(s, 0, 2)
        s = RFix.reduced(s, toggle, at: 10)
        XCTAssertTrue(s.exercises[0].sets[2].isDone)
        XCTAssertEqual(doneAt(s, 0, 2), RFix.at(10))
        s = RFix.reduced(s, .setRIR(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 2), rir: 2), at: 15)
        s = RFix.reduced(s, toggle, at: 20)
        XCTAssertFalse(s.exercises[0].sets[2].isDone)
        XCTAssertNil(doneAt(s, 0, 2), "a set that is pending again has no time")
        XCTAssertEqual(s.exercises[0].sets[2].rir, 2, "the RIR is kept, as before")
    }

    func testLoggingASetAgainAfterTogglingItBackStampsTheNewTime() {
        var s = RFix.designState()
        let toggle = RFix.toggle(s, 0, 3)
        s = RFix.reduced(s, toggle, at: 10)
        s = RFix.reduced(s, toggle, at: 20)
        s = RFix.reduced(s, toggle, at: 30)
        XCTAssertEqual(doneAt(s, 0, 3), RFix.at(30))
    }

    func testLoggingASetThatIsAlreadyLoggedKeepsTheFirstTime() {
        let start = RFix.designState()
        let once = RFix.reduced(start, RFix.log(start, 0, 2), at: 10)
        let twice = RFix.reduced(once, RFix.log(start, 0, 2), at: 99)
        XCTAssertEqual(twice, once, "logSet on a logged set is a no-op")
        XCTAssertEqual(doneAt(twice, 0, 2), RFix.at(10))
    }

    func testEverySetTypeIsStamped() {
        for type in SetType.allCases {
            var s = RFix.designState()
            s = RFix.reduced(s, .setSetType(exerciseID: RFix.ex(s, 1), setID: RFix.setID(s, 1, 0), type: type), at: 1)
            s = RFix.reduced(s, RFix.log(s, 1, 0), at: 5)
            XCTAssertEqual(doneAt(s, 1, 0), RFix.at(5), "\(type)")
        }
    }

    func testOtherEditsLeaveTheTimeAlone() {
        var s = RFix.reduced(RFix.designState(), .logNextSet, at: 100)
        let exerciseID = RFix.ex(s, 0)
        let setID = RFix.setID(s, 0, 0)
        let edits: [WorkoutAction] = [
            .setWeight(exerciseID: exerciseID, setID: setID, kg: 52.5), .setReps(exerciseID: exerciseID, setID: setID, reps: 9),
            .setRIR(exerciseID: exerciseID, setID: setID, rir: 3), .toggleLastSetRIR(2),
            .setSetType(exerciseID: exerciseID, setID: setID, type: .drop), .setNote(exerciseID: exerciseID, note: "easy"),
            .nudgeNextSet(weightSteps: 1, repsSteps: 1), .adjustRest(seconds: 15), .pause, .resume, .skipRest, .goTo(index: 2),
            .addSet(exerciseID: exerciseID), .setRest(exerciseID: exerciseID, seconds: 90), .updateHeartRate(120), .rename("Push"),
        ]
        for (offset, action) in edits.enumerated() {
            s = RFix.reduced(s, action, at: 200 + Double(offset))
            XCTAssertEqual(doneAt(s, 0, 0), RFix.at(100), "\(action)")
        }
    }

    func testADeletedSetComesBackWithItsTimeWhenTheDeletionIsUndone() {
        var s = RFix.reduced(RFix.designState(), .logNextSet, at: 100)
        let logged = s.exercises[0].sets[0]
        s = RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 0), setID: logged.id), at: 110)
        XCTAssertEqual(s.exercises[0].sets.count, 4)
        s = RFix.reduced(s, .undo, at: 112)
        XCTAssertEqual(s.exercises[0].sets[0], logged)
        XCTAssertEqual(doneAt(s, 0, 0), RFix.at(100))
    }

    func testARemovedExerciseComesBackWithTheTimesOfItsSets() {
        var s = RFix.designState()
        s = RFix.reduced(s, [.logNextSet, .logNextSet], start: 100)
        let bench = s.exercises[0]
        s = RFix.reduced(s, .removeExercise(exerciseID: bench.id), at: 120)
        s = RFix.reduced(s, .undo, at: 122)
        XCTAssertEqual(s.exercises[0], bench)
        XCTAssertEqual(s.exercises[0].sets.prefix(2).map { $0.doneAt }, [RFix.at(100), RFix.at(101)])
    }

    func testSupersetMembersAreStampedWhenTheyAreLogged() {
        var s = RFix.reduced(RFix.designState(), .goTo(index: 3))
        s = RFix.reduced(s, .logNextSet, at: 100)          // lateral raise, the superset moves on to the pushdown
        s = RFix.reduced(s, .logNextSet, at: 105)
        XCTAssertEqual(doneAt(s, 3, 0), RFix.at(100))
        XCTAssertEqual(doneAt(s, 4, 0), RFix.at(105))
    }

    func testReplacingAnExerciseStartsItsSetsWithoutTimes() {
        var s = RFix.reduced(RFix.designState(), .logNextSet, at: 100)
        s = RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 0), with: RFix.incline), at: 110)
        XCTAssertTrue(s.exercises[0].sets.allSatisfy { !$0.isDone && $0.doneAt == nil })
    }

    func testAnAddedSetStartsWithoutATime() {
        var s = RFix.designState()
        s = RFix.reduced(s, [.goTo(index: 1), .logNextSet, .logNextSet, .logNextSet], start: 10)
        s = RFix.reduced(s, .addSet(exerciseID: RFix.ex(s, 1)), at: 40)
        let added = s.exercises[1].sets[3]
        XCTAssertFalse(added.isDone)
        XCTAssertNil(added.doneAt)
    }

    func testEachLoggedSetStillBumpsTheRevisionOnce() {
        var s = RFix.designState()
        s.revision = 5
        let toggle = RFix.toggle(s, 0, 2)
        s = RFix.reduced(s, toggle, at: 1)
        XCTAssertEqual(s.revision, 6)
        s = RFix.reduced(s, toggle, at: 2)
        XCTAssertEqual(s.revision, 7)
        s = RFix.reduced(s, .logNextSet, at: 3)
        XCTAssertEqual(s.revision, 8)
    }
}

// MARK: - WorkoutState.heartRateSeries (reducer)

final class HeartRateSeriesTests: XCTestCase {
    /// `s` after one `updateHeartRate` per entry of `samples`, each at `t0 + seconds`.
    private func feed(_ samples: [(Double, Int?)], on state: WorkoutState = RFix.designState()) -> WorkoutState {
        var copy = state
        for (seconds, bpm) in samples { WorkoutReducer.reduce(&copy, .updateHeartRate(bpm), now: RFix.at(seconds)) }
        return copy
    }

    func testTheFirstSampleIsKeptWithTheReducersNow() {
        let s = feed([(5, 120)])
        XCTAssertEqual(s.heartRateSeries, [HeartRateSample(bpm: 120, at: RFix.at(5))])
    }

    func testASampleLessThanThirtySecondsAfterTheLastKeptOneIsNotKept() {
        let s = feed([(0, 120), (29.9, 130)])
        XCTAssertEqual(s.heartRateSeries, [HeartRateSample(bpm: 120, at: RFix.at(0))])
        XCTAssertEqual(s.heartRate, 130, "the current heart rate follows every sample")
        XCTAssertEqual(s.heartRateSum, 250)
        XCTAssertEqual(s.heartRateCount, 2, "so does the average")
    }

    func testASampleExactlyThirtySecondsAfterTheLastKeptOneIsKept() {
        let s = feed([(0, 120), (30, 130)])
        XCTAssertEqual(s.heartRateSeries.map { $0.bpm }, [120, 130])
        XCTAssertEqual(s.heartRateSeries.last?.at, RFix.at(30))
    }

    func testTheSpacingCountsFromTheLastKeptSampleNotFromTheLastReceivedOne() {
        let s = feed([(0, 100), (20, 110), (40, 120), (60, 130), (70, 140)])
        XCTAssertEqual(s.heartRateSeries, [
            HeartRateSample(bpm: 100, at: RFix.at(0)), HeartRateSample(bpm: 120, at: RFix.at(40)), HeartRateSample(bpm: 140, at: RFix.at(70)),
        ])
        XCTAssertEqual(s.heartRateCount, 5)
    }

    func testTheSeriesStopsAtThreeHundredSixtySamplesButTheAverageKeepsCounting() {
        XCTAssertEqual(WorkoutReducer.maximumHeartRateSamples, 360)
        XCTAssertEqual(WorkoutReducer.heartRateSampleInterval, 30)
        let samples = (0..<400).map { (Double($0) * 30, Optional(100 + $0 % 50)) }
        let s = feed(samples)
        XCTAssertEqual(s.heartRateSeries.count, 360)
        XCTAssertEqual(s.heartRateSeries.last?.at, RFix.at(359 * 30), "the series keeps the start of the workout")
        XCTAssertEqual(s.heartRateSeries.map { $0.bpm }, samples.prefix(360).map { $0.1! })
        XCTAssertEqual(s.heartRateCount, 400)
        XCTAssertEqual(s.heartRateSum, samples.reduce(0) { $0 + $1.1! })
    }

    func testSamplesOutsideThirtyToTwoHundredFortyAreNeverKeptAndDoNotUseUpTheSpacing() {
        let s = feed([(0, 29), (10, 241), (20, 0), (30, nil), (40, 120)])
        XCTAssertEqual(s.heartRateSeries, [HeartRateSample(bpm: 120, at: RFix.at(40))])
        XCTAssertEqual(s.heartRate, 120)
        XCTAssertEqual(s.heartRateCount, 1)
        XCTAssertEqual(feed([(0, 30), (30, 240)]).heartRateSeries.map { $0.bpm }, [30, 240], "both ends of the range are valid")
    }

    func testASampleNeverBumpsTheRevision() {
        var s = RFix.designState()
        s.revision = 7
        s = feed([(0, 120), (40, 125)], on: s)
        XCTAssertEqual(s.heartRateSeries.count, 2)
        XCTAssertEqual(s.revision, 7)
        s = RFix.reduced(s, .rename("x"), at: 50)
        XCTAssertEqual(s.revision, 8, "the next real change bumps by exactly one")
    }

    func testAClockThatMovedBackKeepsNothingUntilItPassesTheLastSampleByThirtySeconds() {
        let s = feed([(100, 120), (50, 121), (129.9, 122), (130, 123)])
        XCTAssertEqual(s.heartRateSeries.map { $0.bpm }, [120, 123])
    }

    func testOtherActionsLeaveTheSeriesAlone() {
        var s = feed([(0, 120), (40, 125)])
        let series = s.heartRateSeries
        s = RFix.reduced(s, [.logNextSet, .logNextSet, .pause, .resume, .adjustRest(seconds: 15), .rename("Push"), .undo], start: 100)
        XCTAssertEqual(s.heartRateSeries, series)
    }

    func testTheSeriesIsKeptForAnEmptyWorkoutToo() {
        let empty = WorkoutState(name: "Empty", startedAt: RFix.t0)
        XCTAssertEqual(feed([(3, 90)], on: empty).heartRateSeries, [HeartRateSample(bpm: 90, at: RFix.at(3))])
    }
}

// MARK: - The summary carries both

final class LoggedTimesInTheSummaryTests: XCTestCase {
    private func build(_ state: WorkoutState) -> CompletedWorkout {
        SummaryBuilder.build(from: state, finishedAt: RFix.at(900))
    }

    func testEveryLoggedSetCarriesTheTimeItWasLogged() {
        let s = RFix.reduced(RFix.designState(), [.logNextSet, .logNextSet, .logNextSet], start: 100)
        let summary = build(s)
        XCTAssertEqual(summary.exercises[0].sets.map { $0.loggedAt }, [RFix.at(100), RFix.at(101), RFix.at(102)])
    }

    func testASetThatIsPendingAgainIsLeftOutAndNoStaleTimeSurvives() {
        var s = RFix.reduced(RFix.designState(), [.logNextSet, .logNextSet], start: 100)
        s = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 110)
        let sets = build(s).exercises[0].sets
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0].loggedAt, RFix.at(101))
    }

    func testALoggedSetWithoutATimeGivesNoLoggedAt() {
        var s = RFix.designState()
        s.exercises[0].sets[0].isDone = true          // a workout restored from a file written before the time was recorded
        XCTAssertNil(build(s).exercises[0].sets[0].loggedAt)
    }

    func testTheHeartRateSeriesGoesToTheFinishedWorkout() {
        var s = RFix.designState()
        for (seconds, bpm) in [(0.0, 100), (35.0, 120), (70.0, 140)] {
            WorkoutReducer.reduce(&s, .updateHeartRate(bpm), now: RFix.at(seconds))
        }
        s = RFix.reduced(s, .logNextSet, at: 80)
        let summary = build(s)
        XCTAssertEqual(summary.heartRateSeries, s.heartRateSeries)
        XCTAssertEqual(summary.heartRateSeries?.map { $0.bpm }, [100, 120, 140])
        XCTAssertEqual(summary.averageHeartRate, 120)
    }

    func testNoSamplesGiveNilNotAnEmptyList() {
        let s = RFix.reduced(RFix.designState(), .logNextSet, at: 100)
        XCTAssertNil(build(s).heartRateSeries)
    }
}

// MARK: - Files and payloads written before the fields existed

final class PersistedFieldsCodingTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_791_919_800)

    private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: StrengthJSON.makeEncoder().encode(value)) as? [String: Any])
    }

    /// `value` without the given keys at any depth.
    private func removing(_ keys: Set<String>, from value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.filter { !keys.contains($0.key) }.mapValues { removing(keys, from: $0) }
        }
        if let array = value as? [Any] { return array.map { removing(keys, from: $0) } }
        return value
    }

    private func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        try StrengthJSON.makeDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    private func withoutTimes(_ state: WorkoutState) -> WorkoutState {
        var copy = state
        for k in copy.exercises.indices { for i in copy.exercises[k].sets.indices { copy.exercises[k].sets[i].doneAt = nil } }
        return copy
    }

    // MARK: Legacy JSON

    func testALoggedSetWrittenWithoutDoneAtDecodes() throws {
        let json = #"{"id":"00000000-0000-4000-8000-000000000001","type":"normal","weightKg":80,"reps":6,"isDone":true,"rir":2}"#
        let set = try StrengthJSON.makeDecoder().decode(LoggedSet.self, from: Data(json.utf8))
        XCTAssertEqual(set.weightKg, 80)
        XCTAssertTrue(set.isDone)
        XCTAssertEqual(set.rir, 2)
        XCTAssertNil(set.doneAt)
    }

    func testACompletedSetWrittenWithoutLoggedAtDecodes() throws {
        let json = #"{"type":"warmup","weightKg":50,"reps":8}"#
        let set = try StrengthJSON.makeDecoder().decode(CompletedSet.self, from: Data(json.utf8))
        XCTAssertEqual(set, CompletedSet(type: .warmup, weightKg: 50, reps: 8))
        XCTAssertNil(set.loggedAt)
    }

    func testAWorkoutStateWrittenWithoutASeriesDecodesWithAnEmptyOne() throws {
        var state = RFix.reduced(RFix.designState(), [.logNextSet, .logNextSet], start: 100)
        WorkoutReducer.reduce(&state, .updateHeartRate(130), now: RFix.at(120))
        XCTAssertEqual(state.heartRateSeries.count, 1)
        let legacy = removing(["heartRateSeries", "doneAt"], from: try object(state))
        let decoded = try decode(WorkoutState.self, from: legacy)
        var expected = withoutTimes(state)
        expected.heartRateSeries = []
        XCTAssertEqual(decoded, expected)
        XCTAssertTrue(decoded.heartRateSeries.isEmpty)
    }

    func testAWorkoutStateStillNeedsTheKeysItAlwaysNeeded() throws {
        let state = RFix.designState()
        for key in ["id", "name", "exercises", "templateBaseline", "settings", "revision", "heartRateSum", "startedAt"] {
            let broken = removing([key], from: try object(state))
            XCTAssertThrowsError(try decode(WorkoutState.self, from: broken), "without \(key)")
        }
    }

    func testACompletedWorkoutWrittenWithoutTheNewKeysDecodes() throws {
        var completed = SampleData.history(now: moment)[0]
        completed.exercises[0].sets[0].loggedAt = moment
        completed.heartRateSeries = [HeartRateSample(bpm: 120, at: moment)]
        let legacy = removing(["heartRateSeries", "loggedAt"], from: try object(completed))
        let decoded = try decode(CompletedWorkout.self, from: legacy)
        XCTAssertNil(decoded.heartRateSeries)
        XCTAssertTrue(decoded.exercises.allSatisfy { $0.sets.allSatisfy { $0.loggedAt == nil } })
        XCTAssertEqual(decoded.id, completed.id)
        XCTAssertEqual(decoded.exercises.map { $0.sets.count }, completed.exercises.map { $0.sets.count })
    }

    // MARK: Round trips and the shape on disk

    func testTheNewFieldsRoundTrip() throws {
        var state = RFix.reduced(RFix.designState(), [.logNextSet, .logNextSet], start: 100)
        WorkoutReducer.reduce(&state, .updateHeartRate(130), now: RFix.at(120))
        let decodedState = try StrengthJSON.makeDecoder().decode(WorkoutState.self, from: StrengthJSON.makeEncoder().encode(state))
        XCTAssertEqual(decodedState, state)
        XCTAssertEqual(decodedState.exercises[0].sets[1].doneAt, RFix.at(101))

        let completed = SummaryBuilder.build(from: state, finishedAt: RFix.at(300))
        let decodedCompleted = try StrengthJSON.makeDecoder().decode(CompletedWorkout.self, from: StrengthJSON.makeEncoder().encode(completed))
        XCTAssertEqual(decodedCompleted, completed)
        XCTAssertEqual(decodedCompleted.exercises[0].sets.map { $0.loggedAt }, [RFix.at(100), RFix.at(101)])
        XCTAssertEqual(decodedCompleted.heartRateSeries, state.heartRateSeries)
    }

    func testAnUnsetTimeAndAMissingSeriesWriteNoKeysSoOldFilesStayTheSame() throws {
        XCTAssertNil(try object(LoggedSet(weightKg: 50, reps: 8))["doneAt"])
        XCTAssertNotNil(try object(LoggedSet(weightKg: 50, reps: 8, isDone: true, doneAt: moment))["doneAt"])
        XCTAssertNil(try object(CompletedSet(type: .normal, weightKg: 50, reps: 8))["loggedAt"])
        XCTAssertNotNil(try object(CompletedSet(type: .normal, weightKg: 50, reps: 8, loggedAt: moment))["loggedAt"])
        var completed = SampleData.history(now: moment)[0]
        XCTAssertNil(try object(completed)["heartRateSeries"])
        completed.heartRateSeries = [HeartRateSample(bpm: 120, at: moment)]
        XCTAssertNotNil(try object(completed)["heartRateSeries"])
    }

    func testTheFilesOnDiskKeepTheNewFields() throws {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        var state = RFix.reduced(RFix.designState(), [.logNextSet, .logNextSet], start: 100)
        WorkoutReducer.reduce(&state, .updateHeartRate(130), now: RFix.at(120))
        try persistence.saveActiveWorkout(state)
        XCTAssertEqual(persistence.loadActiveWorkout(), state)

        let completed = SummaryBuilder.build(from: state, finishedAt: RFix.at(300))
        try persistence.saveHistory([completed])
        XCTAssertEqual(persistence.loadHistory(), [completed])
        XCTAssertEqual(persistence.loadHistory().first?.exercises.first?.sets.first?.loggedAt, RFix.at(100))
    }

    // MARK: Sync payloads

    func testTheSeriesTravelsInTheEnvelopeAndAnOlderEnvelopeStillDecodes() throws {
        var state = RFix.reduced(RFix.designState(), .logNextSet, at: 100)
        WorkoutReducer.reduce(&state, .updateHeartRate(130), now: RFix.at(120))
        let envelope = SyncEnvelope(state: state, endedWorkoutID: nil, sentAt: RFix.at(121))
        XCTAssertEqual(try SyncCodec.decode(SyncCodec.encode(.state(envelope))), .state(envelope))

        let payload = try SyncCodec.encode(.state(envelope))
        let data = try XCTUnwrap(payload[SyncCodec.payloadKey] as? Data)
        let legacy = removing(["heartRateSeries", "doneAt"], from: try XCTUnwrap(JSONSerialization.jsonObject(with: data)))
        let decoded = try SyncCodec.decode([SyncCodec.payloadKey: try JSONSerialization.data(withJSONObject: legacy)])
        guard case let .state(older) = decoded else { return XCTFail("not a state") }
        XCTAssertEqual(older.state?.heartRateSeries, [])
        XCTAssertNil(older.state?.exercises[0].sets[0].doneAt)
        XCTAssertEqual(older.state?.revision, state.revision)
    }
}

// MARK: - Phone and Watch

final class PersistedFieldsSyncTests: XCTestCase {
    /// The Watch showed the set as logged from the tap; the phone must stamp it at the tap as well, not when the command arrives.
    func testALateCommandStampsTheSetWithTheTimeOfTheTap() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let tapAt = link.watch.clock.now
            link.tap(link.logSet(0, 2))
            XCTAssertEqual(link.watch.state?.exercises[0].sets[2].doneAt, tapAt)
            link.advance(40)
            try link.deliverCommand()
            XCTAssertEqual(link.phone.state?.exercises[0].sets[2].doneAt, tapAt)
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state, "so the acknowledgement does not move the Watch's copy")
        }
    }

    func testACommandMuchOlderThanTheWindowStampsTheSetAtDeliveryTime() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 2))
            link.advance(SyncReconciler.lateCommandWindow + 30)
            let delivered = link.phone.clock.now
            try link.deliverCommand()
            XCTAssertEqual(link.phone.state?.exercises[0].sets[2].doneAt, delivered)
        }
    }

    /// The Watch's own heart rate is not thrown away with an expired edit, and neither is the series that goes with it.
    func testExpiringKeepsTheWatchsHeartRateSeries() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.toPhone.removeAll()
            link.watch.engine.send(.updateHeartRate(141), origin: .system)
            link.advance(16)
            XCTAssertTrue(link.watch.engine.expirePending())
            XCTAssertEqual(link.watch.state?.heartRate, 141)
            XCTAssertEqual(link.watch.state?.heartRateSeries.map { $0.bpm }, [141])
        }
    }
}
