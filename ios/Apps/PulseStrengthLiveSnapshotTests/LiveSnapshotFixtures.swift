// LiveSnapshotFixtures.swift
//
// Test data for the Live Activity snapshot tests (LiveActivitySnapshotTests.swift): eleven scenarios, each a real
// `WorkoutSnapshot` produced by the app's own code path (WorkoutFactory -> WorkoutReducer -> SnapshotBuilder) from the
// demo template "Upper A · Push" / "Upper B · Pull", at a FIXED reference date, so the images are reproducible.
//
// Timeline convention: `reference` is "now" (the instant the views are drawn at); every action is applied N seconds
// before it. The workout start is `reference - elapsed`.

#if os(iOS)
import Foundation
import PulseStrengthActivity
import PulseStrengthCore

/// One Live Activity state to draw on every surface.
struct LiveScenario: Identifiable {
    /// kebab-case name used in the file names ("logging-weight").
    let slug: String
    /// Short human description for the caption under the image.
    var title: String
    let snapshot: WorkoutSnapshot
    /// The name the widget passes to the views (`WorkoutLiveActivity.workoutName(state:attributes:)`).
    let workoutName: String
    /// `ActivityViewContext.isStale`.
    let isStale: Bool
    /// The instant the views are drawn at (`\.activityStaticNow`).
    let now: Date
    /// What the views must show for this state; checked by `testFixturesMatchIntendedPhases`.
    let expectedDisplayPhase: SnapshotPhase
    /// True: draw the production system timer views (live `Text(timerInterval:)` etc.) instead of the static variant.
    var usesSystemTimers = false

    var id: String { slug }

    /// Value of `\.activityStaticNow`: nil selects the production timer views.
    var staticClock: Date? { usesSystemTimers ? nil : now }

    func withSystemTimers() -> LiveScenario {
        var copy = self
        copy.usesSystemTimers = true
        copy.title += " [production system timer views]"
        return copy
    }
}

@MainActor
enum LiveFixtures {
    /// 2026-02-02 02:40:00 UTC. Any fixed date works; this one only has to stay the same between runs.
    static let referenceDate = Date(timeIntervalSince1970: 1_770_000_000)

    private static let longWorkoutName = "Upper A \u{00B7} Push \u{2014} heavy week 6 of the long program"
    private static let longExerciseName = "Single-arm dumbbell Romanian deadlift, 3-1-1 tempo"

    /// Every scenario at the fixed reference date.
    static func all() -> [LiveScenario] {
        all(reference: referenceDate)
    }

    /// Every scenario relative to `reference` (the system-timer test passes the real current time).
    static func all(reference: Date) -> [LiveScenario] {
        [
            loggingWeight(reference),
            loggingBodyweight(reference),
            loggingDuration(reference),
            resting(reference),
            restOverStale(reference),
            complete(reference),
            pausedLogging(reference),
            pausedResting(reference),
            longNamesLogging(reference),
            longNamesResting(reference),
            longSessionLogging(reference),
        ]
    }

    // MARK: - Scenarios

    /// Barbell bench press, set 3 of 5 (two warm-ups done), weight and reps steppers, heart rate, 24:18 elapsed.
    private static func loggingWeight(_ reference: Date) -> LiveScenario {
        let state = benchLogging(reference: reference, elapsed: 1458, heartRate: 128)
        return scenario(
            slug: "logging-weight",
            title: "Logging \u{00B7} Set 3 of 5 \u{00B7} 82.5 kg \u{00D7} 6 \u{00B7} 128 bpm",
            state: state, reference: reference, expected: .logging
        )
    }

    /// Pull-up: reps only, no weight stepper, no heart rate.
    private static func loggingBodyweight(_ reference: Date) -> LiveScenario {
        var state = WorkoutFactory.makeWorkout(
            from: SampleData.templates()[2], now: reference.addingTimeInterval(-500), id: id(2)
        )
        apply(.logNextSet, to: &state, secondsAgo: 200, reference: reference)
        apply(.skipRest, to: &state, secondsAgo: 60, reference: reference)
        return scenario(
            slug: "logging-bodyweight",
            title: "Logging \u{00B7} bodyweight, reps only \u{00B7} no heart rate",
            state: state, reference: reference, expected: .logging
        )
    }

    /// Plank: a duration exercise (seconds), no weight stepper.
    private static func loggingDuration(_ reference: Date) -> LiveScenario {
        let plank = ExerciseLibrary.exercise(id: "plank")
            ?? Exercise.custom(name: "Plank", muscle: .core, equipment: .bodyweight, tracking: .duration)
        var state = WorkoutFactory.makeEmpty(name: "Core finisher", now: reference.addingTimeInterval(-360), id: id(3))
        apply(.addExercises([plank]), to: &state, secondsAgo: 355, reference: reference)
        apply(.logNextSet, to: &state, secondsAgo: 120, reference: reference)
        apply(.skipRest, to: &state, secondsAgo: 30, reference: reference)
        apply(.updateHeartRate(131), to: &state, secondsAgo: 0, reference: reference)
        return scenario(
            slug: "logging-duration",
            title: "Logging \u{00B7} duration (plank, seconds) \u{00B7} 131 bpm",
            state: state, reference: reference, expected: .logging
        )
    }

    /// Resting: 1:12 left of 2:30 after logging set 3.
    private static func resting(_ reference: Date) -> LiveScenario {
        let state = benchResting(reference: reference, secondsSinceLastLog: 78, heartRate: 119)
        return scenario(
            slug: "resting",
            title: "Resting \u{00B7} 1:12 left of 2:30 \u{00B7} 119 bpm",
            state: state, reference: reference, expected: .resting
        )
    }

    /// The production route to "rest over": the app's last snapshot still says `.resting`, the rest ended 4 s ago, the
    /// system marks the activity stale (`staleDate = restEndsAt`) and the views show "Go" + Log set.
    private static func restOverStale(_ reference: Date) -> LiveScenario {
        let state = benchResting(reference: reference, secondsSinceLastLog: 154, heartRate: 122)
        let builtAt = reference.addingTimeInterval(-154)
        return scenario(
            slug: "rest-over-stale",
            title: "Rest over \u{00B7} stale activity (resting snapshot, isStale)",
            state: state, reference: reference, snapshotAt: builtAt, isStale: true, expected: .restOver
        )
    }

    /// All 20 sets of "Upper A · Push" logged.
    private static func complete(_ reference: Date) -> LiveScenario {
        let elapsed: TimeInterval = 3120
        var state = WorkoutFactory.makeWorkout(
            from: SampleData.templates()[0], now: reference.addingTimeInterval(-elapsed), id: id(1)
        )
        var step = 0
        while WorkoutTargets.nextPending(in: state) != nil && step < 100 {
            step += 1
            apply(.logNextSet, to: &state, secondsAgo: elapsed - Double(step) * 150, reference: reference)
        }
        apply(.updateHeartRate(118), to: &state, secondsAgo: 0, reference: reference)
        return scenario(
            slug: "complete",
            title: "Complete \u{00B7} all sets logged \u{00B7} 118 bpm",
            state: state, reference: reference, expected: .complete
        )
    }

    /// Logging while paused: frozen 24:18 with a "Paused" label; drawn 15 minutes later to prove nothing ticks.
    private static func pausedLogging(_ reference: Date) -> LiveScenario {
        var state = benchLogging(reference: reference, elapsed: 1458, heartRate: 128)
        apply(.pause, to: &state, secondsAgo: 0, reference: reference)
        return scenario(
            slug: "paused-logging",
            title: "Paused \u{00B7} logging (frozen 24:18, drawn 15 min later)",
            state: state, reference: reference, drawnAt: reference.addingTimeInterval(900), expected: .logging
        )
    }

    /// Resting while paused: frozen 1:12 and a half-full static ring.
    private static func pausedResting(_ reference: Date) -> LiveScenario {
        var state = benchResting(reference: reference, secondsSinceLastLog: 78, heartRate: 119)
        apply(.pause, to: &state, secondsAgo: 0, reference: reference)
        return scenario(
            slug: "paused-resting",
            title: "Paused \u{00B7} resting (frozen 1:12 of 2:30)",
            state: state, reference: reference, drawnAt: reference.addingTimeInterval(900), expected: .resting
        )
    }

    /// First pending set is a warm-up, long exercise name and long workout name, high heart rate, 0:42 elapsed.
    private static func longNamesLogging(_ reference: Date) -> LiveScenario {
        var state = WorkoutFactory.makeWorkout(
            from: SampleData.templates()[0], now: reference.addingTimeInterval(-42), id: id(1)
        )
        state.name = longWorkoutName
        state.exercises[0].exercise.name = longExerciseName
        apply(.updateHeartRate(156), to: &state, secondsAgo: 0, reference: reference)
        return scenario(
            slug: "long-names-logging",
            title: "Long names \u{00B7} warm-up set, long exercise + workout name",
            state: state, reference: reference, expected: .logging
        )
    }

    /// Resting with a long exercise name and a long "Next" line (112.5 kg x 12).
    private static func longNamesResting(_ reference: Date) -> LiveScenario {
        var state = WorkoutFactory.makeWorkout(
            from: SampleData.templates()[0], now: reference.addingTimeInterval(-95), id: id(1)
        )
        state.name = longWorkoutName
        state.exercises[0].exercise.name = longExerciseName
        state.exercises[0].sets[1].weightKg = 112.5
        state.exercises[0].sets[1].reps = 12
        apply(.logNextSet, to: &state, secondsAgo: 20, reference: reference)
        apply(.updateHeartRate(158), to: &state, secondsAgo: 0, reference: reference)
        return scenario(
            slug: "long-names-resting",
            title: "Long names \u{00B7} resting, long Next line (0:40 left)",
            state: state, reference: reference, expected: .resting
        )
    }

    /// 1:12:05 elapsed: the elapsed clock switches to its wider "h:mm:ss" frame.
    private static func longSessionLogging(_ reference: Date) -> LiveScenario {
        let state = benchLogging(reference: reference, elapsed: 4325, heartRate: 141)
        return scenario(
            slug: "long-session-logging",
            title: "Long session \u{00B7} 1:12:05 elapsed (hours clock) \u{00B7} 141 bpm",
            state: state, reference: reference, expected: .logging
        )
    }

    // MARK: - State builders

    /// "Upper A · Push" with both warm-ups of the bench press logged and the rest skipped: set 3 of 5 is next.
    private static func benchLogging(reference: Date, elapsed: TimeInterval, heartRate: Int?) -> WorkoutState {
        var state = WorkoutFactory.makeWorkout(
            from: SampleData.templates()[0], now: reference.addingTimeInterval(-elapsed), id: id(1)
        )
        apply(.logNextSet, to: &state, secondsAgo: 1100, reference: reference)
        apply(.logNextSet, to: &state, secondsAgo: 640, reference: reference)
        apply(.skipRest, to: &state, secondsAgo: 300, reference: reference)
        if let bpm = heartRate {
            apply(.updateHeartRate(bpm), to: &state, secondsAgo: 0, reference: reference)
        }
        return state
    }

    /// Same workout with set 3 logged `secondsSinceLastLog` seconds before `reference`: a 150 s rest is running.
    private static func benchResting(reference: Date, secondsSinceLastLog: TimeInterval, heartRate: Int?) -> WorkoutState {
        var state = WorkoutFactory.makeWorkout(
            from: SampleData.templates()[0], now: reference.addingTimeInterval(-1458), id: id(1)
        )
        apply(.logNextSet, to: &state, secondsAgo: 1100, reference: reference)
        apply(.logNextSet, to: &state, secondsAgo: 650, reference: reference)
        apply(.logNextSet, to: &state, secondsAgo: secondsSinceLastLog, reference: reference)
        if let bpm = heartRate {
            apply(.updateHeartRate(bpm), to: &state, secondsAgo: secondsSinceLastLog + 1, reference: reference)
        }
        return state
    }

    // MARK: - Helpers

    private static func apply(
        _ action: WorkoutAction,
        to state: inout WorkoutState,
        secondsAgo: TimeInterval,
        reference: Date
    ) {
        WorkoutReducer.reduce(&state, action, now: reference.addingTimeInterval(-secondsAgo))
    }

    /// Builds the scenario: the snapshot is made at `snapshotAt` (default `reference`), drawn at `drawnAt` (default `reference`).
    private static func scenario(
        slug: String,
        title: String,
        state: WorkoutState,
        reference: Date,
        snapshotAt: Date? = nil,
        drawnAt: Date? = nil,
        isStale: Bool = false,
        expected: SnapshotPhase
    ) -> LiveScenario {
        let snapshot = SnapshotBuilder.make(from: state, now: snapshotAt ?? reference)
        // Exactly what the widget does: the live name from the snapshot, falling back to the name the activity started with.
        let attributes = WorkoutActivityAttributes(workoutID: snapshot.workoutID, workoutName: state.name)
        return LiveScenario(
            slug: slug,
            title: title,
            snapshot: snapshot,
            workoutName: WorkoutLiveActivity.workoutName(state: snapshot, attributes: attributes),
            isStale: isStale,
            now: drawnAt ?? reference,
            expectedDisplayPhase: expected
        )
    }

    /// Fixed UUIDs keep the snapshots (and so the images) identical between runs.
    private static func id(_ number: Int) -> UUID {
        UUID(uuidString: "00000000-0000-4000-8000-" + String(format: "%012d", number)) ?? UUID()
    }
}
#endif
