package health.pulse.strength.ui.hub

import androidx.activity.ComponentActivity
import androidx.activity.ComponentDialog
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.saveable.LocalSaveableStateRegistry
import androidx.compose.runtime.saveable.SaveableStateRegistry
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.hasScrollToIndexAction
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.assertTextEquals
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.RecoveryModel
import health.pulse.strength.core.SampleData
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.PulseClock
import health.pulse.strength.ui.hub.HubTestSupport.fixLocale
import health.pulse.strength.ui.hub.HubTestSupport.setHub
import health.pulse.strength.ui.theme.PulseTheme
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowDialog

/** The hub on a phone with a real store and controller: navigation, back handling, starting, resuming and editing templates. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class HubScreenTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private val started = mutableListOf<WorkoutTemplate?>()
    private var resumed = 0

    @Before fun setUp() = fixLocale()

    private fun show(env: StrengthAppEnvironment = HubTestSupport.environment()) {
        rule.setHub(env, onStart = { started.add(it) }, onResume = { resumed += 1 })
        rule.waitForIdle()
    }

    private fun pressBack() {
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.waitForIdle()
    }

    private fun backIsHandled(): Boolean {
        var handled = false
        rule.runOnUiThread { handled = rule.activity.onBackPressedDispatcher.hasEnabledCallbacks() }
        return handled
    }

    /** The home screen is showing: its "Start Empty Workout" row exists (no pushed screen has one). */
    private fun assertOnHome() {
        rule.onNodeWithText("Start Empty Workout").assertExists()
    }

    private fun SemanticsNodeInteraction.scrollIfNeeded(): SemanticsNodeInteraction {
        val visible = runCatching { assertIsDisplayed() }.isSuccess
        return if (visible) this else performScrollTo()
    }

    private fun click(text: String) {
        rule.onNodeWithText(text).scrollIfNeeded().performClick()
        rule.waitForIdle()
    }

    private fun clickDescription(description: String) {
        rule.onNodeWithContentDescription(description).scrollIfNeeded().performClick()
        rule.waitForIdle()
    }

    /** A template row of the hub or of "See All" (the name alone also matches the recent workouts of the same name). */
    private fun clickTemplate(name: String) {
        rule.onNode(hasClickAction() and hasText(name) and hasText("exercises", substring = true)).scrollIfNeeded().performClick()
        rule.waitForIdle()
    }

    /** The name field of the editor (the first text field; the chooser's search field comes after it). */
    private fun typeTemplateName(name: String) {
        rule.onAllNodes(hasSetTextAction()).onFirst().performTextInput(name)
        rule.waitForIdle()
    }

    /** Selects an exercise in the chooser by searching for it (the list is lazy, most rows are not composed). */
    private fun choose(name: String) {
        rule.onAllNodes(hasSetTextAction()).onLast().performTextReplacement(name)
        rule.waitForIdle()
        rule.onNode(hasClickAction() and hasText(name) and hasSetTextAction().not()).performClick()
        rule.waitForIdle()
    }

    /** A tap on the dimmed area beside the open sheet (the scrim has no place the test could tap, so it is clicked as an action). */
    private fun tapOutsideTheSheet() {
        rule.onNodeWithContentDescription("Close sheet").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
    }

    /** The back button, delivered to the window of the open sheet (a question shown above it would get the latest dialog). */
    private fun pressBackInTheSheet() {
        rule.runOnUiThread {
            val sheet = ShadowDialog.getShownDialogs().last { it.isShowing && it.javaClass.simpleName == "ModalBottomSheetDialogWrapper" }
            (sheet as ComponentDialog).onBackPressedDispatcher.onBackPressed()
        }
        rule.waitForIdle()
    }

    /** A fast drag down on the title of the open sheet, far enough to throw the sheet off the screen. */
    private fun swipeTheSheetDown(titleText: String) {
        rule.onNodeWithText(titleText).performTouchInput { swipe(start = center, end = center.copy(y = center.y + 1200f), durationMillis = 120) }
        rule.waitForIdle()
    }

    private fun assertAsksToDiscard() {
        rule.onNodeWithText("Discard changes?").assertIsDisplayed()
        rule.onNodeWithText("Save").assertIsDisplayed() // the editor is still behind the question
    }

    // region Starting and resuming

    @Test
    fun startEmptyWorkoutCallsOnStartWithNull() {
        show()
        click("Start Empty Workout")
        assertThat(started).containsExactly(null)
        assertThat(resumed).isEqualTo(0)
    }

    @Test
    fun recommendedCardStartsTheNextTemplateInTheRotation() {
        show()
        // Upper B was done most recently, so the rotation wraps to Upper A.
        rule.onNodeWithText("Today · Recommended").assertIsDisplayed()
        click("Start Workout")
        assertThat(started.map { it?.name }).containsExactly("Upper A · Push")
    }

    @Test
    fun runningWorkoutOfTheRecommendedTemplateReadsResume() {
        val env = HubTestSupport.environment(withActiveWorkout = true) // starts the first template, Upper A, which is recommended
        show(env)
        rule.onNodeWithText("Start Workout").assertDoesNotExist()
        click("Resume Workout")
        assertThat(resumed).isEqualTo(1)
        assertThat(started).isEmpty()
    }

    @Test
    fun startingAnotherWorkoutWhileOneRunsAsksAndOffersResume() {
        val env = HubTestSupport.environment(withActiveWorkout = true)
        show(env)
        click("Start Empty Workout")
        rule.onNodeWithText("Workout in progress").assertIsDisplayed()
        rule.onNodeWithText("Finish or discard Upper A · Push before starting another workout.").assertIsDisplayed()
        assertThat(started).isEmpty()
        click("Cancel")
        rule.onNodeWithText("Workout in progress").assertDoesNotExist()
        assertThat(resumed).isEqualTo(0)
        click("Start Empty Workout")
        click("Resume")
        rule.onNodeWithText("Workout in progress").assertDoesNotExist()
        assertThat(resumed).isEqualTo(1)
        assertThat(started).isEmpty()
    }

    @Test
    fun anotherTemplateWhileOneRunsIsRefusedAndItsOwnDetailReadsResume() {
        val env = HubTestSupport.environment()
        val lower = env.store.templates[1]
        env.controller.startWorkout(lower) // Lower A runs; the card recommends Upper A
        show(env)
        click("Start Workout")
        rule.onNodeWithText("Finish or discard Lower A · Quads before starting another workout.").assertIsDisplayed()
        click("Cancel")
        assertThat(started).isEmpty()
        // The template screen of the running workout offers Resume, the others Start (which is refused).
        clickTemplate("Lower A · Quads")
        click("Resume Workout")
        assertThat(resumed).isEqualTo(1)
        pressBack()
        clickTemplate("Upper B · Pull")
        click("Start Workout")
        rule.onNodeWithText("Workout in progress").assertIsDisplayed()
        assertThat(started).isEmpty()
    }

    @Test
    fun dialogClosesWhenTheRunningWorkoutEnds() {
        val env = HubTestSupport.environment(withActiveWorkout = true)
        show(env)
        click("Start Empty Workout")
        rule.onNodeWithText("Workout in progress").assertIsDisplayed()
        rule.runOnUiThread { env.controller.discard() }
        rule.waitForIdle()
        rule.onNodeWithText("Workout in progress").assertDoesNotExist()
        click("Start Workout") // the card is a plain Start again
        assertThat(started).hasSize(1)
    }

    @Test
    fun startingFromATemplateScreenReturnsTheHubToItsHome() {
        show()
        clickTemplate("Lower A · Quads")
        rule.onNodeWithText("Start Workout").assertIsDisplayed()
        click("Start Workout")
        assertThat(started.map { it?.name }).containsExactly("Lower A · Quads")
        assertOnHome() // minimising the workout later must not land on the template screen
        assertThat(backIsHandled()).isFalse()
    }

    @Test
    fun moreMenuOffersTheThreeShortcuts() {
        show()
        clickDescription("More")
        // Each shortcut is also a row or a section of the home screen, so every text exists twice while the menu is open.
        for (item in listOf("Start Empty Workout", "New Template", "Exercise Library")) rule.onAllNodesWithText(item).assertCountEquals(2)
        // The menu entry starts the workout (the row below has the same text, so take the one with the menu's icon).
        rule.onAllNodesWithText("Start Empty Workout")[1].performClick()
        rule.waitForIdle()
        assertThat(started).containsExactly(null)
        clickDescription("More")
        rule.onAllNodesWithText("Exercise Library")[1].performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Search exercises").assertIsDisplayed()
        pressBack()
        clickDescription("More")
        rule.onAllNodesWithText("New Template")[1].performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Save").assertIsNotEnabled()
    }

    // endregion

    // region Navigation and back

    @Test
    fun backIsNotHandledAtTheHomeScreenAndPopsOneScreenElsewhere() {
        show()
        assertThat(backIsHandled()).isFalse()
        clickDescription("See All Templates")
        assertThat(backIsHandled()).isTrue()
        rule.onNodeWithText("Today · Recommended").assertDoesNotExist()
        clickTemplate("Lower A · Quads")
        rule.onNodeWithText("Start Workout").assertIsDisplayed()
        pressBack() // detail -> list
        rule.onNodeWithText("Start Workout").assertDoesNotExist()
        rule.onNodeWithText("Lower A · Quads").assertIsDisplayed()
        assertThat(backIsHandled()).isTrue()
        pressBack() // list -> home
        assertOnHome()
        rule.onNodeWithText("Today · Recommended").assertIsDisplayed()
        assertThat(backIsHandled()).isFalse()
    }

    @Test
    fun topBarBackArrowPopsToo() {
        show()
        clickDescription("View All Muscle Recovery")
        rule.onNodeWithText("Muscle Recovery").assertIsDisplayed()
        clickDescription("Back")
        assertOnHome()
    }

    @Test
    fun settingsGearOpensSettingsInsideTheHubStack() {
        show()
        clickDescription("Settings")
        rule.onNodeWithText("Settings").assertIsDisplayed() // the lead's screen (a placeholder text for now)
        assertThat(backIsHandled()).isTrue()
        pressBack()
        assertOnHome()
    }

    @Test
    fun doubleTappingABackArrowWhileThePageSlidesOutPopsOnlyOneScreen() {
        val env = HubTestSupport.environment()
        // Real transitions: the page that leaves stays composed (and its arrow clickable) for the length of the slide.
        rule.setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { HubTestSupport.demoNow }, ticks = false)) {
                PulseTheme(darkTheme = false, reduceMotion = false) { StrengthHubScreen(env, {}, {}) }
            }
        }
        rule.waitForIdle()
        clickDescription("See All Templates")
        clickTemplate("Lower A · Quads")
        rule.onNodeWithText("Start Workout").assertIsDisplayed() // the template, above the list

        rule.mainClock.autoAdvance = false
        rule.onNodeWithContentDescription("Back").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitForIdle()
        // Mid-slide: the template on its way out and the list coming in each have a back arrow, and the second tap can reach either.
        val arrows = rule.onAllNodesWithContentDescription("Back")
        var frames = 0
        while (arrows.fetchSemanticsNodes().size < 2 && frames++ < 20) rule.mainClock.advanceTimeByFrame()
        arrows.assertCountEquals(2)
        for (index in 0..1) runCatching { arrows[index].performSemanticsAction(SemanticsActions.OnClick) }
        rule.mainClock.autoAdvance = true
        rule.waitForIdle()

        rule.onNodeWithText("Lower A · Quads").assertIsDisplayed() // the list
        rule.onNodeWithText("Today · Recommended").assertDoesNotExist()
        assertThat(backIsHandled()).isTrue()
        clickDescription("Back") // once the slide is over the arrow works again
        assertOnHome()
    }

    @Test
    fun theBackArrowOfTheExerciseDetailPopsExactlyItsOwnScreen() {
        show()
        click("Exercise Library")
        click("Barbell bench press")
        rule.onNodeWithText("Search exercises").assertDoesNotExist() // the exercise detail is on top of the library
        clickDescription("Back")
        rule.onNodeWithText("Search exercises").assertIsDisplayed()
        clickDescription("Back")
        assertOnHome()
    }

    @Test
    fun templateListShowsEveryTemplateWithNextUpAndExerciseNames() {
        show()
        clickDescription("See All Templates")
        rule.onNodeWithText("Next up").assertIsDisplayed()
        rule.onNodeWithText("Upper A · Push").assertIsDisplayed()
        rule.onNodeWithText("Lower A · Quads").assertIsDisplayed()
        rule.onNodeWithText("Upper B · Pull").assertIsDisplayed()
        rule.onNodeWithText("last done 5 days ago", substring = true).assertIsDisplayed()
        rule.onNodeWithText("New Template").assertIsDisplayed()
        rule.onAllNodesWithText("Barbell bench press", substring = true)[0].assertIsDisplayed()
    }

    @Test
    fun templateDetailListsTheExercisesAndOpensTheirDetail() {
        show()
        clickTemplate("Upper A · Push")
        rule.onNodeWithText("6 exercises · about 45 min · last done 5 days ago").assertIsDisplayed()
        rule.onNodeWithText("Edit").assertIsEnabled()
        click("Barbell bench press")
        // The exercise detail screen belongs to another area; its placeholder shows the exercise name.
        rule.onNodeWithText("Start Workout").assertDoesNotExist()
        rule.onNodeWithText("Barbell bench press").assertIsDisplayed()
        pressBack()
        rule.onNodeWithText("Start Workout").assertIsDisplayed()
        pressBack()
        assertOnHome()
    }

    @Test
    fun libraryFiltersBySearchAndMuscleAndKeepsItsStateWhenAnExerciseOpens() {
        show()
        click("Exercise Library")
        rule.onNodeWithText("Back squat").assertIsDisplayed()
        rule.onNode(hasSetTextAction()).performTextInput("bench")
        rule.waitForIdle()
        rule.onNodeWithText("Barbell bench press").assertIsDisplayed()
        rule.onNodeWithText("Back squat").assertDoesNotExist()
        click("Barbell bench press")
        rule.onNodeWithText("Search exercises").assertDoesNotExist() // the detail screen is showing
        pressBack()
        rule.onNode(hasSetTextAction()).assertTextContains("bench")
        rule.onNodeWithText("Barbell bench press").assertIsDisplayed()
        rule.onNodeWithContentDescription("Clear search").performClick()
        rule.waitForIdle()
        click("Legs")
        rule.onNodeWithText("Back squat").assertIsDisplayed()
        rule.onNodeWithText("Barbell bench press").assertDoesNotExist()
        click("Legs") // tapping the selected chip clears the filter
        rule.onNodeWithText("Barbell bench press").assertIsDisplayed()
        rule.onNode(hasSetTextAction()).performTextInput("zzzz")
        rule.waitForIdle()
        rule.onNodeWithText("No exercises found").assertIsDisplayed()
    }

    @Test
    fun recentWorkoutsListAndDetailShowRecordsExercisesAndMuscles() {
        show()
        clickDescription("See All Recent Workouts")
        // Five workouts; the bench record of 10 days ago is flagged.
        click("1 PR")
        rule.onNodeWithText("New personal record").assertIsDisplayed()
        rule.onNodeWithText("85 kg × 5 · est. 1RM 99 kg").assertIsDisplayed()
        rule.onNodeWithText("Exercises").assertIsDisplayed()
        rule.onNodeWithText("Muscles Worked").performScrollTo().assertIsDisplayed()
        rule.onNode(hasText("Barbell bench press") and hasClickAction()).performScrollTo().performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Muscles Worked").assertDoesNotExist()
        pressBack()
        rule.onNodeWithText("Muscles Worked").assertExists()
        pressBack()
        pressBack()
        assertOnHome()
    }

    @Test
    fun recoveryScreenShowsEveryMuscleGroup() {
        show()
        clickDescription("View All Muscle Recovery")
        for (muscle in listOf("Chest", "Shoulders", "Arms", "Back", "Legs", "Core")) {
            rule.onNodeWithContentDescription("$muscle recovery").assertIsDisplayed()
        }
        // Each row reads as one element: muscle, percentage and level.
        fun stateOf(muscle: String) = SemanticsMatcher.expectValue(
            SemanticsProperties.StateDescription,
            when (muscle) {
                "Chest" -> "88 percent, Good"
                "Shoulders" -> "82 percent, Good"
                "Arms" -> "79 percent, Fair"
                "Back" -> "100 percent, Good"
                "Legs" -> "64 percent, Fair"
                else -> "100 percent, Good"
            },
        )
        for (muscle in listOf("Chest", "Shoulders", "Arms", "Back", "Legs", "Core")) {
            rule.onNode(hasContentDescription("$muscle recovery") and stateOf(muscle)).assertIsDisplayed()
        }
    }

    // endregion

    // region Templates: create, edit, delete exercises, cancel

    @Test
    fun creatingATemplatePersistsItAndShowsItInTheList() {
        val env = HubTestSupport.environment()
        show(env)
        click("New Template")
        rule.onNodeWithText("Save").assertIsNotEnabled()
        typeTemplateName("Leg day")
        rule.onNodeWithText("Save").assertIsNotEnabled() // a name alone is not enough
        click("Add Exercises")
        rule.onAllNodesWithText("Add Exercises").assertCountEquals(2) // the row and the chooser's title
        rule.onNodeWithText("Add").assertIsNotEnabled()
        choose("Back squat")
        choose("Leg press")
        rule.onNodeWithText("Add (2)").assertIsEnabled()
        choose("Leg press") // deselect
        rule.onNodeWithText("Add (1)").assertIsEnabled()
        choose("Leg press")
        click("Add (2)")
        rule.onNodeWithText("Back squat").assertIsDisplayed()
        rule.onNodeWithText("Save").assertIsEnabled()
        click("Save")
        rule.onNodeWithText("Save").assertDoesNotExist()

        val created = env.store.templates.last()
        assertThat(created.name).isEqualTo("Leg day")
        assertThat(created.entries.map { it.exercise.name }).containsExactly("Back squat", "Leg press").inOrder()
        assertThat(created.entries.all { it.plannedSets.isNotEmpty() && it.restSeconds > 0 }).isTrue()
        assertThat(created.lastPerformed).isNull()
        assertThat(env.store.templates).hasSize(4)

        // It shows in "See All" ...
        clickDescription("See All Templates")
        rule.onNodeWithText("Leg day").assertIsDisplayed()
        // ... and survives a reload and a new launch.
        env.store.reload()
        assertThat(env.store.templates.map { it.name }).contains("Leg day")
        assertThat(HubTestSupport.reopenedStore(env).templates.map { it.name }).contains("Leg day")
        assertThat(HubTestSupport.reopenedStore(env).templates.last()).isEqualTo(created)
    }

    @Test
    fun editingATemplateRenamesRemovesAndMovesItsExercisesInPlace() {
        val env = HubTestSupport.environment()
        val original = env.store.templates.first()
        show(env)
        clickDescription("Edit plan")
        rule.onNodeWithText("Edit Plan").assertIsDisplayed()
        rule.onNode(hasSetTextAction()).assertTextContains("Upper A · Push")
        rule.onAllNodes(hasSetTextAction()).onFirst().performTextReplacement("Upper A · Push v2")
        // Remove the first exercise, move the (new) first exercise down.
        val first = original.entries[0].exercise.name
        val second = original.entries[1].exercise.name
        rule.onNodeWithContentDescription("Options for $first").performClick()
        rule.onNodeWithText("Remove").performClick()
        rule.waitForIdle()
        rule.onNodeWithContentDescription("Options for $first").assertDoesNotExist()
        rule.onNodeWithContentDescription("Options for $second").performClick()
        rule.onNodeWithText("Move down").performClick()
        rule.waitForIdle()
        click("Save")

        val saved = env.store.templates.first()
        assertThat(saved.id).isEqualTo(original.id)
        assertThat(saved.name).isEqualTo("Upper A · Push v2")
        assertThat(saved.lastPerformed).isEqualTo(original.lastPerformed)
        assertThat(saved.entries).hasSize(original.entries.size - 1)
        assertThat(saved.entries.map { it.exercise.id }).containsExactly(
            original.entries[2].exercise.id, original.entries[1].exercise.id, *original.entries.drop(3).map { it.exercise.id }.toTypedArray(),
        ).inOrder()
        assertThat(env.store.templates).hasSize(3) // replaced, not added
        assertThat(HubTestSupport.reopenedStore(env).templates.first()).isEqualTo(saved)
        rule.onAllNodesWithText("Upper A · Push v2").assertCountEquals(2) // the recommended card and the template row
    }

    @Test
    fun cancellingTheEditorChangesNothing() {
        val env = HubTestSupport.environment()
        val before = env.store.data.value
        show(env)
        clickDescription("Edit plan")
        rule.onAllNodes(hasSetTextAction()).onFirst().performTextInput(" changed")
        click("Cancel")
        rule.onNodeWithText("Edit Plan").assertDoesNotExist()
        assertThat(env.store.data.value).isEqualTo(before)
        click("New Template")
        typeTemplateName("Draft")
        click("Cancel")
        assertThat(env.store.data.value).isEqualTo(before)
    }

    @Test
    fun templateDetailEditButtonOpensTheEditor() {
        show()
        clickTemplate("Lower A · Quads")
        click("Edit")
        rule.onNodeWithText("Edit Plan").assertIsDisplayed()
        rule.onNode(hasSetTextAction()).assertTextContains("Lower A · Quads")
    }

    @Test
    fun savingKeepsTheSelectionOrderOfTheChooser() {
        val env = HubTestSupport.environment(seed = false)
        show(env)
        click("Create Your First Template")
        typeTemplateName("Order")
        click("Add Exercises")
        choose("Push-up")
        choose("Barbell bench press")
        choose("Back squat")
        click("Add (3)")
        click("Save")
        assertThat(env.store.templates.single().entries.map { it.exercise.name }).containsExactly("Push-up", "Barbell bench press", "Back squat").inOrder()
    }

    @Test
    fun chooserRowsAreCheckboxes() {
        show()
        click("New Template")
        click("Add Exercises")
        rule.onNode(hasText("Back squat") and hasClickAction() and hasSetTextAction().not()).assertIsOff()
        choose("Back squat")
        rule.onNode(hasText("Back squat") and hasClickAction() and hasSetTextAction().not()).assertIsOn()
    }

    @Test
    fun tappingOutsideAnEditedEditorAsksBeforeThrowingTheDraftAway() {
        val env = HubTestSupport.environment()
        val before = env.store.data.value
        show(env)
        click("New Template")
        typeTemplateName("Draft")
        tapOutsideTheSheet()
        assertAsksToDiscard()
        click("Keep editing")
        rule.onNodeWithText("Discard changes?").assertDoesNotExist()
        rule.onAllNodes(hasSetTextAction()).onFirst().assertTextEquals("Draft", includeEditableText = true) // nothing was lost
        tapOutsideTheSheet()
        assertAsksToDiscard()
        click("Discard")
        rule.onNodeWithText("Discard changes?").assertDoesNotExist()
        rule.onNodeWithText("Save").assertDoesNotExist()
        assertThat(env.store.data.value).isEqualTo(before)
        // The next editor starts clean.
        click("New Template")
        rule.onNodeWithText("Template name").assertIsDisplayed() // an empty field
    }

    @Test
    fun backAsksBeforeThrowingTheDraftAway() {
        val env = HubTestSupport.environment()
        val before = env.store.data.value
        show(env)
        clickDescription("Edit plan")
        rule.onAllNodes(hasSetTextAction()).onFirst().performTextInput(" v2")
        rule.waitForIdle()
        pressBackInTheSheet()
        assertAsksToDiscard()
        click("Keep editing")
        rule.onNodeWithText("Edit Plan").assertIsDisplayed()
        pressBackInTheSheet()
        click("Discard")
        rule.onNodeWithText("Edit Plan").assertDoesNotExist()
        assertThat(env.store.data.value).isEqualTo(before)
    }

    @Test
    fun aSwipeDownAsksBeforeThrowingTheDraftAway() {
        show()
        clickDescription("Edit plan")
        rule.onAllNodes(hasSetTextAction()).onFirst().performTextInput(" v2")
        rule.waitForIdle()
        swipeTheSheetDown("Edit Plan")
        assertAsksToDiscard()
        click("Keep editing")
        rule.onNodeWithText("Edit Plan").assertIsDisplayed() // the sheet came back to its place
        swipeTheSheetDown("Edit Plan")
        click("Discard")
        rule.onNodeWithText("Edit Plan").assertDoesNotExist()
    }

    @Test
    fun closingAnEditorWithoutChangesDoesNotAsk() {
        val env = HubTestSupport.environment()
        val before = env.store.data.value
        show(env)
        click("New Template")
        tapOutsideTheSheet()
        rule.onNodeWithText("Discard changes?").assertDoesNotExist()
        rule.onNodeWithText("Save").assertDoesNotExist()

        clickDescription("Edit plan")
        pressBackInTheSheet()
        rule.onNodeWithText("Discard changes?").assertDoesNotExist()
        rule.onNodeWithText("Edit Plan").assertDoesNotExist()

        // Typing something and putting everything back is no change either.
        clickDescription("Edit plan")
        rule.onAllNodes(hasSetTextAction()).onFirst().performTextReplacement("Upper A · Pus")
        rule.onAllNodes(hasSetTextAction()).onFirst().performTextReplacement("Upper A · Push")
        rule.waitForIdle()
        tapOutsideTheSheet()
        rule.onNodeWithText("Discard changes?").assertDoesNotExist()
        rule.onNodeWithText("Edit Plan").assertDoesNotExist()
        assertThat(env.store.data.value).isEqualTo(before)
    }

    @Test
    fun cancelAndSaveNeverAsk() {
        val env = HubTestSupport.environment()
        show(env)
        click("New Template")
        typeTemplateName("Gone")
        click("Cancel")
        rule.onNodeWithText("Discard changes?").assertDoesNotExist()
        rule.onNodeWithText("Save").assertDoesNotExist()
        assertThat(env.store.templates.map { it.name }).doesNotContain("Gone")

        clickDescription("Edit plan")
        rule.onAllNodes(hasSetTextAction()).onFirst().performTextReplacement("Upper A · Push v3")
        click("Save")
        rule.onNodeWithText("Discard changes?").assertDoesNotExist()
        rule.onNodeWithText("Save").assertDoesNotExist()
        assertThat(env.store.templates.first().name).isEqualTo("Upper A · Push v3")
    }

    @Test
    fun theEditorKeepsAskingAfterRecreationOnlyWhenTheDraftIsChanged() {
        val env = HubTestSupport.environment()
        val tester = StateRestorationTester(rule)
        tester.setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { HubTestSupport.demoNow }, ticks = false)) {
                PulseTheme(darkTheme = false, reduceMotion = true) { StrengthHubScreen(env, {}, {}) }
            }
        }
        rule.waitForIdle()
        clickDescription("Edit plan")
        tester.emulateSavedInstanceStateRestore() // an untouched draft that went through the saver still equals the template
        rule.waitForIdle()
        rule.onNodeWithText("Edit Plan").assertIsDisplayed()
        tapOutsideTheSheet()
        rule.onNodeWithText("Discard changes?").assertDoesNotExist()
        rule.onNodeWithText("Edit Plan").assertDoesNotExist()

        clickDescription("Edit plan")
        rule.onAllNodes(hasSetTextAction()).onFirst().performTextInput(" v2")
        rule.waitForIdle()
        tester.emulateSavedInstanceStateRestore()
        rule.waitForIdle()
        tapOutsideTheSheet()
        assertAsksToDiscard()
    }

    @Test
    fun theQuestionSurvivesRecreation() {
        val env = HubTestSupport.environment()
        val tester = StateRestorationTester(rule)
        tester.setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { HubTestSupport.demoNow }, ticks = false)) {
                PulseTheme(darkTheme = false, reduceMotion = true) { StrengthHubScreen(env, {}, {}) }
            }
        }
        rule.waitForIdle()
        click("New Template")
        typeTemplateName("Kept")
        tapOutsideTheSheet()
        assertAsksToDiscard()
        tester.emulateSavedInstanceStateRestore()
        rule.waitForIdle()
        assertAsksToDiscard()
        click("Keep editing")
        rule.onAllNodes(hasSetTextAction()).onFirst().assertTextEquals("Kept", includeEditableText = true)
    }

    @Test
    fun doubleTappingSaveSavesTheTemplateOnce() {
        val env = HubTestSupport.environment()
        show(env)
        click("New Template")
        typeTemplateName("Once")
        click("Add Exercises")
        choose("Back squat")
        click("Add (1)")
        // Both taps land before the sheet has slid away.
        rule.mainClock.autoAdvance = false
        repeat(2) { rule.onNodeWithText("Save").performSemanticsAction(SemanticsActions.OnClick) }
        rule.mainClock.autoAdvance = true
        rule.waitForIdle()
        rule.onNodeWithText("Save").assertDoesNotExist()
        assertThat(env.store.templates.count { it.name == "Once" }).isEqualTo(1)
        assertThat(env.store.templates).hasSize(4)
        assertThat(HubTestSupport.reopenedStore(env).templates).hasSize(4)
    }

    @Test
    fun doubleTappingAddInTheChooserAddsTheExercisesOnce() {
        val env = HubTestSupport.environment()
        show(env)
        click("New Template")
        typeTemplateName("Twice")
        click("Add Exercises")
        choose("Back squat")
        choose("Leg press")
        rule.mainClock.autoAdvance = false
        repeat(2) { rule.onNodeWithText("Add (2)").performSemanticsAction(SemanticsActions.OnClick) }
        rule.mainClock.autoAdvance = true
        rule.waitForIdle()
        click("Save")
        assertThat(env.store.templates.last().entries.map { it.exercise.name }).containsExactly("Back squat", "Leg press").inOrder()
    }

    // endregion

    // region First run

    @Test
    fun firstRunHasEmptyStatesAndNoNonsenseFigures() {
        val env = HubTestSupport.environment(seed = false)
        assertThat(env.store.templates).isEmpty()
        assertThat(env.store.history).isEmpty()
        assertThat(env.store.personalBests).isEmpty()
        show(env)
        rule.onNodeWithText("Plan your training").assertIsDisplayed()
        rule.onNodeWithText("Create Your First Template").assertIsDisplayed()
        rule.onNodeWithText("Today · Recommended").assertDoesNotExist()
        rule.onNodeWithText("Start Empty Workout").assertIsDisplayed()
        rule.onNodeWithContentDescription("See All Templates").assertDoesNotExist()
        rule.onNodeWithText("Recent Workouts").assertDoesNotExist()
        rule.onNodeWithText("New Template").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("Muscle Recovery").performScrollTo().assertIsDisplayed()
        // This week: nothing yet.
        rule.onNodeWithText("This Week").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("0 of 4").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("–").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("36 exercises with form demos · create your own").performScrollTo().assertIsDisplayed()
        rule.onAllNodesWithText("NaN", substring = true).assertCountEquals(0)
        rule.onAllNodesWithText("0 kg", substring = true).assertCountEquals(0)
        // Recovery comes from the provider alone.
        rule.onNodeWithContentDescription("Chest recovery").assertExists()
    }

    @Test
    fun firstRunCanStartAnEmptyWorkout() {
        show(HubTestSupport.environment(seed = false))
        click("Start Empty Workout")
        assertThat(started).containsExactly(null)
    }

    @Test
    fun firstRunScreensHaveMessagesInsteadOfBlankSpace() {
        show(HubTestSupport.environment(seed = false))
        clickDescription("More")
        rule.onAllNodesWithText("Exercise Library")[1].performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Barbell bench press").assertIsDisplayed() // the library itself is never empty
        pressBack()
        click("Create Your First Template")
        click("Cancel")
        rule.onNodeWithText("New Template").performScrollTo().performClick()
        rule.waitForIdle()
        click("Cancel")
        rule.onNodeWithContentDescription("View All Muscle Recovery").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun firstTemplateBecomesTheRecommendedCard() {
        val env = HubTestSupport.environment(seed = false)
        show(env)
        click("Create Your First Template")
        typeTemplateName("Full body")
        click("Add Exercises")
        choose("Back squat")
        choose("Barbell bench press")
        click("Add (2)")
        click("Save")
        rule.onNodeWithText("Plan your training").assertDoesNotExist()
        rule.onNodeWithText("Today · Recommended").assertIsDisplayed()
        rule.onNodeWithText("2 exercises · about 20 min").assertIsDisplayed() // the card; the list row adds "next up"
        // No history yet: the coach only comments on recovery (the library's placeholder results are not the user's).
        rule.onNodeWithText("Coach", substring = true).assertIsDisplayed()
        rule.onAllNodesWithText("Aim for", substring = true).assertCountEquals(0)
        click("Start Workout")
        assertThat(started.map { it?.name }).containsExactly("Full body")
        // "See All" appears now that there is a template to list.
        rule.onNodeWithContentDescription("See All Templates").assertExists()
        assertThat(HubTestSupport.reopenedStore(env).templates.map { it.name }).containsExactly("Full body")
    }

    @Test
    fun aFinishedWorkoutFillsTheHistoryAndTheWeek() {
        val env = HubTestSupport.environment(seed = false)
        val finished = SampleData.history(HubTestSupport.demoNow).first() // finished 3 days before the test clock
        env.store.record(finished, null)
        show(env)
        rule.onNodeWithText("Recent Workouts").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("This Week").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText("1 of 4").performScrollTo().assertIsDisplayed()
        rule.onNodeWithText(finished.name).assertIsDisplayed()
        clickDescription("See All Recent Workouts")
        rule.onNodeWithText(finished.name).assertIsDisplayed()
        click(finished.name)
        rule.onNodeWithText("Muscles Worked").performScrollTo().assertIsDisplayed()
    }

    // endregion

    // region Recovery on the home screen

    /** The state of a card of the recovery grid on the home screen ("100 percent"). */
    private fun gridState(muscle: String): String =
        rule.onNodeWithContentDescription("$muscle recovery").fetchSemanticsNode().config[SemanticsProperties.StateDescription]

    private fun readinessState(): String =
        rule.onNodeWithContentDescription("Readiness").fetchSemanticsNode().config[SemanticsProperties.StateDescription]

    /** Logs three sets of the first template's first exercise (a chest exercise) and finishes the workout, through the controller. */
    private fun finishAChestWorkout(env: StrengthAppEnvironment) {
        rule.runOnUiThread {
            env.controller.startWorkout(env.store.templates.first())
            repeat(3) { env.controller.send(WorkoutAction.LogNextSet) }
            env.controller.finish(false)
        }
        rule.waitForIdle()
    }

    @Test
    fun aFinishedWorkoutShowsInTheRecoveryGridAtOnce() {
        val now = HubTestSupport.demoNow
        val env = HubTestSupport.environment(recoveryOf = { RecoveryModel({ it.history }, { now }).provider }, clock = { now })
        show(env)
        assertThat(gridState("Chest")).isEqualTo("100 percent")
        assertThat(readinessState()).isEqualTo("100 percent, Ready")

        finishAChestWorkout(env)

        // The grid below the card follows the card: chest was just trained, the other five groups are untouched (mean 83).
        assertThat(gridState("Chest")).isEqualTo("0 percent")
        assertThat(gridState("Shoulders")).isEqualTo("100 percent")
        rule.onAllNodesWithText("0%", useUnmergedTree = true).assertCountEquals(1)
        assertThat(readinessState()).isEqualTo("83 percent, Ready")
    }

    @Test
    fun theRecoveryGridAgesWhileTheHubStaysOpen() {
        var now = HubTestSupport.demoNow
        val env = HubTestSupport.environment(recoveryOf = { RecoveryModel({ it.history }, { now }).provider }, clock = { now })
        finishAChestWorkout(env)
        rule.setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { now }, ticks = true)) {
                PulseTheme(darkTheme = false, reduceMotion = true) { StrengthHubScreen(env, {}, {}) }
            }
        }
        rule.waitForIdle()
        assertThat(gridState("Chest")).isEqualTo("0 percent")

        // Twelve hours later, at the next minute tick: a quarter of the 48 hours a session of three sets needs.
        now = now.plusSeconds(12 * 3600L)
        rule.mainClock.advanceTimeBy(60_000)
        rule.waitForIdle()
        assertThat(gridState("Chest")).isEqualTo("25 percent")
        assertThat(readinessState()).isEqualTo("88 percent, Ready") // (25 + 5 * 100) / 6
    }

    // endregion

    // region State restoration

    @Test
    fun theBackStackAndTheLibrarySearchSurviveRecreation() {
        val env = HubTestSupport.environment()
        val tester = StateRestorationTester(rule)
        tester.setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { HubTestSupport.demoNow }, ticks = false)) {
                PulseTheme(darkTheme = false, reduceMotion = true) { StrengthHubScreen(env, {}, {}) }
            }
        }
        rule.waitForIdle()
        click("Exercise Library")
        rule.onNode(hasSetTextAction()).performTextInput("squat")
        rule.waitForIdle()
        tester.emulateSavedInstanceStateRestore()
        rule.waitForIdle()
        rule.onNodeWithText("Search exercises").assertDoesNotExist() // the placeholder is gone: the text was restored
        rule.onNode(hasSetTextAction()).assertTextEquals("squat", includeEditableText = true)
        rule.onNodeWithText("Back squat").assertIsDisplayed()
        pressBack()
        assertOnHome()
    }

    @Test
    fun anOpenEditorAndItsDraftSurviveRecreation() {
        val env = HubTestSupport.environment(seed = false)
        val tester = StateRestorationTester(rule)
        tester.setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { HubTestSupport.demoNow }, ticks = false)) {
                PulseTheme(darkTheme = false, reduceMotion = true) { StrengthHubScreen(env, {}, {}) }
            }
        }
        rule.waitForIdle()
        click("Create Your First Template")
        typeTemplateName("Kept")
        click("Add Exercises")
        choose("Back squat")
        click("Add (1)")
        tester.emulateSavedInstanceStateRestore()
        rule.waitForIdle()
        rule.onNodeWithText("Save").assertIsDisplayed()
        rule.onAllNodes(hasSetTextAction()).onFirst().assertTextEquals("Kept", includeEditableText = true)
        rule.onNodeWithText("Back squat").assertIsDisplayed()
        click("Save")
        assertThat(env.store.templates.single().name).isEqualTo("Kept")
        assertThat(env.store.templates.single().entries.map { it.exercise.name }).containsExactly("Back squat")
    }

    @Test
    fun aScreenOpenedAfterRecreationDoesNotInheritTheStateOfAPoppedOne() {
        val env = HubTestSupport.environment()
        val tester = StateRestorationTester(rule)
        tester.setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { HubTestSupport.demoNow }, ticks = false)) {
                PulseTheme(darkTheme = false, reduceMotion = true) { StrengthHubScreen(env, {}, {}) }
            }
        }
        rule.waitForIdle()
        click("Exercise Library")
        rule.onNode(hasSetTextAction()).performTextInput("bench")
        rule.waitForIdle()
        pressBack()
        assertOnHome()
        tester.emulateSavedInstanceStateRestore()
        rule.waitForIdle()
        click("Exercise Library")
        rule.onNodeWithText("Search exercises").assertIsDisplayed() // an empty field, not the old "bench"
        rule.onNodeWithText("Back squat").assertIsDisplayed()
    }

    @Test
    fun aPoppedScreenLeavesNoSavedStateBehind() {
        val env = HubTestSupport.environment()
        val registry = SaveableStateRegistry(restoredValues = null, canBeSaved = { true })
        rule.setContent {
            CompositionLocalProvider(
                LocalSaveableStateRegistry provides registry,
                LocalPulseClock provides PulseClock(now = { HubTestSupport.demoNow }, ticks = false),
            ) {
                PulseTheme(darkTheme = false, reduceMotion = true) { StrengthHubScreen(env, {}, {}) }
            }
        }
        rule.waitForIdle()
        click("Exercise Library")
        rule.onNode(hasSetTextAction()).performTextInput("bench")
        rule.waitForIdle()
        rule.runOnUiThread { assertThat(registry.performSave().toString()).contains("bench") } // the probe sees the open screen's text
        pressBack()
        assertOnHome()
        rule.runOnUiThread { assertThat(registry.performSave().toString()).doesNotContain("bench") }
    }

    // endregion

    @Test
    fun libraryScrollsToTheLastExercise() {
        val env = HubTestSupport.environment()
        show(env)
        click("Exercise Library")
        val last = ExerciseLibrary.filter(env.store.exercises, "", null, null).last().name
        rule.onNode(hasScrollToIndexAction()).performScrollToNode(hasText(last))
        rule.onNodeWithText(last).assertIsDisplayed()
    }
}
