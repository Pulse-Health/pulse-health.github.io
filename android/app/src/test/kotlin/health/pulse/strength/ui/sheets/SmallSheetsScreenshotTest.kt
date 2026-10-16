package health.pulse.strength.ui.sheets

import androidx.compose.ui.test.junit4.v2.createComposeRule
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.Equipment
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.SetType
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.ScreenshotSupport.snapshot
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Photographs the set detail, rest timer and form sheets (`build/screens/setdetail-*.png`, `rest-*.png`, `form-*.png`). */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SmallSheetsScreenshotTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()

    // region Set detail

    private fun shootSetDetail(name: String, dark: Boolean = false) {
        val ref = fixture.ref(0, 2)
        fixture.controller.send(WorkoutAction.SetSetType(ref.exerciseID, ref.setID, SetType.DROP))
        fixture.controller.send(WorkoutAction.SetRIR(ref.exerciseID, ref.setID, 2))
        val file = rule.snapshot(name, dark) {
            SheetFrame(fullHeight = false) { SetDetailSheetContent(fixture.controller, ref, onDone = {}) }
        }
        assertThat(file.length()).isGreaterThan(1000)
    }

    @Test
    fun setDetail() = shootSetDetail("setdetail")

    @Test
    fun setDetailDark() = shootSetDetail("setdetail-dark", dark = true)

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun setDetailLandscape() = shootSetDetail("setdetail-landscape")

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun setDetailSmallFont200() = shootSetDetail("setdetail-small-font-200")

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun setDetailTablet() = shootSetDetail("setdetail-tablet")

    // endregion

    // region Rest

    private fun shootRest(name: String, dark: Boolean = false) {
        val id = fixture.exercises[0].id
        val file = rule.snapshot(name, dark) {
            SheetFrame(fullHeight = false) { RestSettingsSheetContent(fixture.controller, id, onDone = {}) }
        }
        assertThat(file.length()).isGreaterThan(1000)
    }

    @Test
    fun rest() = shootRest("rest")

    @Test
    fun restDark() {
        fixture.controller.send(WorkoutAction.SetAlertWhenRestEnds(false))
        shootRest("rest-dark", dark = true)
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun restLandscape() = shootRest("rest-landscape")

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun restSmallFont200() = shootRest("rest-small-font-200")

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun restTablet() = shootRest("rest-tablet")

    // endregion

    // region Form

    private fun shootForm(name: String, exercise: Exercise, withHistory: Boolean = true, dark: Boolean = false) {
        val file = rule.snapshot(name, dark) {
            SheetFrame(fullHeight = true) {
                FormInfoSheetContent(exercise, onShowHistory = if (withHistory) ({}) else null, onDone = {})
            }
        }
        assertThat(file.length()).isGreaterThan(1000)
    }

    private val bench = ExerciseLibrary.exercise("bench")!!

    @Test
    fun form() = shootForm("form", bench)

    @Test
    fun formDark() = shootForm("form-dark", bench, dark = true)

    @Test
    fun formWithoutHistoryOrDemo() = shootForm(
        "form-custom",
        Exercise.custom("Landmine press", MuscleGroup.SHOULDERS, Equipment.OTHER, TrackingKind.WEIGHT_REPS),
        withHistory = false,
    )

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun formLandscape() = shootForm("form-landscape", bench)

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun formSmallFont200() = shootForm("form-small-font-200", bench)

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun formTablet() = shootForm("form-tablet", bench)

    // endregion
}
