import Foundation
import XCTest
@testable import PulseStrengthCore

// A second fuzzer for the sync protocol, next to the one in SyncProtocolTests.swift. It models the real channels more closely:
//  * phone -> Watch: a one-slot application context (latest wins, always delivered eventually) plus a FIFO sendMessage queue that
//    is dropped while the Watch is unreachable;
//  * Watch -> phone: a fast FIFO (sendMessage) that can fail over to a slow FIFO (transferUserInfo, long delay), duplicates on both;
//  * wall-clock delivery delays (up to 60 s), clock skew between the devices, Watch restarts that replay the cached context,
//    phone relaunches (engine rebuilt from disk), Live Activity edits and workouts restarted from the same template.
// The Watch's client is modelled too: a command that goes over the slow channel is marked as queued (`markQueued`, what
// WatchConnectivityClient does when it uses transferUserInfo), and the expiry timer (`expirePending`) runs whenever the clock moves.
//
// What it guards (the findings of the sync review): the Watch never goes back to an older workout (R1), a lost command does not
// leave the Watch different from the phone even when no further envelope comes (R2), no command runs twice, also across a phone
// relaunch (R4).

struct ChannelConfig {
    var skew: TimeInterval = 0
    var relaunch = false
    var liveActivity = true
    var watchRestart = true
    var maxDelay: TimeInterval = 60
    var steps = 60
    /// Percent of commands that are lost for good (crash while handling, undecodable payload).
    var commandLossPercent = 0
    /// Chance (1 in n) per phone step that the workout is ended; smaller = more churn.
    var endEvery = 14
    /// Extra delay range (in quarter seconds) of the sendMessage queue; the context stays fast.
    var messageDelayQuarters = 8
    /// Watch only taps idempotent / absolute actions (setWeight, logSet, skipRest).
    var idempotentWatch = false
}

@MainActor
final class ChannelPhoneBridge: WorkoutSideEffect {
    weak var link: ChannelLink?
    func workoutStarted(_ state: WorkoutState) { link?.pushEnvelope() }
    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        if case .updateHeartRate = action { return }
        link?.pushEnvelope()
    }
    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) { link?.pushEnvelope() }
}

@MainActor
final class ChannelWatchIssuer: WorkoutSideEffect {
    weak var link: ChannelLink?
    func commandIssued(_ command: RemoteCommand) { link?.send(command) }
}

struct Timed<T> {
    var due: TimeInterval
    var value: T
}

@MainActor
final class ChannelLink {
    var t: TimeInterval = 0
    let config: ChannelConfig
    var random: SvcLCG

    let phoneClock = SvcClock()
    let watchClock = SvcClock()
    let persistence = FileStrengthPersistence.temporary()
    var model: StrengthDataModel
    var phone: WorkoutEngine
    let watchModel = StrengthDataModel(persistence: nil, seedDemoData: true, now: SvcSyncFix.epoch)
    var watch: WorkoutEngine
    let bridge = ChannelPhoneBridge()
    let issuer = ChannelWatchIssuer()
    var watchRecorder = SvcRecorder()

    // channels
    var context: SyncEnvelope?                 // one slot
    var contextDue: TimeInterval = 0
    var messages: [Timed<SyncEnvelope>] = []   // sendMessage queue (FIFO)
    var fast: [Timed<RemoteCommand>] = []      // sendMessage Watch -> phone
    var slow: [Timed<RemoteCommand>] = []      // transferUserInfo Watch -> phone
    var cachedContext: SyncEnvelope?           // what receivedApplicationContext would hold
    var reachable = true

    // bookkeeping
    var generation: [UUID: Int] = [:]
    var generations = 0
    var issued: [RemoteCommand] = []
    var appliedCount: [UUID: Int] = [:]
    var appliedAfterRelaunch = 0
    var relaunchEpoch = 0
    var appliedEpoch: [UUID: Int] = [:]
    var watchMaxGeneration = -1
    var failures: [String] = []
    var jumps = 0

    init(seed: UInt64, config: ChannelConfig) {
        self.config = config
        random = SvcLCG(seed: seed &* 0x9E37_79B9_7F4A_7C15 &+ 0xABCD_1234)
        model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: SvcSyncFix.epoch)
        phone = WorkoutEngine(role: .authority, persistence: persistence, data: model, clock: phoneClock.reader)
        watch = WorkoutEngine(role: .mirror, persistence: nil, data: watchModel, clock: watchClock.reader)
        bridge.link = self
        issuer.link = self
        phone.addEffect(bridge)
        wireWatch()
        watchClock.set(SvcSyncFix.epoch.addingTimeInterval(config.skew))
    }

    func wireWatch() {
        watchRecorder = SvcRecorder()
        watch.addEffect(watchRecorder)
        watch.addEffect(issuer)
    }

    func fail(_ text: String) { failures.append("t=\(t): \(text)") }

    // MARK: time

    func advance(_ dt: TimeInterval) {
        t += dt
        phoneClock.advance(dt)
        watchClock.advance(dt)
        // The client's timer: it wakes up when the oldest unacknowledged edit is due and lets the controller drop it.
        if let due = watch.nextPendingExpiry, due < watchClock.now { watch.expirePending() }
    }

    // MARK: phone side

    func pushEnvelope() {
        totalPushes += 1
        let envelope = phone.makeEnvelope(now: phoneClock.now)
        cachedContext = envelope
        context = envelope
        contextDue = t + Double(random.int(in: 0...6)) / 4
        if reachable && random.int(10) != 0 {
            messages.append(Timed(due: t + Double(random.int(in: 0...config.messageDelayQuarters)) / 4, value: envelope))
        }
    }

    func startWorkout() {
        let template = model.data.templates[random.int(3)]
        if phone.start(template: template) {
            generations += 1
            if let id = phone.state?.id { generation[id] = generations }
            // a timed exercise besides the template's, so that the timer commands have something to act on
            phone.send(.addExercises([ExerciseLibrary.exercise(id: "plank")!]))
        }
    }

    func relaunchPhone() {
        relaunchEpoch += 1
        let newModel = StrengthDataModel(persistence: persistence, seedDemoData: true, now: SvcSyncFix.epoch)
        let engine = WorkoutEngine(role: .authority, persistence: persistence, data: newModel, clock: phoneClock.reader)
        engine.addEffect(bridge)
        model = newModel
        phone = engine
        phone.restore()                         // announces the restored workout -> bridge pushes
    }

    func restartWatch() {
        watch = WorkoutEngine(role: .mirror, persistence: nil, data: watchModel, clock: watchClock.reader)
        wireWatch()
        watchMaxGeneration = -1
        if let cached = cachedContext { watch.receive(cached) }     // receivedApplicationContext at activation
        checkWatch()
    }

    // MARK: Watch side

    func send(_ command: RemoteCommand) {
        issued.append(command)
        if config.commandLossPercent > 0 && random.int(100) < config.commandLossPercent { return }
        let both = random.int(8) == 0
        let useFast = reachable && random.int(6) != 0
        if useFast || both {
            fast.append(Timed(due: t + Double(random.int(in: 0...4)) / 4, value: command))
        }
        if !useFast || both {
            slow.append(Timed(due: t + Double(random.int(in: 4...Int(config.maxDelay * 4))) / 4, value: command))
        }
        if !useFast {
            // The client used transferUserInfo (the phone was out of reach): the system queue delivers it, however late.
            watch.markQueued(commandID: command.id)
        }
    }

    func deliver(_ command: RemoteCommand) {
        let before = phone.state
        // detect a push caused by the command (like PhoneWatchBridge.pushRequests)
        let marker = totalPushes
        phone.receive(command)
        if totalPushes == marker { pushEnvelope() }
        if phone.state != before {
            appliedCount[command.id, default: 0] += 1
            if let epoch = appliedEpoch[command.id], epoch != relaunchEpoch { appliedAfterRelaunch += 1 }
            appliedEpoch[command.id] = relaunchEpoch
            if (appliedCount[command.id] ?? 0) > 1 && !config.relaunch {
                fail("command applied twice: \(command.action)")
            }
        }
    }

    var totalPushes = 0

    func deliver(_ envelope: SyncEnvelope) {
        let before = watch.state?.id
        watch.receive(envelope)
        if let before, let after = watch.state?.id, before != after { jumps += 1 }
        checkWatch()
    }

    func checkWatch() {
        if let id = watch.state?.id, let gen = generation[id] {
            if gen < watchMaxGeneration { fail("Watch went back to an older workout (generation \(gen) < \(watchMaxGeneration))") }
            watchMaxGeneration = max(watchMaxGeneration, gen)
        }
        if watch.pendingCommands.count > SyncReconciler.pendingCapacity { fail("pending list unbounded") }
    }

    // MARK: pump

    func pump() {
        // each channel is FIFO; deliver everything that is due
        var progressed = true
        while progressed {
            progressed = false
            if let envelope = context, contextDue <= t {
                context = nil
                deliver(envelope)
                progressed = true
            }
            if let first = messages.first, first.due <= t {
                messages.removeFirst()
                deliver(first.value)
                if random.int(12) == 0 { messages.append(Timed(due: t + 0.25, value: first.value)) }
                progressed = true
            }
            if let first = fast.first, first.due <= t {
                fast.removeFirst()
                deliver(first.value)
                progressed = true
            }
            if let first = slow.first, first.due <= t {
                slow.removeFirst()
                deliver(first.value)
                progressed = true
            }
        }
    }

    func drain() {
        while context != nil || !messages.isEmpty || !fast.isEmpty || !slow.isEmpty {
            advance(1)
            pump()
        }
    }
}

// MARK: - Runner

extension ChannelLink {
    func watchAction() -> WorkoutAction? {
        guard let state = watch.state, !state.exercises.isEmpty else { return nil }
        let k = random.int(state.exercises.count)
        let entry = state.exercises[k]
        guard !entry.sets.isEmpty else { return nil }
        let setID = entry.sets[random.int(entry.sets.count)].id
        if config.idempotentWatch {
            switch random.int(5) {
            case 0, 1: return .logSet(exerciseID: entry.id, setID: setID)
            case 2: return .setWeight(exerciseID: entry.id, setID: setID, kg: Double(random.int(in: 20...240)) / 2)
            case 3: return .skipRest
            default: return .setReps(exerciseID: entry.id, setID: setID, reps: random.int(in: 1...15))
            }
        }
        switch random.int(12) {
        case 0, 1: return .logSet(exerciseID: entry.id, setID: setID)
        case 2: return .nudgeNextSet(weightSteps: random.int(in: -2...2), repsSteps: random.int(in: -1...1))
        case 3, 4: return .setWeight(exerciseID: entry.id, setID: setID, kg: Double(random.int(in: 20...240)) / 2)
        case 5: return .adjustRest(seconds: random.int(in: -1...1) * 15)
        case 6: return .skipRest
        case 7: return timedStart(in: state)
        case 8: return .stopTimedSet
        case 9: return .cancelTimedSet
        default: return .setReps(exerciseID: entry.id, setID: setID, reps: random.int(in: 1...15))
        }
    }

    /// Starts the first pending set of the workout's timed exercise (nil when it has none).
    func timedStart(in state: WorkoutState) -> WorkoutAction? {
        guard let entry = state.exercises.first(where: { $0.exercise.tracking == .duration }),
              let set = entry.sets.first(where: { !$0.isDone }) else { return nil }
        return .startTimedSet(SetRef(exerciseID: entry.id, setID: set.id))
    }

    func phoneAction(origin: inout ActionOrigin) -> WorkoutAction? {
        guard let state = phone.state, !state.exercises.isEmpty else { return nil }
        let k = random.int(state.exercises.count)
        let entry = state.exercises[k]
        let setID = entry.sets.isEmpty ? SvcSyncFix.uuid(0) : entry.sets[random.int(entry.sets.count)].id
        if config.liveActivity && random.int(2) == 0 {
            origin = .liveActivity                          // the four Live Activity intents
            switch random.int(4) {
            case 0: return .logSet(exerciseID: entry.id, setID: setID)
            case 1: return .nudgeNextSet(weightSteps: random.int(in: -1...1), repsSteps: random.int(in: -1...1))
            case 2: return .adjustRest(seconds: random.int(in: -1...1) * 15)
            default: return .skipRest
            }
        }
        origin = .phone
        switch random.int(12) {
        case 0: return .toggleSet(exerciseID: entry.id, setID: setID)
        case 1: return .setWeight(exerciseID: entry.id, setID: setID, kg: Double(random.int(in: 20...240)) / 2)
        case 2: return .addSet(exerciseID: entry.id)
        case 3: return .deleteSet(exerciseID: entry.id, setID: setID)
        case 4: return .rename("W\(random.int(40))")
        case 5: return .pause
        case 6: return .resume
        case 7: return .logNextSet
        case 8: return .updateHeartRate(random.int(in: 60...190))
        case 9: return timedStart(in: state)
        case 10: return .stopTimedSet
        default: return .undo
        }
    }

    func step() {
        advance(Double(random.int(in: 1...8)) / 4)
        switch random.int(24) {
        case 0...4:
            if let action = watchAction() { watch.send(action, origin: .watch) }
        case 5...8:
            if phone.state == nil {
                startWorkout()
            } else if random.int(config.endEvery) == 0 {
                if random.int(2) == 0 { phone.finish(updateTemplate: false) } else { phone.discard() }
            } else {
                var origin = ActionOrigin.phone
                if let action = phoneAction(origin: &origin) { phone.send(action, origin: origin) }
            }
        case 9:
            reachable.toggle()
        case 10:
            if config.watchRestart && random.int(4) == 0 { restartWatch() }
        case 11:
            if config.relaunch && random.int(3) == 0 { relaunchPhone() }
        case 12:
            advance(Double(random.int(in: 5...30)))
        case 13:
            // an outage: nothing arrives for a while, workouts may end and start meanwhile
            context = nil; messages.removeAll()
            if phone.state == nil { startWorkout() } else { phone.discard(); advance(0.5); startWorkout() }
        default:
            break
        }
        pump()
    }
}

final class SyncChannelFuzzTests: XCTestCase {
    struct Stats { var issued = 0, applied = 0, dupAfterRelaunch = 0, workouts = 0, jumps = 0, timer = 0 }
    private var stats = Stats()

    @MainActor
    private func run(seed: UInt64, config: ChannelConfig, liveness: Bool = false) -> [String] {
        let link = ChannelLink(seed: seed, config: config)
        link.startWorkout()
        link.pump()
        for _ in 0..<config.steps { link.step() }
        link.drain()
        // Everything the phone ever sent has arrived. Wait until even a command that the system queue lost is not shown any more.
        link.advance(SyncReconciler.queuedPendingLifetime + 1)
        if !liveness {
            // The phone says its state once more; with `liveness` it does not: the Watch has to get there on its own.
            link.pushEnvelope()
            link.drain()
        }
        stats.issued += link.issued.count
        stats.timer += link.issued.filter { command in
            switch command.action {
            case .startTimedSet, .stopTimedSet, .cancelTimedSet: return true
            default: return false
            }
        }.count
        stats.applied += link.appliedCount.values.reduce(0, +)
        stats.dupAfterRelaunch += link.appliedAfterRelaunch
        stats.workouts += link.generations
        stats.jumps += link.jumps
        var problems = link.failures
        let w = SyncProto.withoutHeartRate(link.watch.state)
        let p = SyncProto.withoutHeartRate(link.phone.state)
        if w != p {
            problems.append("no convergence: \(SyncProto.difference(link.watch.state, link.phone.state)); pending=\(link.watch.pendingCommands.count)")
        }
        if !link.watch.pendingCommands.isEmpty { problems.append("pending left: \(link.watch.pendingCommands.count)") }
        return problems
    }

    private func sweep(_ name: String, _ seeds: ClosedRange<Int>, _ config: ChannelConfig, liveness: Bool = false) {
        svcMain {
            var bad: [String] = []
            var failingSeeds = 0
            var kinds: [String: Int] = [:]
            stats = Stats()
            for seed in seeds {
                let problems = run(seed: UInt64(seed), config: config, liveness: liveness)
                for problem in problems {
                    let key = String(problem.drop(while: { $0 != ":" }).dropFirst(2).prefix(48))
                    kinds[key, default: 0] += 1
                }
                if !problems.isEmpty { failingSeeds += 1 }
                if !problems.isEmpty && bad.count < 4 { bad.append("seed \(seed): \(problems.prefix(3))") }
            }
            XCTAssertTrue(kinds.isEmpty, "\(name): \(failingSeeds) of \(seeds.count) seeds failed: \(kinds) first: \(bad)")
            XCTAssertGreaterThan(stats.issued, 0, "\(name): the Watch did issue commands")
            if !config.idempotentWatch { XCTAssertGreaterThan(stats.timer, 0, "\(name): the Watch did issue timer commands") }
            if config.relaunch {
                XCTAssertEqual(stats.dupAfterRelaunch, 0, "\(name): a command was applied again after a phone relaunch")
            }
        }
    }

    func testBaselineChannelModel() {
        sweep("baseline", 1...40, ChannelConfig())
    }

    func testClockSkew() {
        sweep("skew+90", 1...20, ChannelConfig(skew: 90))
        sweep("skew-90", 1...20, ChannelConfig(skew: -90))
    }

    /// R4: the phone is relaunched now and then; no command may run again afterwards.
    func testPhoneRelaunchesNeverApplyACommandTwice() {
        var config = ChannelConfig(); config.relaunch = true
        sweep("relaunch", 1...60, config)
        config.idempotentWatch = true
        sweep("idempotent+relaunch", 1...30, config)
    }

    /// R1: workouts end every other step and messages are up to 15 s late. The Watch must never go back to an older workout.
    func testWorkoutChurnNeverRevivesAnOlderWorkout() {
        var config = ChannelConfig(); config.endEvery = 2; config.steps = 120; config.messageDelayQuarters = 60
        sweep("churn", 1...60, config)
    }

    func testLostCommands() {
        var config = ChannelConfig(); config.commandLossPercent = 8; config.steps = 80
        sweep("lost commands", 1...40, config)
    }

    /// R2: 8% of the commands are lost and the phone never sends a last envelope: the Watch must still end up like the phone.
    func testLostCommandsWithoutAFinalPush() {
        var config = ChannelConfig(); config.commandLossPercent = 8; config.steps = 80
        sweep("lost commands, no final push", 1...120, config, liveness: true)
    }

    func testLivenessWithoutExtraPush() {
        sweep("liveness", 1...30, ChannelConfig(), liveness: true)
    }
}
