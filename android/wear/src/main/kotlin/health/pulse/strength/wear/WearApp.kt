package health.pulse.strength.wear

import android.app.Application
import health.pulse.strength.wear.data.WearRuntime

class WearApp : Application() {
    override fun onCreate() {
        super.onCreate()
        WearRuntime.init(this)
    }
}
