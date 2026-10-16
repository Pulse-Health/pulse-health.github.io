package health.pulse.strength.ui.sheets

import androidx.compose.ui.test.junit4.v2.createComposeRule
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.ScreenshotSupport.snapshot
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Photographs the exercise list and the options (`build/screens/list-*.png`, `options-*.png`). */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ListScreenshotTest {
    @get:Rule val rule = createComposeRule()

    private val fixture = SheetFixture()

    private fun shootList(name: String, dark: Boolean = false) {
        val file = rule.snapshot(name, dark) {
            SheetFrame(fullHeight = true) { ExerciseListSheetContent(fixture.controller, fixture.store, onDone = {}) }
        }
        assertThat(file.length()).isGreaterThan(1000)
    }

    private fun progress() {
        // Bench: three sets logged; the second exercise is the current one.
        for (i in 0..2) fixture.ref(0, i).let { fixture.controller.send(WorkoutAction.LogSet(it.exerciseID, it.setID)) }
        fixture.controller.send(WorkoutAction.GoTo(1))
    }

    private fun addMany() {
        val extra = ExerciseLibrary.builtIn.filter { library -> fixture.exercises.none { it.exercise.id == library.id } }.take(8)
        fixture.controller.send(WorkoutAction.AddExercises(extra))
    }

    @Test
    fun typical() {
        progress()
        shootList("list-typical")
    }

    @Test
    fun dark() {
        progress()
        shootList("list-dark", dark = true)
    }

    @Test
    fun longWorkout() {
        progress()
        addMany()
        shootList("list-long")
    }

    @Test
    fun emptyWorkout() {
        fixture.exercises.map { it.id }.forEach { fixture.controller.send(WorkoutAction.RemoveExercise(it)) }
        shootList("list-empty")
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi")
    fun smallPhone() {
        progress()
        shootList("list-small-phone")
    }

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun landscape() {
        progress()
        shootList("list-landscape")
    }

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun tablet() {
        progress()
        shootList("list-tablet")
    }

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2.0f)
    fun fontScale200() {
        progress()
        shootList("list-font-200")
    }

    // region Options

    private fun shootOptions(name: String, index: Int, dark: Boolean = false) {
        val context = ExerciseOptionsContext.of(fixture.controller.state.value, fixture.exercises[index].id)!!
        val file = rule.snapshot(name, dark) {
            SheetFrame(fullHeight = false) { ExerciseOptionsContent(context, onAction = {}) }
        }
        assertThat(file.length()).isGreaterThan(1000)
    }

    @Test
    fun optionsMiddle() = shootOptions("options-middle", 1)

    @Test
    fun optionsSupersetMemberDark() = shootOptions("options-superset-dark", 3, dark = true)

    @Test
    fun optionsFirst() = shootOptions("options-first", 0)

    @Test
    @Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
    fun optionsLandscape() = shootOptions("options-landscape", 1)

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
    fun optionsFontScale200() = shootOptions("options-small-font-200", 1)

    // endregion
}
