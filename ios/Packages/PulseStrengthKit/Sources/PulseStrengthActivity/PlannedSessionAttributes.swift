#if os(iOS)
import ActivityKit
import Foundation
import PulseStrengthCore

/// Attributes of the pre-workout countdown Live Activity (LA-06): a session the user planned for later.
///
/// Like `WorkoutActivityAttributes` this type is shared by the app (`PlannedSessionManager` starts, updates and ends the activity) and
/// the widget extension (`PlannedSessionActivity` renders it), which is why it lives in this package module and not in the app sources:
/// the manager is part of `PulseStrengthIOS`, which the extension does not link. The dynamic part is tiny (four short texts and a date),
/// far below the 4 KB limit; the template name and the first exercise are bounded by `PlannedSessionPlan`.
public struct PlannedSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// "Lower A · Quads"
        public var templateName: String
        /// When the session starts; the countdown runs to this instant. A snooze moves it.
        public var startsAt: Date
        /// "Squat"
        public var firstExerciseName: String
        /// "4 × 5 at 100 kg"
        public var firstSetText: String

        public init(templateName: String, startsAt: Date, firstExerciseName: String, firstSetText: String) {
            self.templateName = templateName
            self.startsAt = startsAt
            self.firstExerciseName = firstExerciseName
            self.firstSetText = firstSetText
        }

        /// "Squat first: 4 × 5 at 100 kg"; nil when the template has no exercise.
        public var firstLine: String? {
            guard !firstExerciseName.isEmpty else { return nil }
            return firstSetText.isEmpty ? firstExerciseName + " first" : firstExerciseName + " first: " + firstSetText
        }
    }

    /// Minutes the "Snooze" button moves the start by.
    public static let snoozeMinutes = 10

    /// The template the "Start now" button starts.
    public var templateID: UUID

    public init(templateID: UUID) {
        self.templateID = templateID
    }
}

/// A planned session: the template and what the countdown shows. Persisted by `PlannedSessionManager` so a relaunch can pick it up again.
public struct PlannedSessionPlan: Codable, Hashable, Sendable {
    public var templateID: UUID
    public var state: PlannedSessionAttributes.ContentState

    public var startsAt: Date { state.startsAt }

    public init(templateID: UUID, state: PlannedSessionAttributes.ContentState) {
        self.templateID = templateID
        self.state = state
    }

    /// A plan for `templateID`; `firstExercise` (usually `template.entries.first`) supplies the "Squat first: 4 × 5 at 100 kg" line.
    public init(templateID: UUID, name: String, firstExercise: TemplateEntry?, startsAt: Date) {
        self.templateID = templateID
        self.state = PlannedSessionAttributes.ContentState(
            templateName: ActivityContentFitting.clamped(name, limit: 40),
            startsAt: startsAt,
            firstExerciseName: firstExercise.map { ActivityContentFitting.clamped($0.exercise.name, limit: 40) } ?? "",
            firstSetText: firstExercise.map { PlannedSessionPlan.setText(for: $0) } ?? ""
        )
    }

    public init(template: WorkoutTemplate, startsAt: Date) {
        self.init(templateID: template.id, name: template.name, firstExercise: template.entries.first, startsAt: startsAt)
    }

    /// The same plan at another start time.
    public func moved(to startsAt: Date) -> PlannedSessionPlan {
        var moved = self
        moved.state.startsAt = startsAt
        return moved
    }

    /// The working sets of `entry` in a few words: "4 × 5 at 100 kg" (sets, reps of the first one, heaviest weight), "3 × 12" for
    /// bodyweight reps, "3 × 45 s" for a duration. All sets count when the entry has only warm-ups.
    public static func setText(for entry: TemplateEntry) -> String {
        let working = entry.plannedSets.filter { $0.type != .warmup }
        let sets = working.isEmpty ? entry.plannedSets : working
        guard let first = sets.first else { return "" }
        let count = String(sets.count)
        let reps = String(first.reps)
        switch entry.exercise.tracking {
        case .weightReps:
            let heaviest = sets.map { $0.weightKg }.max() ?? first.weightKg
            if heaviest > 0 {
                return count + " \u{00D7} " + reps + " at " + NumberText.kg(heaviest) + " kg"
            }
            return count + " \u{00D7} " + reps
        case .repsOnly:
            return count + " \u{00D7} " + reps
        case .duration:
            return count + " \u{00D7} " + reps + " s"
        }
    }
}

// MARK: - Hand-off to the app

/// What a button of the planned-session Live Activity, or the Shortcuts action, asks the app to do with the plan.
public enum PlannedSessionCommand: Sendable {
    /// Plan (or re-plan) a session; replaces an earlier plan.
    case schedule(PlannedSessionPlan)
    /// Move the start by `minutes`.
    case snooze(minutes: Int)
    /// Drop the plan.
    case cancel
}

/// Process-wide hand-off between the planned-session App Intents and the app, the counterpart of `WorkoutCommandBus` for the plan.
///
/// `SnoozePlannedIntent` is a `LiveActivityIntent`, so it runs in the app's process, possibly launched in the background and still
/// starting up: `perform` waits (polling every 50 ms, at most 3 s) for the handler that `PlannedSessionManager` installs and then gives
/// up silently. The intents are compiled into the widget extension as well, which does not link the manager, hence this seam in the
/// module both link.
public final class PlannedSessionBus: @unchecked Sendable {
    /// The handler type installed by the app.
    public typealias Handler = @Sendable (PlannedSessionCommand) async -> Void

    public static let shared = PlannedSessionBus()

    /// Longest time `perform` waits for a handler to be installed.
    private static let maximumWait: TimeInterval = 3
    /// Interval between two checks while waiting for a handler.
    private static let pollInterval: UInt64 = 50_000_000

    /// Guards `handler`.
    private let lock = NSLock()
    private var handler: Handler?

    public init() {}

    /// Installs the handler that executes commands. A later call replaces the earlier handler.
    public func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    /// Runs `command` through the installed handler, waiting for it when the app is still starting. Dropped without an error when no
    /// handler appears or the calling task is cancelled meanwhile.
    public func perform(_ command: PlannedSessionCommand) async {
        guard let resolved = await waitForHandler() else { return }
        await resolved(command)
    }

    // MARK: Private

    private func currentHandler() -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    private func waitForHandler() async -> Handler? {
        if let ready = currentHandler() {
            return ready
        }
        let deadline = Date().addingTimeInterval(Self.maximumWait)
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: Self.pollInterval)
            } catch {
                return currentHandler()
            }
            if let ready = currentHandler() {
                return ready
            }
        }
        return currentHandler()
    }
}
#endif
