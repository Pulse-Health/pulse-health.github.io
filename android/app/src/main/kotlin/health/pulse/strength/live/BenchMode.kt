package health.pulse.strength.live

import android.content.Context
import android.content.Intent

/**
 * SB-02 / SB-04 Bench mode: a full-screen, keep-awake, show-when-locked screen with a big rest timer (and a red-on-black night theme).
 * Owner: system (the activity itself). The widgets and the host UI only use [intent].
 */
object BenchMode {
    /** An intent that opens the bench-mode screen; [night] selects the red-on-black theme (otherwise chosen by the hour). */
    fun intent(context: Context, night: Boolean? = null): Intent =
        Intent().setClassName(context.packageName, "health.pulse.strength.live.BenchModeActivity").also { intent ->
            if (night != null) intent.putExtra("night", night)
        }
}
