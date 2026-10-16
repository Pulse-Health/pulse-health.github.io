package health.pulse.strength.widgets.home

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.DeepLinks
import org.junit.Test

class NextUpModelTest {
    private val preview = HomeFixtures.preview

    @Test
    fun theNextTemplateIsSummarisedAndStartsViaTheStartNextLink() {
        val card = NextUpModel.card(preview)
        assertThat(card.eyebrow).isEqualTo("Next up")
        assertThat(card.title).isEqualTo("Upper A · Push")
        assertThat(card.summary).isEqualTo("6 exercises · ~55 min")
        assertThat(card.wideSummary).isEqualTo("Done 5 days ago")
        assertThat(card.planLine).isEqualTo("Upper / Lower · workout 1 of 3")
        assertThat(card.message).isNull()
        assertThat(card.button).isEqualTo(NextUpButton("Start", DeepLinks.startNext, "Start Upper A · Push"))
        assertThat(card.rows).hasSize(6)
        assertThat(card.rows.first()).isEqualTo(NextUpRow("Bench Press", "3 × 85"))
        assertThat(card.description).isEqualTo("Next up: Upper A · Push, 6 exercises · ~55 min")
    }

    @Test
    fun aTemplateWithoutAnEstimateOrExercisesStillReadsWell() {
        val next = preview.nextUp!!.copy(exerciseCount = 1, estimatedMinutes = 0, exercises = emptyList(), daysSince = null)
        val card = NextUpModel.card(preview.copy(nextUp = next))
        assertThat(card.summary).isEqualTo("1 exercise")
        assertThat(card.wideSummary).isEqualTo("Not done yet")
        assertThat(card.rows).isEmpty()
        assertThat(card.button).isNotNull()
    }

    @Test
    fun withoutTemplatesThereIsNothingToStartAndTheCardSaysWhatToDo() {
        val card = NextUpModel.card(HomeFixtures.empty)
        assertThat(card.title).isEqualTo("No workouts yet")
        assertThat(card.message).isEqualTo("Open Pulse Strength to create a workout")
        assertThat(card.button).isNull()
        assertThat(card.rows).isEmpty()
        assertThat(card.description).contains("Open Pulse Strength to create a workout")
    }

    @Test
    fun aRunningWorkoutTurnsTheCardIntoAResumeCard() {
        val card = NextUpModel.card(preview.copy(active = HomeFixtures.runningWorkout()))
        assertThat(card.eyebrow).isEqualTo("In progress")
        assertThat(card.title).isEqualTo("Upper A · Push")
        assertThat(card.summary).isEqualTo("12 of 20 sets")
        assertThat(card.button).isEqualTo(NextUpButton("Resume", DeepLinks.workout, "Resume Upper A · Push"))
        assertThat(card.rows).containsExactly(NextUpRow("Bench Press", "Set 3 of 5"), NextUpRow("Next", "Set 3 · 80 kg × 6")).inOrder()
    }

    @Test
    fun lastDonePhrases() {
        assertThat(NextUpModel.lastDone(null)).isEqualTo("Not done yet")
        assertThat(NextUpModel.lastDone(0)).isEqualTo("Done today")
        assertThat(NextUpModel.lastDone(1)).isEqualTo("Done yesterday")
        assertThat(NextUpModel.lastDone(5)).isEqualTo("Done 5 days ago")
    }

    @Test
    fun previewRowsFitTheHeightAndLeaveRoomForTheMoreLine() {
        assertThat(NextUpModel.visibleRows(134f, 0)).isEqualTo(0)
        // Everything fits: no "more" line is needed.
        assertThat(NextUpModel.visibleRows(134f, 5)).isEqualTo(5)
        // Six rows need 144 dp: the last one gives way to the "+ N more" line.
        assertThat(NextUpModel.visibleRows(134f, 6)).isEqualTo(4)
        assertThat(NextUpModel.visibleRows(94f, 6)).isEqualTo(3)
        // Never fewer than one row for a template that has exercises.
        assertThat(NextUpModel.visibleRows(20f, 6)).isEqualTo(1)
        // Never more than six rows, however tall the widget is.
        assertThat(NextUpModel.visibleRows(900f, 10)).isEqualTo(6)
    }
}
