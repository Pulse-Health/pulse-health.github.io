import Foundation
import XCTest
@testable import PulseStrengthCore

// MARK: - Fixtures

/// A clock the test moves by hand (usable as the engine's `@Sendable` clock).
final class SvcClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = SvcSyncFix.epoch) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }

    func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }

    var reader: @Sendable () -> Date {
        { [self] in self.now }
    }
}

/// A side effect that remembers everything it is told.
@MainActor
final class SvcRecorder: WorkoutSideEffect {
    enum Event: Equatable {
        case started(WorkoutState)
        case changed(from: WorkoutState, to: WorkoutState, action: WorkoutAction, origin: ActionOrigin)
        case ended(WorkoutState, CompletedWorkout?)
    }

    private(set) var events: [Event] = []
    var onEvent: ((Event) -> Void)?

    func workoutStarted(_ state: WorkoutState) { add(.started(state)) }

    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        add(.changed(from: old, to: new, action: action, origin: origin))
    }

    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) { add(.ended(state, completed)) }

    private func add(_ event: Event) {
        events.append(event)
        onEvent?(event)
    }

    var changes: [Event] { events.filter { if case .changed = $0 { return true } else { return false } } }
}

/// An engine wired to a seeded data model, a temporary directory, a manual clock and a recorder.
@MainActor
final class SvcRig {
    let clock: SvcClock
    let persistence: FileStrengthPersistence
    let model: StrengthDataModel
    let engine: WorkoutEngine
    let recorder = SvcRecorder()
    private(set) var updates = 0

    init(_ test: XCTestCase, role: WorkoutRole = .authority, seed: Bool = true, persistence existing: FileStrengthPersistence? = nil) {
        clock = SvcClock()
        let persistence = existing ?? FileStrengthPersistence.temporary()
        self.persistence = persistence
        if existing == nil {
            let directory = persistence.directory
            test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        }
        model = StrengthDataModel(persistence: persistence, seedDemoData: seed, now: SvcSyncFix.epoch)
        engine = WorkoutEngine(role: role, persistence: persistence, data: model, clock: clock.reader)
        engine.addEffect(recorder)
        engine.onUpdate = { [unowned self] in self.updates += 1 }
    }

    var upperA: WorkoutTemplate { model.data.templates[0] }

    @discardableResult
    func startUpperA() -> WorkoutState {
        engine.start(template: upperA)
        return engine.state!
    }

    /// Logs the next `count` pending sets, one minute apart.
    func logSets(_ count: Int) {
        for _ in 0..<count {
            clock.advance(60)
            engine.send(.logNextSet)
        }
    }

    var diskState: WorkoutState? { persistence.loadActiveWorkout() }
}

// MARK: - Start, send, derived values

final class EngineBasicsTests: XCTestCase {
    func testStartFromATemplateBuildsAndPersistsTheWorkout() {
        svcMain {
            let rig = SvcRig(self)
            XCTAssertTrue(rig.engine.start(template: rig.upperA))
            let state = rig.engine.state
            XCTAssertEqual(state?.name, "Upper A · Push")
            XCTAssertEqual(state?.templateID, rig.upperA.id)
            XCTAssertEqual(state?.exercises.count, 6)
            XCTAssertEqual(state?.startedAt, rig.clock.now)
            XCTAssertEqual(state?.revision, 0)
            XCTAssertEqual(state?.templateBaseline, rig.upperA.entries.map { $0.id })
            XCTAssertEqual(rig.diskState, state)
            XCTAssertNil(rig.engine.lastCompleted)
            XCTAssertEqual(rig.recorder.events, [.started(state!)])
            XCTAssertEqual(rig.updates, 1)
        }
    }

    func testStartRefreshesThePreviousResultsFromTheStore() {
        svcMain {
            let rig = SvcRig(self)
            let squatBefore = rig.upperA.entries[0].exercise
            XCTAssertEqual(squatBefore.previousBestE1RM, 99, "the template carries the library value")
            let workout = SvcDataFix.workout(80, finishedAt: SvcDataFix.daysAgo(0.1), [
                SvcDataFix.entry("bench", [SvcDataFix.work(100, 3)], n: 80),
            ])
            rig.model.record(workout, updateTemplate: nil)
            rig.engine.start(template: rig.upperA)
            let bench = rig.engine.state?.exercises[0].exercise
            XCTAssertEqual(bench?.previousBestE1RM ?? 0, 110, accuracy: 1e-9)
            XCTAssertEqual(bench?.previousSets, [PreviousSet(weightKg: 100, reps: 3)])
            XCTAssertEqual(bench?.name, squatBefore.name)
            XCTAssertEqual(bench?.defaults, squatBefore.defaults)
            XCTAssertEqual(rig.model.template(id: rig.upperA.id)?.entries[0].exercise.previousBestE1RM, 99, "the stored template is not rewritten")
        }
    }

    func testStartKeepsAnExerciseTheStoreDoesNotKnow() {
        svcMain {
            let rig = SvcRig(self)
            var exotic = ExerciseLibrary.exercise(id: "bench")!
            exotic.id = "custom-gone"
            exotic.previousBestE1RM = 77
            let template = WorkoutTemplate(name: "Exotic", entries: [
                TemplateEntry(exercise: exotic, plannedSets: [PlannedSet(weightKg: 50, reps: 5)], restSeconds: 60),
            ])
            rig.engine.start(template: template)
            XCTAssertEqual(rig.engine.state?.exercises[0].exercise, exotic)
        }
    }

    func testStartWithoutATemplateUsesTheNameOrTheDefault() {
        let cases: [(String?, String)] = [(nil, "Workout"), ("   ", "Workout"), ("", "Workout"), ("  Push day \n", "Push day")]
        for (input, expected) in cases {
            svcMain {
                let rig = SvcRig(self, seed: false)
                XCTAssertTrue(rig.engine.start(template: nil, name: input))
                XCTAssertEqual(rig.engine.state?.name, expected)
                XCTAssertEqual(rig.engine.state?.exercises.count, 0)
                XCTAssertNil(rig.engine.state?.templateID)
            }
        }
    }

    func testStartIsIgnoredWhileAWorkoutRuns() {
        svcMain {
            let rig = SvcRig(self)
            let first = rig.startUpperA()
            XCTAssertFalse(rig.engine.start(template: rig.model.data.templates[1]))
            XCTAssertFalse(rig.engine.start(template: nil, name: "Other"))
            XCTAssertEqual(rig.engine.state, first)
            XCTAssertEqual(rig.recorder.events.count, 1)
            XCTAssertEqual(rig.diskState, first)
        }
    }

    func testStartingTheNextWorkoutClearsTheLastCompleted() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(1)
            let completed = rig.engine.finish(updateTemplate: false)
            XCTAssertNotNil(completed)
            XCTAssertEqual(rig.engine.lastCompleted, completed)
            rig.engine.start(template: nil, name: nil)
            XCTAssertNil(rig.engine.lastCompleted)
            XCTAssertNotNil(rig.engine.state)
        }
    }

    func testSendReducesPersistsAndNotifies() {
        svcMain {
            let rig = SvcRig(self)
            let old = rig.startUpperA()
            rig.clock.advance(30)
            rig.engine.send(.logNextSet, origin: .watch)
            let new = rig.engine.state!
            XCTAssertEqual(new.revision, 1)
            XCTAssertEqual(new.exercises[0].sets.filter { $0.isDone }.count, 1)
            XCTAssertNotNil(new.rest, "logging a set starts the rest timer")
            XCTAssertEqual(rig.diskState, new)
            XCTAssertEqual(rig.recorder.events.last, .changed(from: old, to: new, action: .logNextSet, origin: .watch))
            XCTAssertEqual(rig.updates, 2)
        }
    }

    func testTheDefaultOriginIsThePhone() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.engine.send(.nextExercise)
            guard case let .changed(_, _, _, origin)? = rig.recorder.events.last else { return XCTFail("no change") }
            XCTAssertEqual(origin, .phone)
        }
    }

    func testAnActionThatChangesNothingIsNotReported() {
        svcMain {
            let rig = SvcRig(self)
            let state = rig.startUpperA()
            let events = rig.recorder.events.count
            let updates = rig.updates
            rig.engine.send(.skipRest)                                                    // no rest running
            rig.engine.send(.toggleSet(exerciseID: SvcSyncFix.uuid(1), setID: SvcSyncFix.uuid(2)))   // unknown ids
            rig.engine.send(.goTo(index: 0))                                              // already there
            rig.engine.send(.undo)                                                        // nothing to undo
            XCTAssertEqual(rig.engine.state, state)
            XCTAssertEqual(rig.recorder.events.count, events)
            XCTAssertEqual(rig.updates, updates)
        }
    }

    func testSendWithoutAWorkoutDoesNothing() {
        svcMain {
            let rig = SvcRig(self)
            rig.engine.send(.logNextSet)
            rig.engine.send(.pause)
            XCTAssertNil(rig.engine.state)
            XCTAssertTrue(rig.recorder.events.isEmpty)
            XCTAssertEqual(rig.updates, 0)
            XCTAssertNil(rig.diskState)
        }
    }

    func testPublishingHappensBeforeTheEffectsAreTold() {
        svcMain {
            let rig = SvcRig(self)
            var log: [String] = []
            rig.engine.onUpdate = { log.append("update") }
            rig.recorder.onEvent = { event in
                if case let .changed(_, new, _, _) = event {
                    log.append(rig.engine.state == new ? "effect sees new state" : "effect sees stale state")
                } else {
                    log.append("other")
                }
            }
            rig.startUpperA()
            log.removeAll()
            rig.engine.send(.logNextSet)
            XCTAssertEqual(log, ["update", "effect sees new state"])
        }
    }

    func testEffectsAreRegisteredOnceAndToldInOrder() {
        svcMain {
            let rig = SvcRig(self)
            let second = SvcRecorder()
            var order: [String] = []
            rig.recorder.onEvent = { _ in order.append("first") }
            second.onEvent = { _ in order.append("second") }
            rig.engine.addEffect(second)
            rig.engine.addEffect(second)
            rig.engine.addEffect(rig.recorder)
            rig.startUpperA()
            XCTAssertEqual(order, ["first", "second"])
            XCTAssertEqual(second.events.count, 1)
        }
    }

    func testAnEffectMayRegisterAnotherEffectWhileBeingTold() {
        svcMain {
            let rig = SvcRig(self)
            let late = SvcRecorder()
            rig.recorder.onEvent = { event in
                if case .started = event { rig.engine.addEffect(late) }
            }
            rig.startUpperA()
            XCTAssertTrue(late.events.isEmpty, "it missed the event that was already being delivered")
            rig.engine.send(.nextExercise)
            XCTAssertEqual(late.events.count, 1)
        }
    }

    func testDerivedValuesAreNilWithoutAWorkout() {
        svcMain {
            let rig = SvcRig(self)
            XCTAssertNil(rig.engine.presentation(now: rig.clock.now))
            XCTAssertNil(rig.engine.snapshot(now: rig.clock.now))
            XCTAssertTrue(rig.engine.templateDiff().isEmpty)
        }
    }

    func testDerivedValuesFollowTheState() {
        svcMain {
            let rig = SvcRig(self)
            let state = rig.startUpperA()
            var presentation = rig.engine.presentation(now: rig.clock.now)
            XCTAssertEqual(presentation?.totals.totalSets, 20)
            XCTAssertEqual(presentation?.totals.loggedSets, 0)
            XCTAssertEqual(rig.engine.snapshot(now: rig.clock.now)?.workoutID, state.id)

            rig.logSets(2)
            presentation = rig.engine.presentation(now: rig.clock.now)
            XCTAssertEqual(presentation?.totals.loggedSets, 2)
            let snapshot = rig.engine.snapshot(now: rig.clock.now)
            XCTAssertEqual(snapshot?.targetExerciseID, rig.engine.state?.exercises[0].id)
            XCTAssertEqual(snapshot?.targetSetID, rig.engine.state?.exercises[0].sets[2].id)

            XCTAssertTrue(rig.engine.templateDiff().isEmpty)
            rig.engine.send(.addExercises([ExerciseLibrary.exercise(id: "dips")!]))
            XCTAssertEqual(rig.engine.templateDiff().added, 1)
            rig.engine.send(.moveExercise(from: 0, to: 2))
            XCTAssertTrue(rig.engine.templateDiff().reordered)
            XCTAssertEqual(rig.engine.presentation(now: rig.clock.now)?.finishCheck.templateDiff, rig.engine.templateDiff())
        }
    }

    func testTheRecoveryProviderCanBeReplaced() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.engine.recovery = { _ in 41 }
            XCTAssertEqual(rig.engine.presentation(now: rig.clock.now)?.card?.recoveryPercent, 41)
            rig.engine.recovery = { _ in 93 }
            XCTAssertEqual(rig.engine.presentation(now: rig.clock.now)?.card?.recoveryPercent, 93)
        }
    }
}

// MARK: - Heart-rate throttling

final class EngineHeartRateTests: XCTestCase {
    func testHeartRateIsSavedAndReportedAtMostOncePerTenSeconds() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            let baseEvents = rig.recorder.events.count
            let baseUpdates = rig.updates

            rig.engine.send(.updateHeartRate(100), origin: .watch)                         // t = 0: reported
            XCTAssertEqual(rig.recorder.events.count, baseEvents + 1)
            XCTAssertEqual(rig.diskState?.heartRate, 100)

            rig.clock.advance(3)
            rig.engine.send(.updateHeartRate(110), origin: .watch)                         // t = 3: kept in memory only
            XCTAssertEqual(rig.engine.state?.heartRate, 110)
            XCTAssertEqual(rig.engine.state?.heartRateCount, 2)
            XCTAssertEqual(rig.recorder.events.count, baseEvents + 1)
            XCTAssertEqual(rig.diskState?.heartRate, 100)
            XCTAssertEqual(rig.updates, baseUpdates + 2, "the published state still follows every sample")

            rig.clock.advance(6.75)
            rig.engine.send(.updateHeartRate(120), origin: .watch)                         // t = 9.75
            XCTAssertEqual(rig.recorder.events.count, baseEvents + 1)

            rig.clock.advance(0.25)
            rig.engine.send(.updateHeartRate(130), origin: .watch)                         // t = 10: reported
            XCTAssertEqual(rig.recorder.events.count, baseEvents + 2)
            XCTAssertEqual(rig.diskState?.heartRate, 130)
            XCTAssertEqual(rig.engine.state?.heartRateSum, 460)
            XCTAssertEqual(rig.engine.state?.heartRateCount, 4)
            XCTAssertEqual(rig.engine.state?.revision, 0, "heart-rate samples never bump the revision")
            guard case let .changed(from, to, action, origin)? = rig.recorder.events.last else { return XCTFail("no change") }
            XCTAssertEqual(action, .updateHeartRate(130))
            XCTAssertEqual(origin, .watch)
            XCTAssertEqual(from.heartRate, 120, "the effect sees every sample that happened since")
            XCTAssertEqual(to.heartRate, 130)

            rig.clock.advance(9.99)
            rig.engine.send(.updateHeartRate(131))
            XCTAssertEqual(rig.recorder.events.count, baseEvents + 2)
            rig.clock.advance(0.02)
            rig.engine.send(.updateHeartRate(132))
            XCTAssertEqual(rig.recorder.events.count, baseEvents + 3)
        }
    }

    func testOtherActionsAreNeverThrottledAndCarryTheLatestHeartRate() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.engine.send(.updateHeartRate(100))
            rig.clock.advance(1)
            rig.engine.send(.updateHeartRate(111))                                         // not reported
            rig.clock.advance(1)
            rig.engine.send(.logNextSet)
            XCTAssertEqual(rig.recorder.changes.count, 2)
            XCTAssertEqual(rig.diskState, rig.engine.state)
            XCTAssertEqual(rig.diskState?.heartRate, 111)
            rig.clock.advance(1)
            rig.engine.send(.nextExercise)
            rig.clock.advance(1)
            rig.engine.send(.previousExercise)
            XCTAssertEqual(rig.recorder.changes.count, 4)
        }
    }

    func testTheThrottleSurvivesAClockThatGoesBackwards() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.clock.advance(100)
            rig.engine.send(.updateHeartRate(100))
            let count = rig.recorder.events.count
            rig.clock.advance(-60)                                                        // the clock was set back
            rig.engine.send(.updateHeartRate(101))
            XCTAssertEqual(rig.recorder.events.count, count + 1)
            rig.clock.advance(2)
            rig.engine.send(.updateHeartRate(102))
            XCTAssertEqual(rig.recorder.events.count, count + 1)
        }
    }

    func testANewWorkoutReportsItsFirstSampleImmediately() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.engine.send(.updateHeartRate(90))
            rig.engine.discard()
            rig.clock.advance(1)
            rig.startUpperA()
            let count = rig.recorder.changes.count
            rig.engine.send(.updateHeartRate(91))
            XCTAssertEqual(rig.recorder.changes.count, count + 1)
        }
    }

    func testNilHeartRateIsReportedLikeAnySample() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.engine.send(.updateHeartRate(100))
            rig.clock.advance(11)
            rig.engine.send(.updateHeartRate(nil))
            XCTAssertNil(rig.diskState?.heartRate)
            XCTAssertEqual(rig.engine.state?.heartRateCount, 1)
        }
    }

    func testTheMirrorThrottlesTooAndNeverPersists() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            rig.engine.receive(SyncEnvelope(state: SvcSyncFix.richState(), sentAt: rig.clock.now))
            let base = rig.recorder.events.count
            rig.engine.send(.updateHeartRate(100), origin: .watch)
            rig.clock.advance(4)
            rig.engine.send(.updateHeartRate(101), origin: .watch)
            XCTAssertEqual(rig.recorder.events.count, base + 1)
            XCTAssertEqual(rig.engine.state?.heartRate, 101)
            XCTAssertNil(rig.diskState)
        }
    }

    func testTheIntervalIsTenSeconds() {
        XCTAssertEqual(WorkoutEngine.heartRateInterval, 10)
    }
}

// MARK: - Commands and envelopes

final class EngineSyncTests: XCTestCase {
    func testACommandRunsOnceAndKeepsItsOrigin() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            let command = RemoteCommand(id: SvcSyncFix.uuid(50), action: .logNextSet, origin: .liveActivity, issuedAt: rig.clock.now)
            rig.engine.receive(command)
            XCTAssertEqual(rig.engine.state?.revision, 1)
            guard case let .changed(_, _, action, origin)? = rig.recorder.events.last else { return XCTFail("no change") }
            XCTAssertEqual(action, .logNextSet)
            XCTAssertEqual(origin, .liveActivity)

            rig.engine.receive(command)                                                    // redelivered
            XCTAssertEqual(rig.engine.state?.revision, 1)
            XCTAssertEqual(rig.recorder.changes.count, 1)

            rig.engine.receive(RemoteCommand(id: SvcSyncFix.uuid(51), action: .logNextSet, origin: .watch, issuedAt: rig.clock.now))
            XCTAssertEqual(rig.engine.state?.revision, 2)
        }
    }

    func testCommandsFromTheWatchAreHeartRateThrottledToo() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            for (index, bpm) in [100, 101, 102].enumerated() {
                rig.engine.receive(RemoteCommand(id: SvcSyncFix.uuid(60 + index), action: .updateHeartRate(bpm), origin: .watch, issuedAt: rig.clock.now))
                rig.clock.advance(2)
            }
            XCTAssertEqual(rig.recorder.changes.count, 1)
            XCTAssertEqual(rig.engine.state?.heartRate, 102)
        }
    }

    func testTheMirrorIgnoresCommands() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            rig.engine.receive(SyncEnvelope(state: SvcSyncFix.richState(), sentAt: rig.clock.now))
            let before = rig.engine.state
            rig.engine.receive(RemoteCommand(id: SvcSyncFix.uuid(52), action: .logNextSet, origin: .watch, issuedAt: rig.clock.now))
            XCTAssertEqual(rig.engine.state, before)
        }
    }

    func testACommandThatArrivesWithoutAWorkoutIsConsumed() {
        svcMain {
            let rig = SvcRig(self)
            let command = RemoteCommand(id: SvcSyncFix.uuid(53), action: .logNextSet, origin: .watch, issuedAt: rig.clock.now)
            rig.engine.receive(command)
            XCTAssertNil(rig.engine.state)
            rig.startUpperA()
            rig.engine.receive(command)
            XCTAssertEqual(rig.engine.state?.revision, 0, "a late redelivery must not hit the next workout")
        }
    }

    // MARK: Mirror

    private func envelope(_ state: WorkoutState?, ended: UUID? = nil, at rig: SvcRig) -> SyncEnvelope {
        SyncEnvelope(state: state, endedWorkoutID: ended, sentAt: rig.clock.now)
    }

    private func state(id: Int, revision: Int, name: String = "W") -> WorkoutState {
        var state = WorkoutFactory.makeWorkout(from: SampleData.templates()[1], now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(id))
        state.revision = revision
        state.name = name
        return state
    }

    func testTheMirrorAdoptsTheFirstEnvelopeAndAnnouncesTheWorkout() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            let incoming = state(id: 1, revision: 3)
            rig.engine.receive(envelope(incoming, at: rig))
            XCTAssertEqual(rig.engine.state, incoming)
            XCTAssertEqual(rig.recorder.events, [.started(incoming)])
            XCTAssertEqual(rig.updates, 1)
            XCTAssertNil(rig.diskState, "a mirror never persists")
        }
    }

    func testTheMirrorNeverEchoesAdoptedChanges() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            rig.engine.receive(envelope(state(id: 1, revision: 3), at: rig))
            let newer = state(id: 1, revision: 4, name: "Newer")
            rig.engine.receive(envelope(newer, at: rig))
            XCTAssertEqual(rig.engine.state, newer)
            XCTAssertEqual(rig.recorder.changes.count, 0)
            XCTAssertEqual(rig.recorder.events.count, 1, "the same workout is not announced again")
            XCTAssertEqual(rig.updates, 2)
        }
    }

    /// Sync protocol (ARCHITECTURE 3.4): an older envelope is ignored. An envelope with the same revision is adopted (it may only
    /// carry acknowledgements, see SyncProtocolTests), but when it holds the state the Watch already shows nothing is published.
    func testOlderAndEqualEnvelopesAreIgnored() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            let current = state(id: 1, revision: 5, name: "Current")
            rig.engine.receive(envelope(current, at: rig))
            rig.engine.receive(envelope(current, at: rig))
            rig.engine.receive(envelope(state(id: 1, revision: 2, name: "Older"), at: rig))
            XCTAssertEqual(rig.engine.state, current)
            XCTAssertEqual(rig.updates, 1)
        }
    }

    func testAnEnvelopeForAnotherWorkoutWinsEvenWithALowerRevision() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            rig.engine.receive(envelope(state(id: 1, revision: 9), at: rig))
            let other = state(id: 2, revision: 0)
            rig.engine.receive(envelope(other, at: rig))
            XCTAssertEqual(rig.engine.state, other)
            XCTAssertEqual(rig.recorder.events.count, 2)
            XCTAssertEqual(rig.recorder.events.last, .started(other))
        }
    }

    func testAnEnvelopeWithoutAStateEndsTheLocalWorkout() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            let current = state(id: 1, revision: 3)
            rig.engine.receive(envelope(current, at: rig))
            rig.engine.receive(envelope(nil, ended: current.id, at: rig))
            XCTAssertNil(rig.engine.state)
            XCTAssertEqual(rig.recorder.events, [.started(current), .ended(current, nil)])
            XCTAssertNil(rig.engine.lastCompleted)
        }
    }

    func testAnEndWithoutAnIdEndsWhateverRuns() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            let current = state(id: 1, revision: 3)
            rig.engine.receive(envelope(current, at: rig))
            rig.engine.receive(envelope(nil, at: rig))
            XCTAssertNil(rig.engine.state)
            XCTAssertEqual(rig.recorder.events.last, .ended(current, nil))
        }
    }

    func testAnEndNoticeForAnotherWorkoutIsIgnored() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            let current = state(id: 2, revision: 3)
            rig.engine.receive(envelope(current, at: rig))
            rig.engine.receive(envelope(nil, ended: SvcSyncFix.uuid(1), at: rig))
            XCTAssertEqual(rig.engine.state, current)
            XCTAssertEqual(rig.recorder.events.count, 1)
        }
    }

    func testALateEnvelopeOfAnEndedWorkoutDoesNotRevive() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            let current = state(id: 1, revision: 3)
            rig.engine.receive(envelope(current, at: rig))
            rig.engine.receive(envelope(nil, ended: current.id, at: rig))
            rig.engine.receive(envelope(state(id: 1, revision: 3), at: rig))
            rig.engine.receive(envelope(state(id: 1, revision: 4), at: rig))
            XCTAssertNil(rig.engine.state)
            XCTAssertEqual(rig.recorder.events.count, 2)
            // A different workout is welcome.
            rig.engine.receive(envelope(state(id: 7, revision: 0), at: rig))
            XCTAssertEqual(rig.engine.state?.id, SvcSyncFix.uuid(7))
        }
    }

    func testAnEndNoticeBeforeAnyStateStillBlocksThatWorkout() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            rig.engine.receive(envelope(nil, ended: SvcSyncFix.uuid(1), at: rig))
            XCTAssertTrue(rig.recorder.events.isEmpty)
            rig.engine.receive(envelope(state(id: 1, revision: 1), at: rig))
            XCTAssertNil(rig.engine.state)
        }
    }

    func testAnEmptyEnvelopeWithoutAWorkoutDoesNothing() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            rig.engine.receive(envelope(nil, at: rig))
            XCTAssertNil(rig.engine.state)
            XCTAssertTrue(rig.recorder.events.isEmpty)
            XCTAssertEqual(rig.updates, 0)
        }
    }

    func testTheAuthorityIgnoresEnvelopes() {
        svcMain {
            let rig = SvcRig(self)
            let own = rig.startUpperA()
            rig.engine.receive(envelope(state(id: 9, revision: 99), at: rig))
            rig.engine.receive(envelope(nil, ended: own.id, at: rig))
            XCTAssertEqual(rig.engine.state, own)
        }
    }

    func testTheMirrorAppliesEditsOptimisticallyWithoutSaving() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            let incoming = state(id: 1, revision: 3)
            rig.engine.receive(envelope(incoming, at: rig))
            rig.engine.send(.logNextSet, origin: .watch)
            XCTAssertEqual(rig.engine.state?.revision, 4)
            XCTAssertEqual(rig.engine.state?.exercises[0].sets.filter { $0.isDone }.count, 1)
            guard case let .changed(from, _, action, origin)? = rig.recorder.events.last else { return XCTFail("no change") }
            XCTAssertEqual(from, incoming)
            XCTAssertEqual(action, .logNextSet)
            XCTAssertEqual(origin, .watch)
            XCTAssertNil(rig.diskState)
            XCTAssertNil(rig.engine.lastPersistenceError)
        }
    }

    func testTheMirrorNeverRestores() throws {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        try persistence.saveActiveWorkout(SvcSyncFix.richState())
        svcMain {
            let rig = SvcRig(self, role: .mirror, persistence: persistence)
            rig.engine.restore()
            XCTAssertNil(rig.engine.state)
            XCTAssertTrue(rig.recorder.events.isEmpty)
        }
    }

    func testTheMirrorFinishesLocally() {
        svcMain {
            let rig = SvcRig(self, role: .mirror)
            let incoming = state(id: 1, revision: 3)
            rig.engine.receive(envelope(incoming, at: rig))
            rig.clock.advance(60)
            rig.engine.send(.logNextSet, origin: .watch)
            let completed = rig.engine.finish(updateTemplate: false)
            XCTAssertNotNil(completed)
            XCTAssertNil(rig.engine.state)
            XCTAssertEqual(rig.engine.lastCompleted, completed)
            guard case let .ended(_, finished)? = rig.recorder.events.last else { return XCTFail("not ended") }
            XCTAssertEqual(finished, completed)
            XCTAssertNil(rig.diskState)
            // The finished workout is remembered as ended: the phone's stale copy does not bring it back.
            rig.engine.receive(envelope(incoming, at: rig))
            XCTAssertNil(rig.engine.state)
        }
    }

    // MARK: Authority and mirror together

    private func randomAction(_ state: WorkoutState, _ random: inout SvcLCG) -> WorkoutAction {
        let exercises = state.exercises
        func pickExercise() -> WorkoutExercise? { exercises.isEmpty ? nil : exercises[random.int(exercises.count)] }
        func pickSet(_ exercise: WorkoutExercise) -> LoggedSet? { exercise.sets.isEmpty ? nil : exercise.sets[random.int(exercise.sets.count)] }
        let unknown = SvcSyncFix.uuid(9_999)
        switch random.int(34) {
        case 0, 1, 2, 3: return .logNextSet
        case 4, 5:
            guard let e = pickExercise(), let s = pickSet(e) else { return .logNextSet }
            return .toggleSet(exerciseID: e.id, setID: s.id)
        case 6:
            guard let e = pickExercise(), let s = pickSet(e) else { return .logNextSet }
            return .logSet(exerciseID: e.id, setID: s.id)
        case 7:
            guard let e = pickExercise(), let s = pickSet(e) else { return .skipRest }
            return .setWeight(exerciseID: e.id, setID: s.id, kg: Double(random.int(400)) / 4)
        case 8:
            guard let e = pickExercise(), let s = pickSet(e) else { return .skipRest }
            return .setReps(exerciseID: e.id, setID: s.id, reps: random.int(in: -2...30))
        case 9: return .nudgeNextSet(weightSteps: random.int(in: -3...3), repsSteps: random.int(in: -3...3))
        case 10:
            guard let e = pickExercise(), let s = pickSet(e) else { return .skipRest }
            return .setSetType(exerciseID: e.id, setID: s.id, type: SetType.allCases[random.int(SetType.allCases.count)])
        case 11:
            guard let e = pickExercise(), let s = pickSet(e) else { return .skipRest }
            return .setRIR(exerciseID: e.id, setID: s.id, rir: random.int(2) == 0 ? nil : random.int(in: 0...5))
        case 12: return .toggleLastSetRIR(random.int(in: 0...4))
        case 13:
            guard let e = pickExercise() else { return .addSet(exerciseID: unknown) }
            return .addSet(exerciseID: e.id)
        case 14:
            guard let e = pickExercise(), let s = pickSet(e) else { return .undo }
            return .deleteSet(exerciseID: e.id, setID: s.id)
        case 15:
            guard let e = pickExercise() else { return .undo }
            return .setNote(exerciseID: e.id, note: "note \(random.int(100))")
        case 16: return .goTo(index: random.int(in: -1...8))
        case 17: return random.int(2) == 0 ? .nextExercise : .previousExercise
        case 18:
            let library = ExerciseLibrary.builtIn
            return .addExercises([library[random.int(library.count)]])
        case 19:
            guard let e = pickExercise() else { return .undo }
            return .removeExercise(exerciseID: e.id)
        case 20: return .moveExercise(from: random.int(in: 0...7), to: random.int(in: 0...7))
        case 21:
            guard let e = pickExercise() else { return .undo }
            return .moveExerciseBy(exerciseID: e.id, delta: random.int(in: -2...2))
        case 22:
            guard let e = pickExercise() else { return .undo }
            return .replaceExercise(exerciseID: e.id, with: ExerciseLibrary.builtIn[random.int(ExerciseLibrary.builtIn.count)])
        case 23:
            guard let e = pickExercise() else { return .undo }
            return .toggleSuperset(exerciseID: e.id)
        case 24:
            guard let e = pickExercise() else { return .undo }
            return .setRest(exerciseID: e.id, seconds: random.int(in: 0...4) * 30)
        case 25: return .adjustRest(seconds: random.int(in: -2...2) * 15)
        case 26: return .skipRest
        case 27: return random.int(2) == 0 ? .pause : .resume
        case 28: return .undo
        case 29, 30: return .updateHeartRate(random.int(5) == 0 ? nil : random.int(in: 60...190))
        case 31: return .setAutoStartRest(random.int(2) == 0)
        case 32: return .setUsedWatch(random.int(2) == 0)
        default: return .rename("Workout \(random.int(50))")
        }
    }

    private func withoutHeartRate(_ state: WorkoutState?) -> WorkoutState? {
        guard var copy = state else { return nil }
        copy.heartRate = nil
        copy.heartRateSum = 0
        copy.heartRateCount = 0
        return copy
    }

    func testPhoneDiskAndWatchStayInSyncUnderRandomPlay() throws {
        for seed in 1...14 {
            try svcMain {
                var random = SvcLCG(seed: UInt64(seed) &* 7_919)
                let phone = SvcRig(self)
                let watch = SvcRig(self, role: .mirror)
                var heartRateOnly = false

                @MainActor func sync() throws {
                    let envelope = SyncEnvelope(state: phone.engine.state, endedWorkoutID: nil, sentAt: phone.clock.now)
                    let message = try SyncCodec.decode(try SyncCodec.encode(.state(envelope)))
                    guard case let .state(received) = message else { return XCTFail("seed \(seed): not a state message") }
                    watch.engine.receive(received)
                }

                for step in 0..<120 {
                    phone.clock.advance(Double(random.int(in: 0...32)) / 4)
                    watch.clock.set(phone.clock.now)
                    let events = phone.recorder.events.count

                    if phone.engine.state == nil {
                        phone.engine.start(template: random.int(2) == 0 ? phone.upperA : nil, name: "Free \(step)")
                        heartRateOnly = false
                    } else if random.int(40) == 0 {
                        let ended = phone.engine.state!.id
                        if random.int(2) == 0 { phone.engine.finish(updateTemplate: random.int(2) == 0) } else { phone.engine.discard() }
                        XCTAssertNil(phone.diskState, "seed \(seed) step \(step)")
                        watch.engine.receive(SyncEnvelope(state: nil, endedWorkoutID: ended, sentAt: phone.clock.now))
                        XCTAssertNil(watch.engine.state, "seed \(seed) step \(step)")
                        continue
                    } else {
                        let action = randomAction(phone.engine.state!, &random)
                        if case .updateHeartRate = action { heartRateOnly = true } else { heartRateOnly = false }
                        phone.engine.send(action, origin: .phone)
                    }

                    if phone.recorder.events.count > events {
                        XCTAssertEqual(phone.diskState, phone.engine.state, "seed \(seed) step \(step): disk follows the reported state")
                    }
                    try sync()
                    XCTAssertEqual(watch.engine.state?.id, phone.engine.state?.id, "seed \(seed) step \(step)")
                    XCTAssertEqual(watch.engine.state?.revision, phone.engine.state?.revision, "seed \(seed) step \(step)")
                    // Heart-rate samples do not bump the revision, so the Watch may lag behind on them until the next change.
                    XCTAssertEqual(withoutHeartRate(watch.engine.state), withoutHeartRate(phone.engine.state), "seed \(seed) step \(step)")
                    if !heartRateOnly && phone.recorder.events.count > events {
                        XCTAssertEqual(watch.engine.state, phone.engine.state, "seed \(seed) step \(step): a reported change reaches the Watch whole")
                    }
                    XCTAssertNil(watch.diskState)
                }
            }
        }
    }
}

// MARK: - Finish, discard, restore

final class EngineLifecycleTests: XCTestCase {
    func testFinishRecordsTheWorkoutEverywhere() {
        svcMain {
            let rig = SvcRig(self)
            let started = rig.startUpperA()
            rig.logSets(5)
            rig.clock.advance(1_800)
            let previous = rig.engine.state!
            let historyBefore = rig.model.data.history.count

            let completed = rig.engine.finish(updateTemplate: false)
            guard let completed else { return XCTFail("nothing was recorded") }
            XCTAssertNil(rig.engine.state)
            XCTAssertEqual(rig.engine.lastCompleted, completed)
            XCTAssertEqual(completed.name, "Upper A · Push")
            XCTAssertEqual(completed.templateID, started.templateID)
            XCTAssertEqual(completed.finishedAt, rig.clock.now)
            XCTAssertEqual(completed.loggedSets, 5)
            XCTAssertEqual(rig.model.data.history.count, historyBefore + 1)
            XCTAssertEqual(rig.model.data.history.first, completed)
            XCTAssertEqual(rig.persistence.loadHistory().first, completed)
            XCTAssertNil(rig.diskState, "the persisted active workout is deleted")
            XCTAssertEqual(rig.recorder.events.last, .ended(previous, completed))
            XCTAssertEqual(rig.recorder.events.filter { if case .ended = $0 { return true } else { return false } }.count, 1)
            XCTAssertEqual(rig.updates, 1 + 5 + 1)
        }
    }

    func testFinishRaisesThePersonalBest() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(5)                                   // 2 warm-ups, 82.5 x 6, 82.5 x 6, 85 x 6
            let before = rig.model.data.personalBests["bench"]?.estimated1RM ?? 0
            XCTAssertEqual(before, 85 * (1 + 5.0 / 30), accuracy: 1e-9)
            rig.engine.finish(updateTemplate: false)
            let best = rig.model.data.personalBests["bench"]
            XCTAssertEqual(best?.estimated1RM ?? 0, 102, accuracy: 1e-9)
            XCTAssertEqual(best?.weightKg, 85)
            XCTAssertEqual(best?.reps, 6)
            XCTAssertEqual(best?.date, rig.clock.now)
            XCTAssertEqual(rig.persistence.loadPersonalBests()["bench"], best)
            XCTAssertEqual(rig.model.exercise(id: "bench")?.previousBestE1RM ?? 0, 102, accuracy: 1e-9)
        }
    }

    func testFinishLeavesALowerPersonalBestAlone() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(3)                                   // best working set 82.5 x 6 = 99 < 99.17
            let before = rig.model.data.personalBests["bench"]
            rig.engine.finish(updateTemplate: false)
            XCTAssertEqual(rig.model.data.personalBests["bench"], before)
        }
    }

    func testFinishStampsTheTemplateButLeavesItsExercisesAlone() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.engine.send(.addExercises([ExerciseLibrary.exercise(id: "dips")!]))
            rig.logSets(2)
            let templatesBefore = rig.model.data.templates
            rig.engine.finish(updateTemplate: false)
            let templates = rig.model.data.templates
            XCTAssertEqual(templates[0].lastPerformed, rig.clock.now)
            XCTAssertEqual(templates[0].entries, templatesBefore[0].entries)
            XCTAssertEqual(templates[1], templatesBefore[1])
            XCTAssertEqual(templates[2], templatesBefore[2])
            XCTAssertEqual(rig.persistence.loadTemplates(), templates)
        }
    }

    func testFinishCanUpdateTheTemplateFromTheWorkout() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.engine.send(.addExercises([ExerciseLibrary.exercise(id: "dips")!]))
            rig.engine.send(.removeExercise(exerciseID: rig.engine.state!.exercises[5].id))      // crossover goes
            rig.logSets(2)
            let before = rig.upperA
            rig.engine.finish(updateTemplate: true)
            let updated = rig.model.data.templates[0]
            XCTAssertEqual(updated.id, before.id)
            XCTAssertEqual(updated.name, before.name)
            XCTAssertEqual(updated.lastPerformed, rig.clock.now)
            XCTAssertEqual(updated.entries.map { $0.exercise.id }, ["bench", "incline", "ohp", "lateral", "pushdown", "dips"])
            XCTAssertEqual(Array(updated.entries.prefix(5)).map { $0.id }, Array(before.entries.prefix(5)).map { $0.id }, "kept entries keep their ids")
            XCTAssertEqual(rig.model.data.templates.count, 3)
            XCTAssertEqual(rig.persistence.loadTemplates()[0], updated)
        }
    }

    func testUpdatingATemplateOfAWorkoutWithoutOneDoesNothing() {
        svcMain {
            let rig = SvcRig(self)
            rig.engine.start(template: nil, name: "Free")
            rig.engine.send(.addExercises([ExerciseLibrary.exercise(id: "bench")!]))
            rig.logSets(1)
            let templates = rig.model.data.templates
            let completed = rig.engine.finish(updateTemplate: true)
            XCTAssertNotNil(completed)
            XCTAssertNil(completed?.templateID)
            XCTAssertEqual(rig.model.data.templates, templates)
        }
    }

    func testUpdatingATemplateThatNoLongerExistsDoesNotBringItBack() {
        svcMain {
            let rig = SvcRig(self, seed: false)
            let orphan = SampleData.templates()[0]
            rig.engine.start(template: orphan)
            rig.logSets(1)
            rig.engine.finish(updateTemplate: true)
            XCTAssertTrue(rig.model.data.templates.isEmpty)
            XCTAssertEqual(rig.model.data.history.count, 1)
        }
    }

    func testFinishingWithNothingLoggedDiscardsInstead() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            let previous = rig.engine.state!
            let historyBefore = rig.model.data.history
            XCTAssertNil(rig.engine.finish(updateTemplate: true))
            XCTAssertNil(rig.engine.state)
            XCTAssertNil(rig.engine.lastCompleted)
            XCTAssertEqual(rig.model.data.history, historyBefore)
            XCTAssertNil(rig.diskState)
            XCTAssertEqual(rig.recorder.events.last, .ended(previous, nil))
        }
    }

    func testFinishWithoutAWorkoutReturnsNil() {
        svcMain {
            let rig = SvcRig(self)
            XCTAssertNil(rig.engine.finish(updateTemplate: false))
            XCTAssertTrue(rig.recorder.events.isEmpty)
            XCTAssertEqual(rig.updates, 0)
        }
    }

    func testNothingHappensAfterTheWorkoutEnded() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(1)
            rig.engine.finish(updateTemplate: false)
            let events = rig.recorder.events.count
            rig.engine.send(.logNextSet)
            rig.engine.discard()
            XCTAssertNil(rig.engine.finish(updateTemplate: false))
            XCTAssertEqual(rig.recorder.events.count, events)
            XCTAssertNil(rig.diskState)
        }
    }

    func testDiscardDropsTheWorkoutWithoutRecordingIt() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(3)
            let previous = rig.engine.state!
            let history = rig.model.data
            rig.engine.discard()
            XCTAssertNil(rig.engine.state)
            XCTAssertNil(rig.diskState)
            XCTAssertEqual(rig.model.data, history)
            XCTAssertEqual(rig.recorder.events.last, .ended(previous, nil))
        }
    }

    func testDiscardKeepsTheLastFinishedWorkout() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(1)
            let completed = rig.engine.finish(updateTemplate: false)
            rig.engine.start(template: nil, name: "Second")
            XCTAssertNil(rig.engine.lastCompleted)
            rig.engine.discard()
            XCTAssertNil(rig.engine.lastCompleted)
            XCTAssertEqual(rig.model.data.history.first, completed)
        }
    }

    func testDiscardWithoutAWorkoutDoesNothing() {
        svcMain {
            let rig = SvcRig(self)
            rig.engine.discard()
            XCTAssertTrue(rig.recorder.events.isEmpty)
        }
    }

    func testRestoreBringsBackTheSavedWorkoutAndTellsTheEffects() {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let saved = svcMain { () -> WorkoutState in
            let rig = SvcRig(self, persistence: persistence)
            rig.startUpperA()
            rig.logSets(3)
            rig.engine.send(.pause)
            return rig.engine.state!
        }
        svcMain {
            let rig = SvcRig(self, persistence: persistence)
            XCTAssertNil(rig.engine.state)
            rig.engine.restore()
            XCTAssertEqual(rig.engine.state, saved)
            XCTAssertEqual(rig.recorder.events, [.started(saved)])
            XCTAssertEqual(rig.updates, 1)
            // The restored workout is fully alive.
            rig.engine.send(.resume)
            XCTAssertEqual(rig.engine.state?.revision, saved.revision + 1)
            XCTAssertEqual(rig.diskState, rig.engine.state)
            rig.logSets(1)
            XCTAssertNotNil(rig.engine.finish(updateTemplate: false))
        }
    }

    func testRestoreLeavesARunningWorkoutAlone() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(2)
            rig.clock.advance(1)
            rig.engine.send(.updateHeartRate(100))
            rig.clock.advance(1)
            rig.engine.send(.updateHeartRate(101))                       // newer than the file
            let live = rig.engine.state
            let events = rig.recorder.events.count
            rig.engine.restore()
            XCTAssertEqual(rig.engine.state, live)
            XCTAssertEqual(rig.recorder.events.count, events)
        }
    }

    func testRestoreWithoutASavedWorkoutDoesNothing() {
        svcMain {
            let rig = SvcRig(self)
            rig.engine.restore()
            XCTAssertNil(rig.engine.state)
            XCTAssertTrue(rig.recorder.events.isEmpty)
            XCTAssertEqual(rig.updates, 0)
        }
    }

    func testRestoreSurvivesACorruptFile() throws {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        try Data("{ broken".utf8).write(to: directory.appendingPathComponent("active-workout.json"))
        svcMain {
            let rig = SvcRig(self, persistence: persistence)
            rig.engine.restore()
            XCTAssertNil(rig.engine.state)
            rig.startUpperA()
            XCTAssertNotNil(rig.diskState, "a fresh workout overwrites the damaged file")
        }
    }

    func testAnEngineWithoutPersistenceWorksInMemory() {
        svcMain {
            let clock = SvcClock()
            let model = StrengthDataModel(persistence: nil, seedDemoData: true, now: clock.now)
            let engine = WorkoutEngine(role: .authority, persistence: nil, data: model, clock: clock.reader)
            engine.restore()
            XCTAssertNil(engine.state)
            engine.start(template: model.data.templates[0])
            engine.send(.logNextSet)
            XCTAssertEqual(engine.state?.revision, 1)
            XCTAssertNotNil(engine.finish(updateTemplate: false))
            XCTAssertNil(engine.lastPersistenceError)
        }
    }

    func testASaveFailureIsRecordedAndTheWorkoutKeepsRunning() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-engine-blocker-" + UUID().uuidString)
        try Data("file".utf8).write(to: blocker)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocker) }
        svcMain {
            let broken = FileStrengthPersistence(directory: blocker.appendingPathComponent("inner"))
            let rig = SvcRig(self, seed: false, persistence: broken)
            rig.engine.start(template: SampleData.templates()[0])
            XCTAssertNotNil(rig.engine.lastPersistenceError)
            rig.engine.send(.logNextSet)
            XCTAssertEqual(rig.engine.state?.revision, 1, "the in-memory workout is unaffected")
            XCTAssertEqual(rig.recorder.changes.count, 1)
        }
    }

    func testTheSavedWorkoutAlwaysMatchesTheLiveOne() {
        svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            for action: WorkoutAction in [.logNextSet, .nextExercise, .adjustRest(seconds: 15), .pause, .resume, .rename("Renamed"), .logNextSet] {
                rig.clock.advance(5)
                rig.engine.send(action)
                XCTAssertEqual(rig.diskState, rig.engine.state, "\(action)")
            }
        }
    }
}

// MARK: - WorkoutController (Combine wrapper; runs on Apple platforms and, with -DPULSE_COMBINE_SHIM, on Linux)

#if canImport(Combine) || PULSE_COMBINE_SHIM
#if canImport(Combine)
import Combine
#endif

final class WorkoutControllerWrapperTests: XCTestCase {
    @MainActor private func makeStore(persistence: FileStrengthPersistence?) -> StrengthStore {
        let store = StrengthStore(persistence: persistence)
        for template in SampleData.templates() { store.saveTemplate(template) }
        return store
    }

    private func makePersistence() -> FileStrengthPersistence {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return persistence
    }

    func testThePublishedStateFollowsTheWorkout() {
        svcMain {
            let persistence = makePersistence()
            let store = makeStore(persistence: persistence)
            let clock = SvcClock()
            let controller = WorkoutController(store: store, persistence: persistence, clock: clock.reader)
            XCTAssertNil(controller.state)
            XCTAssertNil(controller.presentation(now: clock.now))
            XCTAssertEqual(controller.role, .authority)
            XCTAssertTrue(controller.store === store)

            controller.startWorkout(template: store.templates[0])
            XCTAssertEqual(controller.state?.name, "Upper A · Push")
            XCTAssertEqual(persistence.loadActiveWorkout(), controller.state)

            clock.advance(30)
            controller.send(.logNextSet)
            XCTAssertEqual(controller.state?.revision, 1)
            XCTAssertEqual(controller.presentation(now: clock.now)?.totals.loggedSets, 1)
            XCTAssertEqual(controller.snapshot(now: clock.now)?.workoutID, controller.state?.id)
            XCTAssertTrue(controller.templateDiff().isEmpty)

            let completed = controller.finish(updateTemplate: false)
            XCTAssertNotNil(completed)
            XCTAssertNil(controller.state)
            XCTAssertEqual(controller.lastCompleted, completed)
            XCTAssertEqual(store.history.first, completed, "the store publishes the recorded workout")
            XCTAssertEqual(store.templates[0].lastPerformed, completed?.finishedAt)
            XCTAssertNil(persistence.loadActiveWorkout())
        }
    }

    func testStartingWithoutATemplateAndDiscarding() {
        svcMain {
            let controller = WorkoutController(store: makeStore(persistence: nil), persistence: nil)
            controller.startWorkout(template: nil)
            XCTAssertEqual(controller.state?.name, "Workout")
            controller.startWorkout(template: nil, name: "Second")                       // ignored while one runs
            XCTAssertEqual(controller.state?.name, "Workout")
            controller.discard()
            XCTAssertNil(controller.state)
            XCTAssertNil(controller.lastCompleted)
            controller.startWorkout(template: nil, name: "Second")
            XCTAssertEqual(controller.state?.name, "Second")
        }
    }

    func testEffectsRestoreAndCommands() {
        let persistence = makePersistence()
        svcMain {
            let store = makeStore(persistence: persistence)
            let clock = SvcClock()
            let first = WorkoutController(store: store, persistence: persistence, clock: clock.reader)
            let recorder = SvcRecorder()
            first.addEffect(recorder)
            first.startWorkout(template: store.templates[1])
            let command = RemoteCommand(action: .logNextSet, origin: .watch, issuedAt: clock.now)
            first.receive(command)
            first.receive(command)
            XCTAssertEqual(first.state?.revision, 1)
            XCTAssertEqual(recorder.changes.count, 1)

            // A relaunch picks the workout up again.
            let second = WorkoutController(store: store, persistence: persistence, clock: clock.reader)
            let relaunched = SvcRecorder()
            second.addEffect(relaunched)
            XCTAssertNil(second.state)
            second.restoreFromDisk()
            XCTAssertEqual(second.state, first.state)
            XCTAssertEqual(relaunched.events, [.started(first.state!)])
        }
    }

    func testTheMirrorFollowsEnvelopesAndKeepsTheRecoveryProvider() {
        svcMain {
            let store = makeStore(persistence: nil)
            let controller = WorkoutController(store: store, persistence: nil, role: .mirror, recovery: { _ in 12 })
            XCTAssertEqual(controller.role, .mirror)
            XCTAssertEqual(controller.recovery(.chest), 12)
            controller.recovery = { _ in 77 }
            XCTAssertEqual(controller.recovery(.legs), 77)

            let incoming = SvcSyncFix.richState()
            controller.receive(SyncEnvelope(state: incoming, sentAt: SvcSyncFix.epoch))
            XCTAssertEqual(controller.state, incoming)
            XCTAssertEqual(controller.presentation(now: SvcSyncFix.epoch)?.card?.recoveryPercent, 77)
            controller.receive(SyncEnvelope(state: nil, endedWorkoutID: incoming.id, sentAt: SvcSyncFix.epoch))
            XCTAssertNil(controller.state)
        }
    }

    #if canImport(Combine)
    func testObjectWillChangeFiresForEveryPublishedChange() {
        svcMain {
            let store = makeStore(persistence: nil)
            let controller = WorkoutController(store: store, persistence: nil)
            var count = 0
            let subscription = controller.objectWillChange.sink { count += 1 }
            controller.startWorkout(template: store.templates[0])
            XCTAssertGreaterThan(count, 0)
            let afterStart = count
            controller.send(.skipRest)                                                   // no change
            XCTAssertEqual(count, afterStart)
            controller.send(.nextExercise)
            XCTAssertGreaterThan(count, afterStart)
            subscription.cancel()
        }
    }
    #endif
}

#endif
