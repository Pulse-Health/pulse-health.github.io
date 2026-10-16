package health.pulse.strength.widgets.home

import android.content.Context
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.testing.unit.GlanceAppWidgetUnitTest
import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.GlanceNodeMatcher
import androidx.glance.testing.unit.MappedNode
import androidx.glance.testing.unit.assertHasStartActivityClickAction
import androidx.glance.testing.unit.hasContentDescriptionEqualTo
import androidx.test.core.app.ApplicationProvider
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseActions
import health.pulse.strength.widgets.common.PulseColors
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The Glance node tree of every widget, before it is translated to views: no container may have more than ten children (Glance's limit),
 * and the buttons and cards must start the intents the spec names (widgets/SPEC.md section 4).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "xxhdpi")
class GlanceTreeTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val preview = HomeFixtures.preview
    private val empty = HomeFixtures.empty

    private val anyNode = GlanceNodeMatcher<MappedNode>("any node") { true }
    private val atMostTenChildren = GlanceNodeMatcher<MappedNode>("has at most 10 children") { it.children().size <= GLANCE_CHILD_LIMIT }

    private fun runWidget(case: WidgetCase, size: DpSize, snapshot: WidgetSnapshot, block: GlanceAppWidgetUnitTest.() -> Unit) {
        runGlanceAppWidgetUnitTest {
            setContext(context)
            setAppWidgetSize(size)
            provideComposable {
                if (case.dynamic) GlanceTheme { case.content(snapshot) } else GlanceTheme(colors = PulseColors.colors) { case.content(snapshot) }
            }
            block()
        }
    }

    private fun run(name: String, width: Int, height: Int, snapshot: WidgetSnapshot, block: GlanceAppWidgetUnitTest.() -> Unit) =
        runWidget(WidgetCases.named(name), DpSize(width.dp, height.dp), snapshot, block)

    /** The node described by [description] opens the app on [url]. */
    private fun GlanceAppWidgetUnitTest.assertOpens(description: String, url: String) {
        onNode(hasContentDescriptionEqualTo(description)).assertHasStartActivityClickAction(PulseActions.linkIntent(url))
    }

    @Test
    fun noContainerOfAnyWidgetHasMoreThanTenChildren() {
        for (case in WidgetCases.all) {
            for (size in case.sizes) {
                for (snapshot in listOf(preview, empty)) {
                    runWidget(case, size, snapshot) { onAllNodes(anyNode).assertAll(atMostTenChildren) }
                }
            }
        }
    }

    @Test
    fun theCardsOpenTheAppOnTheLinkOfTheirSubject() {
        run("weekly-goal", 160, 160, preview) {
            assertOpens("3 of 4 workouts this week, 6 week streak", DeepLinks.hub)
        }
        run("pr-spotlight", 160, 160, preview) {
            assertOpens(
                "New PR: Bench Press, 85 kilograms for 5 reps. Estimated one-rep max 99 kilograms, up 4 kilograms",
                DeepLinks.exercise("bench"),
            )
        }
        run("overload", 160, 160, preview) {
            assertOpens(
                "Beat last time. Bench Press: 80 kilograms for 6 reps, 5 days ago. Today: 82.5 kilograms for 6 reps in 4 sets.",
                DeepLinks.exercise("bench"),
            )
        }
        run("lift-trend", 320, 150, preview) {
            assertOpens(
                "Bench Press: estimated one-rep max 96 kilograms, down 3 kilograms since the last session, personal record 99 kilograms",
                DeepLinks.exercise("bench"),
            )
        }
        run("pr-spotlight", 160, 160, empty) {
            assertOpens("No personal records yet. Your first record shows up here.", DeepLinks.hub)
        }
    }

    @Test
    fun theStartButtonsStartTheRightWorkout() {
        run("next-up", 160, 160, preview) { assertOpens("Start Upper A · Push", DeepLinks.startNext) }
        run("training-week", 320, 320, preview) { assertOpens("Start Upper A · Push", DeepLinks.startNext) }
        run("training-week", 320, 320, empty) { assertOpens("Open Pulse Strength", DeepLinks.hub) }
    }

    @Test
    fun aRunningWorkoutIsResumedInsteadOfStartedAgain() {
        val running = preview.copy(active = HomeFixtures.runningWorkout())
        run("next-up", 160, 160, running) { assertOpens("Resume Upper A · Push", DeepLinks.workout) }
        run("training-week", 320, 320, running) { assertOpens("Resume Upper A · Push", DeepLinks.workout) }
    }

    @Test
    fun everyTemplateRowStartsThatTemplateAndTheEmptyWorkoutHasItsOwnLink() {
        run("template-launcher", 320, 320, preview) {
            assertOpens("Start Upper A · Push, next in your rotation", DeepLinks.start("00000000-0000-4000-8000-0000000000a1"))
            assertOpens("Start Lower A · Quads", DeepLinks.start("00000000-0000-4000-8000-0000000000a2"))
            assertOpens("Start Upper B · Pull", DeepLinks.start("00000000-0000-4000-8000-0000000000a3"))
            assertOpens("Start an empty workout", DeepLinks.startEmpty("Workout"))
        }
    }
}

/** Glance renders at most this many children of a Row, Column or Box and drops the rest without a warning. */
private const val GLANCE_CHILD_LIMIT = 10
