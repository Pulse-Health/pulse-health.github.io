package health.pulse.strength.ui.detail

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.Equipment
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.ui.ScreenshotSupport.capture
import health.pulse.strength.ui.ScreenshotSupport.snapshot
import health.pulse.strength.ui.detail.ResultFixtures.library
import health.pulse.strength.ui.detail.ResultFixtures.warmup
import health.pulse.strength.ui.detail.ResultFixtures.work
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** A phone-wide window tall enough for the whole page (2 px per dp keeps the PNG small). */
const val PAGE_PHONE = "w411dp-h2300dp-xhdpi"

/** A 360 dp wide window tall enough for the whole page. */
const val PAGE_SMALL_PHONE = "w360dp-h2600dp-xhdpi"

/**
 * Renders the exercise detail in the states that matter, to be looked at (`app/build/screens/detail-*.png`). The "page" shots
 * use a very tall window so the whole scrolling page is on one image; the "device" shots show what the device shows.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = PAGE_PHONE)
class ExerciseDetailScreenshotTest {
    @get:Rule val rule = createComposeRule()

    @Before fun pinZone() = ResultFixtures.pinTimeZone()

    private fun show(name: String, exercise: Exercise, store: StrengthStore, dark: Boolean = false) {
        val file = rule.snapshot(name, dark = dark) {
            ExerciseDetailScreen(exercise = exercise, store = store, onBack = {})
        }
        assertThat(file.length()).isGreaterThan(1000)
    }

    private fun benchStore(): StrengthStore = ResultFixtures.demoStore()

    /** The end of the page (the page is taller than the window at the biggest font size). */
    private fun captureEnd(name: String) {
        rule.onNode(hasScrollAction()).performScrollToNode(hasText("Demo photos from the Free Exercise DB."))
        rule.waitForIdle()
        assertThat(rule.capture(name).length()).isGreaterThan(1000)
    }

    // region Data states

    @Test
    fun benchWithRecordLight() {
        val store = benchStore()
        show("detail-bench-light", store.exercise("bench")!!, store)
    }

    @Test
    fun benchWithRecordDark() {
        val store = benchStore()
        show("detail-bench-dark", store.exercise("bench")!!, store, dark = true)
    }

    @Test
    fun noHistoryYet() {
        show("detail-empty-weight", library("bench"), ResultFixtures.emptyStore())
    }

    @Test
    fun noHistoryYetDark() {
        show("detail-empty-weight-dark", library("bench"), ResultFixtures.emptyStore(), dark = true)
    }

    @Test
    fun noHistoryBodyweight() {
        show("detail-empty-bodyweight", library("pushup"), ResultFixtures.emptyStore())
    }

    @Test
    fun oneSession() {
        val bench = library("bench")
        val store = ResultFixtures.storeWith(
            ResultFixtures.workout(bench, "Push day", daysAgo = 2.0, sets = listOf(warmup(40.0, 8), work(60.0, 8, 3), work(60.0, 8, 2), work(62.5, 6, 1))),
        )
        show("detail-one-session", bench, store)
    }

    @Test
    fun bodyweightWithSessions() {
        val store = benchStore()
        show("detail-bodyweight", store.exercise("pullup")!!, store)
    }

    @Test
    fun durationExercise() {
        val plank = library("plank")
        val store = ResultFixtures.storeWith(
            ResultFixtures.workout(plank, "Core finisher", daysAgo = 20.0, sets = listOf(work(0.0, 40), work(0.0, 35))),
            ResultFixtures.workout(plank, "Core finisher", daysAgo = 13.0, sets = listOf(work(0.0, 45), work(0.0, 45), work(0.0, 40))),
            ResultFixtures.workout(plank, "Upper A · Push", daysAgo = 6.0, sets = listOf(work(0.0, 60), work(0.0, 50), work(0.0, 45)), isPersonalRecord = true),
        )
        show("detail-duration", plank, store)
    }

    @Test
    fun veryLongName() {
        val custom = Exercise.custom(
            name = "Single-arm landmine press with a staggered stance and a really long name that keeps going",
            muscle = MuscleGroup.SHOULDERS,
            equipment = Equipment.BARBELL,
            tracking = TrackingKind.WEIGHT_REPS,
            id = "custom-long",
        )
        val store = ResultFixtures.storeWith(
            ResultFixtures.workout(
                custom, "Shoulders and a very long workout name that has to wrap onto more than one line", daysAgo = 9.0,
                sets = listOf(work(30.0, 10, 3), work(32.5, 8, 2), work(32.5, 8, 1)), isPersonalRecord = true,
            ),
            ResultFixtures.workout(custom, "Shoulders", daysAgo = 2.0, sets = listOf(work(32.5, 10, 2), work(35.0, 8, 1))),
        )
        store.addCustomExercise(custom)
        show("detail-long-name", store.exercise("custom-long")!!, store)
    }

    @Test
    fun manySessionsExpanded() {
        val bench = library("bench")
        val workouts = (0 until 14).map { index ->
            val kg = 70.0 + index * 1.5 - (if (index % 5 == 4) 4.0 else 0.0)
            ResultFixtures.workout(
                bench, if (index % 2 == 0) "Upper A · Push" else "Chest day", daysAgo = 4.0 + index * 9,
                sets = listOf(warmup(40.0, 8), work(kg, 8, 3), work(kg, 7, 2), work(kg, 6, 1)), isPersonalRecord = index == 13 || index == 9,
            )
        }
        val store = ResultFixtures.storeWith(*workouts.toTypedArray())
        rule.snapshot("detail-many-sessions") { ExerciseDetailScreen(bench, store, onBack = {}) }
        rule.onNodeWithText("See All").performClick()
        // The newest session opens in place and lists its sets.
        rule.onNodeWithText("Jan 8 · Upper A · Push").performClick()
        rule.waitForIdle()
        assertThat(rule.capture("detail-many-sessions-expanded").length()).isGreaterThan(1000)
    }

    // endregion

    // region Font size and window size (whole page)

    @Test
    @Config(qualifiers = PAGE_PHONE, fontScale = 2.0f)
    fun font200Percent() {
        val store = benchStore()
        show("detail-bench-font200", store.exercise("bench")!!, store)
        captureEnd("detail-bench-font200-end")
    }

    @Test
    @Config(qualifiers = PAGE_SMALL_PHONE, fontScale = 2.0f)
    fun font200PercentSmallPhone() {
        val store = benchStore()
        show("detail-bench-font200-small", store.exercise("bench")!!, store)
        captureEnd("detail-bench-font200-small-end")
    }

    @Test
    @Config(qualifiers = PAGE_PHONE, fontScale = 2.0f)
    fun font200PercentEmpty() {
        show("detail-empty-font200", library("bench"), ResultFixtures.emptyStore())
    }

    @Test
    @Config(qualifiers = PAGE_PHONE, fontScale = 1.3f)
    fun font130Percent() {
        val store = benchStore()
        show("detail-bench-font130", store.exercise("bench")!!, store)
    }

    @Test
    @Config(qualifiers = PAGE_SMALL_PHONE)
    fun smallPhonePage() {
        val store = benchStore()
        show("detail-bench-small-page", store.exercise("bench")!!, store)
    }

    // endregion

    // region What a device shows (first screen)

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun devicePhone() {
        val store = benchStore()
        show("detail-device-phone", store.exercise("bench")!!, store)
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi")
    fun deviceSmallPhone() {
        val store = benchStore()
        show("detail-device-small-phone", store.exercise("bench")!!, store)
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun deviceLandscape() {
        val store = benchStore()
        show("detail-device-landscape", store.exercise("bench")!!, store)
    }

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun deviceTablet() {
        val store = benchStore()
        show("detail-device-tablet", store.exercise("bench")!!, store)
    }

    // endregion
}
