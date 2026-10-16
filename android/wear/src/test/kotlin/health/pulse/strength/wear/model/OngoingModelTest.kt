package health.pulse.strength.wear.model

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import org.junit.Test

/** WA-02: what the Ongoing Activity chip says in each state of the workout. */
class OngoingModelTest {
    @Test
    fun whileLoggingTheChipShowsTheWorkoutClock() {
        val model = OngoingModel.of(WearFixtures.workout(), now)

        assertThat(model.title).isEqualTo("Upper A · Push")
        assertThat(model.text).isEqualTo("Bench Press · Set 3 of 4")
        assertThat(model.status).isEqualTo(OngoingStatus.Elapsed(now.minusSeconds(1500).toEpochMilli()))
        assertThat(model.description).isEqualTo("Upper A · Push. Workout running")
    }

    @Test
    fun whileRestingTheChipCountsDownToTheEndOfTheRest() {
        val model = OngoingModel.of(WearFixtures.resting(seconds = 84), now)

        assertThat(model.status).isEqualTo(OngoingStatus.Rest(now.plusSeconds(84).toEpochMilli()))
    }

    @Test
    fun whenTheRestIsOverTheChipSaysSo() {
        assertThat(OngoingModel.of(WearFixtures.workout(phase = SnapshotPhase.REST_OVER), now).status).isEqualTo(OngoingStatus.RestOver)
        val ranOut = WearFixtures.workout(phase = SnapshotPhase.RESTING, restEndsAt = now.minusSeconds(3))
        assertThat(OngoingModel.of(ranOut, now).status).isEqualTo(OngoingStatus.RestOver)
    }

    @Test
    fun aPausedWorkoutFreezesTheClockAtTheElapsedTime() {
        val paused = WearFixtures.workout(isPaused = true, elapsedWhenPaused = 1480)

        val status = OngoingModel.of(paused, now).status

        val start = now.minusSeconds(1500).toEpochMilli()
        assertThat(status).isEqualTo(OngoingStatus.ElapsedPaused(start, start + 1_480_000L))
    }

    @Test
    fun aPausedRestFreezesTheCountdown() {
        val paused = WearFixtures.resting().copy(isPaused = true, restFrozenRemaining = 61)

        assertThat(OngoingModel.of(paused, now).status).isEqualTo(OngoingStatus.RestPaused(61))
        assertThat(OngoingModel.of(paused, now).description).contains("1 minute 1 second left")
    }

    @Test
    fun afterTheLastSetTheChipSaysAllSetsAreLogged() {
        val model = OngoingModel.of(WearFixtures.workout(phase = SnapshotPhase.COMPLETE, loggedSets = 20), now)

        assertThat(model.status).isEqualTo(OngoingStatus.Complete)
        assertThat(model.text).isEqualTo("20 sets logged")
    }
}
