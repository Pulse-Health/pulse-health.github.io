import Foundation

/// Identifiers shared by the app, the widget extension, the App Intents and the Watch app.
/// Replace the placeholders with the Pulse team's real values when integrating.
public enum StrengthConfig {
    /// App Group shared by the iOS app, the widget extension and the Live Activity intents.
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
