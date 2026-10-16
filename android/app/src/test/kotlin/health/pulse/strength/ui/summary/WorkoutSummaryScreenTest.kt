package health.pulse.strength.ui.summary

import android.content.Context
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.SampleData
import health.pulse.strength.ui.detail.PAGE_PHONE
import health.pulse.strength.ui.detail.PAGE_SMALL_PHONE
import health.pulse.strength.ui.detail.ResultFixtures
import health.pulse.strength.ui.detail.setPulse
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Texts, states, callbacks and feedback of the workout summary. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = PAGE_PHONE)
class WorkoutSummaryScreenTest {
    @get:Rule val rule = createComposeRule()

    @Before fun pinZone() = ResultFixtures.pinTimeZone()

    private var doneCount = 0
    private val haptics = mutableListOf<Int>()

    private val recordWorkout get() = ResultFixtures.demoRecordWorkout()

    /** A view that records the haptic feedback it is asked to perform. */
    private fun spyView(): View = object : View(ApplicationProvider.getApplicationContext<Context>()) {
        override fun performHapticFeedback(feedbackConstant: Int): Boolean {
            haptics.add(feedbackConstant)
            return true
        }
    }

    private fun show(workout: CompletedWorkout) {
        val view = spyView()
        rule.setPulse {
            CompositionLocalProvider(LocalView provides view) {
                WorkoutSummaryScreen(workout = workout, onDone = { doneCount++ })
            }
        }
        rule.waitForIdle()
    }

    // region Content

    @Test
    fun showsTheHeadlineAndTheSubtitle() {
        show(recordWorkout)
        rule.onNodeWithText("Workout Complete").assertIsDisplayed()
        // The workout finished on Friday 2 January 2026 and took 56 minutes.
        rule.onNodeWithText("Upper A · Push · Fri, Jan 2 · 56 min").assertIsDisplayed()
        rule.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading) and hasText("Workout Complete")).assertExists()
    }

    @Test
    fun showsTheFigureTiles() {
        show(recordWorkout)
        for ((title, value) in listOf("Duration" to "56m", "Volume" to "5,064 kg", "Sets" to "20", "Avg Heart Rate" to "131 bpm", "Avg RIR" to "2.0")) {
            rule.onNodeWithText(title, useUnmergedTree = true).assertIsDisplayed()
            rule.onNodeWithText(value, useUnmergedTree = true).assertIsDisplayed()
        }
    }

    @Test
    fun theTilesAreReadAsOneFigureEach() {
        show(recordWorkout)
        rule.onNodeWithContentDescription("Duration, 56 minutes").assertIsDisplayed()
        rule.onNodeWithContentDescription("Volume, 5,064 kilograms").assertIsDisplayed()
        rule.onNodeWithContentDescription("Sets, 20").assertIsDisplayed()
        rule.onNodeWithContentDescription("Avg Heart Rate, 131 beats per minute").assertIsDisplayed()
        rule.onNodeWithContentDescription("Avg RIR, 2.0 reps in reserve").assertIsDisplayed()
    }

    @Test
    fun heartRateAndRirAreLeftOutWhenNotRecorded() {
        show(recordWorkout.copy(averageHeartRate = null, averageRIR = null))
        rule.onNodeWithText("Avg Heart Rate", useUnmergedTree = true).assertDoesNotExist()
        rule.onNodeWithText("Avg RIR", useUnmergedTree = true).assertDoesNotExist()
        rule.onNodeWithText("Duration", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun showsThePersonalRecordCard() {
        show(recordWorkout)
        rule.onNodeWithContentDescription(
            "New personal record, Barbell bench press, 85 kilograms for 5 reps, estimated one-rep max 99 kilograms, up 4 kilograms",
        ).assertIsDisplayed()
        rule.onNodeWithText("New personal record", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithText("85 kg × 5 · est. 1RM 99 kg", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithText("4 kg", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun severalRecordsEachGetARow() {
        show(ResultFixtures.manyExercisesWorkout())
        rule.onAllNodesWithText("New personal record", useUnmergedTree = true).assertCountEquals(2)
        rule.onNodeWithText("120 kg × 3 · est. 1RM 132 kg", useUnmergedTree = true).assertIsDisplayed()
        // The squat record rounds to the same whole kilogram as before: 132 against 132, no gain shown.
        rule.onNodeWithContentDescription(
            "New personal record, Back squat, 120 kilograms for 3 reps, estimated one-rep max 132 kilograms",
        ).assertIsDisplayed()
    }

    @Test
    fun noRecordCardWithoutRecords() {
        show(SampleData.history(ResultFixtures.now).first { it.personalRecords.isEmpty() })
        rule.onNodeWithText("New personal record", useUnmergedTree = true).assertDoesNotExist()
        rule.onNodeWithText("Workout Complete").assertIsDisplayed()
    }

    @Test
    fun listsTheExercisesWithTheirSets() {
        show(recordWorkout)
        rule.onNodeWithText("Exercises").assertIsDisplayed()
        rule.onNodeWithContentDescription(
            "Barbell bench press, 5 sets, personal record. W 50×8, W 70×5, 80×6, 82.5×5, 85×5",
        ).assertIsDisplayed()
        rule.onNodeWithContentDescription("Incline dumbbell press, 3 sets. 28×10, 30×8, 28×9").assertIsDisplayed()
        for (name in listOf("Barbell bench press", "Incline dumbbell press", "Overhead press", "Dumbbell lateral raise", "Triceps pushdown", "Cable crossover")) {
            rule.onAllNodesWithText(name, useUnmergedTree = true).assertCountEquals(if (name == "Barbell bench press") 2 else 1)
        }
        rule.onNodeWithText("W 50×8 · W 70×5 · 80×6 · 82.5×5 · 85×5", useUnmergedTree = true).assertIsDisplayed()
        // One PR tag on the list (the record card has none).
        rule.onAllNodesWithContentDescription("Personal record", useUnmergedTree = true).assertCountEquals(1)
    }

    @Test
    fun showsTheMusclesWorkedWithTheirSets() {
        show(recordWorkout)
        rule.onNodeWithText("Muscles Worked").assertIsDisplayed()
        rule.onNodeWithContentDescription("Chest, 9 sets").assertIsDisplayed()
        rule.onNodeWithContentDescription("Shoulders, 6 sets").assertIsDisplayed()
        rule.onNodeWithContentDescription("Arms, 3 sets").assertIsDisplayed()
        rule.onNodeWithText("9 sets", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun aWorkoutWithoutExercisesOrMusclesShowsJustTheFigures() {
        val base = SampleData.history(ResultFixtures.now).first { it.personalRecords.isEmpty() }
        show(base.copy(exercises = emptyList(), muscleSets = emptyList()))
        rule.onNodeWithText("Exercises").assertDoesNotExist()
        rule.onNodeWithText("Muscles Worked").assertDoesNotExist()
        rule.onNodeWithText("Duration", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithText("Done").assertIsDisplayed()
    }

    @Test
    fun aVeryLongNameStaysReadable() {
        val long = "Single-arm landmine press with a staggered stance and a really long name"
        val base = ResultFixtures.manyExercisesWorkout(3)
        show(
            base.copy(
                name = "Upper body strength, hypertrophy and a very long workout name",
                personalRecords = listOf(PersonalRecord("x", long, 32.5, 8, 41.2, 38.0)),
            ),
        )
        rule.onNodeWithText("Upper body strength, hypertrophy and a very long workout name · Fri, Jan 9 · 317 min").assertIsDisplayed()
        rule.onNodeWithText(long, useUnmergedTree = true).assertIsDisplayed()
        // The record's name wraps to several lines instead of being cut.
        assertThat(rule.onNodeWithText(long, useUnmergedTree = true).getUnclippedBoundsInRoot().height).isGreaterThan(40.dp)
    }

    // endregion

    // region Done and feedback

    @Test
    fun doneCallsOnDone() {
        show(recordWorkout)
        rule.onNodeWithText("Done").assertIsDisplayed()
        rule.onNodeWithText("Done").performClick()
        assertThat(doneCount).isEqualTo(1)
    }

    @Test
    fun playsTheSuccessHapticOnceAndALightTapOnDone() {
        show(recordWorkout)
        assertThat(haptics).containsExactly(HapticFeedbackConstants.CONFIRM)
        rule.onNodeWithText("Done").performClick()
        assertThat(haptics).containsExactly(HapticFeedbackConstants.CONFIRM, HapticFeedbackConstants.CLOCK_TICK).inOrder()
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi")
    fun doneStaysPinnedWhileTheContentScrolls() {
        show(ResultFixtures.manyExercisesWorkout())
        rule.onNodeWithText("Done").assertIsDisplayed()
        // The muscle section is below the fold of a 640 dp window until the page is scrolled to its end.
        rule.onNodeWithText("Muscles Worked").assertIsNotDisplayed()
        rule.onNode(hasScrollAction()).performScrollToNode(hasText("Muscles Worked"))
        rule.onNodeWithText("Muscles Worked").assertIsDisplayed()
        rule.onNodeWithText("Done").assertIsDisplayed()
        rule.onNodeWithText("Done").performClick()
        assertThat(doneCount).isEqualTo(1)
    }

    // endregion

    // region Windows

    @Test
    fun theFiguresShareARowOnAPhoneAndStackAtTwiceTheFontSize() {
        show(recordWorkout)
        val duration = rule.onNode(hasContentDescription("Duration, 56 minutes")).getUnclippedBoundsInRoot()
        val volume = rule.onNode(hasContentDescription("Volume, 5,064 kilograms")).getUnclippedBoundsInRoot()
        val sets = rule.onNode(hasContentDescription("Sets, 20")).getUnclippedBoundsInRoot()
        assertThat(volume.top).isEqualTo(duration.top)
        assertThat(sets.top).isEqualTo(duration.top)
        assertThat(volume.left).isGreaterThan(duration.right - 1.dp)
        val heartRate = rule.onNode(hasContentDescription("Avg Heart Rate, 131 beats per minute")).getUnclippedBoundsInRoot()
        // A short last row keeps its columns: the second row starts under the first column.
        assertThat(heartRate.left).isEqualTo(duration.left)
        assertThat(heartRate.top).isGreaterThan(duration.bottom - 1.dp)
    }

    @Test
    @Config(qualifiers = PAGE_PHONE, fontScale = 2.0f)
    fun theFiguresStackInOneColumnAtTwiceTheFontSize() {
        show(recordWorkout)
        val duration = rule.onNode(hasContentDescription("Duration, 56 minutes")).getUnclippedBoundsInRoot()
        val volume = rule.onNode(hasContentDescription("Volume, 5,064 kilograms")).getUnclippedBoundsInRoot()
        assertThat(volume.left).isEqualTo(duration.left)
        assertThat(volume.top).isGreaterThan(duration.bottom - 1.dp)
        rule.onNodeWithText("Done").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = PAGE_SMALL_PHONE, fontScale = 2.0f)
    fun nothingRunsOffTheScreenOnASmallPhoneAtTwiceTheFontSize() {
        show(recordWorkout)
        val texts = listOf("Workout Complete", "Exercises", "Muscles Worked", "Done")
        for (text in texts) {
            val bounds = rule.onNodeWithText(text).getUnclippedBoundsInRoot()
            assertThat(bounds.left.value).isAtLeast(0f)
            assertThat(bounds.right.value).isAtMost(360f)
        }
    }

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun theContentAndTheDoneButtonShareACentredColumnOnATablet() {
        show(recordWorkout)
        val title = rule.onNodeWithText("Workout Complete").getUnclippedBoundsInRoot()
        val done = rule.onNodeWithText("Done").getUnclippedBoundsInRoot()
        // 800 dp window, 640 dp column, 16 dp gutter: the content spans 96...704 dp.
        assertThat(title.left.value).isWithin(1f).of(96f)
        assertThat(done.left.value).isAtLeast(96f)
        assertThat(done.right.value).isAtMost(704f)
        val tile = rule.onNode(hasContentDescription("Sets, 20")).getUnclippedBoundsInRoot()
        assertThat(tile.right.value).isAtMost(704f)
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun theDoneButtonStaysReachableInLandscape() {
        show(recordWorkout)
        rule.onNodeWithText("Done").assertIsDisplayed()
        rule.onNodeWithText("Workout Complete").assertIsDisplayed()
        rule.onNodeWithText("Done").performClick()
        assertThat(doneCount).isEqualTo(1)
    }

    // endregion
}
