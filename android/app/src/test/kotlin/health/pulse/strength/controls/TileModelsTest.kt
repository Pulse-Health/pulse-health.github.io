package health.pulse.strength.controls

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import health.pulse.strength.live.NOW
import health.pulse.strength.live.completeSnapshot
import health.pulse.strength.live.loggingSnapshot
import health.pulse.strength.live.pausedSnapshot
import health.pulse.strength.live.plates
import health.pulse.strength.live.previewWith
import health.pulse.strength.live.restingSnapshot
import org.junit.Test

/** CT-01 ... CT-08: the state, the texts and the click of every Quick Settings tile, as a function of the snapshot. */
class TileModelsTest {
    private fun tile(control: Control, active: WorkoutSnapshot?, snapshot: WidgetSnapshot = previewWith(active)) =
        TileModels.of(control, snapshot, NOW)

    // region CT-01 Start next workout

    @Test
    fun startNextStartsTheSuggestedTemplate() {
        val t = tile(Control.START_NEXT, null)
        assertThat(t.status).isEqualTo(TileStatus.ACTIVE)
        assertThat(t.label).isEqualTo("Start workout")
        assertThat(t.subtitle).isEqualTo("Upper A · Push")
        assertThat(t.action).isEqualTo(TileAction.Link(DeepLinks.startNext))
    }

    @Test
    fun startNextOpensARunningWorkoutInsteadOfStartingAnother() {
        val t = tile(Control.START_NEXT, loggingSnapshot())
        assertThat(t.status).isEqualTo(TileStatus.INACTIVE)
        assertThat(t.action).isEqualTo(TileAction.Link(DeepLinks.workout))
    }

    @Test
    fun startNextIsUnavailableWithoutATemplate() {
        val t = tile(Control.START_NEXT, null, previewWith(null).copy(nextUp = null))
        assertThat(t.status).isEqualTo(TileStatus.UNAVAILABLE)
        assertThat(t.action).isEqualTo(TileAction.None)
    }

    // endregion

    // region CT-02 Log set

    @Test
    fun logSetShowsTheNextSetAndLogsIt() {
        val t = tile(Control.LOG_SET, loggingSnapshot())
        assertThat(t.status).isEqualTo(TileStatus.ACTIVE)
        assertThat(t.subtitle).isEqualTo("Set 4 · 82.5 kg × 6")
        assertThat(t.action).isEqualTo(TileAction.Command(WidgetCommand.of(WidgetCommands.LOG_NEXT_SET)))
        assertThat(tile(Control.LOG_SET, restingSnapshot()).status).isEqualTo(TileStatus.ACTIVE)
    }

    @Test
    fun logSetHasNothingToDoWithoutAPendingSet() {
        assertThat(tile(Control.LOG_SET, null)).isEqualTo(
            TileModel(Control.LOG_SET, "Log set", "No workout", TileStatus.UNAVAILABLE, TileIcon.LOG, TileAction.None),
        )
        assertThat(tile(Control.LOG_SET, pausedSnapshot()).subtitle).isEqualTo("Paused")
        assertThat(tile(Control.LOG_SET, completeSnapshot()).subtitle).isEqualTo("All sets logged")
        assertThat(tile(Control.LOG_SET, completeSnapshot().copy(totalSets = 0)).subtitle).isEqualTo("No sets yet")
        listOf(null, pausedSnapshot(), completeSnapshot()).forEach {
            assertThat(tile(Control.LOG_SET, it).status).isEqualTo(TileStatus.UNAVAILABLE)
        }
    }

    // endregion

    // region CT-03 Rest

    @Test
    fun restShowsTheRemainingTimeAsMinutesAndSeconds() {
        val t = tile(Control.REST, restingSnapshot(remaining = 84))
        assertThat(t.status).isEqualTo(TileStatus.ACTIVE)
        assertThat(t.subtitle).isEqualTo("1:24")
        assertThat(t.contentDescription).isEqualTo("Rest, 1:24")
        assertThat(t.action).isEqualTo(TileAction.OpenBench)
        assertThat(TileModels.of(Control.REST, previewWith(restingSnapshot(remaining = 84)), NOW.plusSeconds(30)).subtitle).isEqualTo("0:54")
    }

    @Test
    fun restSaysGoWhenTheTimeIsOutAndIsUnavailableOtherwise() {
        assertThat(tile(Control.REST, restingSnapshot(remaining = -2)).subtitle).isEqualTo("Go")
        assertThat(tile(Control.REST, loggingSnapshot().copy(phase = SnapshotPhase.REST_OVER)).subtitle).isEqualTo("Go")
        assertThat(tile(Control.REST, loggingSnapshot())).isEqualTo(
            TileModel(Control.REST, "Rest", "Not resting", TileStatus.UNAVAILABLE, TileIcon.REST, TileAction.None),
        )
        assertThat(tile(Control.REST, null).subtitle).isEqualTo("No workout")
    }

    @Test
    fun aPausedRestShowsItsFrozenTime() {
        val paused = restingSnapshot().copy(isPaused = true, restFrozenRemaining = 50, restEndsAt = null)
        val t = tile(Control.REST, paused)
        assertThat(t.subtitle).isEqualTo("0:50 · paused")
        assertThat(t.status).isEqualTo(TileStatus.INACTIVE)
        assertThat(tile(Control.REST, pausedSnapshot()).status).isEqualTo(TileStatus.UNAVAILABLE)
    }

    // endregion

    // region CT-04 +30 s rest

    @Test
    fun addRestAddsThirtySecondsWhileResting() {
        val t = tile(Control.ADD_REST, restingSnapshot())
        assertThat(t.status).isEqualTo(TileStatus.ACTIVE)
        assertThat(t.label).isEqualTo("+30 s rest")
        assertThat(t.action).isEqualTo(TileAction.Command(WidgetCommand.of(WidgetCommands.ADJUST_REST, WidgetCommands.ARG_SECONDS to "30")))
    }

    @Test
    fun addRestIsUnavailableUnlessARestRuns() {
        listOf(null, loggingSnapshot(), restingSnapshot(remaining = -1), pausedSnapshot()).forEach {
            assertThat(tile(Control.ADD_REST, it).status).isEqualTo(TileStatus.UNAVAILABLE)
            assertThat(tile(Control.ADD_REST, it).action).isEqualTo(TileAction.None)
        }
    }

    // endregion

    // region CT-05 Plate calculator

    @Test
    fun platesOpensTheCalculatorAndShowsThePlatesOfTheTargetSet() {
        val idle = tile(Control.PLATES, null)
        assertThat(idle.status).isEqualTo(TileStatus.INACTIVE)
        assertThat(idle.subtitle).isEqualTo("Calculator")
        assertThat(idle.action).isEqualTo(TileAction.Link(DeepLinks.plates))
        val loaded = tile(Control.PLATES, loggingSnapshot().copy(plates = plates()))
        assertThat(loaded.status).isEqualTo(TileStatus.ACTIVE)
        assertThat(loaded.subtitle).isEqualTo("20 + 10 + 2.5 per side")
    }

    // endregion

    // region CT-06 Pause / resume

    @Test
    fun pauseIsAToggleThatIsOnWhilePaused() {
        val running = tile(Control.PAUSE, loggingSnapshot())
        assertThat(running.status).isEqualTo(TileStatus.INACTIVE)
        assertThat(running.label).isEqualTo("Pause workout")
        assertThat(running.icon).isEqualTo(TileIcon.PAUSE)
        assertThat(running.stateDescription).isEqualTo("Running")
        assertThat(running.action).isEqualTo(TileAction.Command(WidgetCommand.of(WidgetCommands.PAUSE)))

        val paused = tile(Control.PAUSE, pausedSnapshot())
        assertThat(paused.status).isEqualTo(TileStatus.ACTIVE)
        assertThat(paused.label).isEqualTo("Resume workout")
        assertThat(paused.subtitle).isEqualTo("Paused · 24:18")
        assertThat(paused.icon).isEqualTo(TileIcon.RESUME)
        assertThat(paused.stateDescription).isEqualTo("Paused")
        assertThat(paused.action).isEqualTo(TileAction.Command(WidgetCommand.of(WidgetCommands.RESUME)))
        // A toggle says its state; the subtitle is not read twice.
        assertThat(paused.contentDescription).isEqualTo("Resume workout")
    }

    @Test
    fun pauseIsUnavailableWithoutAWorkout() {
        val t = tile(Control.PAUSE, null)
        assertThat(t.status).isEqualTo(TileStatus.UNAVAILABLE)
        assertThat(t.action).isEqualTo(TileAction.None)
    }

    // endregion

    // region CT-07 Finish workout

    @Test
    fun finishOpensTheWorkoutWhereTheAppAsksForConfirmation() {
        val running = tile(Control.FINISH, loggingSnapshot())
        assertThat(running.status).isEqualTo(TileStatus.INACTIVE)
        assertThat(running.subtitle).isEqualTo("12 of 20 sets")
        assertThat(running.action).isEqualTo(TileAction.Link(DeepLinks.workout))
        val done = tile(Control.FINISH, completeSnapshot())
        assertThat(done.status).isEqualTo(TileStatus.ACTIVE)
        assertThat(done.subtitle).isEqualTo("All sets logged")
        assertThat(tile(Control.FINISH, null).status).isEqualTo(TileStatus.UNAVAILABLE)
    }

    // endregion

    // region CT-08 Next up

    @Test
    fun nextUpLabelsTheSplit() {
        val t = tile(Control.NEXT_UP, null)
        assertThat(t.label).isEqualTo("Push day")
        assertThat(t.subtitle).isEqualTo("6 exercises · ~55 min")
        assertThat(t.status).isEqualTo(TileStatus.ACTIVE)
        assertThat(t.action).isEqualTo(TileAction.Link(DeepLinks.startNext))
    }

    @Test
    fun nextUpOpensARunningWorkoutAndIsUnavailableWithoutATemplate() {
        val running = tile(Control.NEXT_UP, loggingSnapshot())
        assertThat(running.label).isEqualTo("Push day")
        assertThat(running.action).isEqualTo(TileAction.Link(DeepLinks.workout))
        val none = tile(Control.NEXT_UP, null, previewWith(null).copy(nextUp = null))
        assertThat(none.label).isEqualTo("Next up")
        assertThat(none.status).isEqualTo(TileStatus.UNAVAILABLE)
    }

    // endregion

    @Test
    fun everyControlHasAModelInEveryState() {
        val states = listOf(null, loggingSnapshot(), restingSnapshot(), restingSnapshot(remaining = -1), pausedSnapshot(), completeSnapshot())
        for (control in Control.entries) {
            for (state in states) {
                val t = tile(control, state)
                assertThat(t.control).isEqualTo(control)
                assertThat(t.label).isNotEmpty()
                // A tile that cannot be clicked does nothing.
                if (t.status == TileStatus.UNAVAILABLE) assertThat(t.action).isEqualTo(TileAction.None)
            }
        }
        assertThat(Control.entries).hasSize(8)
        assertThat(WidgetSnapshot.preview.active).isNull()
    }
}
