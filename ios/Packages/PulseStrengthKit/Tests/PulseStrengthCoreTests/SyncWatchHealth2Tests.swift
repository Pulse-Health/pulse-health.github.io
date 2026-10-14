import Foundation
import XCTest
@testable import PulseStrengthCore

// Regression tests for the second round of Watch / Health findings (ARCHITECTURE 3.4 and 5.5):
//  * the Health workout ends when the PHONE ended the workout, not when the Watch learned of it (a finish while the link was down
//    must not stretch the Health duration): `WorkoutEngine.lastEndNoticeSentAt` and `SyncReconciler.healthWorkoutEnd`;
//  * an end notice that reaches a Watch with no workout does nothing in the engine, and the Watch environment settles a Health
//    session nobody claimed (one recovered after a crash) with `SyncReconciler.endNotice(sentAt:settlesSessionStartedAt:)`.
// The Health session itself (`WatchWorkoutSession`, `WatchEnvironment`) is Apple-only; its rules live in the functions tested here.

private enum WatchHealth2 {
    /// A workout of "Upper A · Push" with `logged` sets logged.
    static func state(id: Int, logged: Int) -> WorkoutState {
        var state = WorkoutFactory.makeWorkout(from: SampleData.templates()[0], now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(id))
        for step in 0..<logged {
            WorkoutReducer.reduce(&state, .logNextSet, now: SvcSyncFix.at(60 + Double(step) * 90))
        }
        return state
    }
}

// MARK: - The Health end time rule

final class SyncHealthEndRuleTests: XCTestCase {
    private let start = SvcSyncFix.at(0)
    private let processed = SvcSyncFix.at(1_000)

    func testAnEndTimeWellBeforeTheWatchLearnedOfItIsUsed() {
        let requested = SvcSyncFix.at(400)
        XCTAssertEqual(SyncReconciler.healthWorkoutEnd(requested: requested, processedAt: processed, start: start), requested)
    }

    func testWithoutAnEndTimeTheWatchOwnMomentIsUsed() {
        XCTAssertEqual(SyncReconciler.healthWorkoutEnd(requested: nil, processedAt: processed, start: start), processed)
    }

    func testAnEndTimeWithinTheToleranceIsNotWorthUsing() {
        let tolerance = SyncReconciler.healthEndTolerance
        let near = processed.addingTimeInterval(-1)
        XCTAssertEqual(SyncReconciler.healthWorkoutEnd(requested: near, processedAt: processed, start: start), processed)
        let boundary = processed.addingTimeInterval(-tolerance)
        XCTAssertEqual(SyncReconciler.healthWorkoutEnd(requested: boundary, processedAt: processed, start: start), processed,
                       "exactly the tolerance: not more than the tolerance")
        let beyond = processed.addingTimeInterval(-tolerance - 0.5)
        XCTAssertEqual(SyncReconciler.healthWorkoutEnd(requested: beyond, processedAt: processed, start: start), beyond)
    }

    func testAnImplausibleEndTimeNeverShortensOrBreaksTheWorkout() {
        XCTAssertEqual(
            SyncReconciler.healthWorkoutEnd(requested: processed.addingTimeInterval(60), processedAt: processed, start: start),
            processed, "a phone clock ahead of the Watch's"
        )
        XCTAssertEqual(
            SyncReconciler.healthWorkoutEnd(requested: start.addingTimeInterval(-30), processedAt: processed, start: start),
            processed, "before the start of the Health workout (clocks differ)"
        )
        XCTAssertEqual(
            SyncReconciler.healthWorkoutEnd(requested: start, processedAt: processed, start: start),
            processed, "an empty workout is not recorded"
        )
    }

    func testWithoutAKnownStartTheEndTimeCannotBeChecked() {
        XCTAssertEqual(SyncReconciler.healthWorkoutEnd(requested: SvcSyncFix.at(400), processedAt: processed, start: nil), processed)
    }
}

// MARK: - When did the phone end the workout

final class SyncEndNoticeTimeTests: XCTestCase {
    /// A mirror that adopted `state` at t = 10 and received `notice`; returns what `lastEndNoticeSentAt` said INSIDE `workoutEnded`.
    @MainActor
    private func sentAt(of state: WorkoutState, notice: SyncEnvelope) -> (ended: Bool, sentAt: Date?) {
        let peer = SyncPeer(role: .mirror)
        var seen: Date?
        var told = false
        peer.recorder.onEvent = { [unowned peer] event in
            if case .ended = event {
                told = true
                seen = peer.engine.lastEndNoticeSentAt
            }
        }
        peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
        peer.engine.receive(notice)
        return (told, seen)
    }

    func testTheNoticeOfTheWorkoutThatEndsGivesTheTimeThePhoneSentIt() {
        svcMain {
            let state = WatchHealth2.state(id: 1, logged: 2)
            let result = sentAt(of: state, notice: SyncEnvelope(state: nil, endedWorkoutID: state.id, sentAt: SvcSyncFix.at(20), discarded: false))
            XCTAssertTrue(result.ended)
            XCTAssertEqual(result.sentAt, SvcSyncFix.at(20), "set before the effects are told")
        }
    }

    func testTheLegacyNoWorkoutNoticeGivesItsTimeToo() {
        svcMain {
            let state = WatchHealth2.state(id: 1, logged: 2)
            let result = sentAt(of: state, notice: SyncEnvelope(state: nil, sentAt: SvcSyncFix.at(25)))
            XCTAssertTrue(result.ended)
            XCTAssertEqual(result.sentAt, SvcSyncFix.at(25))
        }
    }

    func testAGhostWorkoutEndsWithTheTimeOfTheNoticeThatRevealedIt() {
        svcMain {
            let ghost = WatchHealth2.state(id: 1, logged: 2)
            let notice = SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(77), sentAt: SvcSyncFix.at(30), discarded: true)
            let result = sentAt(of: ghost, notice: notice)
            XCTAssertTrue(result.ended)
            XCTAssertEqual(result.sentAt, SvcSyncFix.at(30))
        }
    }

    func testAnIgnoredNoticeSetsNothing() {
        svcMain {
            let peer = SyncPeer(role: .mirror)
            let state = WatchHealth2.state(id: 1, logged: 1)
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
            XCTAssertNil(peer.engine.lastEndNoticeSentAt)
            // Sent before the state that was adopted: a stale context. It ends nothing and must not look like an end time.
            peer.engine.receive(SyncEnvelope(state: nil, sentAt: SvcSyncFix.at(5)))
            XCTAssertNotNil(peer.state)
            XCTAssertNil(peer.engine.lastEndNoticeSentAt)
            // A notice of an earlier workout while this one runs changes nothing either.
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(77), sentAt: SvcSyncFix.at(8), discarded: true))
            XCTAssertNotNil(peer.state)
            XCTAssertNil(peer.engine.lastEndNoticeSentAt)
        }
    }

    func testAWorkoutTheWatchEndsItselfHasNoNoticeTime() {
        svcMain {
            let peer = SyncPeer(role: .mirror)
            let first = WatchHealth2.state(id: 1, logged: 1)
            peer.engine.receive(SyncEnvelope(state: first, sentAt: SvcSyncFix.at(10)))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: first.id, sentAt: SvcSyncFix.at(20), discarded: false))
            XCTAssertEqual(peer.engine.lastEndNoticeSentAt, SvcSyncFix.at(20))

            let second = WatchHealth2.state(id: 2, logged: 2)
            peer.engine.receive(SyncEnvelope(state: second, sentAt: SvcSyncFix.at(30)))
            XCTAssertNotNil(peer.engine.finish(updateTemplate: false))
            XCTAssertNil(peer.engine.lastEndNoticeSentAt, "the time of the earlier workout's notice must not outlive it")

            let third = WatchHealth2.state(id: 3, logged: 1)
            peer.engine.receive(SyncEnvelope(state: third, sentAt: SvcSyncFix.at(40)))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: third.id, sentAt: SvcSyncFix.at(50), discarded: false))
            XCTAssertEqual(peer.engine.lastEndNoticeSentAt, SvcSyncFix.at(50))
            let fourth = WatchHealth2.state(id: 4, logged: 1)
            peer.engine.receive(SyncEnvelope(state: fourth, sentAt: SvcSyncFix.at(60)))
            peer.engine.discard()
            XCTAssertNil(peer.engine.lastEndNoticeSentAt)
        }
    }

    func testThePhoneHasNoNoticeTime() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(1)
            XCTAssertNotNil(rig.engine.finish(updateTemplate: false))
            XCTAssertNil(rig.engine.lastEndNoticeSentAt)
            rig.startUpperA()
            rig.engine.discard()
            XCTAssertNil(rig.engine.lastEndNoticeSentAt)
        }
    }

    /// The scenario of the finding: the phone finishes while the link is down and the Watch hears of it ten minutes later. The Health
    /// workout ends when the phone finished it, not ten minutes later.
    func testALateNoticeEndsTheHealthWorkoutWhenThePhoneFinished() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.phoneEdit(.logNextSet)
            try link.deliverAll()
            let startedAt = try XCTUnwrap(link.watch.state).startedAt

            link.advance(1_500)
            let finishedAt = link.phone.clock.now
            XCTAssertNotNil(link.phone.engine.finish(updateTemplate: false))
            link.advance(600)                                   // the notice waits in the link
            try link.deliverAll()

            XCTAssertNil(link.watch.state)
            XCTAssertEqual(link.watch.engine.lastEndNoticeSentAt, finishedAt)
            let end = SyncReconciler.healthWorkoutEnd(
                requested: link.watch.engine.lastEndNoticeSentAt, processedAt: link.watch.clock.now, start: startedAt
            )
            XCTAssertEqual(end, finishedAt, "Health records 1,500 s, not 2,100 s")
            XCTAssertEqual(link.watch.clock.now.timeIntervalSince(end), 600, accuracy: 1e-6)
        }
    }

    func testAPromptNoticeLeavesTheWatchOwnMoment() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.phoneEdit(.logNextSet)
            try link.deliverAll()
            let startedAt = try XCTUnwrap(link.watch.state).startedAt
            link.advance(900)
            XCTAssertNotNil(link.phone.engine.finish(updateTemplate: false))
            link.advance(1)                                     // the link is up: one second
            try link.deliverAll()
            let processed = link.watch.clock.now
            XCTAssertEqual(
                SyncReconciler.healthWorkoutEnd(requested: link.watch.engine.lastEndNoticeSentAt, processedAt: processed, start: startedAt),
                processed
            )
        }
    }
}

// MARK: - An end notice that reaches a Watch with no workout

final class SyncEndNoticeWithoutWorkoutTests: XCTestCase {
    /// The engine has nothing to end, so it tells the effects nothing (it only remembers the id for late states). The Watch
    /// environment sees the envelope itself (`WatchConnectivityClient.onEnvelope`) and decides about a Health session that no
    /// workout has claimed, with the rule below.
    func testTheEngineSaysNothingToTheEffectsForANoticeWithoutAWorkout() {
        svcMain {
            let peer = SyncPeer(role: .mirror)
            let gone = WatchHealth2.state(id: 1, logged: 3)
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: gone.id, sentAt: SvcSyncFix.at(20), discarded: true))
            XCTAssertTrue(peer.recorder.events.isEmpty)
            XCTAssertNil(peer.state)
            XCTAssertNil(peer.engine.lastEndNoticeSentAt, "no workout ended here")
            // A late state of that workout (sent before the notice) is still ignored, a later one is the phone restoring it.
            peer.engine.receive(SyncEnvelope(state: gone, sentAt: SvcSyncFix.at(10)))
            XCTAssertNil(peer.state)
            peer.engine.receive(SyncEnvelope(state: gone, sentAt: SvcSyncFix.at(30)))
            XCTAssertEqual(peer.state?.id, gone.id)
        }
    }

    func testANoticeSentAfterTheSessionBeganSettlesIt() {
        let sessionStart = SvcSyncFix.at(100)
        XCTAssertTrue(SyncReconciler.endNotice(sentAt: SvcSyncFix.at(160), settlesSessionStartedAt: sessionStart),
                      "the phone had no workout after the session began: the workout it records is over")
    }

    func testANoticeSentBeforeTheSessionBeganIsAnOlderWorkoutsAndSettlesNothing() {
        let sessionStart = SvcSyncFix.at(100)
        XCTAssertFalse(SyncReconciler.endNotice(sentAt: SvcSyncFix.at(40), settlesSessionStartedAt: sessionStart),
                       "the last delivered context re-read after a relaunch: an earlier workout was discarded, not this one")
        XCTAssertFalse(SyncReconciler.endNotice(sentAt: sessionStart, settlesSessionStartedAt: sessionStart), "not provably later")
    }

    func testASessionOfUnknownStartIsLeftAlone() {
        XCTAssertFalse(SyncReconciler.endNotice(sentAt: SvcSyncFix.at(500), settlesSessionStartedAt: nil))
    }

    /// The phone's notice for a discard as the Watch reads it from `requestState` after a relaunch: the phone's real envelope, the
    /// session started when the recovered workout did.
    func testThePhonesDiscardNoticeSettlesTheSessionOfTheWorkoutItDiscarded() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.phoneEdit(.logNextSet)
            try link.deliverAll()
            let sessionStart = try XCTUnwrap(link.watch.state).startedAt

            link.advance(120)
            link.phone.engine.discard()
            let notice = try XCTUnwrap(link.toWatch.last)
            XCTAssertNil(notice.state)
            XCTAssertEqual(notice.discarded, true)
            XCTAssertTrue(SyncReconciler.endNotice(sentAt: notice.sentAt, settlesSessionStartedAt: sessionStart))

            // The next workout's session starts after that notice: the same notice, read again, says nothing about it.
            link.advance(60)
            XCTAssertFalse(SyncReconciler.endNotice(sentAt: notice.sentAt, settlesSessionStartedAt: link.phone.clock.now))
        }
    }
}

// MARK: - The controller wrapper

#if canImport(Combine) || PULSE_COMBINE_SHIM

final class SyncWatchHealth2ControllerTests: XCTestCase {
    func testTheControllerForwardsWhenThePhoneSentTheEndNotice() throws {
        svcMain {
            let phoneClock = SvcClock()
            let phone = WorkoutController(store: StrengthStore(persistence: nil, seedDemoData: true), persistence: nil, role: .authority, clock: phoneClock.reader)
            let watch = WorkoutController(store: StrengthStore(persistence: nil), persistence: nil, role: .mirror, clock: SvcClock().reader)
            phone.startWorkout(template: phone.store.templates[0])
            phone.send(.logNextSet)
            watch.receive(phone.makeEnvelope(now: phoneClock.now))
            XCTAssertNotNil(watch.state)
            XCTAssertNil(watch.lastEndNoticeSentAt)

            phoneClock.advance(5)
            let finished = phoneClock.now
            XCTAssertNotNil(phone.finish(updateTemplate: false))
            XCTAssertNil(phone.lastEndNoticeSentAt, "the phone ended it itself")
            watch.receive(phone.makeEnvelope(now: phoneClock.now))
            XCTAssertNil(watch.state)
            XCTAssertEqual(watch.lastEndNoticeSentAt, finished)
        }
    }
}

#endif
