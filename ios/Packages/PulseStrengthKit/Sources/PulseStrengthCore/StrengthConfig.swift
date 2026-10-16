import Foundation

/// Identifiers shared by the app, the widget extension, the App Intents and the Watch app.
/// Replace the placeholders with the Pulse team's real values when integrating.
public enum StrengthConfig {
    /// The App Group that the app, the widget extension and the controls share (the group container holds the strength data, the widget
    /// snapshot and the command inbox). The Info.plist key `PulseAppGroupID` (set from `PULSE_APP_BUNDLE_ID` in the project, so changing the
    /// bundle id changes the group too) wins over `defaultAppGroupID`.
    public static var appGroupID: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "PulseAppGroupID") as? String,
           !value.isEmpty, !value.contains("$(") {
            return value
        }
        return defaultAppGroupID
    }
    /// Used when the Info.plist does not name a group (tests, Linux, a build without the key).
    public static let defaultAppGroupID = "group.health.pulse.strength"
    /// URL scheme used by the Live Activity to open the running workout.
    public static let urlScheme = "pulse-strength"
    /// URL that opens the active workout.
    public static let workoutURL = URL(string: "pulse-strength://workout")!
    /// Darwin notification the extension posts after it appended a command to the inbox (widgets/SPEC.md section 5).
    public static let commandInboxNotification = "health.pulse.strength.command-inbox"
    /// URL that opens the body weight entry (the weigh-in reminder notification uses it).
    public static let weightURL = URL(string: "pulse-strength://weight")!
    /// Prefix of the identifiers of the weigh-in reminder notifications (`<prefix>.0`, `<prefix>.1`, ...).
    public static let weightReminderIDPrefix = "health.pulse.strength.weight"
    /// Identifier of the notification category that carries the "Log weight" text-input action.
    public static let weightReminderCategoryID = "health.pulse.strength.weight.category"
    /// Identifier of the "Log weight" text-input action of the reminder notification.
    public static let weightReminderLogActionID = "health.pulse.strength.weight.log"
    /// Identifier of the rest-over local notification.
    public static let restNotificationID = "health.pulse.strength.rest"
    /// Default name of a workout started without a template.
    public static let defaultWorkoutName = "Workout"
}
