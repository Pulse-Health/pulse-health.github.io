package health.pulse.strength

import android.Manifest
import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.WorkoutAction
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The real activity, started the way the system starts it: a tap on the ongoing notification and the `pulse-strength://workout` link
 * must show the running workout even when the activity (and the process) did not exist before, which is when the request is made
 * before the first composition.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class MainActivityTest {
    @get:Rule
    val rule = createEmptyComposeRule()

    private lateinit var app: PulseStrengthApplication

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext<Application>() as PulseStrengthApplication
        // The notification permission prompt of the first workout is not what is under test.
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun startWorkout() {
        val controller = app.environment.controller
        controller.startWorkout(null, "Push day")
        controller.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("bench")!!)))
    }

    private fun launch(intent: Intent): ActivityScenario<MainActivity> {
        val scenario = ActivityScenario.launch<MainActivity>(intent)
        rule.waitForIdle()
        return scenario
    }

    private fun activeScreens() = rule.onAllNodesWithTag("active-title", useUnmergedTree = true)
    private fun bars() = rule.onAllNodesWithTag("in-progress-bar", useUnmergedTree = true)

    @Test
    fun aTapOnTheOngoingNotificationShowsTheWorkoutWhenTheActivityIsCreated() {
        startWorkout()
        launch(Intent(app, MainActivity::class.java).putExtra(MainActivity.EXTRA_OPEN_WORKOUT, true)).use {
            activeScreens().assertCountEquals(1)
            bars().assertCountEquals(0)
        }
        // Consumed: nothing is left that would open the workout again.
        assertThat(app.environment.openWorkoutRequested.value).isFalse()
    }

    @Test
    fun theDeepLinkShowsTheWorkoutWhenTheActivityIsCreated() {
        startWorkout()
        launch(Intent(Intent.ACTION_VIEW, Uri.parse("pulse-strength://workout")).setClass(app, MainActivity::class.java)).use {
            activeScreens().assertCountEquals(1)
        }
    }

    @Test
    fun aPlainLaunchShowsTheHubWithTheResumeBar() {
        startWorkout()
        launch(Intent(app, MainActivity::class.java)).use {
            activeScreens().assertCountEquals(0)
            bars().assertCountEquals(1)
        }
    }

    @Test
    fun aLinkForAnotherHostDoesNothing() {
        startWorkout()
        launch(Intent(Intent.ACTION_VIEW, Uri.parse("pulse-strength://somewhere-else")).setClass(app, MainActivity::class.java)).use {
            activeScreens().assertCountEquals(0)
        }
    }

    @Test
    fun theRequestOfAnActivityThatIsAlreadyRunningShowsTheWorkoutToo() {
        startWorkout()
        launch(Intent(app, MainActivity::class.java)).use { scenario ->
            activeScreens().assertCountEquals(0)
            scenario.onActivity { activity ->
                val intent = Intent(app, MainActivity::class.java).putExtra(MainActivity.EXTRA_OPEN_WORKOUT, true)
                androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().callActivityOnNewIntent(activity, intent)
            }
            rule.waitForIdle()
            activeScreens().assertCountEquals(1)
        }
    }

    @Test
    fun withoutAWorkoutTheRequestIsDroppedAndTheHubShows() {
        launch(Intent(app, MainActivity::class.java).putExtra(MainActivity.EXTRA_OPEN_WORKOUT, true)).use {
            activeScreens().assertCountEquals(0)
        }
        assertThat(app.environment.openWorkoutRequested.value).isFalse()
    }
}
