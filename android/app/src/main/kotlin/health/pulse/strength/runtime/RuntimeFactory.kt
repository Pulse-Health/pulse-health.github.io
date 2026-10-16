package health.pulse.strength.runtime

import android.content.Context

/** Creates the runtime of the running app. The `core` owner replaces the body with the real, file-backed runtime. */
internal object RuntimeFactory {
    fun create(context: Context): StrengthRuntime.Runtime = PreviewRuntime()
}
