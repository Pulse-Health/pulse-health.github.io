import Foundation
import XCTest
@testable import PulseStrengthCore

// Regression tests for the defects found by the adversarial review of the sync protocol (ARCHITECTURE 3.4, "Hardening").
// Each test is a minimal reproduction of one finding; the names start with the finding's id (R1 ... R7, L1, F1).
// They use the in-memory phone / Watch link of SyncProtocolTests.swift.

// MARK: - Helpers

private enum Hardening {
    /// Encodes `message`, lets `edit` change the JSON object inside `.state` / `.command`, and decodes it again.
    static func rewrite(_ message: SyncMessage, key: String, _ edit: (inout [String: Any]) -> Void) throws -> SyncMessage {
        let data = try XCTUnwrap(try SyncCodec.encode(message)["m"] as? Data)
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var wrapper = try XCTUnwrap(root[key] as? [String: Any])
        var body = try XCTUnwrap(wrapper["_0"] as? [String: Any])
        edit(&body)
        wrapper["_0"] = body
        root[key] = wrapper
        return try SyncCodec.decode(["m": try JSONSerialization.data(withJSONObject: root)])
    }

    /// What a phone build without acknowledgements would have sent for `envelope`: the same payload without `ackedCommandIDs`.
    static func legacy(_ envelope: SyncEnvelope) throws -> SyncEnvelope {
        guard case let .state(old) = try rewrite(.state(envelope), key: "state", { $0.removeValue(forKey: "ackedCommandIDs") }) else {
            throw SyncLinkError.unexpectedKind
        }
        return old
    }

    /// The ids of the workouts a peer was told to start, in order.
    @MainActor static func startedIDs(_ peer: SyncPeer) -> [UUID] {
        peer.recorder.events.compactMap { event -> UUID? in
            if case let .started(state) = event { return state.id } else { return nil }
        }
    }

    /// Two different workouts the phone could have: a started "Upper A" and a started "Lower A".
    @MainActor static func twoWorkouts() throws -> (first: WorkoutState, second: WorkoutState) {
        let source = SyncPeer(role: .authority)
        XCTAssertTrue(source.engine.start(template: source.model.data.templates[0]))
        let first = try XCTUnwrap(source.state)
        source.engine.discard()
        XCTAssertTrue(source.engine.start(template: source.model.data.templates[1]))
        return (first, try XCTUnwrap(source.state))
    }
}

// MARK: - R1, R6: which phone envelopes the Watch believes

final class SyncEnvelopeOrderTests: XCTestCase {
    /// R1. A late envelope of a workout the Watch was never told had ended must not revive it.
    func testR1_ALateEnvelopeOfTheReplacedWorkoutIsIgnored() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced(template: 0)
            let w1 = try XCTUnwrap(link.phone.state?.id)
            link.phoneEdit(.rename("W1 edit"))
            let late = link.toWatch.removeLast()                 // sent while W1 ran, will arrive late
            link.phone.engine.discard()                          // W1 ends ...
            link.toWatch.removeAll()                             // ... and the end notice is lost / coalesced away
            link.advance(1)
            XCTAssertTrue(link.phone.engine.start(template: link.phone.model.data.templates[1]))
            try link.deliverAll()
            let w2 = try XCTUnwrap(link.phone.state?.id)
            XCTAssertNotEqual(w1, w2)
            XCTAssertEqual(link.watch.state?.id, w2, "the Watch follows the new workout")

            link.toWatch.append(late)                            // the reordered W1 envelope finally shows up
            try link.deliverEnvelope()
            XCTAssertEqual(link.watch.state?.id, w2, "a late envelope of the replaced workout is ignored")
            XCTAssertEqual(Hardening.startedIDs(link.watch), [w1, w2], "workoutStarted(W1) is not announced a second time")
            XCTAssertEqual(link.watch.engine.authoritativeRevision, link.phone.state?.revision)
        }
    }

    /// R1. `requestState()` re-feeds the session's cached application context, which can lag behind the phone.
    func testR1_AReplayedCachedContextOfAnOlderWorkoutDoesNotRevive() throws {
        try svcMain {
            let link = SyncLink()
            XCTAssertTrue(link.phone.engine.start(template: link.phone.model.data.templates[0]))
            let cachedContext = try XCTUnwrap(link.toWatch.last)  // what receivedApplicationContext holds
            try link.deliverAll()
            link.phone.engine.discard()
            link.toWatch.removeAll()                              // the Watch never hears that it ended
            link.advance(2)
            XCTAssertTrue(link.phone.engine.start(template: link.phone.model.data.templates[1]))
            try link.deliverAll()
            let current = try XCTUnwrap(link.phone.state)

            link.watch.engine.receive(cachedContext)
            XCTAssertEqual(link.watch.state, current, "the cached context of the earlier workout changes nothing")

            link.advance(1)
            link.phoneEdit(.rename("Still in sync"))
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state, "and the newer workout keeps being followed")
        }
    }

    /// R1. After the Watch heard the newest workout ended, an old workout it never heard about is not welcome either.
    func testR1_AnOlderWorkoutCannotComeBackAfterANewerOneEnded() throws {
        try svcMain {
            let (first, second) = try Hardening.twoWorkouts()
            let peer = SyncPeer(role: .mirror)
            peer.engine.receive(SyncEnvelope(state: second, sentAt: SvcSyncFix.at(50)))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: second.id, sentAt: SvcSyncFix.at(60)))
            XCTAssertNil(peer.state)
            peer.engine.receive(SyncEnvelope(state: first, sentAt: SvcSyncFix.at(40)))
            XCTAssertNil(peer.state, "sent before the end notice of the newer workout: a ghost")
            XCTAssertEqual(Hardening.startedIDs(peer), [second.id])
        }
    }

    /// R1. The comparison must not lock the Watch out when the phone's clock jumped back by a lot.
    func testR1_AStateOfAnotherWorkoutMuchOlderThanTheNewestIsStillAdopted() throws {
        try svcMain {
            let (first, second) = try Hardening.twoWorkouts()
            let peer = SyncPeer(role: .mirror)
            peer.engine.receive(SyncEnvelope(state: first, sentAt: SvcSyncFix.at(10_000)))
            // The phone's clock was set back by 100 s: inside the window, so it looks like a late message.
            peer.engine.receive(SyncEnvelope(state: second, sentAt: SvcSyncFix.at(9_900)))
            XCTAssertEqual(peer.state?.id, first.id)
            // Set back by an hour: far outside the window, the new workout must be followed.
            peer.engine.receive(SyncEnvelope(state: second, sentAt: SvcSyncFix.at(10_000 - 3_600)))
            XCTAssertEqual(peer.state?.id, second.id)
            XCTAssertGreaterThan(SyncReconciler.staleEnvelopeWindow, 0)
            XCTAssertLessThan(SyncReconciler.staleEnvelopeWindow, 3_600)
        }
    }

    /// R1. A workout the phone starts right after the previous one is of course adopted (equal send times included).
    func testR1_ANewWorkoutSentAtTheSameInstantOrLaterIsAdopted() throws {
        try svcMain {
            let (first, second) = try Hardening.twoWorkouts()
            let peer = SyncPeer(role: .mirror)
            peer.engine.receive(SyncEnvelope(state: first, sentAt: SvcSyncFix.at(5)))
            peer.engine.receive(SyncEnvelope(state: second, sentAt: SvcSyncFix.at(5)))
            XCTAssertEqual(peer.state?.id, second.id)
        }
    }

    /// R6. The phone ended the workout (its history write failed, the file was kept), was relaunched and restored the SAME
    /// workout: a state sent after the end notice is a resurrection, not a late message.
    func testR6_ARestoredWorkoutIsShownAgainOnAWatchThatHeardItEnded() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let state = try XCTUnwrap(link.phone.state)
            link.phone.engine.discard()
            try link.deliverAll()
            XCTAssertNil(link.watch.state)
            link.advance(60)

            var restored = state
            restored.revision += 1
            link.toWatch.append(SyncEnvelope(state: restored, sentAt: link.phone.clock.now))
            try link.deliverEnvelope()
            XCTAssertEqual(link.watch.state?.id, state.id, "a state sent AFTER the end notice is a resurrection")
            XCTAssertEqual(Hardening.startedIDs(link.watch), [state.id, state.id], "announced as a workout that starts again")
            XCTAssertEqual(link.watch.engine.authoritativeRevision, restored.revision)
        }
    }

    /// R6. What a late message looks like: sent BEFORE the end notice. It stays ignored, also after the resurrection.
    func testR6_AStateSentBeforeTheEndNoticeStaysIgnored() throws {
        try svcMain {
            let (state, _) = try Hardening.twoWorkouts()
            let peer = SyncPeer(role: .mirror)
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: state.id, sentAt: SvcSyncFix.at(20)))
            XCTAssertNil(peer.state)

            var late = state
            late.revision += 3
            peer.engine.receive(SyncEnvelope(state: late, sentAt: SvcSyncFix.at(15)))
            XCTAssertNil(peer.state, "sent before the notice")
            peer.engine.receive(SyncEnvelope(state: late, sentAt: SvcSyncFix.at(20)))
            XCTAssertNil(peer.state, "sent at the same instant as the notice")

            var restored = state
            restored.revision += 1
            peer.engine.receive(SyncEnvelope(state: restored, sentAt: SvcSyncFix.at(21)))
            XCTAssertEqual(peer.state, restored)

            // The restored workout has a LOWER revision than the stale state: only the send time tells them apart.
            peer.engine.receive(SyncEnvelope(state: late, sentAt: SvcSyncFix.at(16)))
            XCTAssertEqual(peer.state, restored, "a stale message from before the notice does not replace the restored workout")
        }
    }

    /// R6. A duplicate of an older end notice that arrives after a newer one does not lower the bar again.
    func testR6_AnOlderDuplicateOfTheNoticeDoesNotReopenTheWorkout() throws {
        try svcMain {
            let (state, _) = try Hardening.twoWorkouts()
            let peer = SyncPeer(role: .mirror)
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: state.id, sentAt: SvcSyncFix.at(30)))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: state.id, sentAt: SvcSyncFix.at(20)))
            var late = state
            late.revision += 1
            peer.engine.receive(SyncEnvelope(state: late, sentAt: SvcSyncFix.at(25)))
            XCTAssertNil(peer.state)
        }
    }

    /// R6. A workout the Watch finished or discarded itself stays ended whatever the phone sends later.
    func testR6_AWorkoutTheWatchEndedItselfStaysEnded() throws {
        try svcMain {
            let (state, _) = try Hardening.twoWorkouts()
            let peer = SyncPeer(role: .mirror)
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
            peer.engine.discard()
            XCTAssertNil(peer.state)
            var later = state
            later.revision += 4
            peer.engine.receive(SyncEnvelope(state: later, sentAt: SvcSyncFix.at(5_000)))
            XCTAssertNil(peer.state)
        }
    }
}

// MARK: - R2, R7: how long an unacknowledged edit is shown

final class SyncPendingLifetimeTests: XCTestCase {
    /// R2. A command that is really lost produces no envelope: the lifetime must not depend on one arriving.
    func testR2_ALostEditDisappearsWithoutAnyEnvelope() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            XCTAssertNil(link.watch.engine.nextPendingExpiry, "nothing pending, nothing to expire")
            link.tap(link.logSet(0, 0))
            let command = try XCTUnwrap(link.toPhone.first)
            link.toPhone.removeAll()                              // the command is lost
            XCTAssertEqual(link.watch.engine.nextPendingExpiry, command.issuedAt.addingTimeInterval(SyncReconciler.pendingLifetime))

            link.advance(14.9)
            XCTAssertFalse(link.watch.engine.expirePending(), "still within its lifetime")
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 0))

            link.advance(0.2)
            let published = link.watch.published.count
            XCTAssertTrue(link.watch.engine.expirePending(), "an edit was dropped")
            XCTAssertFalse(SyncProto.isDone(link.watch, 0, 0), "the lost tap is not shown any more")
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
            XCTAssertNil(link.watch.engine.nextPendingExpiry)
            XCTAssertEqual(link.watch.state, link.phone.state, "the Watch shows the phone's truth again")
            XCTAssertEqual(link.watch.published.count, published + 1, "published once")
            XCTAssertFalse(link.watch.engine.expirePending(), "nothing left to drop")

            link.advance(600)
            XCTAssertFalse(link.watch.engine.expirePending())
            XCTAssertEqual(link.watch.state, link.phone.state)
        }
    }

    /// R2. Only the edits that are too old go; the newer ones stay on top of the phone's state.
    func testR2_NewerEditsStayWhenOlderOnesExpire() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.advance(10)
            link.tap(link.logSet(0, 1))
            let newer = try XCTUnwrap(link.toPhone.last)
            link.toPhone.removeAll()                              // both are lost
            link.advance(6)                                       // the first one is 16 s old, the second one 6 s
            XCTAssertTrue(link.watch.engine.expirePending())
            XCTAssertFalse(SyncProto.isDone(link.watch, 0, 0))
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 1))
            XCTAssertEqual(link.watch.engine.pendingCommands, [newer])
            XCTAssertEqual(link.watch.engine.nextPendingExpiry, newer.issuedAt.addingTimeInterval(SyncReconciler.pendingLifetime))
        }
    }

    /// R2. The Watch's own heart rate is not thrown away with the expired edit.
    func testR2_ExpiringKeepsTheWatchsHeartRate() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.toPhone.removeAll()
            link.watch.engine.send(.updateHeartRate(141), origin: .system)
            link.advance(16)
            XCTAssertTrue(link.watch.engine.expirePending())
            XCTAssertEqual(link.watch.state?.heartRate, 141)
            XCTAssertEqual(link.watch.state?.heartRateCount, 1)
        }
    }

    /// R2. The expiry rule belongs to the mirror only.
    func testR2_AnAuthorityHasNothingToExpire() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.phoneEdit(link.logSet(0, 0))
            link.advance(60)
            XCTAssertNil(link.phone.engine.nextPendingExpiry)
            XCTAssertFalse(link.phone.engine.expirePending())
        }
    }

    /// R2. An edit that is acknowledged is gone for good; the timer has nothing to do for it.
    func testR2_AnAcknowledgedEditNeedsNoExpiry() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            try link.deliverAll()
            XCTAssertNil(link.watch.engine.nextPendingExpiry)
            link.advance(60)
            XCTAssertFalse(link.watch.engine.expirePending())
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 0))
        }
    }

    /// R7. The phone is out of reach: the command waits in the system queue (transferUserInfo) and is delivered whenever the
    /// phone is back. The first envelope after the outage must not make the logged set blink out.
    func testR7_AnEditHeldInTheTransportQueueSurvivesALateEnvelope() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            let command = try XCTUnwrap(link.toPhone.first)
            link.watch.engine.markQueued(commandID: command.id)    // what the client does when it uses transferUserInfo
            link.advance(30)                                      // the outage; the command waits in the queue
            link.phoneEdit(.rename("while away"))
            let publishedBefore = link.watch.published.count
            try link.deliverEnvelope()                            // the connection returns: the context arrives first
            let shown = link.watch.published.dropFirst(publishedBefore).compactMap { $0 }
            XCTAssertFalse(shown.isEmpty)
            XCTAssertTrue(shown.allSatisfy { $0.exercises[0].sets[0].isDone }, "the logged set never disappears from the Watch")
            XCTAssertEqual(link.watch.state?.name, "while away")
            XCTAssertEqual(link.watch.engine.pendingCommands, [command])
            XCTAssertFalse(link.watch.engine.expirePending(), "and the timer leaves it alone as well")

            try link.deliverAll()                                 // the queued command arrives and is acknowledged
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertTrue(SyncProto.isDone(link.phone, 0, 0))
        }
    }

    /// R7. An edit the transport only SENT (sendMessage) is not queued: it keeps the short lifetime, so a lost command is still
    /// detected after 15 s.
    func testR7_AnEditThatWasNotQueuedKeepsTheShortLifetime() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.advance(30)
            link.phoneEdit(.rename("later"))
            try link.deliverEnvelope()
            XCTAssertFalse(SyncProto.isDone(link.watch, 0, 0))
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
        }
    }

    /// R7. Queued edits are not shown for ever: a command the system queue lost is dropped after the long lifetime.
    func testR7_AQueuedEditThatNeverArrivesEventuallyExpires() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            let command = try XCTUnwrap(link.toPhone.first)
            link.watch.engine.markQueued(commandID: command.id)
            link.toPhone.removeAll()
            XCTAssertEqual(link.watch.engine.nextPendingExpiry, command.issuedAt.addingTimeInterval(SyncReconciler.queuedPendingLifetime))

            link.advance(SyncReconciler.pendingLifetime + 60)
            XCTAssertFalse(link.watch.engine.expirePending())
            link.advance(SyncReconciler.queuedPendingLifetime)
            XCTAssertTrue(link.watch.engine.expirePending())
            XCTAssertFalse(SyncProto.isDone(link.watch, 0, 0))
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertGreaterThan(SyncReconciler.queuedPendingLifetime, 30 * 60, "longer than a workout-sized outage of the phone")
        }
    }

    /// R7. Marking a command that is not (or no longer) pending does nothing and is not remembered.
    func testR7_MarkingAnUnknownOrAnAcknowledgedCommandChangesNothing() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.watch.engine.markQueued(commandID: SvcSyncFix.uuid(404))
            XCTAssertNil(link.watch.engine.nextPendingExpiry)

            link.tap(link.logSet(0, 0))
            let first = try XCTUnwrap(link.toPhone.first)
            try link.deliverAll()                                 // acknowledged
            link.watch.engine.markQueued(commandID: first.id)     // too late: it must not make the next command long-lived
            link.tap(link.logSet(0, 1))
            let second = try XCTUnwrap(link.toPhone.first)
            XCTAssertEqual(link.watch.engine.nextPendingExpiry, second.issuedAt.addingTimeInterval(SyncReconciler.pendingLifetime))
        }
    }

    /// R7. Edits that are queued and edits that are not mix: each follows its own lifetime.
    func testR7_QueuedAndUnqueuedEditsFollowTheirOwnLifetime() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))                           // sent
            link.tap(link.logSet(0, 1))                           // queued
            let queued = link.toPhone[1]
            link.watch.engine.markQueued(commandID: queued.id)
            link.toPhone.removeAll()
            link.advance(20)
            XCTAssertTrue(link.watch.engine.expirePending())
            XCTAssertFalse(SyncProto.isDone(link.watch, 0, 0))
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 1))
            XCTAssertEqual(link.watch.engine.pendingCommands, [queued])
        }
    }
}

// MARK: - R3, R5, L1: commands on the authority

final class SyncCommandOrderTests: XCTestCase {
    /// R3. The two channels have no common order: the user's last absolute edit must not be reverted by an older one.
    func testR3_AnOvertakenAbsoluteEditDoesNotRevertTheNewerOne() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.setWeight(0, 2, 70))
            link.advance(0.5)
            link.tap(link.setWeight(0, 2, 80))                    // the user's last word
            XCTAssertEqual(SyncProto.weight(link.watch, 0, 2), 80)
            try link.deliverCommand(at: 1)                        // the second command (sendMessage) overtakes the first
            try link.deliverCommand(at: 0)
            try link.deliverAll()
            XCTAssertEqual(SyncProto.weight(link.phone, 0, 2), 80, "the phone ends with the user's last edit")
            XCTAssertEqual(SyncProto.weight(link.watch, 0, 2), 80, "and so does the Watch (no snap-back)")
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty, "the overtaken command was acknowledged all the same")
            XCTAssertEqual(link.phone.recorder.changes.count, 1, "and it changed nothing")
        }
    }

    /// R3. The same holds for the other absolute edits, each per value.
    func testR3_EveryAbsoluteEditIsOrderedPerValue() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let ref = link.refs(0, 1)
            let other = link.refs(0, 2)
            let exercise = ref.exercise
            let edits: [(older: WorkoutAction, newer: WorkoutAction, holds: (WorkoutState) -> Bool)] = [
                (.setReps(exerciseID: exercise, setID: ref.set, reps: 3), .setReps(exerciseID: exercise, setID: ref.set, reps: 9),
                 { $0.exercises[0].sets[1].reps == 9 }),
                (.setSetType(exerciseID: exercise, setID: ref.set, type: .failure), .setSetType(exerciseID: exercise, setID: ref.set, type: .drop),
                 { $0.exercises[0].sets[1].type == .drop }),
                (.setRIR(exerciseID: exercise, setID: ref.set, rir: 1), .setRIR(exerciseID: exercise, setID: ref.set, rir: 3),
                 { $0.exercises[0].sets[1].rir == 3 }),
                (.setNote(exerciseID: exercise, note: "first"), .setNote(exerciseID: exercise, note: "second"),
                 { $0.exercises[0].note == "second" }),
                (.setRest(exerciseID: exercise, seconds: 45), .setRest(exerciseID: exercise, seconds: 75),
                 { $0.exercises[0].restSeconds == 75 }),
            ]
            for edit in edits {
                link.tap(edit.older)
                link.tap(edit.newer)
                try link.deliverCommand(at: 1)                    // the newer command overtakes the older one
                try link.deliverCommand(at: 0)
                try link.deliverAll()
                XCTAssertTrue(edit.holds(try XCTUnwrap(link.phone.state)), "the phone keeps the newer value of \(edit.older)")
                XCTAssertEqual(link.watch.state, link.phone.state, "\(edit.older)")
            }
            // A different set is a different value: an older edit of it is not mistaken for a superseded one.
            link.tap(.setWeight(exerciseID: exercise, setID: ref.set, kg: 61))
            link.tap(.setWeight(exerciseID: exercise, setID: other.set, kg: 62))
            try link.deliverCommand(at: 1)
            try link.deliverCommand(at: 0)
            try link.deliverAll()
            XCTAssertEqual(SyncProto.weight(link.phone, 0, 1), 61)
            XCTAssertEqual(SyncProto.weight(link.phone, 0, 2), 62)
        }
    }

    /// R3. Only the Watch's own numbering is compared: a restarted Watch starts again at 1 and is not mistaken for old news.
    func testR3_ARestartedWatchIsNotSuppressedByTheNumbersOfItsPredecessor() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            for kg in [70.0, 72.5, 75.0] { link.tap(link.setWeight(0, 2, kg)) }
            XCTAssertEqual(link.issued.map { $0.sequence }, [1, 2, 3])
            try link.deliverAll()

            link.restartWatch()
            link.pushEnvelope()
            try link.deliverEnvelope(at: link.toWatch.count - 1)
            link.tap(link.setWeight(0, 2, 80))
            XCTAssertEqual(link.issued.last?.sequence, 1, "the new launch starts counting again")
            XCTAssertNotEqual(link.issued.last?.senderID, link.issued.first?.senderID)
            try link.deliverAll()
            XCTAssertEqual(SyncProto.weight(link.phone, 0, 2), 80)
            XCTAssertEqual(link.watch.state, link.phone.state)
        }
    }

    /// R3. Sequence numbers run 1, 2, 3 ... within one launch, for the commands the mirror makes (and only those).
    func testR3_TheMirrorNumbersItsCommands() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.tap(.skipRest)
            link.tap(.updateHeartRate(120))                       // makes no command
            link.tap(link.setWeight(0, 2, 70))
            XCTAssertEqual(link.issued.map { $0.sequence }, [1, 2, 3])
            XCTAssertEqual(Set(link.issued.map { $0.senderID }).count, 1)
            XCTAssertNotNil(link.issued.first?.senderID)
        }
    }

    /// R3. A command without numbers (an older Watch app) is applied in arrival order, as before.
    func testR3_ACommandWithoutNumbersIsAppliedInArrivalOrder() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let ref = link.refs(0, 2)
            let workout = try XCTUnwrap(link.phone.state?.id)
            link.phone.engine.receive(RemoteCommand(action: .setWeight(exerciseID: ref.exercise, setID: ref.set, kg: 80), origin: .watch, workoutID: workout))
            link.phone.engine.receive(RemoteCommand(action: .setWeight(exerciseID: ref.exercise, setID: ref.set, kg: 70), origin: .watch, workoutID: workout))
            XCTAssertEqual(SyncProto.weight(link.phone, 0, 2), 70)
        }
    }

    /// R3. The numbers are optional on the wire: they survive a round trip and an older payload decodes to nil.
    func testR3_SenderAndSequenceTravelOptionally() throws {
        let sender = SvcSyncFix.uuid(77)
        let numbered = RemoteCommand(id: SvcSyncFix.uuid(7), action: .skipRest, origin: .watch, issuedAt: SvcSyncFix.at(2),
                                     workoutID: SvcSyncFix.uuid(1), senderID: sender, sequence: 12)
        XCTAssertEqual(try SyncCodec.decode(try SyncCodec.encode(.command(numbered))), .command(numbered))
        guard case let .command(old) = try Hardening.rewrite(.command(numbered), key: "command", { body in
            XCTAssertEqual(body["sequence"] as? Int, 12)
            body.removeValue(forKey: "senderID")
            body.removeValue(forKey: "sequence")
        }) else { return XCTFail("not a command") }
        XCTAssertNil(old.senderID)
        XCTAssertNil(old.sequence)
        XCTAssertEqual(old.id, numbered.id)
        XCTAssertEqual(old.workoutID, numbered.workoutID)
        let plain = RemoteCommand(action: .skipRest, origin: .watch)
        XCTAssertNil(plain.senderID)
        XCTAssertNil(plain.sequence)
    }

    /// R3. The list of newest edits is bounded, and forgetting a value only means that an old edit of it would be applied.
    func testR3_TheOrderingMemoryIsBounded() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let workout = try XCTUnwrap(link.phone.state?.id)
            let sender = SvcSyncFix.uuid(5)
            let exercise = link.refs(0, 0).exercise
            for number in 1...400 {
                link.phone.engine.receive(RemoteCommand(
                    action: .setNote(exerciseID: SvcSyncFix.uuid(10_000 + number), note: "x"), origin: .watch,
                    workoutID: workout, senderID: sender, sequence: number
                ))
            }
            // Still works for the values that were seen last.
            link.phone.engine.receive(RemoteCommand(action: .setNote(exerciseID: exercise, note: "new"), origin: .watch, workoutID: workout, senderID: sender, sequence: 401))
            link.phone.engine.receive(RemoteCommand(action: .setNote(exerciseID: exercise, note: "old"), origin: .watch, workoutID: workout, senderID: sender, sequence: 400))
            XCTAssertEqual(link.phone.state?.exercises[0].note, "new")
            func memory(_ label: String) -> Int {
                for child in Mirror(reflecting: link.phone.engine).children where child.label == label {
                    return Mirror(reflecting: child.value).children.count
                }
                return -1
            }
            XCTAssertGreaterThan(memory("newestEdit"), 0)
            XCTAssertLessThanOrEqual(memory("newestEdit"), 128)
        }
    }

    /// R5. An effect that edits from inside `workoutChanged` must not make the commands leave in the opposite order.
    func testR5_CommandsLeaveInTheOrderTheyWereApplied() throws {
        try svcMain {
            final class Reactive: WorkoutSideEffect {
                weak var engine: WorkoutEngine?
                var fired = false
                func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
                    if case .logSet = action, !fired {
                        fired = true
                        engine?.send(.adjustRest(seconds: 15), origin: .watch)
                    }
                }
            }
            let link = SyncLink()
            try link.startSynced()
            let reactive = Reactive()
            reactive.engine = link.watch.engine
            link.watch.engine.addEffect(reactive)
            link.tap(link.logSet(0, 0))
            let pendingOrder = link.watch.engine.pendingCommands.map { $0.action }
            XCTAssertEqual(pendingOrder.count, 2)
            XCTAssertEqual(link.toPhone.map { $0.action }, pendingOrder, "commands are sent in the order they were applied")
            XCTAssertEqual(link.toPhone.map { $0.sequence }, [1, 2])
            XCTAssertEqual(link.watch.log.calls.compactMap { call -> WorkoutAction? in
                if case let .issued(command) = call { return command.action } else { return nil }
            }, pendingOrder)

            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state, "and the Watch does not snap to a different result")
        }
    }

    /// R5. An effect that edits from inside `commandIssued` (the client itself) is queued behind the command being announced:
    /// an effect registered after it must not hear the nested command first.
    func testR5_AnEditMadeWhileACommandIsAnnouncedIsAnnouncedAfterIt() throws {
        try svcMain {
            final class Chatty: WorkoutSideEffect {
                weak var engine: WorkoutEngine?
                var fired = false
                func commandIssued(_ command: RemoteCommand) {
                    if !fired {
                        fired = true
                        engine?.send(.adjustRest(seconds: 15), origin: .watch)
                    }
                }
            }
            final class Listener: WorkoutSideEffect {
                var seen: [WorkoutAction] = []
                func commandIssued(_ command: RemoteCommand) { seen.append(command.action) }
            }
            let link = SyncLink()
            try link.startSynced()
            let chatty = Chatty()
            chatty.engine = link.watch.engine
            let listener = Listener()
            link.watch.engine.addEffect(chatty)
            link.watch.engine.addEffect(listener)                 // registered after the chatty effect
            link.tap(link.logSet(0, 0))
            let order = [link.logSet(0, 0), WorkoutAction.adjustRest(seconds: 15)]
            XCTAssertEqual(link.toPhone.map { $0.action }, order)
            XCTAssertEqual(listener.seen, order, "every effect hears the commands in the order they were made")
            XCTAssertEqual(link.watch.engine.pendingCommands.map { $0.action }, order)
            XCTAssertEqual(link.toPhone.map { $0.sequence }, [1, 2])
        }
    }

    /// L1. The Watch showed the rest from the tap; the phone must start it at the tap as well, not when the command arrives.
    func testL1_ALateCommandActsAtTheTimeOfTheTap() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let tapAt = link.watch.clock.now
            link.tap(link.logSet(0, 2))
            let watchEnds = try XCTUnwrap(link.watch.state?.rest?.endsAt)
            XCTAssertEqual(watchEnds, tapAt.addingTimeInterval(150))
            link.advance(40)                                      // queued by transferUserInfo while out of reach
            try link.deliverCommand()
            XCTAssertEqual(link.phone.state?.rest?.endsAt, watchEnds, "the phone anchors the rest at the time of the tap")
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state, "so the acknowledgement does not move the Watch's timer")
        }
    }

    /// L1. With a normal delivery delay the two timers agree as well (before, the phone's was a fraction of a second behind).
    func testL1_TheTwoRestTimersAgreeAfterANormalRoundTrip() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 2))
            link.advance(0.4)
            try link.deliverCommand()
            try link.deliverAll()
            XCTAssertEqual(link.watch.state?.rest, link.phone.state?.rest)
            XCTAssertEqual(link.watch.state, link.phone.state)
        }
    }

    /// L1. A command that is too old is not trusted: it acts at delivery time, like an instant that cannot be explained.
    func testL1_ACommandMuchOlderThanTheWindowActsAtDeliveryTime() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 2))
            link.advance(SyncReconciler.lateCommandWindow + 30)
            let delivered = link.phone.clock.now
            try link.deliverCommand()
            XCTAssertEqual(link.phone.state?.rest?.endsAt, delivered.addingTimeInterval(150))
        }
    }

    /// L1. A command stamped in the future (the Watch's clock runs ahead) acts at delivery time.
    func testL1_ACommandFromTheFutureActsAtDeliveryTime() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.watch.clock.advance(45)                          // the Watch's clock is ahead
            link.tap(link.logSet(0, 2))
            let delivered = link.phone.clock.now
            try link.deliverCommand()
            XCTAssertEqual(link.phone.state?.rest?.endsAt, delivered.addingTimeInterval(150))
        }
    }

    /// L1. A command without a stamp that makes sense (older payload: now) behaves as before.
    func testL1_ACommandStampedNowActsNow() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let ref = link.refs(0, 2)
            let command = RemoteCommand(action: .logSet(exerciseID: ref.exercise, setID: ref.set), origin: .watch,
                                        issuedAt: link.phone.clock.now, workoutID: link.phone.state?.id)
            link.phone.engine.receive(command)
            XCTAssertEqual(link.phone.state?.rest?.endsAt, link.phone.clock.now.addingTimeInterval(150))
        }
    }
}

// MARK: - R4: the phone is relaunched

final class SyncRelaunchTests: XCTestCase {
    /// R4a. A redelivered command is not applied a second time after the phone app was relaunched.
    func testR4_ARedeliveredCommandIsNotAppliedTwiceAfterARelaunch() throws {
        try svcMain {
            let phone1 = SvcRig(self)
            phone1.startUpperA()
            let workoutID = try XCTUnwrap(phone1.engine.state?.id)
            let command = RemoteCommand(action: .nudgeNextSet(weightSteps: 1, repsSteps: 0), origin: .watch, issuedAt: SvcSyncFix.epoch, workoutID: workoutID)
            phone1.engine.receive(command)
            let afterFirst = try XCTUnwrap(phone1.engine.state)

            // The app is killed and relaunched; the active workout is restored from disk.
            let phone2 = SvcRig(self, persistence: phone1.persistence)
            phone2.engine.restore()
            XCTAssertEqual(phone2.engine.state, afterFirst)

            phone2.engine.receive(command)                        // the slow path delivers the same command again
            XCTAssertEqual(phone2.engine.state, afterFirst, "a redelivered command must not apply twice across a relaunch")
            XCTAssertEqual(phone2.engine.state?.revision, afterFirst.revision)
        }
    }

    /// R4b. The first envelope after the relaunch acknowledges what the phone applied before it, so the Watch does not replay it.
    func testR4_TheRestoredPhoneStillAcknowledgesWhatItAppliedBeforeTheRelaunch() throws {
        try svcMain {
            let phone1 = SvcRig(self)
            phone1.startUpperA()
            let watch = SvcRig(self, role: .mirror)
            var issued: [RemoteCommand] = []
            let log = SyncCallLog()
            log.onIssue = { issued.append($0) }
            watch.engine.addEffect(log)
            watch.engine.receive(phone1.engine.makeEnvelope(now: SvcSyncFix.epoch))
            let before = try XCTUnwrap(watch.engine.state?.exercises[0].sets[0].weightKg)

            watch.engine.send(.nudgeNextSet(weightSteps: 1, repsSteps: 0), origin: .watch)
            let command = try XCTUnwrap(issued.first)
            phone1.engine.receive(command)                        // applied and saved; its envelope never leaves

            let phone2 = SvcRig(self, persistence: phone1.persistence)   // the app is relaunched
            phone2.engine.restore()
            watch.clock.advance(1)
            watch.engine.receive(phone2.engine.makeEnvelope(now: SvcSyncFix.at(1)))

            let phoneWeight = try XCTUnwrap(phone2.engine.state?.exercises[0].sets[0].weightKg)
            let watchWeight = try XCTUnwrap(watch.engine.state?.exercises[0].sets[0].weightKg)
            XCTAssertEqual(phoneWeight, before + 2.5)
            XCTAssertEqual(watchWeight, phoneWeight, "the nudge is shown once")
            XCTAssertTrue(watch.engine.pendingCommands.isEmpty, "and is no longer pending")
        }
    }

    /// R4. The acknowledgements are written after every command and read back by `restore()` in their order.
    func testR4_TheAcknowledgementsAreSavedAndRestoredInOrder() throws {
        try svcMain {
            let phone1 = SvcRig(self)
            phone1.startUpperA()
            let workoutID = try XCTUnwrap(phone1.engine.state?.id)
            var ids: [UUID] = []
            for number in 0..<5 {
                let command = RemoteCommand(id: SvcSyncFix.uuid(2_000 + number), action: .skipRest, origin: .watch, workoutID: workoutID)
                ids.append(command.id)
                phone1.engine.receive(command)
                XCTAssertEqual(phone1.persistence.loadAcknowledgedCommands(), ids, "saved right after the command")
            }
            phone1.engine.receive(RemoteCommand(id: ids[0], action: .skipRest, origin: .watch, workoutID: workoutID))
            let expected = Array(ids.dropFirst()) + [ids[0]]
            XCTAssertEqual(phone1.persistence.loadAcknowledgedCommands(), expected, "a repeated id moves to the most recent position")

            let phone2 = SvcRig(self, persistence: phone1.persistence)
            phone2.engine.restore()
            XCTAssertEqual(phone2.engine.makeEnvelope(now: SvcSyncFix.epoch).ackedCommandIDs, expected)
        }
    }

    /// R4. Even a relaunch without a workout (it was finished) remembers which commands were dealt with.
    func testR4_ACommandOfAFinishedWorkoutStaysAcknowledgedAfterARelaunch() throws {
        svcMain {
            let phone1 = SvcRig(self)
            phone1.startUpperA()
            let command = RemoteCommand(action: .skipRest, origin: .watch, workoutID: phone1.engine.state?.id)
            phone1.engine.receive(command)
            phone1.engine.discard()

            let phone2 = SvcRig(self, persistence: phone1.persistence)
            phone2.engine.restore()
            XCTAssertNil(phone2.engine.state)
            XCTAssertEqual(phone2.engine.makeEnvelope(now: SvcSyncFix.epoch).ackedCommandIDs, [command.id])
        }
    }

    /// R4. The memory on disk is bounded and a damaged file reads as empty.
    func testR4_TheAcknowledgementFileIsBoundedAndTolerant() throws {
        let persistence = FileStrengthPersistence.temporary()
        addTeardownBlock { try? FileManager.default.removeItem(at: persistence.directory) }
        XCTAssertEqual(persistence.loadAcknowledgedCommands(), [], "no file")
        let ids = (0..<300).map { SvcSyncFix.uuid(3_000 + $0) }
        try persistence.saveAcknowledgedCommands(ids)
        XCTAssertEqual(persistence.loadAcknowledgedCommands(), Array(ids.suffix(SyncReconciler.acknowledgedMemory)))
        try Data("not json".utf8).write(to: persistence.directory.appendingPathComponent("acknowledged-commands.json"))
        XCTAssertEqual(persistence.loadAcknowledgedCommands(), [], "a damaged file")
        try persistence.saveAcknowledgedCommands([])
        XCTAssertEqual(persistence.loadAcknowledgedCommands(), [])
    }

    /// R4. A mirror never touches the acknowledgement file.
    func testR4_AMirrorWritesNoAcknowledgements() throws {
        svcMain {
            let watch = SvcRig(self, role: .mirror)
            watch.engine.start(template: watch.upperA)
            watch.engine.send(.skipRest, origin: .watch)
            watch.engine.restore()
            XCTAssertEqual(watch.persistence.loadAcknowledgedCommands(), [])
            XCTAssertFalse(FileManager.default.fileExists(atPath: watch.persistence.directory.appendingPathComponent("acknowledged-commands.json").path))
        }
    }
}

// MARK: - F1: a Watch app that is newer than the phone app

final class SyncLegacyPhoneTests: XCTestCase {
    /// F1. A phone build without acknowledgements never acknowledges: the Watch must not wait for acknowledgements.
    func testF1_ANewWatchDoesNotDoubleApplyItsTapsOnAPhoneThatNeverAcknowledges() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.tap(.nudgeNextSet(weightSteps: 1, repsSteps: 0))
            try link.deliverCommand()
            try link.deliverCommand()
            let envelope = try Hardening.legacy(try XCTUnwrap(link.toWatch.last))
            XCTAssertTrue(envelope.isFromLegacyPhone)
            XCTAssertEqual(envelope.ackedCommandIDs, [])

            link.watch.engine.receive(envelope)
            XCTAssertEqual(link.watch.state, link.phone.state, "the phone's state wins: the nudge is not shown twice")
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
        }
    }

    /// F1. The edit is still shown until the phone's first envelope arrives (the optimistic part keeps working).
    func testF1_TheEditIsShownUntilTheLegacyPhoneAnswers() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(.nudgeNextSet(weightSteps: 1, repsSteps: 0))
            let shown = try XCTUnwrap(link.watch.state)
            XCTAssertNotEqual(shown, link.phone.state)
            XCTAssertEqual(link.watch.engine.pendingCommands.count, 1)
        }
    }

    /// F1. Only an envelope that LACKS the entry is legacy; this code's own envelopes (even with no acknowledgements) are not.
    func testF1_OnlyAMissingEntryMarksAnEnvelopeAsLegacy() throws {
        let plain = SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(9), sentAt: SvcSyncFix.at(4))
        XCTAssertFalse(plain.isFromLegacyPhone)
        guard case let .state(roundTripped) = try SyncCodec.decode(try SyncCodec.encode(.state(plain))) else { return XCTFail("not a state") }
        XCTAssertFalse(roundTripped.isFromLegacyPhone, "an empty list is written and read back as a list")
        let legacy = try Hardening.legacy(plain)
        XCTAssertTrue(legacy.isFromLegacyPhone)
        XCTAssertEqual(legacy, plain, "equality ignores the marker")
        XCTAssertEqual(legacy.hashValue, plain.hashValue)
        // A JSON null counts as missing too.
        guard case let .state(nulled) = try Hardening.rewrite(.state(plain), key: "state", { $0["ackedCommandIDs"] = NSNull() }) else { return XCTFail("not a state") }
        XCTAssertTrue(nulled.isFromLegacyPhone)
    }

    /// F1. A phone that acknowledges (this code) keeps the unacknowledged edits on top, as before.
    func testF1_AnAcknowledgingPhoneStillKeepsUnacknowledgedEditsOnTop() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(.nudgeNextSet(weightSteps: 1, repsSteps: 0))
            link.phoneEdit(.rename("unrelated"))                  // an envelope that does not acknowledge the nudge yet
            let envelope = try XCTUnwrap(link.toWatch.last)
            XCTAssertFalse(envelope.isFromLegacyPhone)
            try link.deliverEnvelope(at: link.toWatch.count - 1)
            XCTAssertEqual(link.watch.engine.pendingCommands.count, 1)
            XCTAssertNotEqual(link.watch.state, link.phone.state)
        }
    }

    /// F1. The end of the workout, announced by a legacy phone, still works.
    func testF1_ALegacyEndNoticeStillEndsTheWorkout() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.phone.engine.discard()
            let notice = try Hardening.legacy(try XCTUnwrap(link.toWatch.last))
            link.watch.engine.receive(notice)
            XCTAssertNil(link.watch.state)
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
        }
    }
}

// MARK: - The controller wrapper

#if canImport(Combine) || PULSE_COMBINE_SHIM
#if canImport(Combine)
import Combine
#endif

final class SyncHardeningControllerTests: XCTestCase {
    /// R2, R7. The controller forwards the expiry API of the engine.
    func testTheControllerForwardsTheExpiryAndQueueApi() throws {
        try svcMain {
            let phoneClock = SvcClock()
            let watchClock = SvcClock()
            let phone = WorkoutController(store: StrengthStore(persistence: nil, seedDemoData: true), persistence: nil, role: .authority, clock: phoneClock.reader)
            let watch = WorkoutController(store: StrengthStore(persistence: nil), persistence: nil, role: .mirror, clock: watchClock.reader)
            let log = SyncCallLog()
            watch.addEffect(log)
            phone.startWorkout(template: phone.store.templates[0])
            watch.receive(phone.makeEnvelope(now: phoneClock.now))
            let started = try XCTUnwrap(phone.state)
            XCTAssertNil(watch.nextPendingExpiry)

            watch.send(.logSet(exerciseID: started.exercises[0].id, setID: started.exercises[0].sets[0].id), origin: .watch)
            let first = try XCTUnwrap(log.issued.first)
            XCTAssertEqual(watch.nextPendingExpiry, first.issuedAt.addingTimeInterval(SyncReconciler.pendingLifetime))
            watch.markQueued(commandID: first.id)
            XCTAssertEqual(watch.nextPendingExpiry, first.issuedAt.addingTimeInterval(SyncReconciler.queuedPendingLifetime))

            watch.send(.logSet(exerciseID: started.exercises[0].id, setID: started.exercises[0].sets[1].id), origin: .watch)
            watchClock.advance(20)
            XCTAssertTrue(watch.expirePending())
            XCTAssertEqual(watch.state?.exercises[0].sets[0].isDone, true, "the queued edit stays")
            XCTAssertEqual(watch.state?.exercises[0].sets[1].isDone, false, "the lost one goes")
            XCTAssertEqual(watch.pendingCommands, [first])
        }
    }

    /// F1. The controller treats a legacy envelope like the engine does.
    func testTheControllerLetsALegacyPhoneWin() throws {
        try svcMain {
            let phoneClock = SvcClock()
            let phone = WorkoutController(store: StrengthStore(persistence: nil, seedDemoData: true), persistence: nil, role: .authority, clock: phoneClock.reader)
            let watch = WorkoutController(store: StrengthStore(persistence: nil), persistence: nil, role: .mirror, clock: SvcClock().reader)
            phone.startWorkout(template: phone.store.templates[0])
            watch.receive(phone.makeEnvelope(now: phoneClock.now))
            watch.send(.nudgeNextSet(weightSteps: 1, repsSteps: 0), origin: .watch)
            XCTAssertEqual(watch.pendingCommands.count, 1)
            phone.send(.rename("Phone"))
            watch.receive(try Hardening.legacy(phone.makeEnvelope(now: phoneClock.now)))
            XCTAssertEqual(watch.state, phone.state)
            XCTAssertTrue(watch.pendingCommands.isEmpty)
        }
    }
}

#endif
