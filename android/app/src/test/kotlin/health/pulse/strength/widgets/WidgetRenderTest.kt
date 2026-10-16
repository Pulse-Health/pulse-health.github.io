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
import com.google.common.truth.Truth.assertWithMessage
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

    private val oneByOne = mapOf("1x1-min" to DpSize(40.dp, 40.dp), "1x1-small" to DpSize(58.dp, 58.dp), "1x1" to DpSize(72.dp, 72.dp))
    private val threeByOne = mapOf("3x1-min" to DpSize(180.dp, 40.dp), "3x1-small" to DpSize(180.dp, 58.dp), "3x1" to DpSize(220.dp, 72.dp))
    private val fourByOne = mapOf("4x1-min" to DpSize(250.dp, 40.dp), "4x1-small" to DpSize(250.dp, 48.dp), "4x1" to DpSize(300.dp, 58.dp))
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

    /** The top-left corner of [this] in the coordinates of [root] (the widgets do not scroll or translate). */
    private fun View.positionIn(root: View): Pair<Int, Int> {
        var x = 0
        var y = 0
        var current: View = this
        while (current !== root) {
            x += current.left
            y += current.top
            current = current.parent as View
        }
        return x to y
    }

    /** True when the text of [this] is cut with an ellipsis, or does not fit its own box or the widget. */
    private fun TextView.isCutOff(root: View): Boolean {
        val textLayout = layout ?: return false
        val ellipsized = (0 until textLayout.lineCount).any { textLayout.getEllipsisCount(it) > 0 }
        val (x, y) = positionIn(root)
        val clipped = textLayout.height > height - compoundPaddingTop - compoundPaddingBottom + 1
        val outside = x < -1 || y < -1 || x + width > root.width + 1 || y + height > root.height + 1
        return ellipsized || clipped || outside
    }

    /** The texts of [view] that are cut off, shortened or outside the widget. */
    private fun cutOffTexts(view: View): List<CharSequence> =
        view.descendants().filterIsInstance<TextView>().filter { it.text.isNotEmpty() && it.isCutOff(view) }.map { it.text }

    /** What every widget must hold in the states that have short, known text: nothing is cut off, shortened or outside the widget. */
    private fun checkFits(label: String, view: View) {
        assertWithMessage("$label: text that does not fit").that(cutOffTexts(view)).isEmpty()
    }

    private fun checkStructure(label: String, view: View, bitmap: Bitmap) {
        assertWithMessage("$label: rules of every widget").that(structuralProblems(view, bitmap)).isEmpty()
    }

    /** What every widget must hold in every state, as a list of what it breaks (empty when it holds). */
    private fun structuralProblems(view: View, bitmap: Bitmap): List<String> {
        val problems = mutableListOf<String>()
        val views = view.descendants()
        // Something is drawn: not just the ground colour.
        val ground = bitmap.getPixel(0, 0)
        val pixels = IntArray(bitmap.width * bitmap.height).also { bitmap.getPixels(it, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height) }
        if (pixels.count { it != ground } <= pixels.size / 50) problems += "almost nothing is drawn"
        // Every image says what it is, or is part of a card that does, or is marked as decoration.
        for (image in views.filterIsInstance<ImageView>()) {
            val decorative = image.importantForAccessibility == View.IMPORTANT_FOR_ACCESSIBILITY_NO
            if (!decorative && !image.hasDescribedAncestorOrSelf()) problems += "an image has no description"
        }
        // Every tap target is at least 48 dp each way, or the whole widget where the launcher offers less (a 1x1 cell may be 40 dp).
        for (target in views.filter { it.hasOnClickListeners() }) {
            if (target.width < minOf(dp(48f), view.width) - 1 || target.height < minOf(dp(48f), view.height) - 1) {
                problems += "a tap target of ${target.width} by ${target.height} px"
            }
        }
        if (views.none { it.hasOnClickListeners() }) problems += "nothing can be tapped"
        return problems
    }

    private fun renderEverything(mode: String) {
        val problems = mutableListOf<String>()
        for (scenario in scenarios) {
            for ((stateName, snapshot) in states()) {
                for ((sizeName, size) in scenario.sizes) {
                    val (view, bitmap) = render(scenario.widget, snapshot, size)
                    val name = "${scenario.name}-$stateName-$sizeName"
                    save(bitmap, mode, name)
                    problems += structuralProblems(view, bitmap).map { "$mode/$name: $it" }
                    // The long texts are meant to be shortened; every other state has to fit as it is.
                    val cut = if (stateName == "long") emptyList() else cutOffTexts(view)
                    if (cut.isNotEmpty()) problems += "$mode/$name: text that does not fit $cut"
                }
            }
        }
        assertWithMessage("states that break a rule of every widget").that(problems).isEmpty()
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
                checkFits("log-set-$name-$sizeName", view)
            }
        }
    }

    private fun texts(view: View): List<String> = view.descendants().filterIsInstance<TextView>().map { it.text.toString() }

    @Test
    fun theTimelineLegendNamesEveryKindOfTheBarEvenInTheSmallestWidget() {
        for (size in fourByTwo.values) {
            val (view, _) = render(SessionTimelineWidget(), WidgetFixtures.preview, size)
            assertThat(texts(view)).containsAtLeast("Lifting", "Rest", "Long rest")
        }
    }

    @Test
    fun theTimelineSummaryKeepsTheLongestPartThatFits() {
        val (wide, _) = render(SessionTimelineWidget(), WidgetFixtures.preview, DpSize(320.dp, 146.dp))
        assertThat(texts(wide)).contains(" · 38% under tension · 1 long break")
        val (narrow, _) = render(SessionTimelineWidget(), WidgetFixtures.preview, DpSize(250.dp, 110.dp))
        val tail = texts(narrow).single { it.startsWith(" · 38%") }
        assertThat(tail).isNotEqualTo(" · 38% under tension · 1 long break")
    }

    @Test
    fun fourPartnerLinesAndTheSentenceUnderThemAllShow() {
        val preview = WidgetFixtures.preview
        val friends = listOf("Alexandria", "Bartholomew", "Cornelia").mapIndexed { index, name ->
            preview.partners.first().copy(name = name, initials = name.take(2).uppercase(), completed = index + 1, closedWeek = false)
        }
        val (view, _) = render(PartnerWidget(), preview.copy(partners = friends + preview.partners), DpSize(320.dp, 240.dp))
        assertThat(texts(view)).containsAtLeast("You", "AL", "BA", "CO", "Sam closed their week. Your turn.")
    }

    @Test
    fun tenSetDotsDoNotPushTheProgressOutOfTheLogSetWidget() {
        val active = WidgetFixtures.active().copy(exerciseSetCount = 10, exerciseDoneSets = 4)
        val (view, _) = render(LogSetWidget(), WidgetFixtures.preview.copy(active = active), DpSize(320.dp, 146.dp))
        assertThat(texts(view).any { it.startsWith("6 reps · 6 of 20 sets") }).isTrue()
        checkFits("ten dots", view)
    }

    @Test
    fun theLogSetStepperKeepsTheUnitWhenThereIsRoomAndTheNumberWhenThereIsNot() {
        val weight = WidgetFixtures.preview.copy(active = WidgetFixtures.active())
        assertThat(texts(render(LogSetWidget(), weight, DpSize(320.dp, 146.dp)).first)).contains("82.5 kg")
        assertThat(texts(render(LogSetWidget(), weight, DpSize(250.dp, 110.dp)).first)).contains("82.5")
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

    @Test
    fun aLongBreakAndALongStreakStayOnTheirLineInTheSmallCircles() {
        val preview = WidgetFixtures.preview
        val lapsed = preview.copy(week = preview.week.copy(daysSinceLastWorkout = 104, streakWeeks = 104))
        for ((sizeName, size) in oneByOne) {
            val days = render(DaysSinceWidget(), lapsed, size).first
            assertThat(texts(days)).contains("104d")
            checkFits("days-since-104-$sizeName", days)
            val streak = render(StreakWidget(), lapsed, size).first
            assertThat(texts(streak)).contains("104 wk")
            checkFits("streak-104-$sizeName", streak)
        }
    }

    @Test
    fun theStrengthRatioAsksForTheBodyweightAtEverySizeWithoutCuttingIt() {
        val preview = WidgetFixtures.preview
        val noBodyweight = preview.copy(strengthRatio = preview.strengthRatio?.copy(bodyweightKg = null, ratio = null))
        for ((sizeName, size) in twoByTwo) {
            val (view, bitmap) = render(StrengthRatioWidget(), noBodyweight, size)
            save(bitmap, "light", "strength-ratio-no-bodyweight-$sizeName")
            checkFits("strength-ratio-no-bodyweight-$sizeName", view)
            assertThat(texts(view)).contains("99 kg")
        }
    }

    @Test
    fun theReadinessAdviceIsShownWholeAtEverySizeWhileItFits() {
        val advice = "Good sleep, steady HRV. Go for the top set."
        for ((sizeName, size) in fourByTwo) {
            val (view, _) = render(ReadinessWidget(), WidgetFixtures.preview, size)
            assertThat(texts(view)).contains(advice)
            checkFits("readiness-$sizeName", view)
        }
    }
}
