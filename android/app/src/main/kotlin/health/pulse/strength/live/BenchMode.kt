package health.pulse.strength.live

import android.content.Context
import android.content.Intent

/**
 * SB-02 / SB-04 Bench mode: a full-screen, keep-awake, show-when-locked screen with a big rest timer (and a red-on-black night theme).
 * Owner: system (the activity itself). The widgets and the host UI only use [intent].
 */
object BenchMode {
    /** Boolean extra of the intent: true or false forces the night look, absent leaves it to the hour. */
    const val EXTRA_NIGHT = "night"

    /** An intent that opens the bench-mode screen; [night] selects the red-on-black theme (otherwise chosen by the hour). */
    fun intent(context: Context, night: Boolean? = null): Intent =
        Intent()
            .setClassName(context.packageName, "health.pulse.strength.live.BenchModeActivity")
            // Callable from a service or a widget too; inside the app's own task it only brings the activity to the front.
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .also { intent -> if (night != null) intent.putExtra(EXTRA_NIGHT, night) }
}
