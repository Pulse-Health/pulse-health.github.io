#if os(iOS)
import SwiftUI
import PulseStrengthCore

// Types shared between the independently written screens, sheets and the app environment.

/// What the "Add exercise" picker does with the selection.
public enum PickerMode: Equatable {
    /// Append the selected exercises to the workout.
    case add
    /// Replace the given workout exercise with the single selected exercise.
    case replace(exerciseID: UUID)
}

/// Which value of a set the keypad edits.
public enum KeypadField: Equatable {
    case weight
    case reps
}

/// Apple Watch state worth telling the user about while a workout runs.
/// `.connected` means "nothing to report": no Watch involved, or the Watch is in sync.
public enum WatchStatus: Equatable, Sendable {
    case connected
    /// A paired Watch with the app installed is not reachable (no banner without a Watch).
    case notConnected
    /// Health access for heart rate / workouts was denied.
    case healthDenied
}

private struct WatchStatusKey: EnvironmentKey {
    static let defaultValue: WatchStatus = .connected
}

public extension EnvironmentValues {
    var watchStatus: WatchStatus {
        get { self[WatchStatusKey.self] }
        set { self[WatchStatusKey.self] = newValue }
    }
}

private struct CoachAudienceKey: EnvironmentKey {
    static let defaultValue: AudienceProfile = .unknown
}

public extension EnvironmentValues {
    /// What the host app knows about the person (age group, muscles to avoid); the coach is more careful when it is unknown.
    var coachAudience: AudienceProfile {
        get { self[CoachAudienceKey.self] }
        set { self[CoachAudienceKey.self] = newValue }
    }
}

/// Callbacks of the exercise card (the active-workout screen presents the sheets).
public struct ExerciseCardActions {
    /// Open the keypad for a set's weight or reps.
    public var openKeypad: (SetRef, KeypadField) -> Void
    /// Open the set type / RIR / delete sheet.
    public var openSetDetail: (SetRef) -> Void
    /// Open the form & instructions sheet (media tile tap).
    public var showInfo: (Exercise) -> Void
    /// Open the exercise options dialog for a workout exercise id.
    public var showOptions: (UUID) -> Void
    /// Open the rest timer settings of a workout exercise id.
    public var showRestSettings: (UUID) -> Void

    public init(
        openKeypad: @escaping (SetRef, KeypadField) -> Void,
        openSetDetail: @escaping (SetRef) -> Void,
        showInfo: @escaping (Exercise) -> Void,
        showOptions: @escaping (UUID) -> Void,
        showRestSettings: @escaping (UUID) -> Void
    ) {
        self.openKeypad = openKeypad
        self.openSetDetail = openSetDetail
        self.showInfo = showInfo
        self.showOptions = showOptions
        self.showRestSettings = showRestSettings
    }
}
#endif
