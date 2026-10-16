package health.pulse.strength.runtime

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutFactory
import health.pulse.strength.core.WorkoutState
import health.pulse.strength.core.addingTimeInterval
import java.time.Instant
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Test

/** The throttle of heart-rate-only changes that keeps a watch's stream of readings from rebuilding the snapshot every second. */
class HeartRateThrottleTest {
    private val start: Instant = Instant.parse("2026-10-16T09:41:00Z")
    private val idle: WorkoutState = WorkoutFactory.makeEmpty("Push day", start)

    /** [of] with one more heart-rate reading, the way the reducer keeps them. */
    private fun reading(bpm: Int, of: WorkoutState = idle): WorkoutState =
        of.copy(heartRate = bpm, heartRateSum = of.heartRateSum + bpm, heartRateCount = of.heartRateCount + 1)

    /** The states that get through when each of [steps] arrives at its number of seconds after the start. */
    private suspend fun passed(vararg steps: Pair<Double, WorkoutState?>): List<WorkoutState?> {
        var now = start
        return flow {
            for ((seconds, state) in steps) {
                now = start.addingTimeInterval(seconds)
                emit(state)
            }
        }.heartRateThrottled(10.0) { now }.toList()
    }

    @Test
    fun theFirstReadingPassesAndTheFollowingOnesWaitTenSeconds() = runTest {
        val first = reading(120)
        val second = reading(125, first)
        val third = reading(130, second)
        val fourth = reading(135, third)
        val passed = passed(0.0 to idle, 1.0 to first, 4.0 to second, 10.9 to third, 11.0 to fourth)
        assertThat(passed).containsExactly(idle, first, fourth).inOrder()
    }

    @Test
    fun anyOtherChangePassesAtOnceAndCarriesTheLatestReading() = runTest {
        val first = reading(120)
        val dropped = reading(130, first)
        val renamed = dropped.copy(name = "Renamed")
        val passed = passed(0.0 to idle, 1.0 to first, 2.0 to dropped, 3.0 to renamed)
        assertThat(passed).containsExactly(idle, first, renamed).inOrder()
        assertThat((passed.last())?.heartRate).isEqualTo(130)
    }

    @Test
    fun aChangeOfMoreThanTheHeartRateIsNeverThrottled() = runTest {
        val first = reading(120)
        val both = reading(130, first).copy(name = "Renamed")
        assertThat(passed(0.0 to idle, 1.0 to first, 2.0 to both)).containsExactly(idle, first, both).inOrder()
    }

    @Test
    fun theEndAndTheStartOfAWorkoutPass() = runTest {
        val first = reading(120)
        val dropped = reading(130, first)
        val passed = passed(0.0 to null, 1.0 to idle, 2.0 to first, 3.0 to null, 4.0 to idle, 5.0 to dropped)
        // The reading of the second workout comes less than ten seconds after the first workout's, and is held back like any other.
        assertThat(passed).containsExactly(null, idle, first, null, idle).inOrder()
    }

    @Test
    fun aStateThatDidNotChangePassesLikeAnyOther() = runTest {
        assertThat(passed(0.0 to idle, 1.0 to idle)).containsExactly(idle, idle).inOrder()
    }

    @Test
    fun aClockSetBackwardsDoesNotHoldReadingsBack() = runTest {
        val first = reading(120)
        val second = reading(130, first)
        assertThat(passed(100.0 to idle, 100.0 to first, 50.0 to second)).containsExactly(idle, first, second).inOrder()
    }
}
