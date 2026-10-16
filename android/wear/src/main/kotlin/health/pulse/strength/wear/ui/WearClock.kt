package health.pulse.strength.wear.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import java.time.Instant
import kotlinx.coroutines.delay

/**
 * The current time, refreshed on every full second while [enabled] (a rest countdown or the workout clock is on screen) and frozen
 * otherwise, so an idle screen does not recompose once a second. [clock] is a parameter for tests.
 */
@Composable
internal fun rememberNow(enabled: Boolean, clock: () -> Instant = Instant::now): State<Instant> =
    produceState(initialValue = clock(), enabled) {
        value = clock()
        while (enabled) {
            val millis = clock().toEpochMilli()
            delay(MILLIS_PER_SECOND - Math.floorMod(millis, MILLIS_PER_SECOND))
            value = clock()
        }
    }

private const val MILLIS_PER_SECOND = 1000L
