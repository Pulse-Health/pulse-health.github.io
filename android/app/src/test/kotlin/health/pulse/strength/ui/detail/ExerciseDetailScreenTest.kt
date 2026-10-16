package health.pulse.strength.ui.detail

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.Equipment
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.ui.detail.ResultFixtures.library
import health.pulse.strength.ui.detail.ResultFixtures.warmup
import health.pulse.strength.ui.detail.ResultFixtures.work
import java.time.Instant
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Texts, states and callbacks of the exercise detail. The whole page is composed (a very tall window), so every section can be
 * asserted without scrolling; [scrollsToTheEndOfAShortWindow] covers a real device height.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = PAGE_PHONE)
class ExerciseDetailScreenTest {
    @get:Rule val rule = createComposeRule()

    @Before fun pinZone() = ResultFixtures.pinTimeZone()

    private var backCount = 0

    private fun show(exercise: Exercise, store: StrengthStore, now: Instant = ResultFixtures.now) {
        rule.setPulse(now = now) { ExerciseDetailScreen(exercise = exercise, store = store, onBack = { backCount++ }) }
        rule.waitForIdle()
    }

    private fun showBench(): StrengthStore {
        val store = ResultFixtures.demoStore()
        show(store.exercise("bench")!!, store)
        return store
    }

    // region Content

    @Test
    fun showsTitleSubtitleAndMedia() {
        showBench()
        rule.onNodeWithText("Barbell bench press").assertIsDisplayed()
        rule.onNodeWithText("Chest · Shoulders · Triceps · Barbell").assertIsDisplayed()
        // The badge is part of the picture's description: TalkBack reads the label, not the badge.
        rule.onNodeWithText("Form demo", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithContentDescription("Form demo for Barbell bench press, alternating between the start and the end position")
            .assertIsDisplayed()
        rule.onNodeWithText("Demo photos: Free Exercise DB (public domain).").assertIsDisplayed()
    }

    @Test
    fun titleAndSectionTitlesAreHeadings() {
        showBench()
        val heading = SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading)
        for (text in listOf("Barbell bench press", "Personal Records", "Recent Sessions", "How To")) {
            rule.onNode(heading and hasText(text)).assertExists()
        }
    }

    @Test
    fun showsTheThreeFigureTilesOfAWeightExercise() {
        showBench()
        rule.onNode(hasText("Est. 1RM") and hasText("99 kg")).assertIsDisplayed()
        rule.onNode(hasText("Est. 1RM") and hasText("99 kg")).assert(hasContentDescription("up 6 kilograms over 5 days"))
        rule.onNode(hasText("Best set") and hasText("PR · Jan 2")).assert(hasText("85 × 5"))
        rule.onNode(hasText("Volume · 30d")).assert(hasText("3 sessions"))
        rule.onNode(hasText("Volume · 30d")).assert(hasText("4.1 t"))
    }

    @Test
    fun showsTheChartHeadingAndItsFootnote() {
        showBench()
        rule.onNode(hasText("Estimated 1RM") and hasText("Oct\u00A020,\u00A02025 – Jan\u00A012")).assertIsDisplayed()
        rule.onNodeWithText("12w").assertIsDisplayed()
        rule.onNodeWithText("Estimated with weight × (1 + reps ÷ 30). Warm-up sets are left out.").assertIsDisplayed()
    }

    @Test
    fun theChartIsDescribedForTalkBack() {
        showBench()
        rule.onNodeWithContentDescription(
            "Estimated one-rep max rising from 93 kilograms on Dec 28, 2025 to 99 kilograms on Jan 2, over 5 days, latest 96 kilograms, 3 sessions",
        ).assertIsDisplayed()
    }

    @Test
    fun listsThePersonalRecords() {
        showBench()
        rule.onNode(hasText("Estimated 1RM") and hasText("99 kg") and hasText("Jan 2")).assertExists()
        rule.onNode(hasText("Best set") and hasText("85 kg × 5")).assertExists()
        rule.onNode(hasText("Most reps at 80 kg") and hasText("6") and hasText("Jan 7")).assertExists()
        rule.onNode(hasText("Best session volume") and hasText("1,395 kg") and hasText("Dec 28, 2025")).assertExists()
    }

    @Test
    fun listsTheRecentSessionsWithAPrTagOnTheRecord() {
        showBench()
        rule.onNode(hasText("Jan 7 · Upper A · Push") and hasText("W 50×8 · W 70×5 · 80×6 · 80×6 · 80×5")).assertExists()
        rule.onNode(hasText("Jan 2 · Upper A · Push") and hasText("W 50×8 · W 70×5 · 80×6 · 82.5×5 · 85×5")).assertExists()
        rule.onNode(hasText("Dec 28, 2025 · Upper A · Push") and hasText("W 50×8 · 77.5×6 · 77.5×6 · 77.5×6")).assertExists()
        rule.onAllNodesWithText("PR").assertCountEquals(1)
        rule.onNode(hasText("Jan 2 · Upper A · Push") and hasText("PR")).assertExists()
        // Three sessions: no "See All".
        rule.onNodeWithText("See All").assertDoesNotExist()
    }

    @Test
    fun listsTheHowToCuesAsSteps() {
        showBench()
        rule.onNodeWithContentDescription("Step 1. Pull your shoulder blades back and down and keep your feet planted.").assertIsDisplayed()
        rule.onNodeWithContentDescription("Step 3. Press up and slightly back until your arms are straight.").assertIsDisplayed()
    }

    @Test
    fun usesTheStoreOfAnEnvironmentWithDemoData() {
        val environment = StrengthAppEnvironment.preview()
        show(environment.store.exercise("bench")!!, environment.store, now = Instant.now())
        rule.onNodeWithText("Barbell bench press").assertIsDisplayed()
        rule.onNodeWithText("Personal Records").assertExists()
        rule.onNodeWithText("Recent Sessions").assertExists()
    }

    // endregion

    // region Variants

    @Test
    fun aNewExerciseShowsDashesAnEmptyChartAndAnEmptySessionList() {
        show(library("bench"), ResultFixtures.emptyStore())
        rule.onNode(hasText("Est. 1RM") and hasText("–")).assertIsDisplayed()
        rule.onNode(hasText("Best set") and hasText("–")).assertIsDisplayed()
        rule.onNode(hasText("Volume · 30d") and hasText("0 kg") and hasText("0 sessions")).assertIsDisplayed()
        rule.onNodeWithText("No sessions logged yet").assertIsDisplayed()
        rule.onNodeWithText("No sessions yet").assertIsDisplayed()
        rule.onNodeWithText("Personal Records").assertDoesNotExist()
        rule.onNodeWithText("See All").assertDoesNotExist()
        // The way to do the exercise is still there.
        rule.onNodeWithText("How To").assertIsDisplayed()
        rule.onNodeWithText("Barbell bench press").assertIsDisplayed()
    }

    @Test
    fun aBodyweightExerciseHasNoEstimatedOneRepMax() {
        val store = ResultFixtures.demoStore()
        show(store.exercise("pullup")!!, store)
        rule.onNodeWithText("Pull-up").assertIsDisplayed()
        rule.onNode(hasText("Best set") and hasText("8 reps")).assertExists()
        rule.onNode(hasText("Sessions · 30d") and hasText("Last 30 days") and hasText("1")).assertExists()
        rule.onNodeWithText("Est. 1RM").assertDoesNotExist()
        rule.onNodeWithText("Estimated 1RM").assertDoesNotExist()
        rule.onNodeWithText("Volume · 30d").assertDoesNotExist()
        rule.onNode(hasText("Most reps in a set") and hasText("8")).assertExists()
        rule.onNode(hasText("Best session reps") and hasText("23")).assertExists()
        rule.onNodeWithText("8 reps · 8 reps · 7 reps").assertExists()
    }

    @Test
    fun aDurationExerciseShowsSeconds() {
        val plank = library("plank")
        val store = ResultFixtures.storeWith(
            ResultFixtures.workout(plank, "Core finisher", daysAgo = 13.0, sets = listOf(work(0.0, 45), work(0.0, 45))),
            ResultFixtures.workout(plank, "Upper A · Push", daysAgo = 6.0, sets = listOf(work(0.0, 60), work(0.0, 50)), isPersonalRecord = true),
        )
        show(plank, store)
        rule.onNode(hasText("Best set") and hasText("60 s") and hasText("PR · Jan 6")).assertExists()
        rule.onNode(hasText("Longest set") and hasText("60 s")).assertExists()
        rule.onNode(hasText("Best session time") and hasText("1:50")).assertExists()
        rule.onNodeWithText("Est. 1RM").assertDoesNotExist()
        rule.onNodeWithText("60 s · 50 s").assertExists()
    }

    @Test
    fun anExerciseWithoutMediaShowsNoFormDemoBadgeOrAttribution() {
        val custom = Exercise.custom("My cable fly", MuscleGroup.CHEST, Equipment.CABLE, TrackingKind.WEIGHT_REPS, id = "custom-fly")
        val store = ResultFixtures.emptyStore().also { it.addCustomExercise(custom) }
        show(store.exercise("custom-fly")!!, store)
        rule.onNodeWithText("My cable fly").assertIsDisplayed()
        // The secondary line "Custom" is not shown as a muscle.
        rule.onNodeWithText("Chest · Cable").assertIsDisplayed()
        rule.onNodeWithText("Form demo").assertDoesNotExist()
        rule.onNodeWithContentDescription("No form demo for this exercise yet").assertIsDisplayed()
        rule.onNodeWithText("Demo photos: Free Exercise DB (public domain).").assertDoesNotExist()
    }

    @Test
    fun aVeryLongNameWrapsInsteadOfClipping() {
        val name = "Single-arm landmine press with a staggered stance and a really long name that keeps going"
        val custom = Exercise.custom(name, MuscleGroup.SHOULDERS, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, id = "custom-long")
        val workoutName = "Shoulders and a very long workout name that has to wrap onto more than one line"
        val store = ResultFixtures.storeWith(
            ResultFixtures.workout(custom, workoutName, daysAgo = 2.0, sets = listOf(work(30.0, 10, 3)), isPersonalRecord = true),
        ).also { it.addCustomExercise(custom) }
        show(store.exercise("custom-long")!!, store)
        rule.onNodeWithText(name).assertIsDisplayed()
        rule.onNode(hasText("Jan 10 · $workoutName")).assertIsDisplayed()
        // Wrapped, not cut: the title is taller than one line of 30 sp.
        assertThat(rule.onNodeWithText(name).getUnclippedBoundsInRoot().height).isGreaterThan(80.dp)
    }

    @Test
    fun theSubtitleLeavesOutTheCustomMarker() {
        val bench = library("bench")
        assertThat(subtitle(bench)).isEqualTo("Chest · Shoulders · Triceps · Barbell")
        val custom = Exercise.custom("X", MuscleGroup.BACK, Equipment.OTHER, TrackingKind.REPS_ONLY)
        assertThat(subtitle(custom)).isEqualTo("Back · Other")
        assertThat(subtitle(bench.copy(secondary = ""))).isEqualTo("Chest · Barbell")
    }

    // endregion

    // region Interaction

    @Test
    fun theBackArrowCallsOnBack() {
        showBench()
        rule.onNodeWithContentDescription("Back").performClick()
        assertThat(backCount).isEqualTo(1)
    }

    @Test
    fun theRangeMenuChangesTheWindowOfTheChart() {
        val bench = library("bench")
        // The only session is 200 days old: outside 12 weeks, inside a year.
        val store = ResultFixtures.storeWith(
            ResultFixtures.workout(bench, "Old push day", daysAgo = 200.0, sets = listOf(work(80.0, 5), work(80.0, 5))),
        )
        show(bench, store)
        rule.onNodeWithText("No sessions in this range").assertIsDisplayed()
        rule.onNode(hasContentDescription("Chart range")).assert(hasText("12w"))

        rule.onNode(hasContentDescription("Chart range")).performClick()
        rule.onNodeWithText("1 year").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("No sessions in this range").assertDoesNotExist()
        rule.onNodeWithText("1y").assertIsDisplayed()
        rule.onNodeWithContentDescription("Estimated one-rep max 93 kilograms on Jun 26, 2025, 1 session").assertIsDisplayed()
        // The Est. 1RM tile follows the chart's window.
        rule.onNode(hasText("Est. 1RM") and hasText("93 kg")).assertExists()
    }

    @Test
    fun theRangeMenuOffersEveryWindow() {
        showBench()
        rule.onNode(hasContentDescription("Chart range")).performClick()
        for (title in listOf("4 weeks", "12 weeks", "6 months", "1 year", "All time")) {
            rule.onNodeWithText(title).assertIsDisplayed()
        }
        rule.onNodeWithText("All time").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("All").assertIsDisplayed()
    }

    @Test
    fun anEmptyRangeKeepsTheAllTimeBestInTheTile() {
        val bench = library("bench")
        val store = ResultFixtures.storeWith(
            ResultFixtures.workout(bench, "Old push day", daysAgo = 200.0, sets = listOf(work(80.0, 5))),
        )
        show(bench, store)
        // Nothing in the 12 week window: the all-time best (93.3 kg) shows without a trend.
        rule.onNode(hasText("Est. 1RM") and hasText("93 kg")).assertExists()
    }

    @Test
    fun seeAllShowsEverySessionAndShowLessFoldsThemAgain() {
        val bench = library("bench")
        val workouts = (0 until 8).map { index ->
            ResultFixtures.workout(bench, "Session $index", daysAgo = 3.0 + index * 5, sets = listOf(work(70.0 + index, 8)))
        }
        show(bench, ResultFixtures.storeWith(*workouts.toTypedArray()))
        rule.onNodeWithText("See All").assertIsDisplayed()
        rule.onAllNodesWithText("· Session", substring = true).assertCountEquals(3)
        rule.onNodeWithText("Dec 5, 2025 · Session 7").assertDoesNotExist()

        rule.onNodeWithText("See All").performClick()
        rule.waitForIdle()
        rule.onAllNodesWithText("· Session", substring = true).assertCountEquals(8)
        rule.onNodeWithText("Dec 5, 2025 · Session 7").assertExists()
        rule.onNodeWithText("Show Less").assertIsDisplayed()

        rule.onNodeWithText("Show Less").performClick()
        rule.waitForIdle()
        rule.onAllNodesWithText("· Session", substring = true).assertCountEquals(3)
        rule.onNodeWithText("See All").assertIsDisplayed()
    }

    @Test
    fun aSessionOpensInPlaceToListItsSets() {
        showBench()
        rule.onNodeWithText("RIR 3").assertDoesNotExist()
        rule.onNode(hasText("Jan 7 · Upper A · Push")).assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Collapsed"))

        rule.onNode(hasText("Jan 7 · Upper A · Push")).performClick()
        rule.waitForIdle()
        rule.onNode(hasText("Jan 7 · Upper A · Push")).assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Expanded"))
        rule.onNodeWithContentDescription("Warm-up set, 50 kg × 8").assertIsDisplayed()
        rule.onNodeWithContentDescription("Set 1, 80 kg × 6, RIR 3").assertIsDisplayed()
        rule.onNodeWithContentDescription("Set 2, 80 kg × 6, RIR 2").assertIsDisplayed()
        rule.onNodeWithContentDescription("Set 3, 80 kg × 5, RIR 1").assertIsDisplayed()

        rule.onNode(hasText("Jan 7 · Upper A · Push")).performClick()
        rule.waitForIdle()
        rule.onNodeWithContentDescription("Set 1, 80 kg × 6, RIR 3").assertDoesNotExist()
    }

    @Test
    fun aSessionRowSaysWhatTheTapDoesInTheImperative() {
        showBench()
        // TalkBack speaks "Double tap to <label>".
        rule.onNode(hasText("Jan 7 · Upper A · Push")).assertClickLabel("Show every set of this session")
        rule.onNode(hasText("Jan 7 · Upper A · Push")).performClick()
        rule.waitForIdle()
        rule.onNode(hasText("Jan 7 · Upper A · Push")).assertClickLabel("Hide the sets of this session")
    }

    @Test
    fun seeAllSaysWhatItExpands() {
        val bench = library("bench")
        val workouts = (0 until 8).map { index ->
            ResultFixtures.workout(bench, "Session $index", daysAgo = 3.0 + index * 5, sets = listOf(work(70.0 + index, 8)))
        }
        show(bench, ResultFixtures.storeWith(*workouts.toTypedArray()))
        rule.onNodeWithText("See All").assertClickLabel("Show all sessions")
        rule.onNodeWithText("See All").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Show Less").assertClickLabel("Show fewer sessions")
    }

    private fun SemanticsNodeInteraction.assertClickLabel(label: String) = assert(
        SemanticsMatcher("click label is \"$label\"") { it.config.getOrNull(SemanticsActions.OnClick)?.label == label },
    )

    @Test
    fun theScreenFollowsTheStore() {
        val store = ResultFixtures.emptyStore()
        show(library("bench"), store)
        rule.onNodeWithText("No sessions yet").assertIsDisplayed()

        rule.runOnIdle {
            store.record(
                ResultFixtures.workout(library("bench"), "Push day", daysAgo = 1.0, sets = listOf(warmup(40.0, 8), work(100.0, 3))),
                null,
            )
        }
        rule.waitForIdle()
        rule.onNodeWithText("No sessions yet").assertDoesNotExist()
        rule.onNodeWithText("Personal Records").assertExists()
        rule.onNode(hasText("Jan 11 · Push day")).assertExists()
        rule.onNode(hasText("Best set") and hasText("100 × 3")).assertExists()
    }

    // endregion

    // region Touch targets

    @Test
    fun interactiveElementsAreAtLeast48DpWide() {
        val bench = library("bench")
        val workouts = (0 until 5).map { ResultFixtures.workout(bench, "S$it", daysAgo = 3.0 + it * 4, sets = listOf(work(70.0, 8))) }
        show(bench, ResultFixtures.storeWith(*workouts.toTypedArray()))
        rule.onNode(hasContentDescription("Chart range")).assertWidthIsAtLeast(48.dp)
        rule.onNodeWithText("See All").assertWidthIsAtLeast(48.dp)
        val density = org.robolectric.RuntimeEnvironment.getApplication().resources.displayMetrics.density
        val back = rule.onNodeWithContentDescription("Back").fetchSemanticsNode().touchBoundsInRoot
        assertThat(back.width / density).isAtLeast(48f)
        assertThat(back.height / density).isAtLeast(48f)
        val chart = rule.onNode(hasContentDescription("Chart range")).getUnclippedBoundsInRoot()
        assertThat(chart.height).isAtLeast(48.dp)
    }

    // endregion

    // region Windows

    @Test
    @Config(qualifiers = "w411dp-h891dp-xxhdpi")
    fun scrollsToTheEndOfAShortWindow() {
        showBench()
        rule.onNodeWithText("Demo photos: Free Exercise DB (public domain).").assertDoesNotExist()
        rule.onNode(hasScrollAction()).performScrollToNode(hasText("Demo photos: Free Exercise DB (public domain)."))
        rule.onNodeWithText("Demo photos: Free Exercise DB (public domain).").assertIsDisplayed()
    }

    @Test
    @Config(qualifiers = "w800dp-h1280dp-xhdpi")
    fun theContentColumnIsCentredOnATablet() {
        showBench()
        val bounds = rule.onNodeWithText("Personal Records").getUnclippedBoundsInRoot()
        // 800 dp wide window, 640 dp column with a 16 dp gutter: the text starts at 80 + 16.
        assertThat(bounds.left.value).isWithin(1f).of(96f)
        val tiles = rule.onNode(hasText("Volume · 30d")).getUnclippedBoundsInRoot()
        assertThat(tiles.right.value).isWithin(1f).of(800f - 96f)
    }

    @Test
    @Config(qualifiers = "w360dp-h640dp-xhdpi")
    fun theTilesFitSideBySideOnASmallPhone() {
        showBench()
        val first = rule.onNode(hasText("Est. 1RM") and hasText("99 kg")).getUnclippedBoundsInRoot()
        val second = rule.onNode(hasText("Best set") and hasText("PR · Jan 2")).getUnclippedBoundsInRoot()
        assertThat(second.top).isEqualTo(first.top)
        assertThat(second.left).isGreaterThan(first.right - 1.dp)
    }

    @Test
    @Config(qualifiers = PAGE_PHONE, fontScale = 2.0f)
    fun theTilesStackAtTwiceTheFontSize() {
        showBench()
        val first = rule.onNode(hasText("Est. 1RM") and hasText("99 kg")).getUnclippedBoundsInRoot()
        val second = rule.onNode(hasText("Best set") and hasText("PR · Jan 2")).getUnclippedBoundsInRoot()
        assertThat(second.left).isEqualTo(first.left)
        assertThat(second.top).isGreaterThan(first.bottom - 1.dp)
        // Nothing runs off the screen: the title and the chart heading are fully inside the 411 dp window.
        for (text in listOf("Barbell bench press", "Personal Records", "Estimated with weight × (1 + reps ÷ 30). Warm-up sets are left out.")) {
            val bounds = rule.onNodeWithText(text).getUnclippedBoundsInRoot()
            assertThat(bounds.left.value).isAtLeast(0f)
            assertThat(bounds.right.value).isAtMost(411f)
        }
    }

    // endregion
}
