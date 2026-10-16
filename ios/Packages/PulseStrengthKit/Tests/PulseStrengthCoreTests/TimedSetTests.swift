import XCTest
@testable import PulseStrengthCore

// MARK: - The reducer

final class TimedSetReducerTests: XCTestCase {
    /// A workout of two plank entries (3 sets of 45 s, rest 45 s; 2 sets of 30 s, rest 30 s), a bench and a push-up.
    private func workout() -> WorkoutState {
        RFix.state([
            RFix.entry(1, RFix.plank, RFix.normal(3, 0, 45), rest: 45),
            RFix.entry(2, RFix.plank, RFix.normal(2, 0, 30), rest: 30),
            RFix.entry(3, RFix.bench, RFix.normal(2, 80, 5), rest: 150),
            RFix.entry(4, RFix.pushup, RFix.normal(2, 0, 12), rest: 60),
        ])
    }

    private func ref(_ s: WorkoutState, _ k: Int, _ i: Int) -> SetRef { SetRef(exerciseID: RFix.ex(s, k), setID: RFix.setID(s, k, i)) }

    private func start(_ s: WorkoutState, _ k: Int = 0, _ i: Int = 0, at seconds: Double = 0) -> WorkoutState {
        RFix.reduced(s, .startTimedSet(ref(s, k, i)), at: seconds)
    }

    // MARK: Start

    func testStartingATimedSetRecordsTheStartAndTheTarget() {
        let s = workout()
        let timed = start(s, 1, 0, at: 5)
        XCTAssertEqual(timed.timedSet, TimedSetState(setRef: ref(s, 1, 0), startedAt: RFix.at(5), targetSeconds: 30))
        XCTAssertEqual(timed.currentIndex, 1, "the exercise of the set becomes current")
        XCTAssertEqual(timed.revision, 1)
        XCTAssertFalse(timed.exercises[1].sets[0].isDone)
    }

    func testStartingEndsARunningRest() {
        var s = workout()
        s.rest = RestState(endsAt: RFix.at(100), totalSeconds: 60)
        XCTAssertNil(start(s).rest)
    }

    func testOnlyAPendingSetOfATimedExerciseCanBeStarted() {
        let s = workout()
        XCTAssertEqual(start(s, 2, 0), s, "a bench set is not timed")
        XCTAssertEqual(start(s, 3, 0), s, "nor a push-up")
        var done = s
        done.exercises[0].sets[0].isDone = true
        XCTAssertEqual(RFix.reduced(done, .startTimedSet(ref(done, 0, 0))), done, "a logged set cannot be timed again")
        let ghost = SetRef(exerciseID: RFix.uuid(0xDEAD, 1), setID: RFix.uuid(0xDEAD, 2))
        XCTAssertEqual(RFix.reduced(s, .startTimedSet(ghost)), s)
        XCTAssertEqual(RFix.reduced(s, .startTimedSet(SetRef(exerciseID: RFix.ex(s, 0), setID: ghost.setID))), s)
        XCTAssertEqual(RFix.reduced(s, .startTimedSet(SetRef(exerciseID: ghost.exerciseID, setID: RFix.setID(s, 0, 0)))), s)
    }

    func testASecondTimedSetCannotStartWhileOneRuns() {
        let first = start(workout())
        let second = RFix.reduced(first, .startTimedSet(ref(first, 1, 0)), at: 10)
        XCTAssertEqual(second, first, "nothing changes, not even the revision")
        XCTAssertEqual(RFix.reduced(first, .startTimedSet(ref(first, 0, 0)), at: 10), first, "nor does the same set restart")
    }

    func testStartingWhilePausedStartsFrozen() {
        var s = RFix.reduced(workout(), .pause, at: 3)
        s = RFix.reduced(s, .startTimedSet(ref(s, 0, 0)), at: 8)
        XCTAssertEqual(s.timedSet?.frozenElapsed, 0)
        s = RFix.reduced(s, .resume, at: 20)
        XCTAssertNil(s.timedSet?.frozenElapsed)
        XCTAssertEqual(s.timedSet?.startedAt, RFix.at(20), "the timer starts when the workout resumes")
    }

    // MARK: Stop

    func testStoppingLogsTheSecondsAndStartsTheRest() {
        var s = start(workout())
        s = RFix.reduced(s, .stopTimedSet, at: 30.9)
        let set = s.exercises[0].sets[0]
        XCTAssertTrue(set.isDone)
        XCTAssertEqual(set.reps, 30, "whole seconds, rounded down")
        XCTAssertNil(s.timedSet)
        XCTAssertEqual(s.lastLogged, ref(s, 0, 0))
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(30.9 + 45), totalSeconds: 45), "the rest of the exercise, as after logSet")
    }

    func testStoppingFollowsTheRestRulesOfTheSetType() {
        var s = start(workout())
        s.exercises[0].sets[0].type = .warmup
        s = RFix.reduced(s, .stopTimedSet, at: 20)
        XCTAssertEqual(s.rest?.totalSeconds, 30, "a warm-up rests 40 % of 45 s, at least 30 s")

        var drops = start(workout())
        drops.exercises[0].sets[0].type = .drop
        drops.exercises[0].sets[1].type = .drop
        drops = RFix.reduced(drops, .stopTimedSet, at: 20)
        XCTAssertNil(drops.rest, "a drop set that another drop set follows rests for nothing")
    }

    func testStoppingInASupersetAdvancesToTheNextMemberWithoutRest() {
        var s = RFix.state([
            RFix.entry(1, RFix.plank, RFix.normal(2, 0, 45), rest: 45, group: "A"),
            RFix.entry(2, RFix.pushup, RFix.normal(2, 0, 12), rest: 45, group: "A"),
        ])
        s = RFix.reduced(s, .startTimedSet(ref(s, 0, 0)), at: 0)
        s = RFix.reduced(s, .stopTimedSet, at: 40)
        XCTAssertEqual(s.currentIndex, 1)
        XCTAssertNil(s.rest)
        XCTAssertEqual(s.exercises[0].sets[0].reps, 40)
    }

    func testTheSecondsAreClampedToThreeHours() {
        var s = start(workout())
        s = RFix.reduced(s, .stopTimedSet, at: 50_000)
        XCTAssertEqual(s.exercises[0].sets[0].reps, 10_800)
        XCTAssertEqual(WorkoutReducer.maximumDurationSeconds, 10_800)
    }

    func testAClockThatMovedBackwardsLogsZeroSeconds() {
        var s = start(workout(), 0, 0, at: 100)
        s = RFix.reduced(s, .stopTimedSet, at: 40)
        XCTAssertEqual(s.exercises[0].sets[0].reps, 0)
        XCTAssertTrue(s.exercises[0].sets[0].isDone)
    }

    func testStoppingWithoutATimerChangesNothing() {
        let s = workout()
        XCTAssertEqual(RFix.reduced(s, .stopTimedSet), s)
        XCTAssertEqual(RFix.reduced(s, .cancelTimedSet), s)
    }

    func testATimerWhoseSetIsGoneJustEnds() {
        var s = start(workout())
        s.exercises[0].sets.removeAll()
        let stopped = RFix.reduced(s, .stopTimedSet, at: 20)
        XCTAssertNil(stopped.timedSet)
        XCTAssertNil(stopped.lastLogged)
        var logged = start(workout())
        logged.exercises[0].sets[0].isDone = true
        let ended = RFix.reduced(logged, .stopTimedSet, at: 20)
        XCTAssertNil(ended.timedSet)
        XCTAssertEqual(ended.exercises[0].sets[0].reps, 45, "an already logged set keeps its seconds")
        XCTAssertNil(ended.rest)
    }

    // MARK: Cancel and the other ways a timer ends

    func testCancelDropsTheTimerAndLogsNothing() {
        let s = start(workout())
        let cancelled = RFix.reduced(s, .cancelTimedSet, at: 20)
        XCTAssertNil(cancelled.timedSet)
        XCTAssertEqual(cancelled.exercises, s.exercises)
        XCTAssertNil(cancelled.lastLogged)
        XCTAssertNil(cancelled.rest)
        XCTAssertEqual(cancelled.revision, s.revision + 1)
    }

    func testLoggingTheTimedSetByHandEndsTheTimer() {
        let s = start(workout())
        let logged = RFix.reduced(s, RFix.log(s, 0, 0), at: 12)
        XCTAssertNil(logged.timedSet)
        XCTAssertEqual(logged.exercises[0].sets[0].reps, 45, "logSet keeps the planned seconds")
        XCTAssertEqual(logged.rest?.totalSeconds, 45)
        let toggled = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 12)
        XCTAssertNil(toggled.timedSet)
        let next = RFix.reduced(s, .logNextSet, at: 12)
        XCTAssertNil(next.timedSet, "the next pending set is the timed one")
    }

    func testDeletingTheSetTheExerciseOrReplacingItEndsTheTimer() {
        let s = start(workout())
        XCTAssertNil(RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 0))).timedSet)
        XCTAssertNil(RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 0))).timedSet)
        XCTAssertNil(RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 0), with: RFix.pushup)).timedSet)
        // another set or exercise is no reason to end it
        XCTAssertNotNil(RFix.reduced(s, .deleteSet(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 1))).timedSet)
        XCTAssertNotNil(RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 1))).timedSet)
        XCTAssertNotNil(RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 2), with: RFix.squat)).timedSet)
        XCTAssertNotNil(RFix.reduced(s, .nextExercise).timedSet, "moving to another exercise leaves the timer running")
    }

    // MARK: Rest

    func testNoRestStartsWhileATimedSetRuns() {
        var s = start(workout())
        s = RFix.reduced(s, RFix.log(s, 2, 0), at: 10)             // a bench set is logged meanwhile
        XCTAssertNil(s.rest, "no rest, even though the bench has one")
        XCTAssertNotNil(s.timedSet)
        XCTAssertNotNil(s.lastLogged)
        s = RFix.reduced(s, .adjustRest(seconds: 30), at: 11)
        XCTAssertNil(s.rest, "a rest cannot be started by hand either")
        s = RFix.reduced(s, .stopTimedSet, at: 20)
        XCTAssertEqual(s.rest?.totalSeconds, 45, "after the timer the rest follows")
    }

    // MARK: Pause and resume

    func testPauseFreezesTheElapsedTimeAndResumeContinuesIt() {
        var s = start(workout(), at: 0)
        s = RFix.reduced(s, .pause, at: 10)
        XCTAssertEqual(s.timedSet?.frozenElapsed, 10)
        XCTAssertEqual(s.timedSet?.elapsed(now: RFix.at(500)), 10)
        s = RFix.reduced(s, .resume, at: 50)
        XCTAssertNil(s.timedSet?.frozenElapsed)
        XCTAssertEqual(s.timedSet?.startedAt, RFix.at(40))
        XCTAssertEqual(s.timedSet?.elapsed(now: RFix.at(60)), 20)
        let stopped = RFix.reduced(s, .stopTimedSet, at: 60)
        XCTAssertEqual(stopped.exercises[0].sets[0].reps, 20)
    }

    func testStoppingWhilePausedLogsTheFrozenTime() {
        var s = start(workout(), at: 0)
        s = RFix.reduced(s, .pause, at: 12)
        s = RFix.reduced(s, .stopTimedSet, at: 400)
        XCTAssertEqual(s.exercises[0].sets[0].reps, 12)
        XCTAssertEqual(s.rest?.frozenRemaining, 45, "a rest that starts while paused is frozen")
    }

    func testPausingTwiceKeepsTheFirstFreeze() {
        var s = start(workout(), at: 0)
        s = RFix.reduced(s, .pause, at: 10)
        let again = RFix.reduced(s, .pause, at: 30)
        XCTAssertEqual(again, s)
    }

    // MARK: Editing while it runs

    func testEditingTheSecondsOfTheRunningSetMovesTheTarget() {
        var s = start(workout())
        s = RFix.reduced(s, .setReps(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 0), reps: 60), at: 5)
        XCTAssertEqual(s.timedSet?.targetSeconds, 60)
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: 0, repsSteps: 2), at: 6)
        XCTAssertEqual(s.exercises[0].sets[0].reps, 70, "5 s per step")
        XCTAssertEqual(s.timedSet?.targetSeconds, 70)
        let other = RFix.reduced(s, .setReps(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 1), reps: 99), at: 7)
        XCTAssertEqual(other.timedSet?.targetSeconds, 70, "another set leaves the target alone")
    }

    func testTheSecondsOfATimedSetGoUpToThreeHoursOtherRepsStayAt999() {
        let s = workout()
        let long = RFix.reduced(s, .setReps(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 0), reps: 20_000))
        XCTAssertEqual(long.exercises[0].sets[0].reps, 10_800)
        let exact = RFix.reduced(s, .setReps(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 0), reps: 3_600))
        XCTAssertEqual(exact.exercises[0].sets[0].reps, 3_600, "an hour no longer clamps at 999")
        let bench = RFix.reduced(s, .setReps(exerciseID: RFix.ex(s, 2), setID: RFix.setID(s, 2, 0), reps: 20_000))
        XCTAssertEqual(bench.exercises[2].sets[0].reps, 999)
        let pushup = RFix.reduced(s, .setReps(exerciseID: RFix.ex(s, 3), setID: RFix.setID(s, 3, 0), reps: 3_600))
        XCTAssertEqual(pushup.exercises[3].sets[0].reps, 999)
        let nudged = RFix.reduced(s, .nudgeNextSet(weightSteps: 0, repsSteps: 1_000))
        XCTAssertEqual(nudged.exercises[0].sets[0].reps, 45 + 1_000 * 5)
    }

    // MARK: Revision

    func testEveryTimerActionThatChangesSomethingBumpsTheRevisionOnce() {
        var s = workout()
        s = RFix.reduced(s, .startTimedSet(ref(s, 0, 0)), at: 1)
        XCTAssertEqual(s.revision, 1)
        s = RFix.reduced(s, .pause, at: 2)
        XCTAssertEqual(s.revision, 2)
        s = RFix.reduced(s, .resume, at: 3)
        XCTAssertEqual(s.revision, 3)
        s = RFix.reduced(s, .stopTimedSet, at: 4)
        XCTAssertEqual(s.revision, 4)
        XCTAssertEqual(RFix.reduced(s, .stopTimedSet, at: 5).revision, 4, "nothing to stop")
        XCTAssertEqual(RFix.reduced(s, .updateHeartRate(120), at: 5).revision, 4, "a heart rate sample never bumps it")
    }
}

// MARK: - The presenter

final class TimedSetPresenterTests: XCTestCase {
    private func state(target: Int = 45) -> WorkoutState {
        var s = PresFix.workout([
            PresFix.entry(1, PresFix.lib("plank"), PresFix.normal(3, 0, target), rest: 45),
            PresFix.entry(2, PresFix.lib("bench"), PresFix.normal(2, 80, 5)),
        ])
        s = PresFix.reduced(s, .startTimedSet(SetRef(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[1].id)), at: 100)
        return s
    }

    func testTheTimerFields() throws {
        let s = state()
        let timed = try XCTUnwrap(PresFix.present(s, at: 120).timedSet)
        XCTAssertEqual(timed.exerciseID, s.exercises[0].id)
        XCTAssertEqual(timed.setID, s.exercises[0].sets[1].id)
        XCTAssertEqual(timed.setNumber, 2)
        XCTAssertEqual(timed.elapsedSeconds, 20)
        XCTAssertEqual(timed.targetSeconds, 45)
        XCTAssertEqual(timed.remainingSeconds, 25)
        XCTAssertFalse(timed.isOverTarget)
        XCTAssertFalse(timed.isPaused)
        XCTAssertEqual(timed.elapsedText, "0:20")
        XCTAssertEqual(timed.targetText, "0:45")
        XCTAssertEqual(timed.remainingText, "0:25")
    }

    func testTheTargetIsReportedNotActedOn() throws {
        let s = state()
        let atTarget = try XCTUnwrap(PresFix.present(s, at: 145).timedSet)
        XCTAssertEqual(atTarget.remainingSeconds, 0)
        XCTAssertTrue(atTarget.isOverTarget)
        let beyond = try XCTUnwrap(PresFix.present(s, at: 190).timedSet)
        XCTAssertEqual(beyond.elapsedSeconds, 90, "the stopwatch keeps counting")
        XCTAssertEqual(beyond.remainingSeconds, 0)
        XCTAssertTrue(beyond.isOverTarget)
        XCTAssertNotNil(PresFix.present(s, at: 190).timedSet, "the screen decides; the state still has the timer")
        XCTAssertFalse(s.exercises[0].sets[1].isDone, "the set is still pending")
    }

    func testAZeroTargetIsNeverOverTarget() throws {
        let timed = try XCTUnwrap(PresFix.present(state(target: 0), at: 160).timedSet)
        XCTAssertEqual(timed.targetSeconds, 0)
        XCTAssertFalse(timed.isOverTarget)
        XCTAssertEqual(timed.remainingSeconds, 0)
    }

    func testPausedTimersAreFrozen() throws {
        var s = state()
        s = PresFix.reduced(s, .pause, at: 130)
        let timed = try XCTUnwrap(PresFix.present(s, at: 900).timedSet)
        XCTAssertEqual(timed.elapsedSeconds, 30)
        XCTAssertTrue(timed.isPaused)
    }

    func testNoTimerWithoutOne() {
        XCTAssertNil(PresFix.present(PresFix.freshUpperA()).timedSet)
        XCTAssertNil(PresFix.present(PresFix.workout([])).timedSet)
    }

    func testTheRestDockDoesNotShowWhileATimedSetRuns() {
        var s = state()
        s.rest = RestState(endsAt: PresFix.at(200), totalSeconds: 100)       // a state the reducer would not make
        XCTAssertNil(PresFix.present(s, at: 120).dock)
        s.timedSet = nil
        XCTAssertNotNil(PresFix.present(s, at: 120).dock)
    }

    func testATimerWhoseSetIsGoneShowsNothing() {
        var s = state()
        s.exercises[0].sets.removeAll()
        XCTAssertNil(PresFix.present(s, at: 120).timedSet)
        var wrong = state()
        wrong.timedSet?.setRef.setID = PresFix.uuid(0xDEAD, 1)
        XCTAssertNil(PresFix.present(wrong, at: 120).timedSet)
    }

    func testAbsurdTimesStayInRange() throws {
        var s = state()
        s.timedSet?.targetSeconds = Int.max
        s.timedSet?.startedAt = PresFix.at(-1e12)
        let timed = try XCTUnwrap(PresFix.present(s, at: 120).timedSet)
        XCTAssertEqual(timed.targetSeconds, 10_800)
        XCTAssertEqual(timed.elapsedSeconds, 10_800)
        XCTAssertTrue(timed.isOverTarget)
        s.timedSet?.targetSeconds = Int.min
        s.timedSet?.startedAt = PresFix.at(1e12)
        let negative = try XCTUnwrap(PresFix.present(s, at: 120).timedSet)
        XCTAssertEqual(negative.targetSeconds, 0)
        XCTAssertEqual(negative.elapsedSeconds, 0)
    }

    func testTheSnapshotStaysInTheLoggingPhaseAndIsUnchanged() {
        let s = state()
        let snapshot = SnapshotBuilder.make(from: s, now: PresFix.at(120))
        XCTAssertEqual(snapshot.phase, .logging)
        XCTAssertEqual(snapshot.tracking, .duration)
        XCTAssertEqual(snapshot.repsText, "45")
        XCTAssertEqual(snapshot.repsUnit, "sec")
        var idle = s
        idle.timedSet = nil
        XCTAssertEqual(SnapshotBuilder.make(from: idle, now: PresFix.at(120)).phase, .logging)
        XCTAssertEqual(snapshot.targetSetID, s.exercises[0].sets[0].id, "the next pending set of the workout is still the target")
    }
}

// MARK: - Sync and storage

final class TimedSetSyncTests: XCTestCase {
    private func timedState() -> WorkoutState {
        var s = RFix.state([RFix.entry(1, RFix.plank, RFix.normal(2, 0, 45), rest: 45), RFix.entry(2, RFix.bench, RFix.normal(2, 80, 5), rest: 150)])
        s = RFix.reduced(s, .startTimedSet(SetRef(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 0))), at: 5)
        return s
    }

    func testAStateWithATimerRoundTripsThroughTheSyncCodec() throws {
        let s = timedState()
        XCTAssertNotNil(s.timedSet)
        let envelope = SyncMessage.state(SyncEnvelope(state: s, sentAt: RFix.at(6)))
        XCTAssertEqual(try SyncCodec.decode(try SyncCodec.encode(envelope)), envelope)
        var paused = RFix.reduced(s, .pause, at: 15)
        paused.revision += 1
        let pausedMessage = SyncMessage.state(SyncEnvelope(state: paused, sentAt: RFix.at(16)))
        let decoded = try SyncCodec.decode(try SyncCodec.encode(pausedMessage))
        XCTAssertEqual(decoded, pausedMessage)
        guard case let .state(back) = decoded else { return XCTFail("not a state") }
        XCTAssertEqual(back.state?.timedSet?.frozenElapsed, 10)
    }

    func testTheNewActionsRoundTripAsCommands() throws {
        let s = timedState()
        for action in [WorkoutAction.startTimedSet(SetRef(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 1))), .stopTimedSet, .cancelTimedSet] {
            let command = SyncMessage.command(RemoteCommand(action: action, origin: .watch, issuedAt: RFix.at(1), workoutID: s.id))
            XCTAssertEqual(try SyncCodec.decode(try SyncCodec.encode(command)), command)
        }
    }

    func testAStateWrittenBeforeTimedSetsDecodesWithoutATimer() throws {
        var s = timedState()
        s.timedSet = nil
        let data = try StrengthJSON.makeEncoder().encode(s)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "timedSet")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("timedSet"))
        XCTAssertEqual(try StrengthJSON.makeDecoder().decode(WorkoutState.self, from: old), s)
        // the same as an envelope of an older phone
        let envelope = SyncEnvelope(state: s, sentAt: RFix.at(1))
        var envelopeObject = try XCTUnwrap(JSONSerialization.jsonObject(with: try StrengthJSON.makeEncoder().encode(envelope)) as? [String: Any])
        var inner = try XCTUnwrap(envelopeObject["state"] as? [String: Any])
        inner.removeValue(forKey: "timedSet")
        envelopeObject["state"] = inner
        let decoded = try StrengthJSON.makeDecoder().decode(SyncEnvelope.self, from: try JSONSerialization.data(withJSONObject: envelopeObject))
        XCTAssertNil(decoded.state?.timedSet)
        XCTAssertEqual(decoded.state, s)
    }

    func testTheTimerIsWrittenOnlyWhenThereIsOne() throws {
        var s = timedState()
        XCTAssertTrue(String(decoding: try StrengthJSON.makeEncoder().encode(s), as: UTF8.self).contains("\"timedSet\""))
        s.timedSet = nil
        XCTAssertFalse(String(decoding: try StrengthJSON.makeEncoder().encode(s), as: UTF8.self).contains("timedSet"))
    }

    func testTheWatchReplaysItsTimerCommandsOnThePhonesState() {
        let base = RFix.state([RFix.entry(1, RFix.plank, RFix.normal(2, 0, 45), rest: 45)])
        let workout = base.id
        let ref = SetRef(exerciseID: RFix.ex(base, 0), setID: RFix.setID(base, 0, 0))
        let pending = [
            RemoteCommand(action: .startTimedSet(ref), origin: .watch, issuedAt: RFix.at(5), workoutID: workout),
            RemoteCommand(action: .pause, origin: .watch, issuedAt: RFix.at(15), workoutID: workout),
            RemoteCommand(action: .resume, origin: .watch, issuedAt: RFix.at(35), workoutID: workout),
            RemoteCommand(action: .stopTimedSet, origin: .watch, issuedAt: RFix.at(45), workoutID: workout),
        ]
        let shown = SyncReconciler.rebase(base, replaying: pending)
        XCTAssertNil(shown.timedSet)
        XCTAssertEqual(shown.exercises[0].sets[0].reps, 20, "10 s before the pause and 10 s after it: each command acts at the time it was issued")
        XCTAssertTrue(shown.exercises[0].sets[0].isDone)
        XCTAssertEqual(shown.rest?.totalSeconds, 45)
    }
}

// MARK: - Through the engine

final class TimedSetEngineTests: XCTestCase {
    @MainActor
    private func makeRig(_ test: XCTestCase) -> SvcRig {
        let rig = SvcRig(test, seed: false)
        rig.engine.start(template: nil, name: "Core")
        rig.engine.send(.addExercises([ExerciseLibrary.exercise(id: "plank")!]))
        return rig
    }

    @MainActor
    private func ref(_ engine: WorkoutEngine, _ i: Int = 0) -> SetRef {
        let entry = engine.state!.exercises[0]
        return SetRef(exerciseID: entry.id, setID: entry.sets[i].id)
    }

    func testFinishingWithARunningTimerLeavesTheSetOutAndClearsIt() throws {
        try svcMain {
            let rig = makeRig(self)
            rig.clock.advance(10)
            rig.engine.send(.logNextSet)                                   // a first set is logged
            rig.clock.advance(60)
            rig.engine.send(.startTimedSet(ref(rig.engine, 1)))
            XCTAssertNotNil(rig.engine.state?.timedSet)
            XCTAssertNotNil(rig.engine.presentation(now: rig.clock.now)?.timedSet)
            let completed = try XCTUnwrap(rig.engine.finish(updateTemplate: false))
            XCTAssertEqual(completed.loggedSets, 1, "the set that was being timed is not logged")
            XCTAssertNil(rig.engine.state)
            XCTAssertNil(rig.persistence.loadActiveWorkout())
        }
    }

    func testDiscardingClearsTheTimer() {
        svcMain {
            let rig = makeRig(self)
            rig.engine.send(.startTimedSet(ref(rig.engine)))
            XCTAssertNotNil(rig.engine.state?.timedSet)
            rig.engine.discard()
            XCTAssertNil(rig.engine.state)
            XCTAssertNil(rig.persistence.loadActiveWorkout())
            // the next workout starts without one
            rig.engine.start(template: nil, name: "Next")
            XCTAssertNil(rig.engine.state?.timedSet)
        }
    }

    func testTheTimerSurvivesARestoreOfTheSavedWorkout() throws {
        try svcMain {
            let rig = makeRig(self)
            rig.clock.advance(5)
            rig.engine.send(.startTimedSet(ref(rig.engine)))
            let saved = try XCTUnwrap(rig.persistence.loadActiveWorkout())
            XCTAssertEqual(saved.timedSet, rig.engine.state?.timedSet)
            let second = WorkoutEngine(role: .authority, persistence: rig.persistence, data: rig.model, recovery: DemoRecovery.provider, clock: rig.clock.reader)
            second.restore()
            XCTAssertEqual(second.state?.timedSet, saved.timedSet)
            rig.clock.advance(20)
            XCTAssertEqual(second.presentation(now: rig.clock.now)?.timedSet?.elapsedSeconds, 20)
        }
    }

    func testTheStopCommandOfTheWatchActsAtTheTimeOfTheTap() {
        svcMain {
            let rig = makeRig(self)
            rig.engine.send(.startTimedSet(ref(rig.engine)))
            let tapped = rig.clock.now.addingTimeInterval(30)
            rig.clock.advance(34)                                          // the command reaches the phone four seconds later
            let command = RemoteCommand(action: .stopTimedSet, origin: .watch, issuedAt: tapped, workoutID: rig.engine.state?.id)
            XCTAssertLessThan(4, SyncReconciler.lateCommandWindow)
            rig.engine.receive(command)
            XCTAssertEqual(rig.engine.state?.exercises[0].sets[0].reps, 30, "30 s as the Watch showed, not 34")
            XCTAssertNil(rig.engine.state?.timedSet)
        }
    }

    func testAMirrorMakesACommandOfTheNewActionsAndAcknowledgementsClearThem() throws {
        try svcMain {
            let phone = SvcRig(self, role: .authority, seed: false)
            phone.engine.start(template: nil, name: "Core")
            phone.engine.send(.addExercises([ExerciseLibrary.exercise(id: "plank")!]))
            let watch = SvcRig(self, role: .mirror, seed: false)
            watch.engine.receive(phone.engine.makeEnvelope(now: phone.clock.now))
            XCTAssertEqual(watch.engine.state?.id, phone.engine.state?.id)
            watch.engine.send(.startTimedSet(ref(watch.engine)), origin: .watch)
            XCTAssertNotNil(watch.engine.state?.timedSet)
            XCTAssertEqual(watch.engine.pendingCommands.count, 1)
            let command = try XCTUnwrap(watch.engine.pendingCommands.first)
            phone.engine.receive(command)
            XCTAssertEqual(phone.engine.state?.timedSet?.setRef, ref(phone.engine))
            watch.engine.receive(phone.engine.makeEnvelope(now: phone.clock.now.addingTimeInterval(1)))
            XCTAssertTrue(watch.engine.pendingCommands.isEmpty)
            XCTAssertEqual(watch.engine.state?.timedSet?.setRef, ref(phone.engine))
        }
    }
}
