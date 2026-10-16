package health.pulse.strength

import android.app.Application

class PulseStrengthApplication : Application() {
    /** The shared environment; created on first use, which is process start ([onCreate]) in the running app. */
    val environment: StrengthAppEnvironment by lazy { StrengthAppEnvironment.live(this) }

    override fun onCreate() {
        super.onCreate()
        environment.services?.let { registerActivityLifecycleCallbacks(it.foreground) }
        // Touch it now so that a notification action that starts the process in the background finds the running workout restored.
        environment.controller.restoreFromDisk()
    }
}
