package health.pulse.strength.core

/** Identifiers and defaults shared by the app, its notification actions and the deep link. */
object StrengthConfig {
    /** URL scheme that opens the running workout (from the ongoing notification or any other app). */
    const val urlScheme: String = "pulse-strength"

    /** URL that opens the active workout. */
    const val workoutUrl: String = "pulse-strength://workout"

    /** Identifier of the rest-over notification. */
    const val restNotificationId: String = "health.pulse.strength.rest"

    /** Default name of a workout started without a template. */
    const val defaultWorkoutName: String = "Workout"
}
