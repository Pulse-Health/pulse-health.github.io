package health.pulse.strength.ui.active

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.ui.ScreenshotSupport.capture
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.GraphicsMode

/**
 * The states of the active-workout screen that are rendered to `build/screens/active-<state>-<device>.png`. The concrete subclasses
 * set the device (window size, font scale) through `@Config`, so the same states are checked on every size.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
abstract class ActiveScreenshotScenarios(
    private val device: String,
    /** The system bars of the device, in dp (the cut-out side of a phone held sideways is [leftDp]). */
    private val topDp: Int = 28,
    private val bottomDp: Int = 24,
    private val leftDp: Int = 0,
    private val rightDp: Int = 0,
) {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private fun shot(state: String, fixture: ActiveFixture, dark: Boolean = false, imeDp: Int = 0, openNote: Boolean = false): File {
        val name = "active-$state-$device"
        rule.setContent {
            TestScreenTheme(ClockHandle(), dark) {
                ActiveWorkoutScreen(
                    controller = fixture.controller,
                    store = fixture.store,
                    onMinimise = {},
                    onFinished = {},
                )
            }
        }
        rule.waitForIdle()
        if (openNote) {
            rule.tagged("note-button").performClick()
            rule.waitForIdle()
        }
        rule.applySystemBars(topDp, bottomDp, leftDp, rightDp, imeDp)
        val file = rule.capture(name)
        assertThat(file.length()).isGreaterThan(2000)
        return file
    }

    /** Bench with its warm-ups and a first working set logged (a personal record), resting with the "Reps left" row. */
    private fun typicalFixture(): ActiveFixture {
        val fixture = ActiveFixture()
        val exercise = fixture.exerciseID(0)
        fixture.send(WorkoutAction.SetWeight(exercise, fixture.setID(0, 2), 85.0))
        fixture.log(0, 0..2, secondsAgo = 78)
        fixture.send(WorkoutAction.ToggleLastSetRIR(2))
        return fixture
    }

    @Test
    fun typical() {
        shot("typical", typicalFixture())
    }

    @Test
    fun typicalDark() {
        shot("typical-dark", typicalFixture(), dark = true)
    }

    @Test
    fun noRestWithTipAndNote() {
        val fixture = typicalFixture()
        fixture.send(WorkoutAction.SkipRest)
        fixture.send(WorkoutAction.SetNote(fixture.exerciseID(0), "Seat at 4, pause on the chest"))
        shot("tip", fixture)
    }

    /** The note field is open and the keyboard (280 dp) is up: the dock steps aside and the field stays above the keyboard. */
    @Test
    fun noteWithKeyboard() {
        val fixture = typicalFixture()
        fixture.send(WorkoutAction.SetNote(fixture.exerciseID(0), "Seat at 4"))
        shot("keyboard", fixture, imeDp = 280, openNote = true)
    }

    @Test
    fun empty() {
        shot("empty", ActiveFixture(template = null))
    }

    @Test
    fun paused() {
        val fixture = typicalFixture()
        fixture.send(WorkoutAction.Pause)
        shot("paused", fixture)
    }

    @Test
    fun restFinished() {
        val fixture = ActiveFixture()
        fixture.log(0, 0..2, secondsAgo = 160)
        shot("rest-finished", fixture)
    }

    @Test
    fun longList() {
        val fixture = ActiveFixture()
        val exercise = fixture.exerciseID(1)
        repeat(8) { fixture.send(WorkoutAction.AddSet(exercise)) }
        fixture.send(WorkoutAction.GoTo(1))
        fixture.log(1, 0..4, secondsAgo = 20)
        shot("long", fixture)
    }

    @Test
    fun undoToast() {
        val fixture = typicalFixture()
        fixture.send(WorkoutAction.RemoveExercise(fixture.exerciseID(5)))
        shot("undo", fixture)
    }

    @Test
    fun superset() {
        val fixture = ActiveFixture()
        fixture.send(WorkoutAction.GoTo(3))
        shot("superset", fixture)
    }
}
