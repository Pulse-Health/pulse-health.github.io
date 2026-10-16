package health.pulse.strength.controls

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.live.completeSnapshot
import health.pulse.strength.live.loggingSnapshot
import health.pulse.strength.live.pausedSnapshot
import health.pulse.strength.live.previewWith
import health.pulse.strength.live.restingSnapshot
import health.pulse.strength.runtime.PreviewRuntime
import health.pulse.strength.runtime.StrengthRuntime
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Test

/** CT-10: one button, three meanings: log set while logging, skip rest while resting, start the next workout with none running. */
class PrimaryActionTest {
    private lateinit var runtime: PreviewRuntime

    @Before
    fun install() {
        runtime = PreviewRuntime()
        StrengthRuntime.installForTest(runtime)
    }

    @After
    fun restore() {
        StrengthRuntime.installForTest(PreviewRuntime())
    }

    /** Presses the button in the state [active] and returns what reached the engine. */
    private fun press(active: WorkoutSnapshot?): List<String> {
        runtime.publish(previewWith(active))
        runtime.received.clear()
        runBlocking { StrengthRuntime.commands.primaryAction() }
        return runtime.received.toList()
    }

    @Test
    fun withNoWorkoutItStartsTheNextOne() {
        assertThat(press(null)).containsExactly("startNext")
    }

    @Test
    fun whileLoggingItLogsTheSet() {
        assertThat(press(loggingSnapshot())).containsExactly("logNextSet")
    }

    @Test
    fun whileRestingItSkipsTheRest() {
        assertThat(press(restingSnapshot())).containsExactly("skipRest")
    }

    @Test
    fun whenTheRestIsOverItLogsTheSet() {
        assertThat(press(loggingSnapshot().copy(phase = SnapshotPhase.REST_OVER))).containsExactly("logNextSet")
    }

    @Test
    fun itNeverFinishesAWorkout() {
        listOf(null, loggingSnapshot(), restingSnapshot(), completeSnapshot(), pausedSnapshot()).forEach {
            assertThat(press(it)).doesNotContain("finish")
        }
    }

    @Test
    fun theConfirmationTellsWhatHappened() {
        assertThat(PrimaryAction.kindFor(previewWith(null))).isEqualTo(PrimaryKind.START_NEXT)
        assertThat(PrimaryAction.confirmation(previewWith(null))).isEqualTo("Starting Upper A · Push")

        assertThat(PrimaryAction.kindFor(previewWith(loggingSnapshot()))).isEqualTo(PrimaryKind.LOG_SET)
        assertThat(PrimaryAction.confirmation(previewWith(loggingSnapshot()))).isEqualTo("Set logged · 82.5 kg × 6")

        assertThat(PrimaryAction.kindFor(previewWith(restingSnapshot()))).isEqualTo(PrimaryKind.SKIP_REST)
        assertThat(PrimaryAction.confirmation(previewWith(restingSnapshot()))).isEqualTo("Rest skipped")

        assertThat(PrimaryAction.confirmation(previewWith(completeSnapshot()))).isEqualTo("All sets logged")
        assertThat(PrimaryAction.confirmation(previewWith(null).copy(nextUp = null))).isEqualTo("No workout to start")
    }

    @Test
    fun theConfirmationNamesWhatARepsOnlySetAsked() {
        val reps = loggingSnapshot().copy(
            tracking = TrackingKind.REPS_ONLY,
            showsWeight = false,
            weightText = "BW",
            repsText = "12",
        )
        assertThat(PrimaryAction.confirmation(previewWith(reps))).isEqualTo("Set logged · 12 reps")
    }
}
