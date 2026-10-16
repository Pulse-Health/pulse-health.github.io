package health.pulse.strength.ui.hub

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.Equipment
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.SampleData
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.ui.ScreenshotSupport.capture
import health.pulse.strength.ui.hub.HubTestSupport.clickDescription
import health.pulse.strength.ui.hub.HubTestSupport.clickTemplate
import health.pulse.strength.ui.hub.HubTestSupport.clickText
import health.pulse.strength.ui.hub.HubTestSupport.fixLocale
import health.pulse.strength.ui.hub.HubTestSupport.setHub
import health.pulse.strength.ui.hub.HubTestSupport.setPulseContent
import health.pulse.strength.ui.theme.PulseTheme
import org.junit.Before
import org.junit.Rule
import org.junit.Test

/** What the screenshot classes of the different window sizes share: setup, fixtures and the capture of a named picture. */
abstract class HubShotsCore(private val tag: String) {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    @Before fun setUp() = fixLocale()

    protected fun show(env: StrengthAppEnvironment = HubTestSupport.environment(), dark: Boolean = false) {
        rule.setHub(env, dark = dark)
        rule.waitForIdle()
    }

    protected fun shot(name: String) {
        assertThat(rule.capture("hub-$name-$tag").length()).isGreaterThan(1000)
    }

    protected fun showSheet(env: StrengthAppEnvironment, dark: Boolean = false, plain: Boolean = false, content: @Composable () -> Unit) {
        rule.setPulseContent(dark) {
            HubTestSupport.SheetPreview(
                container = if (plain) PulseTheme.colors.card else PulseTheme.colors.ground,
                background = { StrengthHubScreen(env, {}, {}) },
                content = content,
            )
        }
        rule.waitForIdle()
    }

    /** The recommended template has a very long name, one of its exercises too; the demo history is there. */
    protected fun longNamesEnvironment(): StrengthAppEnvironment {
        val env = HubTestSupport.environment(seed = false)
        val longExercise = Exercise.custom(
            name = "Single-arm cable high-to-low chest fly with a long pause at the bottom",
            muscle = MuscleGroup.CHEST,
            equipment = Equipment.CABLE,
            tracking = TrackingKind.WEIGHT_REPS,
        )
        env.store.addCustomExercise(longExercise)
        val long = WorkoutTemplate(
            name = "Upper body strength and hypertrophy block, week three: heavy singles then back-off volume",
            entries = listOf("bench", "ohp", "dbrow").map { HubEditorDraft.makeEntry(ExerciseLibrary.exercise(it)!!) } +
                HubEditorDraft.makeEntry(longExercise),
        )
        env.store.saveTemplate(long)
        for (template in SampleData.templates()) env.store.saveTemplate(template)
        // The demo workouts were done oldest first; the most recent one is the last template, so the rotation wraps to the long one.
        for (workout in SampleData.history(HubTestSupport.demoNow).reversed()) env.store.record(workout, null)
        return env
    }
}

/** The pictures of the tall variants: the whole scrolling page of the main screens in one window. */
abstract class HubTallShotsBase(tag: String) : HubShotsCore(tag) {
    @Test fun home() {
        show()
        shot("home")
    }

    @Test fun homeEmpty() {
        show(HubTestSupport.environment(seed = false))
        shot("home-empty")
    }

    @Test fun homeLongNames() {
        show(longNamesEnvironment())
        shot("home-longnames")
    }

    @Test fun workoutDetail() {
        show()
        rule.clickDescription("See All Recent Workouts")
        rule.clickText("1 PR")
        shot("workout-detail")
    }
}

/** The pictures of the real-size variants: what the user sees, including the bottom of the scrolled home screen. */
abstract class HubShotsBase(tag: String) : HubShotsCore(tag) {
    @Test fun home() {
        show()
        shot("home")
    }

    @Test fun homeBottom() {
        show()
        rule.onNodeWithText("Exercise Library").performScrollTo()
        rule.waitForIdle()
        shot("home-bottom")
    }

    @Test fun homeEmpty() {
        show(HubTestSupport.environment(seed = false))
        shot("home-empty")
    }

    @Test fun homeDark() {
        show(dark = true)
        shot("home-dark")
    }

    @Test fun templateList() {
        show()
        rule.clickDescription("See All Templates")
        shot("templates")
    }

    @Test fun templateDetail() {
        show()
        rule.clickTemplate("Upper A · Push")
        shot("template-detail")
    }

    @Test fun library() {
        show()
        rule.clickText("Exercise Library")
        shot("library")
    }

    @Test fun workoutDetail() {
        show()
        rule.clickDescription("See All Recent Workouts")
        rule.clickText("1 PR")
        shot("workout-detail")
    }

    @Test fun recovery() {
        show()
        rule.clickDescription("View All Muscle Recovery")
        shot("recovery")
    }

    @Test fun editor() {
        val env = HubTestSupport.environment()
        val template = env.store.templates.first()
        showSheet(env) {
            HubTemplateEditorContent(isNew = false, draft = HubEditorDraft(template.name, template.entries), onCancel = {}, onSave = {}, onAddExercises = {})
        }
        shot("editor")
    }

    @Test fun chooser() {
        val env = HubTestSupport.environment()
        showSheet(env, plain = true) {
            HubExerciseChooserContent(
                results = ExerciseLibrary.filter(env.store.exercises, "", null, null),
                query = "",
                onQueryChange = {},
                selected = listOf("squat", "bench"),
                onToggle = {},
                onCancel = {},
                onConfirm = {},
            )
        }
        shot("chooser")
    }
}
