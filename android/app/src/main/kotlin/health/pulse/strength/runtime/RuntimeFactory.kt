package health.pulse.strength.runtime

import android.content.Context
import health.pulse.strength.PulseStrengthApplication

/** Creates the runtime of the running app: a [LiveRuntime] around the store, the workout controller and the settings of its environment. */
internal object RuntimeFactory {
    fun create(context: Context): StrengthRuntime.Runtime {
        val environment = (context.applicationContext as PulseStrengthApplication).environment
        val services = checkNotNull(environment.services) { "The environment of the running app has its platform services" }
        return LiveRuntime(context, environment.store, environment.controller, services.settings.weeklyGoal)
    }
}
