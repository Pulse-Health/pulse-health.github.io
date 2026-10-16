package health.pulse.strength.widgets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.widget.Chronometer
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseColors
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.extras.BodyMapWidget
import health.pulse.strength.widgets.extras.FormCueWidget
import health.pulse.strength.widgets.extras.LoadedBarWidget
import health.pulse.strength.widgets.extras.LogSetWidget
import health.pulse.strength.widgets.extras.PartnerWidget
import health.pulse.strength.widgets.extras.PlateauWidget
import health.pulse.strength.widgets.extras.ReadinessWidget
import health.pulse.strength.widgets.extras.RestDayWidget
import health.pulse.strength.widgets.extras.SessionTimelineWidget
import health.pulse.strength.widgets.extras.StrengthRatioWidget
import health.pulse.strength.widgets.extras.YearInIronWidget
import health.pulse.strength.widgets.lock.DaysSinceWidget
import health.pulse.strength.widgets.lock.InlineStatusWidget
import health.pulse.strength.widgets.lock.NextUpCompactWidget
import health.pulse.strength.widgets.lock.OverloadCompactWidget
import health.pulse.strength.widgets.lock.PrCompactWidget
import health.pulse.strength.widgets.lock.QuickStartWidget
import health.pulse.strength.widgets.lock.StreakWidget
import health.pulse.strength.widgets.lock.WeeklyGoalCompactWidget
import health.pulse.strength.widgets.lock.WeeklySetsCompactWidget
import java.io.File
import java.io.FileOutputStream
import java.time.Instant
import kotlin.math.roundToInt
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Composes every lock-screen and extras widget the way the launcher receives it (a `RemoteViews`), inflates it, draws it into
 * `build/widgets/<light|dark>/<widget>-<state>-<size>.png` and checks the rules that hold for all of them: something is drawn, every
 * image has a description of its own or inside the card it belongs to, and every tap target is at least 48 dp. Nothing has run on a launcher;
 * this is the closest the JVM gets.
 */
@OptIn(ExperimentalGlanceRemoteViewsApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class WidgetRenderTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    /** A widget with the sizes it is checked at: the smallest a launcher offers, and a typical one. */
    private class Scenario(val name: String, val widget: PulseWidget, val sizes: Map<String, DpSize>)

    private val oneByOne = mapOf("1x1-small" to DpSize(58.dp, 58.dp), "1x1" to DpSize(72.dp, 72.dp))
    private val threeByOne = mapOf("3x1-small" to DpSize(180.dp, 58.dp), "3x1" to DpSize(220.dp, 72.dp))
    private val fourByOne = mapOf("4x1-small" to DpSize(250.dp, 48.dp), "4x1" to DpSize(300.dp, 58.dp))
    private val twoByTwo = mapOf("2x2-small" to DpSize(110.dp, 110.dp), "2x2" to DpSize(146.dp, 146.dp))
    private val fourByTwo = mapOf("4x2-small" to DpSize(250.dp, 110.dp), "4x2" to DpSize(320.dp, 146.dp), "4x2-tall" to DpSize(320.dp, 190.dp))

    private val scenarios = listOf(
        Scenario("weekly-goal-compact", WeeklyGoalCompactWidget(), oneByOne),
        Scenario("days-since", DaysSinceWidget(), oneByOne),
        Scenario("streak", StreakWidget(), oneByOne),
        Scenario("quick-start", QuickStartWidget(), oneByOne),
        Scenario("next-up-compact", NextUpCompactWidget(), threeByOne),
        Scenario("weekly-sets-compact", WeeklySetsCompactWidget(), threeByOne),
        Scenario("pr-compact", PrCompactWidget(), threeByOne),
        Scenario("overload-compact", OverloadCompactWidget(), threeByOne),
        Scenario("inline-week", InlineStatusWidget(InlineStatusWidget.Mode.WEEK), fourByOne),
        Scenario("inline-split", InlineStatusWidget(InlineStatusWidget.Mode.SPLIT), fourByOne),
        Scenario("inline-rest", InlineStatusWidget(InlineStatusWidget.Mode.REST), fourByOne),
        Scenario("body-map", BodyMapWidget(), fourByTwo),
        Scenario("log-set", LogSetWidget(), fourByTwo),
        Scenario("partner", PartnerWidget(), fourByTwo),
        Scenario("form-cue", FormCueWidget(), twoByTwo),
        Scenario("loaded-bar", LoadedBarWidget(), twoByTwo),
        Scenario("rest-day", RestDayWidget(), twoByTwo),
        Scenario("strength-ratio", StrengthRatioWidget(), twoByTwo),
        Scenario("year-in-iron", YearInIronWidget(), twoByTwo),
        Scenario("readiness", ReadinessWidget(), fourByTwo),
        Scenario("plateau", PlateauWidget(), fourByTwo),
        Scenario("session-timeline", SessionTimelineWidget(), fourByTwo),
    )

    /** The snapshots every widget is drawn from: the idealised preview (a rest day), the same on a training day, a fresh install, and long texts. */
    private fun states(): Map<String, WidgetSnapshot> {
        val preview = WidgetFixtures.preview
        return mapOf(
            "preview" to preview,
            "training-day" to preview.copy(restDay = null),
            "empty" to WidgetFixtures.empty(),
            "long" to preview.copy(
                nextUp = preview.nextUp?.copy(
                    name = "Upper A · Incline Dumbbell Press and Cable Crossover Push",
                    splitLabel = "Incline Dumbbell Press and Cable Crossover day",
                ),
                latestPR = preview.latestPR?.copy(exerciseName = "Incline Dumbbell Bench Press with Pause"),
                overload = preview.overload?.copy(exerciseName = "Incline Dumbbell Bench Press with Pause"),
                formCue = preview.formCue?.copy(
                    exerciseName = "Incline Dumbbell Bench Press with Pause",
                    cue = "Keep your shoulder blades pulled back and down, your feet planted, and press the dumbbells up and slightly in over your chest.",
                ),
                lastSession = preview.lastSession?.copy(name = "Upper B · Barbell Row and Weighted Pull-up Pull"),
                strengthRatio = preview.strengthRatio?.copy(exerciseName = "Incline Dumbbell Bench Press with Pause"),
                readiness = preview.readiness?.copy(message = "Good sleep, steady heart rate variability and a calm week. Go for the top set and add a back-off set."),
                partners = listOf(
                    preview.partners.first().copy(name = "Alexandria", initials = "AL", completed = 2, closedWeek = false),
                    preview.partners.first().copy(name = "Bartholomew", initials = "BA", completed = 4, closedWeek = true),
                    preview.partners.first().copy(name = "Cornelia", initials = "CO", completed = 1, closedWeek = false),
                ),
            ),
        )
    }

    private fun dp(value: Float): Int = (value * context.resources.displayMetrics.density).roundToInt()

    private fun render(widget: PulseWidget, snapshot: WidgetSnapshot, size: DpSize): Pair<View, Bitmap> = runBlocking {
        val views = GlanceRemoteViews().compose(context = context, size = size) {
            GlanceTheme(colors = PulseColors.colors) { widget.Content(snapshot) }
        }.remoteViews
        val width = dp(size.width.value)
        val height = dp(size.height.value)
        val view = views.apply(context, FrameLayout(context))
        view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        view.layout(0, 0, width, height)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val night = context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES
        val canvas = Canvas(bitmap)
        canvas.drawColor(if (night) Color.rgb(0x10, 0x12, 0x15) else Color.rgb(0xE9, 0xE9, 0xEE))
        view.draw(canvas)
        view to bitmap
    }

    private fun save(bitmap: Bitmap, mode: String, name: String) {
        val file = File("build/widgets/$mode/$name.png")
        file.parentFile?.mkdirs()
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun View.descendants(): List<View> =
        listOf(this) + if (this is ViewGroup) (0 until childCount).flatMap { getChildAt(it).descendants() } else emptyList()

    private fun View.hasDescribedAncestorOrSelf(): Boolean {
        var current: View? = this
        while (current != null) {
            if (!current.contentDescription.isNullOrBlank()) return true
            current = current.parent as? View
        }
        return false
    }

    private fun checkStructure(label: String, view: View, bitmap: Bitmap) {
        val views = view.descendants()
        // Something is drawn: not just the ground colour.
        val ground = bitmap.getPixel(0, 0)
        val pixels = IntArray(bitmap.width * bitmap.height).also { bitmap.getPixels(it, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height) }
        assertThat(pixels.count { it != ground }).isGreaterThan(pixels.size / 50)
        // Every image says what it is, or is part of a card that does, or is marked as decoration.
        for (image in views.filterIsInstance<ImageView>()) {
            val decorative = image.importantForAccessibility == View.IMPORTANT_FOR_ACCESSIBILITY_NO
            assertThat(decorative || image.hasDescribedAncestorOrSelf()).isTrue()
        }
        // Every tap target is at least 48 dp each way.
        val minimum = dp(48f) - 1
        for (target in views.filter { it.hasOnClickListeners() }) {
            assertThat(target.width).isAtLeast(minimum)
            assertThat(target.height).isAtLeast(minimum)
        }
        assertThat(views.any { it.hasOnClickListeners() }).isTrue()
        assertThat(label).isNotEmpty()
    }

    private fun renderEverything(mode: String) {
        for (scenario in scenarios) {
            for ((stateName, snapshot) in states()) {
                for ((sizeName, size) in scenario.sizes) {
                    val (view, bitmap) = render(scenario.widget, snapshot, size)
                    val name = "${scenario.name}-$stateName-$sizeName"
                    save(bitmap, mode, name)
                    checkStructure("$mode/$name", view, bitmap)
                }
            }
        }
    }

    @Test
    fun everyWidgetRendersInLightMode() = renderEverything("light")

    @Test
    fun everyWidgetRendersInDarkMode() {
        RuntimeEnvironment.setQualifiers("+night")
        renderEverything("dark")
    }

    @Test
    fun logSetRendersEveryPhaseOfARunningWorkout() {
        val situations = mapOf(
            "logging-weight" to WidgetFixtures.active(),
            "logging-reps" to WidgetFixtures.active(tracking = TrackingKind.REPS_ONLY),
            "logging-timed" to WidgetFixtures.active(tracking = TrackingKind.DURATION),
            "resting" to WidgetFixtures.active(SnapshotPhase.RESTING, restRemainingSeconds = 75, at = Instant.now()),
            "rest-over" to WidgetFixtures.active(SnapshotPhase.REST_OVER),
            "paused" to WidgetFixtures.active(SnapshotPhase.RESTING, isPaused = true, restRemainingSeconds = 42),
            "complete" to WidgetFixtures.active(SnapshotPhase.COMPLETE),
        )
        for ((name, active) in situations) {
            for ((sizeName, size) in fourByTwo) {
                val (view, bitmap) = render(LogSetWidget(), WidgetFixtures.preview.copy(active = active), size)
                save(bitmap, "light", "log-set-$name-$sizeName")
                checkStructure("log-set-$name-$sizeName", view, bitmap)
            }
        }
    }

    @Test
    fun theRestCountdownIsASystemChronometerCountingDown() {
        val active = WidgetFixtures.active(SnapshotPhase.RESTING, restRemainingSeconds = 75, at = Instant.now())
        val (view, _) = render(LogSetWidget(), WidgetFixtures.preview.copy(active = active), DpSize(320.dp, 146.dp))
        val chronometer = view.descendants().filterIsInstance<Chronometer>().single()
        assertThat(chronometer.isCountDown).isTrue()
        assertThat(view.descendants().filterIsInstance<TextView>().map { it.text.toString() }).containsAtLeast("+15 s", "Skip")
    }

    @Test
    fun aSnapshotThatOutlivedItsRestShowsNoCountdown() {
        val stale = WidgetFixtures.active(SnapshotPhase.RESTING, restRemainingSeconds = -30, at = Instant.now())
        val (view, _) = render(LogSetWidget(), WidgetFixtures.preview.copy(active = stale), DpSize(320.dp, 146.dp))
        assertThat(view.descendants().filterIsInstance<Chronometer>()).isEmpty()
        assertThat(view.descendants().filterIsInstance<TextView>().map { it.text.toString() }).contains("Log set")
    }
}
