package health.pulse.strength.ui.hub

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performTextInput
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
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import health.pulse.strength.ui.theme.PulseTheme
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Screenshots of the hub on a normal phone (411 × 891 dp). The "tall" ones use a very high window so the whole scrolling page is in
 * one picture. PNGs are written to `app/build/screens/hub-*.png`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class HubScreenshotTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    @Before fun setUp() = fixLocale()

    private fun show(env: StrengthAppEnvironment = HubTestSupport.environment(), dark: Boolean = false) {
        rule.setHub(env, dark = dark)
        rule.waitForIdle()
    }

    private fun shot(name: String) {
        assertThat(rule.capture(name).length()).isGreaterThan(1000)
    }

    /** Templates and a library exercise with names that do not fit one line anywhere; the long template is the recommended one. */
    private fun longNamesEnvironment(): StrengthAppEnvironment {
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

    // region Home

    @Test
    @Config(qualifiers = "w411dp-h1900dp-xhdpi")
    fun homeDemoTall() {
        show()
        shot("hub-home-demo-tall")
    }

    @Test
    fun homeDemoPhone() {
        show()
        shot("hub-home-demo-phone")
    }

    @Test
    @Config(qualifiers = "w411dp-h1900dp-xhdpi")
    fun homeEmptyTall() {
        show(HubTestSupport.environment(seed = false))
        shot("hub-home-empty-tall")
    }

    @Test
    fun homeEmptyPhone() {
        show(HubTestSupport.environment(seed = false))
        shot("hub-home-empty-phone")
    }

    @Test
    @Config(qualifiers = "w411dp-h1900dp-xhdpi")
    fun homeWorkoutInProgressTall() {
        show(HubTestSupport.environment(withActiveWorkout = true))
        shot("hub-home-running-tall")
    }

    @Test
    @Config(qualifiers = "w411dp-h1900dp-xhdpi")
    fun homeLongNamesTall() {
        show(longNamesEnvironment())
        shot("hub-home-longnames-tall")
    }

    @Test
    @Config(qualifiers = "w411dp-h1900dp-xhdpi")
    fun homeDemoDarkTall() {
        show(dark = true)
        shot("hub-home-demo-dark-tall")
    }

    @Test
    @Config(qualifiers = "w411dp-h1900dp-xhdpi")
    fun homeEmptyDarkTall() {
        show(HubTestSupport.environment(seed = false), dark = true)
        shot("hub-home-empty-dark-tall")
    }


    // endregion

    // region Pushed screens

    @Test
    fun templateList() {
        show()
        rule.clickDescription("See All Templates")
        shot("hub-templates")
    }

    @Test
    fun templateDetail() {
        show()
        rule.clickTemplate("Upper A · Push")
        shot("hub-template-detail")
    }

    @Test
    fun templateDetailEmptyAndRunning() {
        val env = HubTestSupport.environment(seed = false)
        env.store.saveTemplate(WorkoutTemplate(name = "Empty plan", entries = emptyList()))
        show(env)
        rule.clickDescription("See All Templates")
        shot("hub-templates-empty-plan")
        rule.clickTemplate("Empty plan")
        shot("hub-template-detail-no-exercises")
    }

    @Test
    fun templateListLongNames() {
        show(longNamesEnvironment())
        rule.clickDescription("See All Templates")
        shot("hub-templates-longnames")
    }

    @Test
    fun templateDetailRunning() {
        show(HubTestSupport.environment(withActiveWorkout = true))
        rule.clickTemplate("Upper A · Push")
        shot("hub-template-detail-running")
    }

    @Test
    fun library() {
        show()
        rule.clickText("Exercise Library")
        shot("hub-library")
        rule.onAllNodesFirstTextField().performTextInput("press")
        rule.waitForIdle()
        shot("hub-library-search")
    }

    @Test
    fun libraryLongNameAndNoResult() {
        show(longNamesEnvironment())
        rule.clickText("Exercise Library")
        rule.onAllNodesFirstTextField().performTextInput("single")
        rule.waitForIdle()
        shot("hub-library-longname")
        rule.onAllNodesFirstTextField().performTextInput("zzz")
        rule.waitForIdle()
        shot("hub-library-noresult")
    }

    @Test
    fun history() {
        show()
        rule.clickDescription("See All Recent Workouts")
        shot("hub-history")
    }

    @Test
    @Config(qualifiers = "w411dp-h1500dp-xhdpi")
    fun workoutDetailWithRecord() {
        show()
        rule.clickDescription("See All Recent Workouts")
        rule.clickText("1 PR")
        shot("hub-workout-detail-pr")
    }

    @Test
    fun recovery() {
        show()
        rule.clickDescription("View All Muscle Recovery")
        shot("hub-recovery")
    }

    @Test
    fun recoveryLow() {
        val env = HubTestSupport.environment(recovery = { muscle -> when (muscle) { MuscleGroup.CHEST -> 12; MuscleGroup.BACK -> 55; MuscleGroup.LEGS -> 60; else -> 100 } })
        show(env)
        shot("hub-home-recovery-low")
        rule.clickDescription("View All Muscle Recovery")
        shot("hub-recovery-low")
    }

    @Test
    fun settingsPlaceholder() {
        show()
        rule.clickDescription("Settings")
        shot("hub-settings-route")
    }

    // endregion

    // region Sheets (their content rendered inside a faux sheet over the scrimmed hub)

    private fun showSheet(env: StrengthAppEnvironment, dark: Boolean = false, container: Color? = null, content: @Composable () -> Unit) {
        rule.setPulseContent(dark) {
            HubTestSupport.SheetPreview(
                container = container ?: PulseTheme.colors.ground,
                background = { StrengthHubScreen(env, {}, {}) },
                content = content,
            )
        }
        rule.waitForIdle()
    }

    @Test
    fun editorNewEmpty() {
        showSheet(HubTestSupport.environment()) {
            HubTemplateEditorContent(isNew = true, draft = HubEditorDraft("", emptyList()), onCancel = {}, onSave = {}, onAddExercises = {})
        }
        shot("hub-editor-new-empty")
    }

    @Test
    fun editorEditsDemoTemplate() {
        val env = HubTestSupport.environment()
        val template = env.store.templates.first()
        showSheet(env) {
            HubTemplateEditorContent(
                isNew = false,
                draft = HubEditorDraft(template.name, template.entries),
                onCancel = {}, onSave = {}, onAddExercises = {},
            )
        }
        shot("hub-editor-edit")
    }

    @Test
    fun editorDark() {
        val env = HubTestSupport.environment()
        val template = env.store.templates.first()
        showSheet(env, dark = true) {
            HubTemplateEditorContent(isNew = false, draft = HubEditorDraft(template.name, template.entries.take(3)), onCancel = {}, onSave = {}, onAddExercises = {})
        }
        shot("hub-editor-edit-dark")
    }

    @Test
    fun editorLongNames() {
        val env = longNamesEnvironment()
        val template = env.store.templates.first()
        showSheet(env) {
            HubTemplateEditorContent(isNew = false, draft = HubEditorDraft(template.name, template.entries), onCancel = {}, onSave = {}, onAddExercises = {})
        }
        shot("hub-editor-longnames")
    }

    @Test
    fun chooserWithSelection() {
        val env = HubTestSupport.environment()
        val results = ExerciseLibrary.filter(env.store.exercises, "", null, null)
        showSheet(env, container = null) {
            HubExerciseChooserContent(
                results = results,
                query = "",
                onQueryChange = {},
                selected = listOf("squat", "bench"),
                onToggle = {},
                onCancel = {},
                onConfirm = {},
            )
        }
        shot("hub-chooser")
    }

    @Test
    fun chooserNoResult() {
        showSheet(HubTestSupport.environment()) {
            HubExerciseChooserContent(results = emptyList(), query = "zzz", onQueryChange = {}, selected = emptyList(), onToggle = {}, onCancel = {}, onConfirm = {})
        }
        shot("hub-chooser-noresult")
    }

    // endregion

    private fun androidx.compose.ui.test.junit4.ComposeContentTestRule.onAllNodesFirstTextField() =
        onAllNodes(hasSetTextAction()).onFirst()
}
