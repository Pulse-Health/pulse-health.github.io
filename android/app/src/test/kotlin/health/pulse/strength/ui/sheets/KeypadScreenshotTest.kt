package health.pulse.strength.ui.sheets

import androidx.compose.ui.test.junit4.v2.createComposeRule
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.KeypadField
import health.pulse.strength.ui.ScreenshotSupport.snapshot
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Photographs the keypad sheet's content (`build/screens/keypad-*.png`). */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class KeypadScreenshotTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()

    private fun shoot(name: String, field: KeypadField, exerciseIndex: Int = 0, setIndex: Int = 2, dark: Boolean = false) {
        val ref = fixture.ref(exerciseIndex, setIndex)
        val file = rule.snapshot(name, dark) {
            SheetFrame(fullHeight = false) {
                KeypadSheetContent(fixture.controller, ref, field, onDone = {})
            }
        }
        assertThat(file.length()).isGreaterThan(1000)
    }

    @Test
    fun weightField() = shoot("keypad-weight", KeypadField.WEIGHT)

    @Test
    fun repsField() {
        fixture.controller.send(WorkoutAction.SetWeight(fixture.ref(0, 2).exerciseID, fixture.ref(0, 2).setID, 102.5))
        shoot("keypad-reps", KeypadField.REPS)
    }

    @Test
    fun dark() = shoot("keypad-weight-dark", KeypadField.WEIGHT, dark = true)

    @Test
    fun loggedSetShowsDone() {
        fixture.controller.send(WorkoutAction.LogSet(fixture.ref(0, 2).exerciseID, fixture.ref(0, 2).setID))
        shoot("keypad-logged", KeypadField.REPS)
    }

    @Test
    fun dumbbellWithoutPlates() = shoot("keypad-dumbbell", KeypadField.WEIGHT, exerciseIndex = 1, setIndex = 0)

    @Test
    fun heavyBarbellWithManyPlates() {
        val ref = fixture.ref(0, 2)
        fixture.controller.send(WorkoutAction.SetWeight(ref.exerciseID, ref.setID, 187.75))
        shoot("keypad-many-plates", KeypadField.WEIGHT)
    }

    @Test
    fun bodyweightDuration() {
        val plank = ExerciseLibrary.exercise("plank")!!
        fixture.controller.send(WorkoutAction.AddExercises(listOf(plank)))
        shoot("keypad-duration", KeypadField.WEIGHT, exerciseIndex = fixture.exercises.lastIndex, setIndex = 0)
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi")
    fun smallPhone() = shoot("keypad-small-phone", KeypadField.WEIGHT)

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun landscape() = shoot("keypad-landscape", KeypadField.WEIGHT)

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun tablet() = shoot("keypad-tablet", KeypadField.WEIGHT)

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2.0f)
    fun fontScale200() = shoot("keypad-font-200", KeypadField.WEIGHT)

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun smallPhoneFontScale200() = shoot("keypad-small-phone-font-200", KeypadField.WEIGHT)

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi", fontScale = 1.3f)
    fun landscapeLargeFont() = shoot("keypad-landscape-font-130", KeypadField.REPS)
}
