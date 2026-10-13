// WatchSnapshotFixtures.swift
//
// The workouts the Apple Watch snapshot tests draw. Every state is produced by the REAL reducer (`WorkoutReducer.reduce`) from
// the demo template "Upper A · Push" / "Upper B · Pull" (`SampleData`), played forward with a script of waits and actions at
// fixed instants, so what a screen shows is exactly what the app would show for that sequence of taps.
//
// This file is deliberately free of SwiftUI, XCTest and watchOS: it only needs Foundation and PulseStrengthCore, so it can
// be type-checked and run on Linux (see the report of the change that added it).
//
// Times are offsets from the start of the workout. A screen is drawn at `WatchFixture.date`; the pages take that date as an
// argument, so the stills are fully deterministic. The whole-screen tests (`WatchRootView`) read the real clock instead, so
// they use `WatchFixtures.anchored(_:)` to put the workout start just far enough in the past.

import Foundation
import PulseStrengthCore

/// A workout state and the instant a screen is drawn at.
struct WatchFixture {
    var state: WorkoutState
    var date: Date

    /// What the Watch derives from the state (the same builder the controller uses for `snapshot(now:)`).
    var snapshot: WorkoutSnapshot {
        SnapshotBuilder.make(from: state, now: date)
    }

    /// Seconds from the start of the workout to `date`.
    var offset: TimeInterval {
        date.timeIntervalSince(state.startedAt)
    }
}

/// Plays a workout forward: `wait(until:)` moves the clock, `apply(_:)` runs a reducer action at the current instant.
struct WatchScript {
    private(set) var state: WorkoutState
    private(set) var now: Date
    private let start: Date

    init(state: WorkoutState, start: Date) {
        self.state = state
        self.start = start
        self.now = start
    }

    /// Moves the clock to `offset` seconds after the start of the workout (never backwards).
    mutating func wait(until offset: TimeInterval) {
        let target = start.addingTimeInterval(offset)
        if target > now { now = target }
    }

    mutating func apply(_ action: WorkoutAction) {
        WorkoutReducer.reduce(&state, action, now: now)
    }

    /// Logs the next pending set at `offset`; `keepRest` false skips the rest timer a second later (the lifter did not wait).
    mutating func logNextSet(at offset: TimeInterval, keepRest: Bool = false) {
        wait(until: offset)
        apply(.logNextSet)
        if !keepRest {
            wait(until: offset + 1)
            apply(.skipRest)
        }
    }

    var fixture: WatchFixture {
        WatchFixture(state: state, date: now)
    }
}

enum WatchFixtures {
    /// The instant the demo workouts start at (any fixed date will do).
    static let referenceStart = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static let workoutID: UUID = UUID(uuidString: "5A1D0000-0000-4000-8000-0000000000A1") ?? UUID()

    // MARK: Templates

    /// "Upper A · Push": bench (2 warm-ups + 3 working sets, rest 2:30), incline, overhead press, a superset, crossover; 20 sets.
    static func upperPush() -> WorkoutTemplate {
        SampleData.templates()[0]
    }

    /// "Upper B · Pull": pull-up (bodyweight reps), rows, pulldown, ...; 19 sets.
    static func upperPull() -> WorkoutTemplate {
        SampleData.templates()[2]
    }

    private static func script(_ template: WorkoutTemplate, start: Date) -> WatchScript {
        WatchScript(state: WorkoutFactory.makeWorkout(from: template, now: start, id: workoutID), start: start)
    }

    // MARK: Log set page

    /// Bench press, set 3 of 5 (82.5 kg x 6) after two warm-ups; 6:42 into the workout; no rest running.
    static func loggingWeightReps(start: Date) -> WatchFixture {
        var s = script(upperPush(), start: start)
        s.logNextSet(at: 95)     // warm-up 50 x 8
        s.logNextSet(at: 235)    // warm-up 70 x 5
        s.wait(until: 402)
        return s.fixture
    }

    /// The very first set of the workout, a warm-up ("Warm-up · Set 1 of 5"), 0:48 in.
    static func loggingWarmup(start: Date) -> WatchFixture {
        var s = script(upperPush(), start: start)
        s.wait(until: 48)
        return s.fixture
    }

    /// Pull-up: bodyweight, reps only (no weight row), set 1 of 3, 2:11 in.
    static func loggingRepsOnly(start: Date) -> WatchFixture {
        var s = script(upperPull(), start: start)
        s.wait(until: 131)
        return s.fixture
    }

    /// Plank: a timed exercise ("sec"), set 1, 1:26 in. An empty workout named "Core finisher" that gets the plank added.
    static func loggingDuration(start: Date) -> WatchFixture {
        var state = WorkoutFactory.makeEmpty(name: "Core finisher", now: start, id: workoutID)
        if let plank = ExerciseLibrary.exercise(id: "plank") {
            WorkoutReducer.reduce(&state, .addExercises([plank]), now: start)
        }
        var s = WatchScript(state: state, start: start)
        s.wait(until: 86)
        return s.fixture
    }

    /// Every set of "Upper B · Pull" logged (19 of 19): the page says "All sets logged".
    static func allLogged(start: Date) -> WatchFixture {
        var s = script(upperPull(), start: start)
        var offset: TimeInterval = 0
        var guardCount = 0
        while WorkoutTargets.nextPending(in: s.state) != nil && guardCount < 200 {
            offset += 105
            s.logNextSet(at: offset, keepRest: true)
            guardCount += 1
        }
        s.wait(until: offset + 40)
        return s.fixture
    }

    // MARK: Rest page

    /// Rest after bench set 3 of 5: 1:12 of 2:30 left, next is the same exercise ("82.5 kg x 6").
    static func restRunning(start: Date) -> WatchFixture {
        var s = script(upperPush(), start: start)
        s.logNextSet(at: 95)
        s.logNextSet(at: 235)
        s.logNextSet(at: 350, keepRest: true)    // rest 150 s, ends at 500
        s.wait(until: 428)
        return s.fixture
    }

    /// Rest after the last bench set: the next set belongs to the next exercise, so its name is shown under "Next".
    static func restNextExercise(start: Date) -> WatchFixture {
        var s = script(upperPush(), start: start)
        s.logNextSet(at: 95)
        s.logNextSet(at: 235)
        s.logNextSet(at: 350)
        s.logNextSet(at: 470)
        s.logNextSet(at: 600, keepRest: true)    // rest 150 s, ends at 750
        s.wait(until: 678)
        return s.fixture
    }

    /// The same rest, paused with 1:30 left: the countdown is frozen, the title reads "Paused".
    static func restPaused(start: Date) -> WatchFixture {
        var s = script(upperPush(), start: start)
        s.logNextSet(at: 95)
        s.logNextSet(at: 235)
        s.logNextSet(at: 350, keepRest: true)
        s.wait(until: 410)
        s.apply(.pause)
        s.wait(until: 440)
        return s.fixture
    }

    /// The rest ran out 10 s ago and was not dismissed: "Go", the ring full.
    static func restOver(start: Date) -> WatchFixture {
        var s = script(upperPush(), start: start)
        s.logNextSet(at: 95)
        s.logNextSet(at: 235)
        s.logNextSet(at: 350, keepRest: true)
        s.wait(until: 510)
        return s.fixture
    }

    // MARK: Metrics page and summary

    /// Upper A, 24:18 in: the whole bench block and the first incline set are logged (6 of 20 sets, 1,780 kg), no rest running.
    /// With `heartRate` three samples (126, 134, 142 bpm) have arrived from the Watch sensor; without, none has.
    static func midWorkout(start: Date, heartRate: Bool) -> WatchFixture {
        var s = script(upperPush(), start: start)
        s.logNextSet(at: 95)
        s.logNextSet(at: 235)
        s.logNextSet(at: 350)
        s.logNextSet(at: 470)
        s.logNextSet(at: 600)
        s.logNextSet(at: 780)    // incline set 1
        if heartRate {
            s.wait(until: 1380)
            s.apply(.updateHeartRate(126))
            s.wait(until: 1410)
            s.apply(.updateHeartRate(134))
            s.wait(until: 1440)
            s.apply(.updateHeartRate(142))
        }
        s.wait(until: 1458)
        return s.fixture
    }

    // MARK: Whole-screen tests (real clock)

    /// Rebuilds a fixture so that "now" (the real clock) is half a second after its drawing instant. Screens that read the
    /// system clock (`WatchRootView` runs a `TimelineView`) then show the same texts as the fixed-date stills, as long as the
    /// render takes less than half a second.
    static func anchored(_ make: (Date) -> WatchFixture) -> WatchFixture {
        let offset = make(referenceStart).offset
        return make(Date().addingTimeInterval(-(offset + 0.5)))
    }
}
