package health.pulse.strength.services

import android.app.Activity
import android.app.Application
import android.os.Bundle

/** Knows whether one of the app's activities is on screen (started), so alerts the UI already shows are not repeated as notifications. */
class AppForegroundTracker : Application.ActivityLifecycleCallbacks {
    @Volatile
    private var started = 0

    val isForeground: Boolean get() = started > 0

    override fun onActivityStarted(activity: Activity) {
        started += 1
    }

    override fun onActivityStopped(activity: Activity) {
        started = maxOf(0, started - 1)
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityResumed(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
