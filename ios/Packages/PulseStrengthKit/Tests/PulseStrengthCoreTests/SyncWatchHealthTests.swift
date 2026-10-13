import Foundation
import XCTest
@testable import PulseStrengthCore

// Regression tests for the Watch / Health findings of the review (ARCHITECTURE 3.4 and 5.5):
//  * a workout the phone DISCARDED must not be saved to Apple Health by the Watch, so the end notice says how the workout ended
//    (`SyncEnvelope.discarded`, `WorkoutEngine.lastEndDiscarded`);
//  * a stale "no workout" notice must not end a workout that was adopted after the notice was written.

private enum WatchHealth {
    /// A workout of "Upper A · Push" with `logged` sets logged.
    static func state(id: Int, logged: Int) -> WorkoutState {
        var state = WorkoutFactory.makeWorkout(from: SampleData.templates()[0], now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(id))
        for step in 0..<logged {
            WorkoutReducer.reduce(&state, .logNextSet, now: SvcSyncFix.at(60 + Double(step) * 90))
        }
        return state
    }

    /// Encodes `message`, removes `key` (or sets it to null) from the JSON object inside `.state`, and decodes it again.
    static func removing(_ key: String, from envelope: SyncEnvelope, asNull: Bool = false) throws -> SyncEnvelope {
        let data = try XCTUnwrap(try SyncCodec.encode(.state(envelope))["m"] as? Data)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var wrapper = try XCTUnwrap(root["state"] as? [String: Any])
        var body = try XCTUnwrap(wrapper["_0"] as? [String: Any])
        if asNull { body[key] = NSNull() } else { body.removeValue(forKey: key) }
        wrapper["_0"] = body
        root["state"] = wrapper
        guard case let .state(decoded) = try SyncCodec.decode(["m": try JSONSerialization.data(withJSONObject: root)]) else {
            throw SyncLinkError.unexpectedKind
        }
        return decoded
    }

    static func roundTrip(_ envelope: SyncEnvelope) throws -> SyncEnvelope {
        guard case let .state(decoded) = try SyncCodec.decode(try SyncCodec.encode(.state(envelope))) else {
            throw SyncLinkError.unexpectedKind
        }
        return decoded
    }
}

// MARK: - The outcome on the wire

final class SyncEndOutcomeWireTests: XCTestCase {
    func testTheOutcomeSurvivesTheCodec() throws {
        for outcome in [true, false] as [Bool?] {
            let envelope = SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(9), sentAt: SvcSyncFix.at(4), discarded: outcome)
            let decoded = try WatchHealth.roundTrip(envelope)
            XCTAssertEqual(decoded.discarded, outcome)
            XCTAssertEqual(decoded, envelope)
        }
        let silent = SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(9), sentAt: SvcSyncFix.at(4))
        XCTAssertNil(silent.discarded)
        XCTAssertNil(try WatchHealth.roundTrip(silent).discarded)
    }

    func testThePayloadOfAnOlderPhoneHasNoOutcome() throws {
        let envelope = SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(9), sentAt: SvcSyncFix.at(4), discarded: true)
        XCTAssertNil(try WatchHealth.removing("discarded", from: envelope).discarded, "a payload without the entry")
        XCTAssertNil(try WatchHealth.removing("discarded", from: envelope, asNull: true).discarded, "a JSON null")
        let older = try WatchHealth.removing("discarded", from: envelope)
        XCTAssertFalse(older.isFromLegacyPhone, "the outcome is not what marks a phone without acknowledgements")
    }

    func testTheOutcomeIsPartOfEqualityAndHashing() {
        let id = SvcSyncFix.uuid(9)
        let discarded = SyncEnvelope(state: nil, endedWorkoutID: id, sentAt: SvcSyncFix.at(4), discarded: true)
        let finished = SyncEnvelope(state: nil, endedWorkoutID: id, sentAt: SvcSyncFix.at(4), discarded: false)
        let silent = SyncEnvelope(state: nil, endedWorkoutID: id, sentAt: SvcSyncFix.at(4))
        XCTAssertNotEqual(discarded, finished)
        XCTAssertNotEqual(discarded, silent)
        XCTAssertNotEqual(finished, silent)
        XCTAssertEqual(Set([discarded, finished, silent]).count, 3)
    }
}

// MARK: - What the phone says

final class SyncPhoneEndOutcomeTests: XCTestCase {
    func testADiscardIsAnnouncedAsDiscarded() throws {
        try svcMain {
            let rig = SvcRig(self)
            let started = rig.startUpperA()
            rig.logSets(2)
            rig.engine.discard()
            XCTAssertTrue(rig.engine.lastEndDiscarded)
            let envelope = rig.engine.makeEnvelope(now: rig.clock.now)
            XCTAssertNil(envelope.state)
            XCTAssertEqual(envelope.endedWorkoutID, started.id)
            XCTAssertEqual(envelope.discarded, true, "a discard with logged sets looks like a finish without the flag")
            XCTAssertEqual(try WatchHealth.roundTrip(envelope).discarded, true)
        }
    }

    func testAFinishIsAnnouncedAsFinished() throws {
        svcMain {
            let rig = SvcRig(self)
            let started = rig.startUpperA()
            rig.logSets(2)
            XCTAssertNotNil(rig.engine.finish(updateTemplate: false))
            XCTAssertFalse(rig.engine.lastEndDiscarded)
            let envelope = rig.engine.makeEnvelope(now: rig.clock.now)
            XCTAssertEqual(envelope.endedWorkoutID, started.id)
            XCTAssertEqual(envelope.discarded, false)
        }
    }

    func testAFinishWithNothingLoggedIsADiscardLikeThePhoneTreatsIt() throws {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            XCTAssertNil(rig.engine.finish(updateTemplate: false), "the engine discards it")
            XCTAssertTrue(rig.engine.lastEndDiscarded)
            XCTAssertEqual(rig.engine.makeEnvelope(now: rig.clock.now).discarded, true)
        }
    }

    func testTheOutcomeBelongsToTheWorkoutThatEndedLast() throws {
        try svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(1)
            rig.engine.discard()
            XCTAssertEqual(rig.engine.makeEnvelope(now: rig.clock.now).discarded, true)
            rig.startUpperA()
            rig.logSets(1)
            let second = try XCTUnwrap(rig.engine.state)
            XCTAssertNotNil(rig.engine.finish(updateTemplate: false))
            let envelope = rig.engine.makeEnvelope(now: rig.clock.now)
            XCTAssertEqual(envelope.endedWorkoutID, second.id)
            XCTAssertEqual(envelope.discarded, false, "the second workout was finished")
        }
    }

    func testARunningWorkoutAndAFreshPhoneSayNothing() throws {
        svcMain {
            let rig = SvcRig(self)
            XCTAssertNil(rig.engine.makeEnvelope(now: rig.clock.now).discarded, "no workout ended since launch")
            rig.startUpperA()
            let running = rig.engine.makeEnvelope(now: rig.clock.now)
            XCTAssertNotNil(running.state)
            XCTAssertNil(running.discarded)
        }
    }

    func testARelaunchedPhoneDoesNotClaimAnOutcome() throws {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(1)
            rig.engine.discard()
            let relaunched = SvcRig(self, persistence: rig.persistence)
            relaunched.engine.restore()
            let envelope = relaunched.engine.makeEnvelope(now: relaunched.clock.now)
            XCTAssertNil(envelope.endedWorkoutID)
            XCTAssertNil(envelope.discarded)
        }
    }
}

// MARK: - What the Watch makes of it

final class SyncWatchEndOutcomeTests: XCTestCase {
    /// A mirror that adopted `state` at t = 10 and received `notice`; returns what `lastEndDiscarded` said INSIDE `workoutEnded`.
    @MainActor
    private func outcome(of state: WorkoutState, notice: SyncEnvelope) -> (ended: Bool, discarded: Bool?) {
        let peer = SyncPeer(role: .mirror)
        var seen: Bool?
        peer.recorder.onEvent = { [unowned peer] event in
            if case .ended = event { seen = peer.engine.lastEndDiscarded }
        }
        peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
        peer.engine.receive(notice)
        return (peer.state == nil, seen)
    }

    func testAnExplicitDiscardIsDiscardedWhateverTheWatchSees() throws {
        svcMain {
            let withSets = WatchHealth.state(id: 1, logged: 3)
            let notice = SyncEnvelope(state: nil, endedWorkoutID: withSets.id, sentAt: SvcSyncFix.at(20), discarded: true)
            let result = outcome(of: withSets, notice: notice)
            XCTAssertTrue(result.ended)
            XCTAssertEqual(result.discarded, true, "set before the effects are told")
        }
    }

    func testAnExplicitFinishIsSavedEvenWhenTheWatchMissedEverySet() throws {
        svcMain {
            let stale = WatchHealth.state(id: 1, logged: 0)
            let notice = SyncEnvelope(state: nil, endedWorkoutID: stale.id, sentAt: SvcSyncFix.at(20), discarded: false)
            XCTAssertEqual(outcome(of: stale, notice: notice).discarded, false, "the phone recorded it; the Watch's copy is stale")
        }
    }

    func testANoticeThatDoesNotSayFallsBackToTheLoggedSets() throws {
        svcMain {
            let empty = WatchHealth.state(id: 1, logged: 0)
            let used = WatchHealth.state(id: 2, logged: 2)
            XCTAssertEqual(
                outcome(of: empty, notice: SyncEnvelope(state: nil, endedWorkoutID: empty.id, sentAt: SvcSyncFix.at(20))).discarded,
                true, "the phone discards a finish without a logged set"
            )
            XCTAssertEqual(
                outcome(of: used, notice: SyncEnvelope(state: nil, endedWorkoutID: used.id, sentAt: SvcSyncFix.at(20))).discarded,
                false
            )
        }
    }

    func testTheLegacyNoWorkoutNoticeFallsBackToTheLoggedSetsToo() throws {
        svcMain {
            let empty = WatchHealth.state(id: 1, logged: 0)
            let used = WatchHealth.state(id: 2, logged: 2)
            XCTAssertEqual(outcome(of: empty, notice: SyncEnvelope(state: nil, sentAt: SvcSyncFix.at(20))).discarded, true)
            XCTAssertEqual(outcome(of: used, notice: SyncEnvelope(state: nil, sentAt: SvcSyncFix.at(20))).discarded, false)
        }
    }

    func testTheFlagOfAnotherWorkoutDoesNotDecideAGhostWorkout() throws {
        svcMain {
            let ghostWithSets = WatchHealth.state(id: 1, logged: 2)
            let ghostEmpty = WatchHealth.state(id: 2, logged: 0)
            let other = SvcSyncFix.uuid(77)
            // The notice is newer than the last state adopted (t = 10) and names another workout: the shown one is a ghost.
            let loud = SyncEnvelope(state: nil, endedWorkoutID: other, sentAt: SvcSyncFix.at(20), discarded: true)
            let quiet = SyncEnvelope(state: nil, endedWorkoutID: other, sentAt: SvcSyncFix.at(20), discarded: false)
            let first = outcome(of: ghostWithSets, notice: loud)
            XCTAssertTrue(first.ended)
            XCTAssertEqual(first.discarded, false, "it has logged sets: saved, whatever happened to the other workout")
            let second = outcome(of: ghostEmpty, notice: quiet)
            XCTAssertTrue(second.ended)
            XCTAssertEqual(second.discarded, true)
        }
    }

    func testAMirrorThatEndsItselfFollowsTheCompletedWorkout() throws {
        svcMain {
            let discarding = SyncPeer(role: .mirror)
            discarding.engine.receive(SyncEnvelope(state: WatchHealth.state(id: 1, logged: 2), sentAt: SvcSyncFix.at(10)))
            discarding.engine.discard()
            XCTAssertTrue(discarding.engine.lastEndDiscarded)

            let finishing = SyncPeer(role: .mirror)
            finishing.engine.receive(SyncEnvelope(state: WatchHealth.state(id: 1, logged: 2), sentAt: SvcSyncFix.at(10)))
            XCTAssertNotNil(finishing.engine.finish(updateTemplate: false))
            XCTAssertFalse(finishing.engine.lastEndDiscarded)
        }
    }

    func testThroughTheLinkThePhonesDiscardAndFinishReachTheWatch() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.phoneEdit(.logNextSet)
            try link.deliverAll()
            link.phone.engine.discard()
            try link.deliverAll()
            XCTAssertNil(link.watch.state)
            XCTAssertTrue(link.watch.engine.lastEndDiscarded, "the Watch is told to throw its Health session away")

            link.advance(5)
            try link.startSynced(template: 1)
            link.phoneEdit(.logNextSet)
            try link.deliverAll()
            XCTAssertNotNil(link.phone.engine.finish(updateTemplate: false))
            try link.deliverAll()
            XCTAssertNil(link.watch.state)
            XCTAssertFalse(link.watch.engine.lastEndDiscarded, "the Watch saves it")
        }
    }
}

// MARK: - A stale "no workout" notice

final class SyncStaleNoWorkoutNoticeTests: XCTestCase {
    /// The Watch re-reads the last delivered application context whenever it wakes. It can lag behind a message: a workout the
    /// phone started after that context was written is adopted from the message, and the old "no workout" must not end it.
    func testAStaleNoWorkoutContextDoesNotEndAWorkoutAdoptedAfterIt() throws {
        svcMain {
            let peer = SyncPeer(role: .mirror)
            let state = WatchHealth.state(id: 1, logged: 0)
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
            peer.engine.receive(SyncEnvelope(state: nil, sentAt: SvcSyncFix.at(0)))
            XCTAssertEqual(peer.state, state, "sent before the state that was adopted: a stale context")
            XCTAssertEqual(peer.recorder.events, [.started(state)], "no end, no second start for the Health session")

            // The real context lands: the same workout again, nothing changes.
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10.5)))
            XCTAssertEqual(peer.recorder.events, [.started(state)])
        }
    }

    func testANoWorkoutNoticeSentAfterTheStateStillEndsTheWorkout() throws {
        svcMain {
            let peer = SyncPeer(role: .mirror)
            let state = WatchHealth.state(id: 1, logged: 1)
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
            peer.engine.receive(SyncEnvelope(state: nil, sentAt: SvcSyncFix.at(10.5)))
            XCTAssertNil(peer.state)
            XCTAssertEqual(peer.recorder.events, [.started(state), .ended(state, nil)])
        }
    }

    func testANoWorkoutNoticeSentAtTheSameInstantAsTheStateStillEnds() throws {
        svcMain {
            let peer = SyncPeer(role: .mirror)
            let state = WatchHealth.state(id: 1, logged: 0)
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
            peer.engine.receive(SyncEnvelope(state: nil, sentAt: SvcSyncFix.at(10)))
            XCTAssertNil(peer.state, "equal times: the notice is not provably older")
        }
    }

    func testAStaleNoticeDoesNotEndTheNextWorkoutEither() throws {
        svcMain {
            let peer = SyncPeer(role: .mirror)
            let first = WatchHealth.state(id: 1, logged: 1)
            let second = WatchHealth.state(id: 2, logged: 0)
            peer.engine.receive(SyncEnvelope(state: first, sentAt: SvcSyncFix.at(10)))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: first.id, sentAt: SvcSyncFix.at(20), discarded: false))
            peer.engine.receive(SyncEnvelope(state: second, sentAt: SvcSyncFix.at(30)))
            XCTAssertEqual(peer.state?.id, second.id)
            peer.engine.receive(SyncEnvelope(state: nil, sentAt: SvcSyncFix.at(5)))
            XCTAssertEqual(peer.state?.id, second.id, "the replayed context is older than the state of the second workout")
            XCTAssertEqual(peer.recorder.events.count, 3)
        }
    }

    func testTheLinkScenarioOfTheReview() throws {
        try svcMain {
            let link = SyncLink()
            // The phone app was launched; the Watch asked for the state before any workout: (no state, no id).
            link.pushEnvelope()
            let stale = try XCTUnwrap(link.toWatch.last)
            XCTAssertNil(stale.state)
            XCTAssertNil(stale.endedWorkoutID)
            link.advance(10)
            try link.startSynced()                              // the Watch adopts the new workout from the message
            let state = try XCTUnwrap(link.watch.state)
            link.watch.engine.receive(stale)                    // a wrist raise re-reads the old context
            XCTAssertEqual(link.watch.state, state)
            XCTAssertEqual(link.watch.recorder.events.count, 1, "started once, never ended")
        }
    }
}

// MARK: - The controller wrapper

#if canImport(Combine) || PULSE_COMBINE_SHIM

final class SyncWatchHealthControllerTests: XCTestCase {
    func testTheControllerForwardsTheOutcomeOfTheLastEnd() throws {
        svcMain {
            let phoneClock = SvcClock()
            let phone = WorkoutController(store: StrengthStore(persistence: nil, seedDemoData: true), persistence: nil, role: .authority, clock: phoneClock.reader)
            let watch = WorkoutController(store: StrengthStore(persistence: nil), persistence: nil, role: .mirror, clock: SvcClock().reader)
            phone.startWorkout(template: phone.store.templates[0])
            phone.send(.logNextSet)
            watch.receive(phone.makeEnvelope(now: phoneClock.now))
            XCTAssertNotNil(watch.state)

            phoneClock.advance(5)
            phone.discard()
            XCTAssertTrue(phone.lastEndDiscarded)
            let notice = phone.makeEnvelope(now: phoneClock.now)
            XCTAssertEqual(notice.discarded, true)
            watch.receive(notice)
            XCTAssertNil(watch.state)
            XCTAssertTrue(watch.lastEndDiscarded)
        }
    }
}

#endif
