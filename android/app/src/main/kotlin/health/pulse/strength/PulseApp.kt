package health.pulse.strength

import android.app.Application
import health.pulse.strength.runtime.StrengthRuntime

class PulseApp : Application() {
    override fun onCreate() {
        super.onCreate()
        StrengthRuntime.init(this)
    }
}
