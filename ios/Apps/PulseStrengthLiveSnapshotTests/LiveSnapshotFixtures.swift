// LiveSnapshotFixtures.swift
//
// Test data for the Live Activity snapshot tests (LiveActivitySnapshotTests.swift): twenty-one scenarios, each a real
// `WorkoutSnapshot` produced by the app's own code path (WorkoutFactory -> WorkoutReducer -> SnapshotBuilder) from the
// demo template "Upper A · Push" / "Upper B · Pull" (and an empty workout), at a FIXED reference date, so the images
// are reproducible.
//
// The first twelve are the phases of the original Live Activity. The other nine are the live moments of widgets/SPEC.md
// (LA-01...LA-05, LA-08, LA-10): the state is real, and the moment (record, superset brief, plates, coach tip, finish brief,
// set progress) is laid over the builder's snapshot by the fixture, with the values of LiveActivityNext.dc.html, so the images
// do not depend on how far `SnapshotBuilder` has come.
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
            emptyWorkout(reference),
            pausedLogging(reference),
            pausedResting(reference),
            longNamesLogging(reference),
            longNamesResting(reference),
            longSessionLogging(reference),
            recordResting(reference),
            recordLogging(reference),
            supersetLogging(reference),
            supersetResting(reference),
            platesLogging(reference),
            coachTipResting(reference),
            finishCard(reference),
            dotsHeartRate(reference),
            dotsManySets(reference),
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

    /// "Start Empty Workout" before the first exercise is added: no set at all. The builder calls it `.complete` (nothing
    /// is pending), but nothing was logged, so the views show "No exercises yet" and not "All sets logged".
    private static func emptyWorkout(_ reference: Date) -> LiveScenario {
        var state = WorkoutFactory.makeEmpty(name: "Workout", now: reference.addingTimeInterval(-95), id: id(4))
        apply(.updateHeartRate(96), to: &state, secondsAgo: 0, reference: reference)
        return scenario(
            slug: "empty-workout",
            title: "Empty workout \u{00B7} no exercises yet \u{00B7} 96 bpm",
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

    // MARK: - Live moments

    /// LA-01: a record was logged two seconds ago; the gold banner is up and the 2:30 rest has just started. Compact priority: the
    /// record wins over the rest countdown.
    private static func recordResting(_ reference: Date) -> LiveScenario {
        let state = benchResting(reference: reference, secondsSinceLastLog: 2, heartRate: 134)
        return scenario(
            slug: "record-resting",
            title: "Record \u{00B7} banner over the rest (2:28 left) \u{00B7} 134 bpm",
            state: state, reference: reference, expected: .resting
        ) { snapshot in
            snapshot.moment = record(for: snapshot, reference: reference)
        }
    }

    /// LA-01 with the rest timer off for the lift: the banner over the next set.
    private static func recordLogging(_ reference: Date) -> LiveScenario {
        var state = benchLogging(reference: reference, elapsed: 2280, heartRate: 134)
        if let exerciseID = state.exercises.first?.id {
            apply(.setRest(exerciseID: exerciseID, seconds: 0), to: &state, secondsAgo: 5, reference: reference)
        }
        apply(.logNextSet, to: &state, secondsAgo: 2, reference: reference)
        return scenario(
            slug: "record-logging",
            title: "Record \u{00B7} banner over the next set (no rest timer)",
            state: state, reference: reference, expected: .logging
        ) { snapshot in
            snapshot.moment = record(for: snapshot, reference: reference)
        }
    }

    /// LA-02: round 2 of 3 of the lateral raise (A1, logged) and triceps pushdown (A2, next) superset.
    private static func supersetLogging(_ reference: Date) -> LiveScenario {
        let state = supersetState(reference: reference, lastStep: 14, secondsSinceLastLog: 40)
        return scenario(
            slug: "superset-logging",
            title: "Superset A \u{00B7} round 2/3 \u{00B7} A1 done, A2 next \u{00B7} Log A2",
            state: state, reference: reference, expected: .logging
        ) { snapshot in
            snapshot.superset = supersetBrief(of: state)
        }
    }

    /// The last member of round 2 is logged: the 60 s rest runs and the next target is A1 of round 3. Compact priority: the rest
    /// countdown wins over the superset.
    private static func supersetResting(_ reference: Date) -> LiveScenario {
        let state = supersetState(reference: reference, lastStep: 15, secondsSinceLastLog: 20)
        return scenario(
            slug: "superset-resting",
            title: "Superset A \u{00B7} resting between round 2 and 3 (0:40 left)",
            state: state, reference: reference, expected: .resting
        ) { snapshot in
            snapshot.superset = supersetBrief(of: state)
        }
    }

    /// LA-03: set 3 of the bench press, 82.5 kg on a 20 kg bar: 25 + 5 + 1.25 per side.
    private static func platesLogging(_ reference: Date) -> LiveScenario {
        let state = benchLogging(reference: reference, elapsed: 1458, heartRate: 128)
        return scenario(
            slug: "plates-logging",
            title: "Plates \u{00B7} 82.5 kg on a 20 kg bar \u{00B7} 25 + 5 + 1.25 per side",
            state: state, reference: reference, expected: .logging
        ) { snapshot in
            snapshot.plates = plateBrief(totalKg: 82.5, barKg: 20)
        }
    }

    /// LA-04: set 3 felt easy (3 reps in reserve); the tip suggests 85 kg for set 4.
    private static func coachTipResting(_ reference: Date) -> LiveScenario {
        let state = benchResting(reference: reference, secondsSinceLastLog: 50, heartRate: 119)
        return scenario(
            slug: "coach-tip-resting",
            title: "Coach tip \u{00B7} 85 kg or keep 82.5 \u{00B7} resting (1:40 left)",
            state: state, reference: reference, expected: .resting
        ) { snapshot in
            guard let exerciseID = snapshot.targetExerciseID, let setID = snapshot.targetSetID else { return }
            snapshot.coachTip = CoachTipBrief(
                title: "Felt easy?",
                subtitle: "3 reps in reserve on set 3",
                text: "Add 2.5 kg for set 4 to stay at 1\u{2013}2 RIR.",
                suggestedWeightKg: 85,
                suggestedWeightText: "85 kg",
                keepWeightText: "Keep 82.5",
                targetSetID: setID,
                targetExerciseID: exerciseID
            )
        }
    }

    /// LA-05: all 20 sets of "Upper A · Push" logged and the workout finished; the Watch recorded it, one record.
    private static func finishCard(_ reference: Date) -> LiveScenario {
        let elapsed: TimeInterval = 3120
        var state = WorkoutFactory.makeWorkout(
            from: SampleData.templates()[0], now: reference.addingTimeInterval(-elapsed), id: id(1)
        )
        var step = 0
        while WorkoutTargets.nextPending(in: state) != nil && step < 100 {
            step += 1
            apply(.logNextSet, to: &state, secondsAgo: elapsed - Double(step) * 150, reference: reference)
        }
        let completed = SummaryBuilder.build(from: state, finishedAt: reference)
        return scenario(
            slug: "finish",
            title: "Finish card \u{00B7} four tiles \u{00B7} saved to Health \u{00B7} one record",
            state: state, reference: reference, expected: .complete
        ) { snapshot in
            var brief = SnapshotBuilder.finishBrief(from: completed, savedToHealth: true)
            brief.personalRecordCount = max(brief.personalRecordCount, 1)
            snapshot.finish = brief
        }
    }

    /// LA-08 and LA-10: set 3 of 5 with two sets done, and the Watch reports 142 bpm (compact trailing shows the heart rate).
    private static func dotsHeartRate(_ reference: Date) -> LiveScenario {
        let state = benchLogging(reference: reference, elapsed: 1458, heartRate: 142)
        return scenario(
            slug: "dots-heart-rate",
            title: "Set dots 2 of 5 done \u{00B7} 142 bpm in the compact island",
            state: state, reference: reference, expected: .logging
        ) { snapshot in
            snapshot.exerciseDoneSets = 2
            snapshot.exerciseSetCount = 5
        }
    }

    /// LA-08 with more sets than the compact slot has room for dots, and no heart rate (compact trailing shows the elapsed clock).
    private static func dotsManySets(_ reference: Date) -> LiveScenario {
        let state = benchLogging(reference: reference, elapsed: 1458, heartRate: nil)
        return scenario(
            slug: "dots-many-sets",
            title: "Set dots 4 of 10 done (text fallback) \u{00B7} no heart rate",
            state: state, reference: reference, expected: .logging
        ) { snapshot in
            snapshot.exerciseDoneSets = 4
            snapshot.exerciseSetCount = 10
        }
    }

    // MARK: - Moment builders

    /// The record of LiveActivityNext.dc.html (85 x 5, estimated 1RM 99, up 4) for the exercise the snapshot shows, banner up for 4 s.
    private static func record(for snapshot: WorkoutSnapshot, reference: Date) -> PRMoment {
        PRMoment(
            exerciseName: snapshot.exerciseName,
            weightText: "85",
            repsText: "5",
            estimated1RM: 99,
            deltaKg: 4,
            expiresAt: reference.addingTimeInterval(2)
        )
    }

    /// The plates for `totalKg` as `SnapshotBuilder` is meant to describe them (widgets/SPEC.md section 2, "Live moments").
    private static func plateBrief(totalKg: Double, barKg: Double) -> PlateBrief? {
        guard let plan = PlateCalculator.plan(totalKg: totalKg, barKg: barKg) else { return nil }
        return PlateBrief(
            totalKg: totalKg,
            barKg: barKg,
            perSide: plan.perSide,
            leftoverKg: plan.leftoverKg,
            summary: plan.perSide.map { NumberText.kg($0) }.joined(separator: " + ")
        )
    }

    /// "Upper A · Push" up to the superset, one set per minute, the last one `secondsSinceLastLog` seconds before `reference`.
    /// Sets 1...11 are the bench press, incline press and overhead press; 12, 14 are the lateral raise (A1), 13, 15 the triceps
    /// pushdown (A2). Logging A1 starts no rest and moves on to A2; logging A2 starts the 60 s rest and returns to A1.
    /// `lastStep` 14 ends with A2 of round 2 next (logging), 15 with A1 of round 3 next (resting).
    private static func supersetState(reference: Date, lastStep: Int, secondsSinceLastLog: TimeInterval) -> WorkoutState {
        let elapsed: TimeInterval = 1500
        var state = WorkoutFactory.makeWorkout(
            from: SampleData.templates()[0], now: reference.addingTimeInterval(-elapsed), id: id(1)
        )
        for step in 1...lastStep {
            let secondsAgo = secondsSinceLastLog + Double(lastStep - step) * 60
            apply(.logNextSet, to: &state, secondsAgo: secondsAgo, reference: reference)
            if step == 13 {
                apply(.skipRest, to: &state, secondsAgo: secondsAgo - 5, reference: reference)
            }
        }
        return state
    }

    /// The `SupersetBrief` for the exercise `state` shows next, as LiveActivityNext.dc.html draws it: the round is the number of
    /// sets the shown member has done plus one ("round 2/3" while A2 is next after A1 of round 2), and a member is done when its set
    /// of that round is logged.
    private static func supersetBrief(of state: WorkoutState) -> SupersetBrief? {
        let shown = WorkoutTargets.nextPending(in: state)?.exerciseIndex ?? state.clampedIndex
        guard state.exercises.indices.contains(shown), let group = state.exercises[shown].supersetGroup else { return nil }
        let members = state.exercises.enumerated().filter { $0.element.supersetGroup == group }
        let rounds = state.exercises[shown].sets.count
        let round = min(state.exercises[shown].doneCount + 1, max(rounds, 1))
        var briefs: [SupersetMember] = []
        for (position, member) in members.enumerated() {
            let sets = member.element.sets
            let pending = sets.first(where: { !$0.isDone }) ?? sets.last
            let detail = pending.map { NumberText.kg($0.weightKg) + " \u{00D7} " + String($0.reps) } ?? ""
            briefs.append(SupersetMember(
                tag: group + String(position + 1),
                name: member.element.exercise.name,
                detail: detail,
                isDone: member.element.doneCount >= round,
                isCurrent: member.offset == shown
            ))
        }
        return SupersetBrief(label: group, round: round, rounds: rounds, members: briefs)
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
    /// `decorate` lays a live moment (record, superset, plates, coach tip, finish, set progress) over the builder's snapshot.
    private static func scenario(
        slug: String,
        title: String,
        state: WorkoutState,
        reference: Date,
        snapshotAt: Date? = nil,
        drawnAt: Date? = nil,
        isStale: Bool = false,
        expected: SnapshotPhase,
        decorate: (inout WorkoutSnapshot) -> Void = { _ in }
    ) -> LiveScenario {
        var snapshot = SnapshotBuilder.make(from: state, now: snapshotAt ?? reference)
        decorate(&snapshot)
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
