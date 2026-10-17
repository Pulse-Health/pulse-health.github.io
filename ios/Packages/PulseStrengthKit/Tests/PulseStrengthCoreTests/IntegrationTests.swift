import Foundation
import XCTest
@testable import PulseStrengthCore

// End-to-end checks across the areas (library, sample data, factory, reducer, presenter, snapshot, summary, engine, sync codec).
// Every expected number below is derived by hand from the design (Active.dc.html) and ARCHITECTURE.md section 3, not read back
// from the code under test.
//
// "Upper A · Push": bench W 50x8, W 70x5, 82.5x6, 82.5x6, 85x6 (rest 150); incline 3x28x10 (90); ohp 3x45x8 (120);
// lateral 3x8x15 and pushdown 3x30x12 (60, superset A); crossover 3x15x12 (60). 20 sets. Bench best estimated 1RM before: 99 kg.

final class IntegrationFlowTests: XCTestCase {

    private func index(_ state: WorkoutState, _ exerciseID: String) -> Int {
        state.exercises.firstIndex { $0.exercise.id == exerciseID } ?? -1
    }

    // MARK: Opening state

    func testTheOpeningStateOfTheDesignWorkout() throws {
        try svcMain {
            let rig = SvcRig(self)
            let state = rig.startUpperA()
            let presentation = try XCTUnwrap(rig.engine.presentation(now: rig.clock.now))

            XCTAssertEqual(state.exercises.map { $0.exercise.id }, ["bench", "incline", "ohp", "lateral", "pushdown", "crossover"])
            XCTAssertEqual(state.exercises.map { $0.supersetGroup }, [nil, nil, nil, "A", "A", nil])
            XCTAssertEqual(state.exercises.map { $0.restSeconds }, [150, 90, 120, 60, 60, 60])
            XCTAssertEqual(state.exercises.map { $0.sets.count }, [5, 3, 3, 3, 3, 3])
            XCTAssertEqual(state.templateBaseline.count, 6)
            XCTAssertEqual(state.currentIndex, 0)
            XCTAssertEqual(state.revision, 0)

            XCTAssertEqual(presentation.totals.totalSets, 20)
            XCTAssertEqual(presentation.totals.loggedSets, 0)
            XCTAssertEqual(presentation.header.title, "Upper A · Push")
            XCTAssertEqual(presentation.header.clockText, "0:00")
            XCTAssertEqual(presentation.header.setsText, "0 of 20")
            XCTAssertEqual(presentation.header.volumeText, "0")
            XCTAssertEqual(presentation.header.heartRateText, "–")
            XCTAssertEqual(presentation.header.segments.count, 6)
            XCTAssertEqual(presentation.navigator?.position, 1)
            XCTAssertEqual(presentation.navigator?.total, 6)
            XCTAssertNil(presentation.dock)
            XCTAssertNil(presentation.undoText)

            let card = try XCTUnwrap(presentation.card)
            XCTAssertEqual(card.exercise.id, "bench")
            XCTAssertEqual(card.recoveryPercent, 88)
            XCTAssertEqual(card.recoveryLevel, .good)
            XCTAssertEqual(card.restText, "2:30")
            XCTAssertEqual(card.weightColumnTitle, "kg")
            XCTAssertEqual(card.repsColumnTitle, "Reps")
            XCTAssertNil(card.supersetLabel)
            XCTAssertEqual(card.rows.map { $0.number }, ["W", "W", "1", "2", "3"])
            XCTAssertEqual(card.rows.map { $0.weightText }, ["50", "70", "82.5", "82.5", "85"])
            XCTAssertEqual(card.rows.map { $0.repsText }, ["8", "5", "6", "6", "6"])
            // The last session of the demo history (5 days ago).
            XCTAssertEqual(card.rows.map { $0.previousText }, ["50 × 8", "70 × 5", "80 × 6", "80 × 6", "80 × 5"])
            XCTAssertEqual(card.rows.map { $0.isNext }, [true, false, false, false, false])
            XCTAssertEqual(card.rows.filter { $0.isPersonalRecord }.count, 0)
            XCTAssertEqual(card.coachTip, "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")

            XCTAssertFalse(presentation.finishCheck.canFinish)
            XCTAssertEqual(presentation.finishCheck.title, "Nothing logged yet")
            XCTAssertFalse(presentation.finishCheck.asksToUpdateTemplate)
            XCTAssertTrue(rig.engine.templateDiff().isEmpty)

            let snapshot = try XCTUnwrap(rig.engine.snapshot(now: rig.clock.now))
            XCTAssertEqual(snapshot.phase, .logging)
            XCTAssertEqual(snapshot.setLabel, "Warm-up · Set 1 of 5")
            XCTAssertEqual(snapshot.weightText, "50")
            XCTAssertEqual(snapshot.repsText, "8")
            XCTAssertEqual(snapshot.repsUnit, "reps")
            XCTAssertTrue(snapshot.showsWeight)
            XCTAssertEqual(snapshot.exerciseIndex, 0)
            XCTAssertEqual(snapshot.exerciseCount, 6)
            XCTAssertEqual(snapshot.targetExerciseID, state.exercises[0].id)
            XCTAssertEqual(snapshot.targetSetID, state.exercises[0].sets[0].id)
            XCTAssertEqual(snapshot.nextExerciseName, "Incline dumbbell press")
            XCTAssertEqual(snapshot.loggedSets, 0)
            XCTAssertEqual(snapshot.totalSets, 20)
            XCTAssertNil(snapshot.restEndsAt)
        }
    }

    // MARK: Logging, rest, personal record

    func testLoggingTheBenchSetsFollowsTheDesign() throws {
        try svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()

            // Warm-ups rest max(30, round(150 * 0.4 / 5) * 5) = 60 s, a working set rests the exercise's 150 s.
            rig.logSets(1)
            XCTAssertEqual(rig.engine.state?.rest?.totalSeconds, 60)
            rig.logSets(1)
            XCTAssertEqual(rig.engine.state?.rest?.totalSeconds, 60)
            rig.logSets(1)
            let afterThird = try XCTUnwrap(rig.engine.state)
            XCTAssertEqual(afterThird.rest?.totalSeconds, 150)
            XCTAssertEqual(afterThird.rest?.endsAt, rig.clock.now.addingTimeInterval(150))
            XCTAssertEqual(afterThird.revision, 3)

            let presentation = try XCTUnwrap(rig.engine.presentation(now: rig.clock.now))
            XCTAssertEqual(presentation.totals.loggedSets, 3)
            XCTAssertEqual(presentation.header.setsText, "3 of 20")
            XCTAssertEqual(presentation.header.volumeText, "495")            // 82.5 x 6; warm-ups excluded
            XCTAssertEqual(presentation.header.clockText, "3:00")
            let card = try XCTUnwrap(presentation.card)
            XCTAssertEqual(card.rows.map { $0.isDone }, [true, true, true, false, false])
            XCTAssertEqual(card.rows.map { $0.isNext }, [false, false, false, true, false])
            XCTAssertNil(card.coachTip, "no tip while a rest timer runs")
            XCTAssertEqual(card.rows[2].isPersonalRecord, true, "82.5 x 6 is no estimate record (99.0, not above 99 + 0.05) but beats the 80 kg of the best 6 reps")
            XCTAssertEqual(card.rows[2].prKind, .repRecord(reps: 6))
            XCTAssertNil(card.rows[2].estimated1RM)
            XCTAssertEqual(card.rows[2].accessibilityLabel, "Set 3, working set, 82.5 kilograms, 6 reps, logged")

            let dock = try XCTUnwrap(presentation.dock)
            XCTAssertEqual(dock.phase, .running)
            XCTAssertEqual(dock.totalSeconds, 150)
            XCTAssertEqual(dock.remainingSeconds, 150)
            XCTAssertEqual(dock.remainingText, "2:30")
            XCTAssertEqual(dock.nextSetText, "Next · Set 2 · 82.5 kg × 6")
            XCTAssertTrue(dock.showsRIR)

            let snapshot = try XCTUnwrap(rig.engine.snapshot(now: rig.clock.now))
            XCTAssertEqual(snapshot.phase, .resting)
            XCTAssertEqual(snapshot.setLabel, "Set 4 of 5")
            XCTAssertEqual(snapshot.nextSetText, "Set 4 · 82.5 kg × 6")
            XCTAssertEqual(snapshot.restEndsAt, rig.clock.now.addingTimeInterval(150))
            XCTAssertEqual(snapshot.restStartedAt, rig.clock.now)
            XCTAssertEqual(snapshot.restTotalSeconds, 150)

            // 40 s later the dock counts down; 150 s later it is over.
            let later = rig.clock.now.addingTimeInterval(40)
            XCTAssertEqual(rig.engine.presentation(now: later)?.dock?.remainingSeconds, 110)
            XCTAssertEqual(rig.engine.snapshot(now: later)?.phase, .resting)
            let over = rig.clock.now.addingTimeInterval(151)
            XCTAssertEqual(rig.engine.presentation(now: over)?.dock?.phase, .finished)
            XCTAssertEqual(rig.engine.presentation(now: over)?.dock?.remainingText, "Go")
            XCTAssertEqual(rig.engine.snapshot(now: over)?.phase, .restOver)
        }
    }

    func testTheHeaviestBenchSetIsThePersonalRecord() throws {
        try svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(5)

            let presentation = try XCTUnwrap(rig.engine.presentation(now: rig.clock.now))
            let rows = try XCTUnwrap(presentation.card).rows
            XCTAssertEqual(rows.map { $0.isPersonalRecord }, [false, false, true, false, true])
            XCTAssertEqual(rows.map { $0.prKind }, [nil, nil, .repRecord(reps: 6), nil, .estimated1RM])
            XCTAssertEqual(rows[4].estimated1RM, 102)                        // 85 x (1 + 6/30)
            XCTAssertEqual(presentation.header.volumeText, "1,500")          // 495 + 495 + 510
            XCTAssertEqual(presentation.totals.completedExercises, 1)

            // The bench is complete: the current exercise stays, the next target is the incline press.
            XCTAssertEqual(rig.engine.state?.currentIndex, 0)
            let snapshot = try XCTUnwrap(rig.engine.snapshot(now: rig.clock.now))
            XCTAssertEqual(snapshot.exerciseName, "Incline dumbbell press")
            XCTAssertEqual(snapshot.setLabel, "Set 1 of 3")
            XCTAssertEqual(snapshot.weightText, "28")
            XCTAssertEqual(snapshot.nextExerciseName, "Overhead press")
        }
    }

    // MARK: Superset

    func testTheSupersetAlternatesAndRestsAfterTheLastMember() throws {
        try svcMain {
            let rig = SvcRig(self)
            let started = rig.startUpperA()
            let lateral = index(started, "lateral")
            let pushdown = index(started, "pushdown")
            XCTAssertEqual([lateral, pushdown], [3, 4])

            rig.logSets(5 + 3 + 3)                                           // bench, incline, ohp
            XCTAssertEqual(rig.engine.state?.rest?.totalSeconds, 120)

            rig.logSets(1)                                                   // lateral set 1
            var state = try XCTUnwrap(rig.engine.state)
            XCTAssertTrue(state.exercises[lateral].sets[0].isDone)
            XCTAssertEqual(state.currentIndex, pushdown, "moves on to the partner")
            XCTAssertNil(state.rest, "no rest between the members")
            var snapshot = try XCTUnwrap(rig.engine.snapshot(now: rig.clock.now))
            XCTAssertEqual(snapshot.phase, .logging)
            XCTAssertEqual(snapshot.targetExerciseID, state.exercises[pushdown].id)
            XCTAssertEqual(snapshot.setLabel, "Set 1 of 3")
            XCTAssertEqual(snapshot.weightText, "30")
            XCTAssertEqual(snapshot.repsText, "12")

            rig.logSets(1)                                                   // pushdown set 1
            state = try XCTUnwrap(rig.engine.state)
            XCTAssertEqual(state.currentIndex, lateral, "back to the first member")
            XCTAssertEqual(state.rest?.totalSeconds, 60)
            snapshot = try XCTUnwrap(rig.engine.snapshot(now: rig.clock.now))
            XCTAssertEqual(snapshot.phase, .resting)
            XCTAssertEqual(snapshot.targetExerciseID, state.exercises[lateral].id)
            XCTAssertEqual(snapshot.setLabel, "Set 2 of 3")
            XCTAssertEqual(rig.engine.presentation(now: rig.clock.now)?.card?.supersetLabel, "Superset A")
        }
    }

    // MARK: Finishing

    func testTheWholeWorkoutEndToEnd() throws {
        try svcMain {
            let rig = SvcRig(self)
            let started = rig.startUpperA()
            let templateID = started.templateID
            let historyBefore = rig.model.data.history.count
            XCTAssertEqual(historyBefore, 5)
            // The demo record is 85 kg x 5 from 10 days ago: 85 x (1 + 5/30) = 99.17 kg (the design shows it rounded, "99").
            let demoBest = 85.0 * (1 + 5.0 / 30)
            XCTAssertEqual(rig.model.data.personalBests["bench"]?.estimated1RM ?? 0, demoBest, accuracy: 0.0001)

            rig.logSets(20)
            let presentation = try XCTUnwrap(rig.engine.presentation(now: rig.clock.now))
            XCTAssertEqual(presentation.totals.loggedSets, 20)
            XCTAssertEqual(presentation.totals.completedExercises, 6)
            XCTAssertEqual(presentation.header.setsText, "20 of 20")
            // 1,500 bench + 840 incline + 1,080 ohp + 360 lateral + 1,080 pushdown + 540 crossover.
            XCTAssertEqual(presentation.header.volumeText, "5,400")
            XCTAssertTrue(presentation.finishCheck.canFinish)
            XCTAssertEqual(presentation.finishCheck.title, "Finish workout?")
            XCTAssertEqual(presentation.finishCheck.message, "All sets are logged. Nice work.")
            XCTAssertEqual(rig.engine.snapshot(now: rig.clock.now)?.phase, .complete)
            XCTAssertEqual(rig.engine.snapshot(now: rig.clock.now)?.setLabel, "All sets logged")
            XCTAssertNil(rig.engine.snapshot(now: rig.clock.now)?.targetSetID)

            rig.clock.advance(120)
            let completed = try XCTUnwrap(rig.engine.finish(updateTemplate: false))
            XCTAssertEqual(completed.loggedSets, 20)
            XCTAssertEqual(completed.volumeKg, 5_400, accuracy: 0.0001)
            XCTAssertEqual(completed.durationSeconds, 20 * 60 + 120)
            XCTAssertEqual(completed.exercises.count, 6)
            XCTAssertEqual(completed.exercises.map { $0.sets.count }, [5, 3, 3, 3, 3, 3])
            let bench = try XCTUnwrap(completed.personalRecords.first { $0.exerciseID == "bench" })
            XCTAssertEqual(bench.estimated1RM, 102, accuracy: 0.0001)
            XCTAssertEqual(bench.weightKg, 85)
            XCTAssertEqual(bench.reps, 6)
            XCTAssertEqual(bench.previousBest, demoBest, accuracy: 0.0001)
            XCTAssertEqual(completed.exercises.filter { $0.isPersonalRecord }.map { $0.exerciseID }, ["bench"])
            XCTAssertEqual(completed.muscleSets.first?.muscle, .chest)

            // Everything recorded: history (newest first), personal best, template, nothing left active.
            XCTAssertEqual(rig.model.data.history.count, historyBefore + 1)
            XCTAssertEqual(rig.model.data.history.first, completed)
            let best = try XCTUnwrap(rig.model.data.personalBests["bench"])
            XCTAssertEqual(best.estimated1RM, 102, accuracy: 0.0001)
            XCTAssertEqual(best.weightKg, 85)
            XCTAssertEqual(best.reps, 6)
            XCTAssertEqual(rig.model.data.templates.first { $0.id == templateID }?.lastPerformed, completed.finishedAt)
            XCTAssertNil(rig.engine.state)
            XCTAssertNil(rig.diskState)
            XCTAssertEqual(rig.persistence.loadHistory().first, completed)
            XCTAssertEqual(rig.persistence.loadPersonalBests()["bench"]?.estimated1RM ?? 0, 102, accuracy: 0.0001)

            // The next session starts from the new results: bench best 102, last sets = today's, no PR for the same 85 x 6.
            rig.clock.advance(3_600)
            XCTAssertTrue(rig.engine.start(template: rig.upperA))
            let next = try XCTUnwrap(rig.engine.state)
            XCTAssertEqual(next.exercises[0].exercise.previousBestE1RM, 102, accuracy: 0.0001)
            XCTAssertEqual(next.exercises[0].exercise.previousSets.map { $0.weightKg }, [50, 70, 82.5, 82.5, 85])
            XCTAssertEqual(next.exercises[0].exercise.previousSets.map { $0.reps }, [8, 5, 6, 6, 6])
            rig.logSets(5)
            let rows = try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)?.card).rows
            XCTAssertEqual(rows.map { $0.isPersonalRecord }, [false, false, false, false, false])
            XCTAssertEqual(rows.map { $0.previousText }, ["50 × 8", "70 × 5", "82.5 × 6", "82.5 × 6", "85 × 6"])
        }
    }

    func testFinishingAnEditedWorkoutOffersAndAppliesTheTemplateUpdate() throws {
        try svcMain {
            let rig = SvcRig(self)
            let started = rig.startUpperA()
            rig.logSets(5)
            let crossover = started.exercises[5].id
            rig.engine.send(.removeExercise(exerciseID: crossover))
            rig.engine.send(.addExercises([ExerciseLibrary.exercise(id: "pushup")!]))

            let check = try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)).finishCheck
            XCTAssertEqual(check.templateDiff, TemplateDiff(added: 1, removed: 1, reordered: false))
            XCTAssertEqual(check.diffMessage, "Changes: 1 added, 1 removed.")
            XCTAssertTrue(check.asksToUpdateTemplate)
            XCTAssertEqual(check.unloggedSets, 15, "incline, ohp, lateral, pushdown and the push-up (3 sets each) are pending")

            let completed = try XCTUnwrap(rig.engine.finish(updateTemplate: true))
            XCTAssertEqual(completed.loggedSets, 5)
            let template = try XCTUnwrap(rig.model.data.templates.first { $0.id == started.templateID })
            XCTAssertEqual(template.entries.map { $0.exercise.id }, ["bench", "incline", "ohp", "lateral", "pushdown", "pushup"])
            XCTAssertEqual(template.lastPerformed, completed.finishedAt)
            XCTAssertEqual(template.entries[0].plannedSets.map { $0.type }, [.warmup, .warmup, .normal, .normal, .normal])
        }
    }

    // MARK: Other surfaces (Live Activity, Watch)

    func testTheLiveActivityButtonsActOnTheSnapshotTarget() throws {
        try svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(2)                                                   // both warm-ups; the 82.5 kg set is next

            // "+" on the weight: nudge by one step of the barbell (2.5 kg).
            rig.engine.receive(RemoteCommand(action: .nudgeNextSet(weightSteps: 1, repsSteps: 0), origin: .liveActivity))
            var snapshot = try XCTUnwrap(rig.engine.snapshot(now: rig.clock.now))
            XCTAssertEqual(snapshot.weightText, "85")
            XCTAssertEqual(snapshot.repsText, "6")
            XCTAssertEqual(rig.engine.state?.exercises[0].sets[2].weightKg, 85)

            // "Log set" logs exactly the set the snapshot named, once, even when the system delivers the command twice.
            let exerciseID = try XCTUnwrap(snapshot.targetExerciseID)
            let setID = try XCTUnwrap(snapshot.targetSetID)
            let log = RemoteCommand(action: .logSet(exerciseID: exerciseID, setID: setID), origin: .liveActivity)
            rig.engine.receive(log)
            rig.engine.receive(log)
            XCTAssertEqual(rig.engine.state?.exercises[0].sets[2].isDone, true)
            XCTAssertEqual(rig.engine.state?.exercises[0].sets.filter { $0.isDone }.count, 3)
            XCTAssertEqual(rig.recorder.changes.count, 2 + 1 + 1, "two warm-ups, the nudge, the log; the duplicate is dropped")
            if case let .changed(_, _, action, origin)? = rig.recorder.changes.last {
                XCTAssertEqual(action, .logSet(exerciseID: exerciseID, setID: setID))
                XCTAssertEqual(origin, .liveActivity)
            } else {
                XCTFail("the log command was not reported")
            }

            // Rest buttons: +15 s then Skip.
            snapshot = try XCTUnwrap(rig.engine.snapshot(now: rig.clock.now))
            XCTAssertEqual(snapshot.phase, .resting)
            XCTAssertEqual(snapshot.restTotalSeconds, 150)
            rig.engine.receive(RemoteCommand(action: .adjustRest(seconds: 15), origin: .liveActivity))
            snapshot = try XCTUnwrap(rig.engine.snapshot(now: rig.clock.now))
            XCTAssertEqual(snapshot.restTotalSeconds, 165)
            XCTAssertEqual(snapshot.restEndsAt, rig.clock.now.addingTimeInterval(165))
            rig.engine.receive(RemoteCommand(action: .skipRest, origin: .liveActivity))
            XCTAssertEqual(rig.engine.snapshot(now: rig.clock.now)?.phase, .logging)
        }
    }

    func testThePhoneAndTheWatchAgreeOverTheWire() throws {
        try svcMain {
            let phone = SvcRig(self)
            let watch = SvcRig(self, role: .mirror, seed: true)
            phone.startUpperA()
            phone.logSets(3)
            phone.engine.send(.updateHeartRate(131), origin: .watch)

            // Phone -> wire -> Watch.
            let envelope = SyncEnvelope(state: phone.engine.state, sentAt: phone.clock.now)
            let payload = try SyncCodec.encode(.state(envelope))
            guard case let .state(received) = try SyncCodec.decode(payload) else { return XCTFail("not a state message") }
            XCTAssertEqual(received, envelope)
            watch.clock.set(phone.clock.now)
            watch.engine.receive(received)
            XCTAssertEqual(watch.engine.state, phone.engine.state)
            XCTAssertEqual(watch.engine.snapshot(now: phone.clock.now), phone.engine.snapshot(now: phone.clock.now))
            XCTAssertEqual(watch.engine.presentation(now: phone.clock.now), phone.engine.presentation(now: phone.clock.now))
            XCTAssertNil(watch.diskState, "the Watch never saves the workout")
            XCTAssertEqual(watch.recorder.changes.count, 0, "adopting the phone's state is not echoed")

            // Watch -> wire -> phone: "Log set" from the Watch's snapshot.
            let snapshot = try XCTUnwrap(watch.engine.snapshot(now: phone.clock.now))
            let action = WorkoutAction.logSet(exerciseID: try XCTUnwrap(snapshot.targetExerciseID), setID: try XCTUnwrap(snapshot.targetSetID))
            watch.engine.send(action, origin: .watch)                        // optimistic on the Watch
            let command = RemoteCommand(action: action, origin: .watch, issuedAt: phone.clock.now)
            let commandPayload = try SyncCodec.encode(.command(command))
            guard case let .command(arrived) = try SyncCodec.decode(commandPayload) else { return XCTFail("not a command") }
            phone.engine.receive(arrived)
            XCTAssertEqual(phone.engine.state?.exercises[0].sets[3].isDone, true)
            XCTAssertEqual(watch.engine.state?.exercises[0].sets[3].isDone, true)
            // The phone replies with its state: the same revision as the optimistic Watch copy, so both stay equal.
            XCTAssertEqual(phone.engine.state?.revision, watch.engine.state?.revision)

            // The phone ends the workout: the Watch is told and clears its copy.
            phone.engine.discard()
            let ended = try SyncCodec.encode(.state(SyncEnvelope(state: nil, endedWorkoutID: received.state?.id, sentAt: phone.clock.now)))
            guard case let .state(endedEnvelope) = try SyncCodec.decode(ended) else { return XCTFail("not a state message") }
            watch.engine.receive(endedEnvelope)
            XCTAssertNil(watch.engine.state)
        }
    }
}
