import Foundation

/// Identifiers shared by the app, the widget extension, the App Intents and the Watch app.
/// Replace the placeholders with the Pulse team's real values when integrating.
public enum StrengthConfig {
    /// App Group reserved for sharing data with the Pulse app. The standalone host app declares no App Group (its data lives in
    /// Application Support); adding the capability to the app makes `StrengthAppEnvironment.live` use the group container.
    public static let appGroupID = "group.health.pulse.strength"
    /// URL scheme used by the Live Activity to open the running workout.
    public static let urlScheme = "pulse-strength"
    /// URL that opens the active workout.
    public static let workoutURL = URL(string: "pulse-strength://workout")!
    /// Identifier of the rest-over local notification.
    public static let restNotificationID = "health.pulse.strength.rest"
    /// Default name of a workout started without a template.
    public static let defaultWorkoutName = "Workout"
}
