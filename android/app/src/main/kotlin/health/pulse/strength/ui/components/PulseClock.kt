package health.pulse.strength.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import java.time.Instant
import kotlinx.coroutines.delay

/**
 * The time source of clock-driven UI (the workout clock, the rest countdown). Tests provide a fixed one ([ticks] = false) so
 * screenshots are deterministic.
 */
class PulseClock(val now: () -> Instant = { Instant.now() }, val ticks: Boolean = true)

val LocalPulseClock = compositionLocalOf { PulseClock() }

/**
 * The current time, refreshed every [periodMillis] (the SwiftUI `TimelineView(.periodic)` counterpart). Read the returned state
 * where the time is used so only that part recomposes.
 */
@Composable
fun rememberNow(periodMillis: Long = 1000L): State<Instant> {
    val clock = LocalPulseClock.current
    val state = remember(clock) { mutableStateOf(clock.now()) }
    if (clock.ticks) {
        LaunchedEffect(clock, periodMillis) {
            while (true) {
                state.value = clock.now()
                delay(periodMillis)
            }
        }
    }
    return state
}
