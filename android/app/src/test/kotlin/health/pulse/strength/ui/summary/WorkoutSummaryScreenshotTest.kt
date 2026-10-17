package health.pulse.strength.ui.summary

import androidx.compose.ui.test.junit4.v2.createComposeRule
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.SampleData
import health.pulse.strength.ui.ScreenshotSupport.snapshot
import health.pulse.strength.ui.detail.PAGE_PHONE
import health.pulse.strength.ui.detail.PAGE_SMALL_PHONE
import health.pulse.strength.ui.detail.ResultFixtures
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders the workout summary in the states that matter (`app/build/screens/summary-*.png`). "Page" shots use a tall window so the
 * whole scrolling page and the pinned Done bar are on one image; "device" shots show what a device shows.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = PAGE_PHONE)
class WorkoutSummaryScreenshotTest {
    @get:Rule val rule = createComposeRule()

    @Before fun pinZone() = ResultFixtures.pinTimeZone()

    private fun show(name: String, workout: CompletedWorkout, dark: Boolean = false) {
        val file = rule.snapshot(name, dark = dark) { WorkoutSummaryScreen(workout = workout, onDone = {}) }
        assertThat(file.length()).isGreaterThan(1000)
    }

    private val recordWorkout get() = ResultFixtures.demoRecordWorkout()
    private val plainWorkout get() = SampleData.history(ResultFixtures.now).first { it.personalRecords.isEmpty() }

    // region Data states

    @Test fun withRecordLight() = show("summary-record-light", recordWorkout)

    @Test fun withRecordDark() = show("summary-record-dark", recordWorkout, dark = true)

    @Test fun withoutRecord() = show("summary-no-record", plainWorkout)

    @Test
    fun withoutHeartRateOrRir() {
        show("summary-no-hr", recordWorkout.copy(averageHeartRate = null, averageRIR = null))
    }

    @Test
    fun withoutExercises() {
        show("summary-empty", plainWorkout.copy(exercises = emptyList(), muscleSets = emptyList(), personalRecords = emptyList(), loggedSets = 0, volumeKg = 0.0))
    }

    @Test
    fun manyExercises() {
        show("summary-many", ResultFixtures.manyExercisesWorkout(14))
    }

    @Test
    fun longNames() {
        val long = "Single-arm landmine press with a staggered stance and a really long name"
        val base = ResultFixtures.manyExercisesWorkout(5)
        show(
            "summary-long-names",
            base.copy(
                name = "Upper body strength, hypertrophy and a very long workout name",
                exercises = base.exercises.mapIndexed { index, exercise -> if (index % 2 == 0) exercise.copy(name = long) else exercise },
                personalRecords = listOf(PersonalRecord("x", long, 32.5, 8, 41.2, 38.0)),
            ),
        )
    }

    @Test
    fun smallRecord() {
        // A gain that rounds to nothing shows no arrow; a one-rep record reads "1 rep".
        show(
            "summary-record-no-gain",
            recordWorkout.copy(personalRecords = listOf(PersonalRecord("bench", "Barbell bench press", 100.0, 1, 100.0, 99.8))),
        )
    }

    // endregion

    // region Font size

    @Test
    @Config(qualifiers = PAGE_PHONE, fontScale = 2.0f)
    fun font200Percent() = show("summary-font200", recordWorkout)

    @Test
    @Config(qualifiers = PAGE_SMALL_PHONE, fontScale = 2.0f)
    fun font200PercentSmallPhone() = show("summary-font200-small", recordWorkout)

    @Test
    @Config(qualifiers = PAGE_PHONE, fontScale = 1.3f)
    fun font130Percent() = show("summary-font130", recordWorkout)

    // endregion

    // region What a device shows

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun devicePhone() = show("summary-device-phone", recordWorkout)

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi")
    fun deviceSmallPhone() = show("summary-device-small-phone", recordWorkout)

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun deviceLandscape() = show("summary-device-landscape", recordWorkout)

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun deviceTablet() = show("summary-device-tablet", recordWorkout)

    // endregion
}
