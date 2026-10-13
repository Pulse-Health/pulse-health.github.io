import Foundation
import XCTest
@testable import PulseStrengthCore

// Tests of the phone / Watch sync protocol (ARCHITECTURE 3.4): optimistic edits on the mirror, acknowledgements from the
// authority, and convergence over a link that duplicates, delays, reorders and drops messages.
//
// The harness below connects an authority engine (the phone) and a mirror engine (the Watch) through an in-memory `SyncLink`.
// The link behaves like `PhoneWatchBridge` and `WatchConnectivityClient`: the phone pushes `makeEnvelope(now:)` after every
// change and after every command it received (changed or not); the Watch sends each `commandIssued` command to the phone.
// A scenario scripts the delivery by hand (deliver / delay / duplicate / reorder / drop); the fuzz test draws it from a seed.
// `WorkoutController` is a thin wrapper over `WorkoutEngine`, so the scenarios run on the engines (always compiled); the
// controller wrapper has its own tests at the end of the file (they need Combine or the Combine stand-in).

// MARK: - Harness

/// Records what the engine tells a side effect about commands, in call order.
@MainActor
final class SyncCallLog: WorkoutSideEffect {
    enum Call: Equatable {
        case changed(WorkoutAction, ActionOrigin)
        case issued(RemoteCommand)
    }

    private(set) var calls: [Call] = []
    var onIssue: ((RemoteCommand) -> Void)?

    var issued: [RemoteCommand] {
        calls.compactMap { if case let .issued(command) = $0 { return command } else { return nil } }
    }

    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        calls.append(.changed(action, origin))
    }

    func commandIssued(_ command: RemoteCommand) {
        calls.append(.issued(command))
        onIssue?(command)
    }
}

/// One side of the link: an engine with its own clock, a recorder and a log of the states it published.
@MainActor
final class SyncPeer {
    let clock = SvcClock()
    let model: StrengthDataModel
    let engine: WorkoutEngine
    let recorder = SvcRecorder()
    let log = SyncCallLog()
    private(set) var published: [WorkoutState?] = []

    init(role: WorkoutRole) {
        model = StrengthDataModel(persistence: nil, seedDemoData: true, now: SvcSyncFix.epoch)
        engine = WorkoutEngine(role: role, persistence: nil, data: model, clock: clock.reader)
        engine.addEffect(recorder)
        engine.addEffect(log)
        engine.onUpdate = { [unowned self] in self.published.append(self.engine.state) }
    }

    var state: WorkoutState? { engine.state }
}

/// The phone's side effect: what `PhoneWatchBridge` does, pushing an envelope for every change except heart-rate samples.
@MainActor
final class SyncPhoneBridge: WorkoutSideEffect {
    private weak var link: SyncLink?

    init(link: SyncLink) {
        self.link = link
    }

    func workoutStarted(_ state: WorkoutState) { link?.pushEnvelope() }

    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        if case .updateHeartRate = action { return }
        link?.pushEnvelope()
    }

    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) { link?.pushEnvelope() }
}

enum SyncLinkError: Error {
    case unexpectedKind
}

/// The outcome of delivering one command to the phone.
struct SyncDelivery {
    var command: RemoteCommand
    var changedState: Bool
}

/// An in-memory connection between a phone (authority) and a Watch (mirror) with a scriptable transport.
@MainActor
final class SyncLink {
    let phone = SyncPeer(role: .authority)
    private(set) var watch = SyncPeer(role: .mirror)

    /// Commands on their way to the phone, oldest first. Index 0 is the next one `deliverCommand()` delivers.
    var toPhone: [RemoteCommand] = []
    /// Envelopes on their way to the Watch, oldest first.
    var toWatch: [SyncEnvelope] = []
    /// How many copies of a command are sent: 2 = the fast path (sendMessage) and the slow path (transferUserInfo) both deliver.
    var copiesPerCommand = 1
    /// Pushes every message through `SyncCodec` (JSON) on its way.
    var useCodec = true

    /// Every command the Watch issued, in order, over all Watch restarts.
    private(set) var issued: [RemoteCommand] = []
    /// How many envelopes the phone pushed.
    private(set) var pushes = 0

    private var bridge: SyncPhoneBridge?

    init() {
        let bridge = SyncPhoneBridge(link: self)
        self.bridge = bridge
        phone.engine.addEffect(bridge)
        wireWatch()
    }

    private func wireWatch() {
        watch.log.onIssue = { [unowned self] command in
            self.issued.append(command)
            for _ in 0..<self.copiesPerCommand { self.toPhone.append(command) }
        }
    }

    // MARK: Time

    /// Moves both clocks.
    func advance(_ seconds: TimeInterval) {
        phone.clock.advance(seconds)
        watch.clock.advance(seconds)
    }

    // MARK: Actions

    /// Starts a workout from a sample template on the phone and delivers everything.
    func startSynced(template index: Int = 0) throws {
        XCTAssertTrue(phone.engine.start(template: phone.model.data.templates[index]))
        try deliverAll()
    }

    /// A tap on the Watch.
    func tap(_ action: WorkoutAction) {
        watch.engine.send(action, origin: .watch)
    }

    /// A change made on the phone itself.
    func phoneEdit(_ action: WorkoutAction) {
        phone.engine.send(action)
    }

    /// The Watch app restarts: a new mirror without any state; commands already sent stay on their way.
    func restartWatch() {
        watch = SyncPeer(role: .mirror)
        watch.clock.set(phone.clock.now)
        wireWatch()
    }

    /// The phone pushes its current envelope (what `PhoneWatchBridge` does after a change or a `requestState`).
    func pushEnvelope() {
        pushes += 1
        toWatch.append(phone.engine.makeEnvelope(now: phone.clock.now))
    }

    // MARK: Delivery

    private func transit(_ message: SyncMessage) throws -> SyncMessage {
        useCodec ? try SyncCodec.decode(try SyncCodec.encode(message)) : message
    }

    /// Delivers `toPhone[index]`. Like the bridge, the phone pushes an envelope afterwards when the command itself caused none.
    @discardableResult
    func deliverCommand(at index: Int = 0) throws -> SyncDelivery {
        guard case let .command(command) = try transit(.command(toPhone.remove(at: index))) else { throw SyncLinkError.unexpectedKind }
        let before = phone.engine.state
        let pushesBefore = pushes
        phone.engine.receive(command)
        if pushes == pushesBefore { pushEnvelope() }
        return SyncDelivery(command: command, changedState: phone.engine.state != before)
    }

    /// Delivers `toWatch[index]`.
    func deliverEnvelope(at index: Int = 0) throws {
        guard case let .state(envelope) = try transit(.state(toWatch.remove(at: index))) else { throw SyncLinkError.unexpectedKind }
        watch.engine.receive(envelope)
    }

    func dropCommand(at index: Int = 0) { toPhone.remove(at: index) }

    func dropEnvelope(at index: Int = 0) { toWatch.remove(at: index) }

    /// Puts a second copy of `toPhone[index]` at the end of the queue (the slow path delivers it later).
    func duplicateCommand(at index: Int = 0) { toPhone.append(toPhone[index]) }

    /// Puts a second copy of `toWatch[index]` at the end of the queue.
    func duplicateEnvelope(at index: Int = 0) { toWatch.append(toWatch[index]) }

    /// Keeps only the newest envelope (`updateApplicationContext` holds one value).
    func coalesceEnvelopes() {
        if let last = toWatch.last { toWatch = [last] }
    }

    /// Delivers everything in flight in order, including what the deliveries cause, until nothing is left.
    func deliverAll() throws {
        while !toPhone.isEmpty || !toWatch.isEmpty {
            while !toPhone.isEmpty { try deliverCommand() }
            while !toWatch.isEmpty { try deliverEnvelope() }
        }
    }

    // MARK: Observations

    /// Exercise id and set id of set `i` of exercise `k` in the phone's workout.
    func refs(_ k: Int, _ i: Int) -> (exercise: UUID, set: UUID) {
        let state = phone.engine.state!
        return (state.exercises[k].id, state.exercises[k].sets[i].id)
    }

    func logSet(_ k: Int, _ i: Int) -> WorkoutAction {
        let target = refs(k, i)
        return .logSet(exerciseID: target.exercise, setID: target.set)
    }

    func setWeight(_ k: Int, _ i: Int, _ kg: Double) -> WorkoutAction {
        let target = refs(k, i)
        return .setWeight(exerciseID: target.exercise, setID: target.set, kg: kg)
    }
}

/// Small helpers shared by the sync protocol tests.
enum SyncProto {
    @MainActor static func isDone(_ peer: SyncPeer, _ k: Int, _ i: Int) -> Bool {
        peer.engine.state?.exercises[k].sets[i].isDone ?? false
    }

    @MainActor static func weight(_ peer: SyncPeer, _ k: Int, _ i: Int) -> Double? {
        peer.engine.state?.exercises[k].sets[i].weightKg
    }

    static func loggedSets(_ state: WorkoutState?) -> Int {
        state?.exercises.reduce(0) { $0 + $1.doneCount } ?? 0
    }

    /// Names the fields in which two states differ (for failure messages).
    static func difference(_ a: WorkoutState?, _ b: WorkoutState?) -> String {
        guard let a, let b else { return "one side has no workout (\(a == nil ? "left" : "right") is nil)" }
        var parts: [String] = []
        if a.id != b.id { parts.append("id") }
        if a.name != b.name { parts.append("name \(a.name) / \(b.name)") }
        if a.revision != b.revision { parts.append("revision \(a.revision) / \(b.revision)") }
        if a.currentIndex != b.currentIndex { parts.append("currentIndex \(a.currentIndex) / \(b.currentIndex)") }
        if a.pausedAt != b.pausedAt { parts.append("pausedAt") }
        if a.pausedTotal != b.pausedTotal { parts.append("pausedTotal") }
        if a.rest != b.rest { parts.append("rest \(String(describing: a.rest)) / \(String(describing: b.rest))") }
        if a.lastLogged != b.lastLogged { parts.append("lastLogged") }
        if a.settings != b.settings { parts.append("settings") }
        if a.undo != b.undo { parts.append("undo") }
        if a.exercises.map({ $0.id }) != b.exercises.map({ $0.id }) { parts.append("exercise list") }
        for (x, y) in zip(a.exercises, b.exercises) where x != y {
            if x.sets != y.sets { parts.append("sets of \(x.exercise.id): \(x.sets.map { "\($0.isDone ? "x" : "-")\($0.weightKg)×\($0.reps)" }) / \(y.sets.map { "\($0.isDone ? "x" : "-")\($0.weightKg)×\($0.reps)" })") }
            if x.restSeconds != y.restSeconds { parts.append("rest seconds of \(x.exercise.id)") }
            if x.note != y.note { parts.append("note of \(x.exercise.id)") }
            if x.supersetGroup != y.supersetGroup { parts.append("superset of \(x.exercise.id)") }
        }
        return parts.isEmpty ? "(equal ignoring heart rate)" : parts.joined(separator: "; ")
    }

    static func withoutHeartRate(_ state: WorkoutState?) -> WorkoutState? {
        guard var copy = state else { return nil }
        copy.heartRate = nil
        copy.heartRateSum = 0
        copy.heartRateCount = 0
        return copy
    }
}

// MARK: - Scenarios

final class SyncProtocolScenarioTests: XCTestCase {
    // MARK: Round trips

    func testASingleTapRoundTrip() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let start = try XCTUnwrap(link.phone.state)
            XCTAssertEqual(link.watch.state, start, "the Watch adopted the phone's state")
            XCTAssertEqual(link.watch.engine.authoritativeRevision, start.revision)

            link.advance(5)
            let action = link.logSet(0, 2)
            link.tap(action)

            // Optimistic: visible at once, remembered as pending, sent once; the phone has not heard of it yet.
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 2))
            XCTAssertEqual(link.watch.engine.pendingCommands.count, 1)
            XCTAssertEqual(link.toPhone.count, 1)
            XCTAssertEqual(link.phone.state, start)
            XCTAssertEqual(link.watch.engine.authoritativeRevision, start.revision, "an own edit does not move the phone's revision")
            let command = link.toPhone[0]
            XCTAssertEqual(command.action, action)
            XCTAssertEqual(command.origin, .watch)
            XCTAssertEqual(command.workoutID, start.id)
            XCTAssertEqual(command.issuedAt, link.watch.clock.now)
            XCTAssertEqual(link.watch.engine.pendingCommands, [command])

            let delivery = try link.deliverCommand()
            XCTAssertTrue(delivery.changedState)
            XCTAssertTrue(SyncProto.isDone(link.phone, 0, 2))
            XCTAssertEqual(link.phone.state?.revision, start.revision + 1)
            XCTAssertEqual(link.toWatch.count, 1, "the change is announced once, with the acknowledgement")
            XCTAssertEqual(link.toWatch[0].ackedCommandIDs, [command.id])
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 2), "still shown while the acknowledgement is on its way")

            try link.deliverEnvelope()
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertEqual(link.watch.engine.authoritativeRevision, link.phone.state?.revision)
            XCTAssertEqual(link.watch.recorder.changes.count, 1, "only the tap itself: adopting the phone's state is never echoed")
            XCTAssertEqual(link.issued.count, 1, "one command for one tap")
        }
    }

    func testRapidTapsKeepShowingEveryTapWhileTheFirstAcknowledgementIsLate() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let a = link.logSet(0, 0)
            let b = link.logSet(0, 1)
            let c = link.logSet(0, 2)

            let beforeA = link.watch.published.count
            link.tap(a)
            link.advance(1)
            let beforeB = link.watch.published.count
            link.tap(b)
            XCTAssertEqual(link.watch.engine.pendingCommands.count, 2)

            // The phone applies A; its envelope reaches the Watch only after B was tapped.
            try link.deliverCommand()
            XCTAssertEqual(SyncProto.loggedSets(link.phone.state), 1)
            try link.deliverEnvelope()
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 0))
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 1), "B is still shown on top of the phone's state")
            XCTAssertEqual(link.watch.engine.pendingCommands.map { $0.action }, [b], "A is acknowledged, B is not")

            link.advance(1)
            let beforeC = link.watch.published.count
            link.tap(c)
            XCTAssertEqual(link.watch.engine.pendingCommands.map { $0.action }, [b, c])

            // B and C reach the phone; their envelopes arrive reordered: C's first, then B's (stale, ignored).
            try link.deliverCommand()
            try link.deliverCommand()
            XCTAssertEqual(link.toWatch.count, 2)
            try link.deliverEnvelope(at: 1)
            XCTAssertEqual(SyncProto.loggedSets(link.watch.state), 3)
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty, "C's envelope acknowledges A, B and C")
            let publishedBeforeStale = link.watch.published.count
            try link.deliverEnvelope(at: 0)
            XCTAssertEqual(link.watch.published.count, publishedBeforeStale, "a stale envelope publishes nothing")

            XCTAssertEqual(link.watch.state, link.phone.state)
            // No flicker: every state the Watch published from a tap on shows that tap.
            for (first, set) in [(beforeA, 0), (beforeB, 1), (beforeC, 2)] {
                let shown = link.watch.published.dropFirst(first)
                XCTAssertFalse(shown.isEmpty)
                for published in shown {
                    XCTAssertTrue(published?.exercises[0].sets[set].isDone ?? false, "set \(set) was always shown once tapped")
                }
            }
        }
    }

    // MARK: Duplicates

    func testADuplicateCommandIsAppliedOnceAndAcknowledgedTwice() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.copiesPerCommand = 2                        // fast path and slow path both deliver
            link.tap(link.logSet(0, 0))
            XCTAssertEqual(link.toPhone.count, 2)
            XCTAssertEqual(link.toPhone[0].id, link.toPhone[1].id)
            XCTAssertEqual(link.issued.count, 1)
            let revision = try XCTUnwrap(link.phone.state?.revision)

            let first = try link.deliverCommand()
            let second = try link.deliverCommand()
            XCTAssertTrue(first.changedState)
            XCTAssertFalse(second.changedState)
            XCTAssertEqual(link.phone.state?.revision, revision + 1)
            XCTAssertEqual(link.phone.recorder.changes.count, 1)
            XCTAssertEqual(SyncProto.loggedSets(link.phone.state), 1)
            XCTAssertEqual(link.toWatch.count, 2, "the duplicate is acknowledged by an envelope of its own")
            XCTAssertEqual(link.toWatch.map { $0.ackedCommandIDs }, [[first.command.id], [first.command.id]])

            // Whichever envelope arrives first adopts the state; the other changes nothing and publishes nothing.
            try link.deliverEnvelope(at: 1)
            let published = link.watch.published.count
            try link.deliverEnvelope(at: 0)
            XCTAssertEqual(link.watch.published.count, published)
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
        }
    }

    func testTheSlowPathCopyArrivesLongAfterTheFastOneAndOtherEdits() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.duplicateCommand()                                           // sendMessage and transferUserInfo both carry it
            let fast = try link.deliverCommand()                              // the fast copy arrives; the slow one is held back
            try link.deliverEnvelope()

            // Half a minute and several edits later the slow copy turns up.
            link.advance(30)
            link.tap(link.logSet(0, 1))
            link.tap(link.setWeight(0, 2, 87.5))
            link.phoneEdit(.rename("Moved on"))
            try link.deliverCommand(at: 1)                                    // the Watch's later edits first
            try link.deliverCommand(at: 1)
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state)
            let settled = try XCTUnwrap(link.phone.state)

            link.toPhone.append(fast.command)                                 // the slow copy of the first command
            XCTAssertFalse(try link.deliverCommand().changedState)
            XCTAssertEqual(link.phone.state, settled)
            XCTAssertEqual(link.phone.recorder.changes.filter { if case .changed(_, _, let action, .watch) = $0 { return action == fast.command.action } else { return false } }.count, 1,
                           "the first tap changed the phone once")
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state)
        }
    }

    func testALateDuplicateIsStillIgnoredAndItsAcknowledgementIsRenewed() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            let first = try link.deliverCommand().command
            let workoutID = try XCTUnwrap(link.phone.state?.id)

            // 70 more commands push the first one out of the window of 64 acknowledgements.
            let exerciseID = link.refs(1, 0).exercise
            for number in 0..<70 {
                link.phone.engine.receive(RemoteCommand(action: .setNote(exerciseID: exerciseID, note: "n\(number)"), origin: .watch, workoutID: workoutID))
            }
            let acknowledged = link.phone.engine.makeEnvelope(now: link.phone.clock.now).ackedCommandIDs
            XCTAssertEqual(acknowledged.count, SyncReconciler.acknowledgementWindow)
            XCTAssertFalse(acknowledged.contains(first.id), "the oldest acknowledgements fall out of the window")

            let before = link.phone.state
            link.phone.engine.receive(first)                                    // the slow path delivers it again, late
            XCTAssertEqual(link.phone.state, before, "a duplicate does nothing")
            XCTAssertEqual(link.phone.engine.makeEnvelope(now: link.phone.clock.now).ackedCommandIDs.last, first.id,
                           "but it is acknowledged again, as the most recent")
        }
    }

    // MARK: Late commands of another workout

    func testEveryActionThatNamesAnIdIsANoOpInAnotherWorkout() {
        let template = SampleData.templates()[0]
        let old = WorkoutFactory.makeWorkout(from: template, now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(1))
        let new = WorkoutFactory.makeWorkout(from: template, now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(2))
        let exerciseID = old.exercises[0].id
        let setID = old.exercises[0].sets[2].id
        let bench = ExerciseLibrary.exercise(id: "bench")!
        let actions: [WorkoutAction] = [
            .toggleSet(exerciseID: exerciseID, setID: setID), .logSet(exerciseID: exerciseID, setID: setID),
            .setWeight(exerciseID: exerciseID, setID: setID, kg: 99), .setReps(exerciseID: exerciseID, setID: setID, reps: 3),
            .setSetType(exerciseID: exerciseID, setID: setID, type: .failure), .setRIR(exerciseID: exerciseID, setID: setID, rir: 2),
            .addSet(exerciseID: exerciseID), .deleteSet(exerciseID: exerciseID, setID: setID),
            .setNote(exerciseID: exerciseID, note: "late"), .removeExercise(exerciseID: exerciseID),
            .moveExerciseBy(exerciseID: exerciseID, delta: 1), .replaceExercise(exerciseID: exerciseID, with: bench),
            .toggleSuperset(exerciseID: exerciseID), .setRest(exerciseID: exerciseID, seconds: 10),
        ]
        for action in actions {
            var state = new
            WorkoutReducer.reduce(&state, action, now: SvcSyncFix.at(10))
            XCTAssertEqual(state, new, "\(action) must not touch a workout that does not own its ids")
        }
        // Actions without an id act on whatever runs; this is why a command also names its workout.
        var state = new
        WorkoutReducer.reduce(&state, .logNextSet, now: SvcSyncFix.at(10))
        XCTAssertNotEqual(state, new)
    }

    func testALateCommandOfAnEarlierWorkoutIsIgnoredByThePhone() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced(template: 0)
            let first = try XCTUnwrap(link.phone.state)

            // The Watch taps; the commands are slow (transferUserInfo while out of reach).
            link.tap(link.logSet(0, 0))                                       // names set and exercise ids
            link.tap(.nudgeNextSet(weightSteps: 1, repsSteps: 0))             // names nothing
            link.tap(.adjustRest(seconds: 15))                                // names nothing
            link.tap(.skipRest)                                               // names nothing
            XCTAssertEqual(link.toPhone.count, 4)
            let late = link.toPhone

            // Meanwhile the phone discards the workout and starts another.
            link.phone.engine.discard()
            XCTAssertTrue(link.phone.engine.start(template: link.phone.model.data.templates[1]))
            let second = try XCTUnwrap(link.phone.state)
            XCTAssertNotEqual(second.id, first.id)
            let changes = link.phone.recorder.changes.count

            for _ in 0..<4 {
                XCTAssertFalse(try link.deliverCommand().changedState)
            }
            XCTAssertEqual(link.phone.state, second, "no late command touched the new workout")
            XCTAssertEqual(link.phone.recorder.changes.count, changes)
            XCTAssertEqual(Set(link.phone.engine.makeEnvelope(now: link.phone.clock.now).ackedCommandIDs), Set(late.map { $0.id }),
                           "they are all acknowledged")
        }
    }

    func testACommandFromASenderThatDoesNotNameItsWorkoutActsOnWhateverRuns() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced(template: 0)
            // An older Watch app sends no workout id: ids still protect id-bearing actions, an id-less one runs.
            let stale = link.phone.state!
            link.phone.engine.discard()
            XCTAssertTrue(link.phone.engine.start(template: link.phone.model.data.templates[1]))
            let current = link.phone.state!

            let named = RemoteCommand(action: .logSet(exerciseID: stale.exercises[0].id, setID: stale.exercises[0].sets[0].id), origin: .watch)
            link.phone.engine.receive(named)
            XCTAssertEqual(link.phone.state, current)

            let anonymous = RemoteCommand(action: .logNextSet, origin: .watch)
            link.phone.engine.receive(anonymous)
            XCTAssertEqual(SyncProto.loggedSets(link.phone.state), 1)
            XCTAssertEqual(link.phone.engine.makeEnvelope(now: link.phone.clock.now).ackedCommandIDs, [named.id, anonymous.id])
        }
    }

    // MARK: Concurrent edits

    func testPhoneAndWatchEditDifferentThingsAtTheSameTime() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let start = try XCTUnwrap(link.phone.state)

            link.phoneEdit(link.setWeight(1, 0, 77.5))                        // the phone changes the incline weight
            link.tap(link.logSet(0, 0))                                       // the Watch logs the first bench set
            XCTAssertEqual(SyncProto.weight(link.watch, 1, 0), start.exercises[1].sets[0].weightKg, "the Watch has not heard yet")

            // The phone's envelope reaches the Watch before the Watch's command reaches the phone.
            try link.deliverEnvelope()
            XCTAssertEqual(SyncProto.weight(link.watch, 1, 0), 77.5, "the phone's edit arrived")
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 0), "and the Watch's own tap is still shown on top")
            XCTAssertEqual(link.watch.engine.pendingCommands.count, 1)

            try link.deliverCommand()
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertEqual(SyncProto.weight(link.phone, 1, 0), 77.5)
            XCTAssertTrue(SyncProto.isDone(link.phone, 0, 0))
            XCTAssertEqual(link.phone.state?.revision, start.revision + 2)
        }
    }

    func testOnAConflictingEditTheAuthoritysOrderDecidesAndBothSidesConverge() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()

            // Both change the weight of the same set while the other has not heard.
            link.phoneEdit(link.setWeight(0, 2, 100))
            link.tap(link.setWeight(0, 2, 70))
            try link.deliverEnvelope()
            XCTAssertEqual(SyncProto.weight(link.watch, 0, 2), 70, "the Watch keeps showing its own unacknowledged edit")
            try link.deliverCommand()
            XCTAssertEqual(SyncProto.weight(link.phone, 0, 2), 70, "the phone applied the Watch's edit after its own")
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertEqual(SyncProto.weight(link.watch, 0, 2), 70)

            // The phone changes it again: the phone's later word is what both end up with.
            link.tap(link.setWeight(0, 2, 72.5))
            link.phoneEdit(link.setWeight(0, 2, 90))
            try link.deliverCommand()                                         // the Watch's 72.5 reaches the phone first ...
            XCTAssertEqual(SyncProto.weight(link.phone, 0, 2), 72.5)
            link.phoneEdit(link.setWeight(0, 2, 95))                          // ... and the phone then has the last word
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertEqual(SyncProto.weight(link.watch, 0, 2), 95)
        }
    }

    func testWhenThePhoneDeletesWhatTheWatchLoggedThePhoneWins() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let doomed = link.refs(0, 4)

            link.phoneEdit(.deleteSet(exerciseID: doomed.exercise, setID: doomed.set))
            link.tap(.logSet(exerciseID: doomed.exercise, setID: doomed.set))
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 4))
            let changesAfterDelete = link.phone.recorder.changes.count

            try link.deliverEnvelope()
            XCTAssertEqual(link.watch.state?.exercises[0].sets.count, 4, "the phone's deletion wins on the Watch at once")
            XCTAssertEqual(link.watch.engine.pendingCommands.count, 1, "the tap is still unacknowledged")

            XCTAssertFalse(try link.deliverCommand().changedState, "the phone cannot log a set that is gone")
            XCTAssertEqual(link.phone.recorder.changes.count, changesAfterDelete)
            try link.deliverAll()
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty, "the no-op was acknowledged")
            XCTAssertEqual(link.watch.state, link.phone.state)
        }
    }

    // MARK: Stale and reordered envelopes

    func testAStaleEnvelopeIsIgnored() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.phoneEdit(.rename("One"))
            link.phoneEdit(.rename("Two"))
            link.phoneEdit(.rename("Three"))
            XCTAssertEqual(link.toWatch.count, 3)

            try link.deliverEnvelope(at: 2)
            XCTAssertEqual(link.watch.state?.name, "Three")
            let published = link.watch.published.count
            let revision = link.watch.engine.authoritativeRevision
            try link.deliverEnvelope(at: 0)
            try link.deliverEnvelope(at: 0)
            XCTAssertEqual(link.watch.state?.name, "Three")
            XCTAssertEqual(link.watch.published.count, published)
            XCTAssertEqual(link.watch.engine.authoritativeRevision, revision)
        }
    }

    func testTheMirrorFollowsThePhoneEvenWhenItsOwnRevisionRanAhead() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let start = try XCTUnwrap(link.phone.state)

            // Three taps while out of reach raise the Watch's own revision far above the phone's.
            link.tap(link.logSet(0, 0))
            link.tap(link.logSet(0, 1))
            link.tap(link.logSet(0, 2))
            XCTAssertEqual(link.watch.state?.revision, start.revision + 3)
            link.toPhone.removeAll()                                         // none of them gets through (yet)

            link.phoneEdit(.rename("Phone edit"))
            let envelope = try XCTUnwrap(link.toWatch.last)
            XCTAssertEqual(envelope.state?.revision, start.revision + 1)
            XCTAssertFalse(SyncReconciler.isNewer(try XCTUnwrap(envelope.state), than: link.watch.state),
                           "the first-generation rule would have ignored it for good")

            try link.deliverEnvelope(at: link.toWatch.count - 1)
            XCTAssertEqual(link.watch.state?.name, "Phone edit", "the phone's edit is adopted")
            XCTAssertEqual(SyncProto.loggedSets(link.watch.state), 3, "with the three unacknowledged taps on top")
            XCTAssertEqual(link.watch.engine.authoritativeRevision, start.revision + 1)
        }
    }

    func testEnvelopesThatArriveInAnyOrderLeaveTheNewestState() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            for number in 1...5 { link.phoneEdit(.rename("Edit \(number)")) }
            XCTAssertEqual(link.toWatch.count, 5)

            var lastRevision = link.watch.engine.authoritativeRevision ?? -1
            for index in [2, 0, 2, 0, 0] {                                  // positions in the shrinking queue: edit 3, 1, 5, 2, 4
                try link.deliverEnvelope(at: index)
                let revision = try XCTUnwrap(link.watch.engine.authoritativeRevision)
                XCTAssertGreaterThanOrEqual(revision, lastRevision, "the adopted revision never goes back")
                lastRevision = revision
            }
            XCTAssertEqual(link.watch.state?.name, "Edit 5")
            XCTAssertEqual(link.watch.state, link.phone.state)
        }
    }

    // MARK: No-ops, expiry, bounds

    func testANoOpCommandIsAcknowledgedWithoutAStateChange() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()

            // The phone logs the set itself; the Watch, which has not heard, taps the same set.
            link.phoneEdit(link.logSet(0, 0))
            link.tap(link.logSet(0, 0))
            let command = try XCTUnwrap(link.toPhone.first)
            let phoneState = try XCTUnwrap(link.phone.state)
            let changes = link.phone.recorder.changes.count

            let delivery = try link.deliverCommand()
            XCTAssertFalse(delivery.changedState)
            XCTAssertEqual(link.phone.state, phoneState)
            XCTAssertEqual(link.phone.recorder.changes.count, changes, "no change was reported")
            let ack = try XCTUnwrap(link.toWatch.last)
            XCTAssertEqual(ack.ackedCommandIDs, [command.id], "yet the command is acknowledged")
            XCTAssertEqual(ack.state, phoneState, "with an envelope of the same revision")

            // The acknowledgement overtakes the phone's own envelope: it is enough to clear the Watch's pending tap.
            try link.deliverEnvelope(at: link.toWatch.count - 1)
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
            XCTAssertEqual(link.watch.state, link.phone.state)
            let published = link.watch.published.count
            try link.deliverAll()
            XCTAssertEqual(link.watch.published.count, published, "the older envelopes of the same state publish nothing")
        }
    }

    func testAnUnacknowledgedEditExpiresAfterFifteenSeconds() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.toPhone.removeAll()                                          // the command is lost

            link.advance(14.9)
            link.phoneEdit(.rename("A"))
            try link.deliverEnvelope(at: link.toWatch.count - 1)
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 0), "still within its lifetime")
            XCTAssertEqual(link.watch.engine.pendingCommands.count, 1)

            link.advance(0.2)
            link.phoneEdit(.rename("B"))
            try link.deliverEnvelope(at: link.toWatch.count - 1)
            XCTAssertFalse(SyncProto.isDone(link.watch, 0, 0), "older than 15 s: the lost tap is not shown any more")
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
            XCTAssertEqual(link.watch.state, link.phone.state)
        }
    }

    func testThePendingListIsBounded() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            for number in 0..<100 { link.tap(.setNote(exerciseID: link.refs(0, 0).exercise, note: "note \(number)")) }
            XCTAssertEqual(link.watch.engine.pendingCommands.count, SyncReconciler.pendingCapacity)
            XCTAssertEqual(link.toPhone.count, 100, "every tap still became a command")
            XCTAssertEqual(link.watch.engine.pendingCommands.last, link.toPhone.last, "the newest are kept")
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
        }
    }

    // MARK: Ending

    func testTheWorkoutEndsWhileCommandsArePending() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let ended = try XCTUnwrap(link.phone.state?.id)
            link.tap(link.logSet(0, 0))
            link.tap(link.logSet(0, 1))
            XCTAssertEqual(link.watch.engine.pendingCommands.count, 2)

            // The phone ends the workout before the commands arrive.
            link.phone.engine.discard()
            let notice = try XCTUnwrap(link.toWatch.last)
            XCTAssertNil(notice.state)
            XCTAssertEqual(notice.endedWorkoutID, ended)
            let shown = try XCTUnwrap(link.watch.state, "the Watch shows its two taps until it hears of the end")
            XCTAssertEqual(SyncProto.loggedSets(shown), 2)
            try link.deliverEnvelope(at: link.toWatch.count - 1)
            XCTAssertNil(link.watch.state)
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
            XCTAssertNil(link.watch.engine.authoritativeRevision)
            XCTAssertEqual(link.watch.recorder.events.last, .ended(shown, nil), "workoutEnded(previous, completed: nil)")
        }
    }

    func testCommandsThatArriveAfterTheEndAreConsumedAndAcknowledged() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            link.tap(link.logSet(0, 1))
            let sent = link.toPhone.map { $0.id }
            link.phone.engine.discard()
            link.toWatch.removeAll()
            link.pushEnvelope()                                              // the end notice, delivered later

            for _ in 0..<2 { XCTAssertFalse(try link.deliverCommand().changedState) }
            XCTAssertNil(link.phone.state)
            let ack = try XCTUnwrap(link.toWatch.last)
            XCTAssertNil(ack.state)
            XCTAssertNotNil(ack.endedWorkoutID)
            XCTAssertEqual(ack.ackedCommandIDs, sent)

            // The Watch gets the acknowledgements first, then the end notice, then a duplicate of it.
            let events = link.watch.recorder.events.count
            try link.deliverEnvelope(at: 1)
            try link.deliverEnvelope(at: 1)
            XCTAssertNil(link.watch.state, "the end notice ended the workout")
            try link.deliverEnvelope(at: 0)
            XCTAssertNil(link.watch.state)
            XCTAssertEqual(link.watch.recorder.events.count, events + 1, "the Watch heard of the end once")

            // A new workout is welcome and carries none of the old taps.
            XCTAssertTrue(link.phone.engine.start(template: link.phone.model.data.templates[1]))
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertEqual(SyncProto.loggedSets(link.watch.state), 0)
        }
    }

    func testFinishingKeepsTheCommandsThatArrivedBeforeIt() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            try link.deliverCommand()
            let completed = link.phone.engine.finish(updateTemplate: false)
            XCTAssertEqual(completed?.loggedSets, 1, "the Watch's tap is part of the saved workout")
            try link.deliverAll()
            XCTAssertNil(link.watch.state)
            XCTAssertNil(link.watch.engine.lastCompleted)
        }
    }

    // MARK: Restart

    func testARestartedWatchAdoptsTheCurrentStateAndCatchesUp() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))                                       // in flight when the Watch app restarts
            link.phoneEdit(.rename("Before restart"))                        // an envelope the new Watch will receive late (stale by then)

            link.restartWatch()
            XCTAssertNil(link.watch.state)
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
            XCTAssertNil(link.watch.engine.authoritativeRevision)

            // requestState: the phone answers with its current envelope; the new Watch adopts the first thing it receives.
            link.pushEnvelope()
            try link.deliverEnvelope(at: link.toWatch.count - 1)
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertEqual(link.watch.recorder.events, [.started(try XCTUnwrap(link.phone.state))], "announced once, as a new workout")
            XCTAssertEqual(link.watch.engine.authoritativeRevision, link.phone.state?.revision)

            // The command of the previous run reaches the phone; its acknowledgement matches nothing on the new Watch.
            let delivery = try link.deliverCommand()
            XCTAssertTrue(delivery.changedState)
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertTrue(SyncProto.isDone(link.watch, 0, 0))
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
            XCTAssertEqual(link.watch.state?.name, "Before restart")

            // And it works as before: a new tap round-trips.
            link.tap(link.logSet(0, 1))
            XCTAssertEqual(link.watch.engine.pendingCommands.count, 1)
            try link.deliverAll()
            XCTAssertEqual(link.watch.state, link.phone.state)
            XCTAssertEqual(SyncProto.loggedSets(link.phone.state), 2)
        }
    }

    func testAnOldEnvelopeThatReachesARestartedWatchFirstIsCorrectedByTheNext() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.phoneEdit(.rename("Old"))
            link.phoneEdit(.rename("New"))
            link.restartWatch()
            try link.deliverEnvelope(at: 0)                                  // a new Watch has no revision to compare with
            XCTAssertEqual(link.watch.state?.name, "Old")
            try link.deliverEnvelope(at: 0)
            XCTAssertEqual(link.watch.state?.name, "New")
            XCTAssertEqual(link.watch.state, link.phone.state)
        }
    }

    // MARK: End notices

    @MainActor private func fixture() throws -> (peer: SyncPeer, state: WorkoutState) {
        let peer = SyncPeer(role: .mirror)
        let source = SyncPeer(role: .authority)
        XCTAssertTrue(source.engine.start(template: source.model.data.templates[0]))
        return (peer, try XCTUnwrap(source.state))
    }

    func testAnEmptyNoticeWithoutAWorkoutChangesNothingAndBlocksNothing() throws {
        try svcMain {
            let (peer, state) = try fixture()
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: nil, sentAt: SvcSyncFix.epoch))
            XCTAssertNil(peer.state)
            XCTAssertTrue(peer.recorder.events.isEmpty)
            XCTAssertTrue(peer.published.isEmpty)
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.epoch))
            XCTAssertEqual(peer.state, state, "no workout id was blacklisted")
        }
    }

    func testAnEmptyNoticeEndsTheRunningWorkoutButDoesNotBlockItsNextState() throws {
        try svcMain {
            let (peer, state) = try fixture()
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.epoch))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: nil, sentAt: SvcSyncFix.at(1)))
            XCTAssertNil(peer.state, "the legacy notice \"no workout\" ends whatever runs")
            XCTAssertEqual(peer.recorder.events.last, .ended(state, nil))

            // The notice named nobody, so the workout is not blacklisted: the phone's next state for it is adopted again.
            var later = state
            later.revision += 1
            peer.engine.receive(SyncEnvelope(state: later, sentAt: SvcSyncFix.at(2)))
            XCTAssertEqual(peer.state, later)
            XCTAssertEqual(peer.recorder.events.last, .started(later))
        }
    }

    func testANoticeThatNamesTheRunningWorkoutEndsAndBlocksIt() throws {
        try svcMain {
            let (peer, state) = try fixture()
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.epoch))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: state.id, sentAt: SvcSyncFix.at(1)))
            XCTAssertNil(peer.state)
            var later = state
            later.revision += 5
            peer.engine.receive(SyncEnvelope(state: later, sentAt: SvcSyncFix.at(2)))
            XCTAssertNil(peer.state, "an ended workout is not revived by a late state")
        }
    }

    func testANoticeOfAnEarlierWorkoutDoesNotEndTheRunningOne() throws {
        try svcMain {
            let (peer, state) = try fixture()
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
            // Sent before the running workout's state: a late notice of a workout that ended earlier.
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(77), sentAt: SvcSyncFix.at(5)))
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(78), sentAt: SvcSyncFix.at(10)))
            XCTAssertEqual(peer.state, state)
            XCTAssertEqual(peer.recorder.events.count, 1)
        }
    }

    func testANoticeSentAfterTheLastAdoptedStateEndsAGhostWorkout() throws {
        try svcMain {
            let (peer, state) = try fixture()
            peer.engine.receive(SyncEnvelope(state: state, sentAt: SvcSyncFix.at(10)))
            // The Watch never heard that its workout ended and another one started and ended: the newest notice names a
            // different workout than the one shown, and was sent after everything the Watch adopted.
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(77), sentAt: SvcSyncFix.at(40)))
            XCTAssertNil(peer.state)
            XCTAssertEqual(peer.recorder.events.last, .ended(state, nil))
        }
    }

    func testAMirrorThatStartedItsOwnWorkoutIgnoresNoticesOfOtherWorkouts() {
        svcMain {
            let peer = SyncPeer(role: .mirror)
            XCTAssertTrue(peer.engine.start(template: peer.model.data.templates[0]))
            let state = peer.state
            XCTAssertNil(peer.engine.authoritativeRevision)
            peer.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: SvcSyncFix.uuid(77), sentAt: SvcSyncFix.at(40)))
            XCTAssertEqual(peer.state, state, "without an adopted phone state there is nothing to compare with")
        }
    }

    // MARK: Authority

    func testTheAuthoritysEnvelope() throws {
        try svcMain {
            let phone = SyncPeer(role: .authority)
            let now = SvcSyncFix.at(3)

            // Never had a workout: nothing to say, nobody to name.
            var envelope = phone.engine.makeEnvelope(now: now)
            XCTAssertNil(envelope.state)
            XCTAssertNil(envelope.endedWorkoutID)
            XCTAssertEqual(envelope.ackedCommandIDs, [])
            XCTAssertEqual(envelope.sentAt, now)

            XCTAssertTrue(phone.engine.start(template: phone.model.data.templates[0]))
            let state = try XCTUnwrap(phone.state)
            let command = RemoteCommand(action: .skipRest, origin: .watch, workoutID: state.id)
            phone.engine.receive(command)
            envelope = phone.engine.makeEnvelope(now: now)
            XCTAssertEqual(envelope.state, phone.state)
            XCTAssertNil(envelope.endedWorkoutID, "a running workout is not an ended one")
            XCTAssertEqual(envelope.ackedCommandIDs, [command.id], "acknowledged although it changed nothing")

            phone.engine.discard()
            envelope = phone.engine.makeEnvelope(now: now)
            XCTAssertNil(envelope.state)
            XCTAssertEqual(envelope.endedWorkoutID, state.id)
            XCTAssertEqual(envelope.ackedCommandIDs, [command.id], "acknowledgements outlive the workout")
        }
    }

    func testAcknowledgementsAreTheMostRecentCommandsInOrder() throws {
        try svcMain {
            let phone = SyncPeer(role: .authority)
            XCTAssertTrue(phone.engine.start(template: phone.model.data.templates[0]))
            let workoutID = try XCTUnwrap(phone.state?.id)
            var ids: [UUID] = []
            for number in 0..<300 {
                let command = RemoteCommand(id: SvcSyncFix.uuid(1_000 + number), action: .skipRest, origin: .watch, workoutID: workoutID)
                ids.append(command.id)
                phone.engine.receive(command)
            }
            let acknowledged = phone.engine.makeEnvelope(now: SvcSyncFix.epoch).ackedCommandIDs
            XCTAssertEqual(acknowledged, Array(ids.suffix(64)))
            XCTAssertEqual(SyncReconciler.acknowledgementWindow, 64)
            XCTAssertEqual(SyncReconciler.acknowledgedMemory, 256)
        }
    }

    func testAMirrorAcknowledgesNothingAndIgnoresCommands() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let before = link.watch.state
            let command = RemoteCommand(action: .skipRest, origin: .watch, workoutID: before?.id)
            link.watch.engine.receive(command)
            XCTAssertEqual(link.watch.state, before)
            XCTAssertEqual(link.watch.engine.makeEnvelope(now: SvcSyncFix.epoch).ackedCommandIDs, [])
        }
    }

    // MARK: Commands issued by the mirror

    func testTheMirrorIssuesOneCommandPerEditMadeOnTheWatch() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            let watch = link.watch
            let workoutID = try XCTUnwrap(watch.state?.id)

            link.advance(2)
            link.tap(link.logSet(0, 0))
            let issued = try XCTUnwrap(watch.log.issued.first)
            XCTAssertEqual(watch.log.issued.count, 1)
            XCTAssertEqual(issued.action, link.logSet(0, 0))
            XCTAssertEqual(issued.origin, .watch)
            XCTAssertEqual(issued.workoutID, workoutID)
            XCTAssertEqual(issued.issuedAt, watch.clock.now, "stamped by the Watch's own clock")
            XCTAssertEqual(watch.log.calls, [.changed(link.logSet(0, 0), .watch), .issued(issued)], "after workoutChanged, once")

            // No command: heart rate, edits of another origin, edits that change nothing.
            watch.engine.send(.updateHeartRate(120), origin: .watch)
            watch.engine.send(.updateHeartRate(121), origin: .system)
            watch.engine.send(.rename("Local"), origin: .phone)
            watch.engine.send(.skipRest, origin: .liveActivity)
            link.tap(link.logSet(0, 0))                                       // already logged: no change
            link.tap(.goTo(index: 0))                                         // already there
            XCTAssertEqual(watch.log.issued.count, 1)
            XCTAssertEqual(watch.engine.pendingCommands, [issued])

            // The authority never issues commands.
            link.phone.engine.send(link.logSet(0, 3), origin: .watch)
            XCTAssertTrue(link.phone.log.issued.isEmpty)
            XCTAssertTrue(link.phone.engine.pendingCommands.isEmpty)
        }
    }

    func testAdoptingAnEnvelopeNeverIssuesOrEchoesACommand() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.tap(link.logSet(0, 0))
            let issued = link.watch.log.issued.count
            let changes = link.watch.recorder.changes.count
            link.phoneEdit(.rename("From the phone"))
            link.phoneEdit(link.logSet(0, 1))
            try link.deliverEnvelope(at: link.toWatch.count - 1)
            XCTAssertEqual(link.watch.log.issued.count, issued)
            XCTAssertEqual(link.watch.recorder.changes.count, changes)
            XCTAssertEqual(link.watch.log.calls.filter { if case .changed = $0 { return true } else { return false } }.count, changes)
        }
    }

    // MARK: Phone <-> Watch heart rate

    func testHeartRateIsNotAnEditAndSurvivesAcknowledgements() throws {
        try svcMain {
            let link = SyncLink()
            try link.startSynced()
            link.watch.engine.send(.updateHeartRate(130), origin: .system)    // what WatchEnvironment does
            XCTAssertEqual(link.watch.state?.heartRate, 130)
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
            link.tap(link.logSet(0, 0))
            try link.deliverAll()
            XCTAssertEqual(SyncProto.withoutHeartRate(link.watch.state), SyncProto.withoutHeartRate(link.phone.state))
            XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty)
        }
    }
}

// MARK: - Pure rules

final class SyncAdoptionRuleTests: XCTestCase {
    private func state(id: Int, revision: Int) -> WorkoutState {
        WorkoutState(id: SvcSyncFix.uuid(id), name: "W", startedAt: SvcSyncFix.epoch, revision: revision)
    }

    func testShouldAdoptTable() {
        let current = SvcSyncFix.uuid(1)
        // No workout shown, or another one: always adopted, whatever the revision.
        XCTAssertTrue(SyncReconciler.shouldAdopt(incoming: state(id: 1, revision: 0), authoritativeRevision: nil, currentWorkoutID: nil))
        XCTAssertTrue(SyncReconciler.shouldAdopt(incoming: state(id: 2, revision: 0), authoritativeRevision: 50, currentWorkoutID: current))
        // No phone revision known for the workout shown: adopted.
        XCTAssertTrue(SyncReconciler.shouldAdopt(incoming: state(id: 1, revision: 0), authoritativeRevision: nil, currentWorkoutID: current))
        // The same workout: higher and equal revisions are adopted, lower ones are stale.
        XCTAssertTrue(SyncReconciler.shouldAdopt(incoming: state(id: 1, revision: 6), authoritativeRevision: 5, currentWorkoutID: current))
        XCTAssertTrue(SyncReconciler.shouldAdopt(incoming: state(id: 1, revision: 5), authoritativeRevision: 5, currentWorkoutID: current))
        XCTAssertFalse(SyncReconciler.shouldAdopt(incoming: state(id: 1, revision: 4), authoritativeRevision: 5, currentWorkoutID: current))
    }

    func testTheOldRuleIsKeptAndStillStrict() {
        let local = state(id: 1, revision: 5)
        XCTAssertTrue(SyncReconciler.isNewer(state(id: 1, revision: 6), than: local))
        XCTAssertFalse(SyncReconciler.isNewer(state(id: 1, revision: 5), than: local))
        XCTAssertTrue(SyncReconciler.isNewer(state(id: 2, revision: 0), than: local))
        XCTAssertTrue(SyncReconciler.isNewer(state(id: 1, revision: 0), than: nil))
    }

    func testRemainingPendingDropsAcknowledgedAndExpiredEdits() {
        let now = SvcSyncFix.at(100)
        func command(_ number: Int, age: TimeInterval) -> RemoteCommand {
            RemoteCommand(id: SvcSyncFix.uuid(number), action: .skipRest, origin: .watch, issuedAt: now.addingTimeInterval(-age))
        }
        let pending = [command(1, age: 20), command(2, age: 15), command(3, age: 14.9), command(4, age: 1), command(5, age: 0), command(6, age: -3)]
        let remaining = SyncReconciler.remainingPending(pending, acknowledged: [SvcSyncFix.uuid(4), SvcSyncFix.uuid(99)], now: now)
        XCTAssertEqual(remaining.map { $0.id }, [2, 3, 5, 6].map { SvcSyncFix.uuid($0) },
                       "older than 15 s and acknowledged edits go; exactly 15 s stays; a future issue time counts as new")
        XCTAssertEqual(SyncReconciler.remainingPending([], acknowledged: [SvcSyncFix.uuid(1)], now: now), [])
        XCTAssertEqual(SyncReconciler.pendingLifetime, 15)
        XCTAssertEqual(SyncReconciler.pendingCapacity, 64)
    }

    func testRebaseReplaysTheEditsInOrderAtTheirOwnTime() {
        let base = WorkoutFactory.makeWorkout(from: SampleData.templates()[0], now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(1))
        let first = base.exercises[0].sets[2].id
        let exerciseID = base.exercises[0].id
        let log = RemoteCommand(action: .logSet(exerciseID: exerciseID, setID: first), origin: .watch, issuedAt: SvcSyncFix.at(30), workoutID: base.id)
        let weight = RemoteCommand(action: .setWeight(exerciseID: exerciseID, setID: first, kg: 90), origin: .watch, issuedAt: SvcSyncFix.at(31), workoutID: base.id)
        let rebased = SyncReconciler.rebase(base, replaying: [log, weight])

        var expected = base
        WorkoutReducer.reduce(&expected, log.action, now: SvcSyncFix.at(30))
        WorkoutReducer.reduce(&expected, weight.action, now: SvcSyncFix.at(31))
        XCTAssertEqual(rebased, expected)
        XCTAssertEqual(rebased.rest?.endsAt, SvcSyncFix.at(30).addingTimeInterval(150), "the rest started when the Watch was tapped")
        XCTAssertEqual(SyncReconciler.rebase(base, replaying: []), base)
    }

    func testRebaseSkipsEditsOfAnotherWorkoutAndEditsWithoutTargets() {
        let base = WorkoutFactory.makeWorkout(from: SampleData.templates()[0], now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(1))
        let foreign = RemoteCommand(action: .logNextSet, origin: .watch, issuedAt: SvcSyncFix.at(5), workoutID: SvcSyncFix.uuid(2))
        let gone = RemoteCommand(action: .logSet(exerciseID: SvcSyncFix.uuid(3), setID: SvcSyncFix.uuid(4)), origin: .watch, issuedAt: SvcSyncFix.at(5), workoutID: base.id)
        XCTAssertEqual(SyncReconciler.rebase(base, replaying: [foreign, gone]), base)
        let unnamed = RemoteCommand(action: .logNextSet, origin: .watch, issuedAt: SvcSyncFix.at(5))
        XCTAssertEqual(SyncProto.loggedSets(SyncReconciler.rebase(base, replaying: [unnamed])), 1, "an older sender names no workout")
    }
}

// MARK: - Randomized

final class SyncProtocolFuzzTests: XCTestCase {
    /// A random edit the Watch could make from what it shows.
    private func watchAction(_ state: WorkoutState, _ random: inout SvcLCG) -> WorkoutAction {
        let k = random.int(state.exercises.count)
        let entry = state.exercises[k]
        let setID = entry.sets.isEmpty ? SvcSyncFix.uuid(0) : entry.sets[random.int(entry.sets.count)].id
        switch random.int(10) {
        case 0, 1: return .logSet(exerciseID: entry.id, setID: setID)
        case 2: return .logNextSet
        case 3: return .toggleSet(exerciseID: entry.id, setID: setID)
        case 4: return .nudgeNextSet(weightSteps: random.int(in: -2...2), repsSteps: random.int(in: -1...1))
        case 5: return .setWeight(exerciseID: entry.id, setID: setID, kg: Double(random.int(in: 20...240)) / 2)
        case 6: return .setReps(exerciseID: entry.id, setID: setID, reps: random.int(in: 1...15))
        case 7: return .adjustRest(seconds: random.int(in: -1...1) * 15)
        case 8: return .skipRest
        default: return .setNote(exerciseID: entry.id, note: "n\(random.int(9))")
        }
    }

    /// A random edit made on the phone itself.
    private func phoneAction(_ state: WorkoutState, _ random: inout SvcLCG) -> WorkoutAction {
        let k = random.int(state.exercises.count)
        let entry = state.exercises[k]
        let setID = entry.sets.isEmpty ? SvcSyncFix.uuid(0) : entry.sets[random.int(entry.sets.count)].id
        switch random.int(16) {
        case 0, 1: return .toggleSet(exerciseID: entry.id, setID: setID)
        case 2: return .setWeight(exerciseID: entry.id, setID: setID, kg: Double(random.int(in: 20...240)) / 2)
        case 3: return .addSet(exerciseID: entry.id)
        case 4: return .deleteSet(exerciseID: entry.id, setID: setID)
        case 5: return .setNote(exerciseID: entry.id, note: "p\(random.int(9))")
        case 6: return .nextExercise
        case 7: return random.int(2) == 0 ? .pause : .resume
        case 8: return .rename("Workout \(random.int(30))")
        case 9: return .addExercises([ExerciseLibrary.exercise(id: "pushup")!])
        case 10: return .removeExercise(exerciseID: entry.id)
        case 11: return .undo
        case 12: return .updateHeartRate(random.int(5) == 0 ? nil : random.int(in: 60...190))
        case 13: return .logNextSet
        case 14: return .adjustRest(seconds: random.int(in: -1...1) * 15)
        default: return .setAutoStartRest(random.int(2) == 0)
        }
    }

    @MainActor
    private func run(seed: UInt64) throws {
        var random = SvcLCG(seed: seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678_9ABC_DEF1)
        let link = SyncLink()
        link.useCodec = seed % 6 == 0                                         // a sixth of the runs go through the JSON codec
        var applied: [UUID: Int] = [:]                                        // per command id: how often it changed the phone
        var delivered = Set<UUID>()
        var lastAdopted: (workout: UUID, revision: Int)?                      // what the current Watch adopted last
        let tag = "seed \(seed)"

        func deliverCommand(at index: Int) throws {
            let id = link.toPhone[index].id
            let wasDelivered = delivered.contains(id)
            let before = link.phone.state
            let delivery = try link.deliverCommand(at: index)
            delivered.insert(id)
            if delivery.changedState { applied[id, default: 0] += 1 }
            XCTAssertLessThanOrEqual(applied[id] ?? 0, 1, "\(tag): command applied twice")
            if wasDelivered { XCTAssertEqual(link.phone.state, before, "\(tag): a duplicate command changed the state") }
        }

        func deliverEnvelope(at index: Int) throws {
            try link.deliverEnvelope(at: index)
            if let id = link.watch.state?.id, let revision = link.watch.engine.authoritativeRevision {
                if let last = lastAdopted, last.workout == id {
                    XCTAssertGreaterThanOrEqual(revision, last.revision, "\(tag): the adopted revision of a workout went back")
                }
                lastAdopted = (id, revision)
            }
        }

        func startWorkout() {
            link.phone.engine.start(template: link.phone.model.data.templates[random.int(3)])
        }

        func endWorkout() {
            if random.int(2) == 0 { link.phone.engine.finish(updateTemplate: random.int(2) == 0) } else { link.phone.engine.discard() }
        }

        startWorkout()
        try deliverEnvelope(at: 0)                                            // the Watch starts out in sync

        for _ in 0..<40 {
            link.advance(Double(random.int(in: 1...8)) / 4)                   // 0.25 ... 2 s between steps (exact in binary and in JSON)
            switch random.int(20) {
            case 0...3:
                if let state = link.watch.state, !state.exercises.isEmpty {
                    link.copiesPerCommand = random.int(4) == 0 ? 2 : 1       // sometimes both the fast and the slow path deliver
                    link.tap(watchAction(state, &random))
                }
            case 4...6:
                if let state = link.phone.state {
                    if random.int(14) == 0 {
                        endWorkout()
                    } else if !state.exercises.isEmpty {
                        link.phoneEdit(phoneAction(state, &random))
                    }
                } else {
                    startWorkout()
                }
            case 7...10:
                guard !link.toPhone.isEmpty else { break }
                let index = random.int(link.toPhone.count)                    // any queued command: delivery is not in order
                switch random.int(10) {
                case 0: link.dropCommand(at: index)
                case 1, 2: link.duplicateCommand(at: index); try deliverCommand(at: index)             // a copy stays on the way
                default: try deliverCommand(at: index)
                }
            case 11...14:
                guard !link.toWatch.isEmpty else { break }
                let index = random.int(link.toWatch.count)
                switch random.int(10) {
                case 0: link.dropEnvelope(at: index)
                case 1: link.duplicateEnvelope(at: index); try deliverEnvelope(at: index)
                default: try deliverEnvelope(at: index)
                }
            case 15:
                link.coalesceEnvelopes()
            case 18:
                // An outage: the Watch hears nothing for a while (or only the last envelope) while workouts end and start.
                link.toWatch.removeAll()
                for _ in 0..<random.int(in: 1...3) {
                    if link.phone.state == nil { startWorkout() } else { endWorkout() }
                    link.advance(0.5)
                }
                if random.int(2) == 0 { link.coalesceEnvelopes() } else { link.toWatch.removeAll() }
            case 16:
                if random.int(4) == 0 {
                    link.restartWatch()
                    lastAdopted = nil
                }
            case 17:
                link.advance(Double(random.int(in: 5...20)))                  // a long pause: edits can expire
            default:
                break
            }
        }

        // Quiescence: everything still in flight is delivered in order, the unacknowledged edits of dropped commands expire,
        // and the phone sends its current envelope once more.
        while !link.toPhone.isEmpty || !link.toWatch.isEmpty {
            while !link.toPhone.isEmpty { try deliverCommand(at: 0) }
            while !link.toWatch.isEmpty { try deliverEnvelope(at: 0) }
        }
        link.advance(SyncReconciler.pendingLifetime + 1)
        link.pushEnvelope()
        try deliverEnvelope(at: 0)

        let gap = SyncProto.difference(link.watch.state, link.phone.state)
        XCTAssertEqual(link.watch.state?.id, link.phone.state?.id, "\(tag): same workout")
        XCTAssertEqual(SyncProto.withoutHeartRate(link.watch.state), SyncProto.withoutHeartRate(link.phone.state), "\(tag): the mirror equals the authority; differs in \(gap)")
        XCTAssertEqual(link.watch.state, link.phone.state, "\(tag): even the heart rate agrees after the final envelope")
        XCTAssertTrue(link.watch.engine.pendingCommands.isEmpty, "\(tag): nothing is left unacknowledged")

        // No command ran twice, however often it was delivered: the changes the phone reported for the Watch's commands are
        // exactly the commands that changed something, once each.
        XCTAssertTrue(applied.values.allSatisfy { $0 <= 1 }, "\(tag): a set was logged twice")
        let reportedFromWatch = link.phone.recorder.changes.filter {
            if case let .changed(_, _, _, origin) = $0 { return origin == .watch } else { return false }
        }.count
        XCTAssertEqual(reportedFromWatch, applied.values.reduce(0, +), "\(tag): every change from the Watch belongs to one delivered command")
    }

    func testRandomDeliveryConvergesAndNeverAppliesACommandTwice() throws {
        try svcMain {
            for seed in 1...320 {
                try run(seed: UInt64(seed))
            }
        }
    }
}

// MARK: - The controller wrapper

#if canImport(Combine) || PULSE_COMBINE_SHIM
#if canImport(Combine)
import Combine
#endif

/// Pushes the authority controller's envelope into a queue, like the bridge does.
@MainActor
private final class ControllerBridge: WorkoutSideEffect {
    var envelopes: [SyncEnvelope] = []
    private weak var controller: WorkoutController?
    private let clock: SvcClock

    init(controller: WorkoutController, clock: SvcClock) {
        self.controller = controller
        self.clock = clock
    }

    func workoutStarted(_ state: WorkoutState) { push() }

    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        if case .updateHeartRate = action { return }
        push()
    }

    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) { push() }

    private func push() {
        if let controller { envelopes.append(controller.makeEnvelope(now: clock.now)) }
    }
}

final class SyncControllerProtocolTests: XCTestCase {
    @MainActor
    private struct Pair {
        let phoneClock = SvcClock()
        let watchClock = SvcClock()
        let phone: WorkoutController
        let watch: WorkoutController
        let bridge: ControllerBridge
        let commands = SyncCallLog()

        init() {
            let store = StrengthStore(persistence: nil, seedDemoData: true)
            phone = WorkoutController(store: store, persistence: nil, role: .authority, clock: phoneClock.reader)
            watch = WorkoutController(store: StrengthStore(persistence: nil), persistence: nil, role: .mirror, clock: watchClock.reader)
            bridge = ControllerBridge(controller: phone, clock: phoneClock)
            phone.addEffect(bridge)
            watch.addEffect(commands)
        }
    }

    func testTheControllersRoundTripAWatchTap() throws {
        try svcMain {
            let pair = Pair()
            pair.phone.startWorkout(template: pair.phone.store.templates[0])
            let started = try XCTUnwrap(pair.phone.state)
            XCTAssertNil(pair.watch.authoritativeRevision)
            pair.watch.receive(try XCTUnwrap(pair.bridge.envelopes.last))
            XCTAssertEqual(pair.watch.state, started)
            XCTAssertEqual(pair.watch.authoritativeRevision, started.revision)
            XCTAssertTrue(pair.watch.pendingCommands.isEmpty)

            let exerciseID = started.exercises[0].id
            let setID = started.exercises[0].sets[2].id
            pair.watch.send(.logSet(exerciseID: exerciseID, setID: setID), origin: .watch)
            XCTAssertEqual(pair.watch.state?.exercises[0].sets[2].isDone, true)
            let command = try XCTUnwrap(pair.commands.issued.first)
            XCTAssertEqual(pair.watch.pendingCommands, [command])
            XCTAssertEqual(pair.watch.authoritativeRevision, started.revision)

            pair.phone.receive(command)
            pair.phone.receive(command)                                      // the slow path: a duplicate
            XCTAssertEqual(pair.phone.state?.revision, started.revision + 1)
            XCTAssertEqual(pair.bridge.envelopes.last?.ackedCommandIDs, [command.id])
            XCTAssertEqual(pair.phone.makeEnvelope(now: SvcSyncFix.epoch).ackedCommandIDs, [command.id])

            pair.watch.receive(try XCTUnwrap(pair.bridge.envelopes.last))
            XCTAssertTrue(pair.watch.pendingCommands.isEmpty)
            XCTAssertEqual(pair.watch.state, pair.phone.state)
            XCTAssertEqual(pair.watch.authoritativeRevision, pair.phone.state?.revision)
        }
    }

    func testTheControllerEnvelopeNamesTheEndedWorkout() throws {
        try svcMain {
            let pair = Pair()
            pair.phone.startWorkout(template: nil, name: "Free")
            let id = try XCTUnwrap(pair.phone.state?.id)
            pair.watch.receive(try XCTUnwrap(pair.bridge.envelopes.last))
            pair.phone.discard()
            let notice = try XCTUnwrap(pair.bridge.envelopes.last)
            XCTAssertNil(notice.state)
            XCTAssertEqual(notice.endedWorkoutID, id)
            pair.watch.receive(notice)
            XCTAssertNil(pair.watch.state)
            XCTAssertTrue(pair.watch.pendingCommands.isEmpty)
            XCTAssertNil(pair.watch.authoritativeRevision)
        }
    }

    func testAMirrorControllerKeepsUnacknowledgedTapsOnTopOfNewerEnvelopes() throws {
        try svcMain {
            let pair = Pair()
            pair.phone.startWorkout(template: pair.phone.store.templates[0])
            pair.watch.receive(try XCTUnwrap(pair.bridge.envelopes.last))
            let started = try XCTUnwrap(pair.phone.state)

            pair.watch.send(.logSet(exerciseID: started.exercises[0].id, setID: started.exercises[0].sets[0].id), origin: .watch)
            pair.phone.send(.rename("Phone"))
            pair.watch.receive(try XCTUnwrap(pair.bridge.envelopes.last))
            XCTAssertEqual(pair.watch.state?.name, "Phone")
            XCTAssertEqual(pair.watch.state?.exercises[0].sets[0].isDone, true)
            XCTAssertEqual(pair.watch.pendingCommands.count, 1)
        }
    }
}

#endif
