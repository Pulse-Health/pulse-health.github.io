// WorkoutControlState.swift
//
// What the controls (Control Center, the Lock Screen's bottom slots) and the Action button need to know about the workout, read from the WidgetSnapshot
// the app wrote: the phase of the running workout and the texts of the control labels. Foundation and PulseStrengthCore only, so the app
// (PrimaryActionIntent) and the widget extension (the controls) share one definition of "resting", "rest over" and "idle".
// TARGET MEMBERSHIP: with the other files of Apps/Shared/Intents - the app and the widget extension.

#if os(iOS)
import Foundation
import PulseStrengthCore

/// What the workout is doing, as far as a control or the Action button can tell from `WidgetSnapshot.active`.
enum WorkoutControlPhase: Equatable, Sendable {
    /// No workout runs. A snapshot that only carries the card of a finished workout (`finish`) counts as none.
    case idle
    /// A set waits to be logged.
    case logging
    /// The rest timer runs, or stands still because the workout is paused.
    case resting
    /// The rest timer ran out and the next set is due.
    case restOver
    /// Every set is logged; only finishing is left, and that always needs the app.
    case complete

    /// The phase at `now`. The app writes the snapshot when the workout changes, not when a rest timer runs out, so a `.resting` snapshot whose
    /// countdown has ended is `.restOver` here (the Live Activity makes the same call with its stale date).
    init(active: WorkoutSnapshot?, now: Date = Date()) {
        guard let active, active.finish == nil else {
            self = .idle
            return
        }
        switch active.phase {
        case .logging:
            self = .logging
        case .complete:
            self = .complete
        case .restOver:
            self = .restOver
        case .resting:
            if active.isPaused {
                self = .resting
            } else if let end = active.restEndsAt, end > now {
                self = .resting
            } else {
                self = .restOver
            }
        }
    }
}

/// What the control labels are drawn from: the phase, the workout that comes next and, while a rest runs, the rest timer.
struct WorkoutControlState: Sendable, Equatable {
    /// How the rest timer is drawn.
    enum Rest: Sendable, Equatable {
        /// There is no rest to show.
        case none
        /// The countdown runs; the system draws the ticking digits (`Text(timerInterval:)`), so the label needs no refresh.
        case running(ClosedRange<Date>)
        /// The workout is paused, so the rest stands still at this many seconds.
        case frozen(seconds: Int)
        /// The countdown ran out.
        case over
    }

    var phase: WorkoutControlPhase
    var isPaused: Bool
    /// The template `nextUp` names and its short label ("Push day"); nil without templates.
    var nextName: String?
    var nextSplit: String?
    /// The name of the running workout; empty when none runs.
    var workoutName: String
    /// "Set 4 of 5" or "Warm-up · Set 1 of 2": the set a Log set button logs; empty when no workout runs.
    var setLabel: String
    var rest: Rest
}

extension WorkoutControlState {
    /// What the gallery and the placeholder show: nothing running, a workout that comes next.
    static let preview = WorkoutControlState(
        phase: .idle,
        isPaused: false,
        nextName: "Upper A · Push",
        nextSplit: "Push day",
        workoutName: "",
        setLabel: "",
        rest: .none
    )

    /// The state of `snapshot` at `now`; the empty state (nothing running, no next workout) when there is no snapshot.
    init(snapshot: WidgetSnapshot?, now: Date = Date()) {
        let active = snapshot?.active
        let phase = WorkoutControlPhase(active: active, now: now)
        let isRunning = phase != .idle
        self.init(
            phase: phase,
            isPaused: isRunning && (active?.isPaused ?? false),
            nextName: snapshot?.nextUp?.name,
            nextSplit: snapshot?.nextUp?.splitLabel,
            workoutName: isRunning ? (active?.workoutName ?? "") : "",
            setLabel: isRunning ? (active?.setLabel ?? "") : "",
            rest: Self.rest(of: active, phase: phase, now: now)
        )
    }

    // MARK: Labels

    /// Start workout: "Start Push day", or "Open workout" while one runs (the engine never starts a second workout).
    var startTitle: String {
        guard phase == .idle else { return "Open workout" }
        guard let split = nextSplit, !split.isEmpty else { return "Start workout" }
        return "Start " + split
    }

    /// Next up: the workout that comes next, or "Open <name>" for the one that runs.
    var nextUpTitle: String {
        guard phase == .idle else { return workoutName.isEmpty ? "Open workout" : "Open " + workoutName }
        guard let name = nextName, !name.isEmpty else { return "Start a workout" }
        return name
    }

    /// Log set: "Log set 4 of 5", "Log warm-up set 1 of 2", "All sets logged" or, with nothing running, "Log set".
    var logTitle: String {
        switch phase {
        case .idle:
            return "Log set"
        case .complete:
            return "All sets logged"
        case .logging, .resting, .restOver:
            return Self.logTitle(setLabel: setLabel)
        }
    }

    /// The status line of the Pause toggle while it is off.
    var pauseStatus: String {
        phase == .idle ? "No workout" : "Running"
    }

    /// "Log set 4 of 5" for the snapshot's "Set 4 of 5" and "Log warm-up set 1 of 2" for "Warm-up · Set 1 of 2" (the two forms `SnapshotBuilder`
    /// writes); anything else gives "Log set".
    static func logTitle(setLabel: String) -> String {
        let warmUpPrefix = "Warm-up · Set "
        if setLabel.hasPrefix(warmUpPrefix) {
            return "Log warm-up set " + String(setLabel.dropFirst(warmUpPrefix.count))
        }
        let setPrefix = "Set "
        if setLabel.hasPrefix(setPrefix) {
            return "Log set " + String(setLabel.dropFirst(setPrefix.count))
        }
        return "Log set"
    }

    // MARK: Private

    /// The rest timer of `active` at `now`. The countdown range starts no later than `now` and its end, so it is a valid range whatever dates the
    /// snapshot holds (a `ClosedRange` with its bounds the wrong way round traps).
    private static func rest(of active: WorkoutSnapshot?, phase: WorkoutControlPhase, now: Date) -> Rest {
        guard let active else { return .none }
        switch phase {
        case .idle, .logging, .complete:
            return .none
        case .restOver:
            return .over
        case .resting:
            if active.isPaused {
                return .frozen(seconds: max(0, active.restFrozenRemaining ?? 0))
            }
            guard let end = active.restEndsAt else { return .over }
            let start = active.restStartedAt ?? end.addingTimeInterval(-Double(max(active.restTotalSeconds, 0)))
            return .running(min(start, now, end)...end)
        }
    }
}
#endif
