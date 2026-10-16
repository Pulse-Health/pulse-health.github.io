package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseActions
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetSizes

/**
 * HS-01 Next up (2x2) and HS-07 Next workout, previewed (4x2): the template to train next, a Start button, and, once the widget is wide
 * enough, its first exercises with the planned sets × weight. While a workout runs it turns into a Resume card for that workout.
 */
class NextUpWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        NextUpContent(snapshot)
    }
}

/** The 2x2 provider (also offered on the glanceable hub, SB-01). */
class NextUpReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = NextUpWidget()
}

/** The 4x2 provider: the same widget placed wide, listed separately in the picker. */
class NextUpWideReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = NextUpWidget()
}

/** One planned exercise (or, while training, the current set) as a line of the wide card. */
internal data class NextUpRow(val title: String, val trailing: String)

internal data class NextUpButton(val label: String, val link: String, val description: String)

/** What the card says. Pure data, so the choice of texts and targets is unit tested without Glance. */
internal data class NextUpCard(
    val eyebrow: String,
    val title: String,
    /** Under the title of the compact card. */
    val summary: String?,
    /** Under the title of the wide card, which shows [rows] beside it. */
    val wideSummary: String?,
    /** The training plan the template belongs to and its place in it, when there is a plan. */
    val planLine: String?,
    /** Shown when there is nothing to start. */
    val message: String?,
    val button: NextUpButton?,
    val rows: List<NextUpRow>,
    val description: String,
    /** The same for a screen reader when the wide card shows [rows] too (a described card hides its children from the reader). */
    val wideDescription: String,
)

internal object NextUpModel {
    const val EmptyMessage = "Open Pulse Strength to create a workout"
    private const val EmptyTitle = "No workouts yet"

    fun card(snapshot: WidgetSnapshot): NextUpCard {
        val active = snapshot.active
        val next = snapshot.nextUp
        return when {
            active != null -> {
                val progress = "${active.loggedSets} of ${active.totalSets} sets"
                NextUpCard(
                    eyebrow = "In progress",
                    title = active.workoutName,
                    summary = progress,
                    wideSummary = progress,
                    planLine = null,
                    message = null,
                    button = NextUpButton("Resume", DeepLinks.workout, "Resume ${active.workoutName}"),
                    rows = listOfNotNull(
                        NextUpRow(active.exerciseName, active.setLabel),
                        active.nextSetText.takeIf { it.isNotBlank() }?.let { NextUpRow("Next", it) },
                    ),
                    description = "Workout in progress: ${active.workoutName}, $progress logged",
                    wideDescription = "Workout in progress: ${active.workoutName}, $progress logged. " +
                        "Now: ${active.exerciseName}, ${active.setLabel}" +
                        (active.nextSetText.takeIf { it.isNotBlank() }?.let { ". Next: $it" } ?: ""),
                )
            }
            next != null -> {
                val summary = HomeText.dotted(
                    HomeText.exercises(next.exerciseCount),
                    next.estimatedMinutes.takeIf { it > 0 }?.let { HomeText.minutes(it) },
                )
                NextUpCard(
                    eyebrow = "Next up",
                    title = next.name,
                    summary = summary,
                    wideSummary = lastDone(next.daysSince),
                    planLine = planLine(next.planName, next.planPosition, next.planCount),
                    message = null,
                    button = NextUpButton("Start", DeepLinks.startNext, "Start ${next.name}"),
                    rows = next.exercises.map { NextUpRow(it.name, it.summary) },
                    description = "Next up: ${next.name}, $summary",
                    wideDescription = "Next up: ${next.name}, $summary" +
                        (planLine(next.planName, next.planPosition, next.planCount)?.let { ". $it" } ?: "") +
                        (next.exercises.takeIf { it.isNotEmpty() }?.joinToString("; ", prefix = ". Exercises: ") { "${it.name} ${it.summary}" } ?: ""),
                )
            }
            else -> NextUpCard(
                eyebrow = "Next up",
                title = EmptyTitle,
                summary = null,
                wideSummary = null,
                planLine = null,
                message = EmptyMessage,
                button = null,
                rows = emptyList(),
                description = "$EmptyTitle. $EmptyMessage",
                wideDescription = "$EmptyTitle. $EmptyMessage",
            )
        }
    }

    /** "Upper / Lower · workout 1 of 3"; null without a plan. */
    fun planLine(name: String?, position: Int?, count: Int?): String? {
        if (name.isNullOrBlank()) return null
        return HomeText.dotted(name, if (position != null && count != null) "workout $position of $count" else null)
    }

    /** "Done 5 days ago", "Done today", "Not done yet". */
    fun lastDone(daysSince: Int?): String = when {
        daysSince == null -> "Not done yet"
        daysSince <= 0 -> "Done today"
        daysSince == 1 -> "Done yesterday"
        else -> "Done $daysSince days ago"
    }

    /** Preview rows that fit into [availableDp] of height (a row is 24 dp, the "+ N more" line 18 dp). */
    fun visibleRows(availableDp: Float, total: Int): Int {
        if (total == 0) return 0
        val all = HomeLayout.rowsThatFit(availableDp, ROW_DP, max = MAX_ROWS)
        if (all >= total) return total
        return HomeLayout.rowsThatFit(availableDp, ROW_DP, reserveDp = MORE_DP, max = MAX_ROWS).coerceAtLeast(1)
    }

    private const val ROW_DP = 24f
    private const val MORE_DP = 18f
    private const val MAX_ROWS = 6
}

@Composable
internal fun NextUpContent(snapshot: WidgetSnapshot) {
    val card = NextUpModel.card(snapshot)
    val size = LocalSize.current
    if (WidgetSizes.isWide(size)) WideNextUp(card, size) else CompactNextUp(card, size)
}

@Composable
private fun CompactNextUp(card: NextUpCard, size: DpSize) {
    val roomForSummary = size.height >= 124.dp
    val titleLines = if (size.height >= 142.dp) 2 else 1
    WidgetCard(
        padding = 12.dp,
        bottomPadding = if (card.button != null) 4.dp else 12.dp,
        description = card.description,
    ) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Eyebrow(card.eyebrow)
            Spacer(GlanceModifier.height(2.dp))
            Label(card.title, 17.sp, GlanceTheme.colors.onSurface, FontWeight.Bold, maxLines = titleLines)
            if (roomForSummary && card.summary != null) {
                Label(card.summary, 13.sp, GlanceTheme.colors.onSurfaceVariant)
            }
            if (card.message != null) {
                Label(card.message, 13.sp, GlanceTheme.colors.onSurfaceVariant, maxLines = if (size.height >= 130.dp) 3 else 2)
            }
            Spacer(GlanceModifier.defaultWeight())
            card.button?.let { StartButton(it) }
        }
    }
}

@Composable
private fun WideNextUp(card: NextUpCard, size: DpSize) {
    val leftWidth = ((size.width - 24.dp) * 0.38f).coerceIn(104.dp, 160.dp)
    val shown = NextUpModel.visibleRows(size.height.value - 16f, card.rows.size)
    val titleLines = if (size.height >= 170.dp) 2 else 1
    // Title, button and the touch margin of the button take 103 dp: below 124 dp there is no room for the line under the title.
    val roomForSummary = size.height >= 124.dp
    val roomForPlan = size.height >= 140.dp
    WidgetCard(padding = 12.dp, bottomPadding = if (card.button != null) 4.dp else 12.dp, description = card.wideDescription) {
        Row(modifier = GlanceModifier.fillMaxSize()) {
            Column(modifier = GlanceModifier.width(leftWidth).fillMaxHeight()) {
                Eyebrow(card.eyebrow)
                Spacer(GlanceModifier.height(2.dp))
                Label(card.title, 17.sp, GlanceTheme.colors.onSurface, FontWeight.Bold, maxLines = titleLines)
                if (roomForSummary) card.wideSummary?.let { Label(it, 13.sp, GlanceTheme.colors.onSurfaceVariant) }
                if (roomForPlan) card.planLine?.let { Label(it, 13.sp, GlanceTheme.colors.onSurfaceVariant) }
                Spacer(GlanceModifier.defaultWeight())
                card.button?.let { StartButton(it) }
            }
            Box(modifier = GlanceModifier.width(1.dp).fillMaxHeight().background(HomeColors.separator)) {}
            Column(
                modifier = GlanceModifier.defaultWeight().fillMaxHeight().padding(start = 14.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (card.rows.isEmpty()) {
                    Label(card.message ?: "No exercises in this template yet", 14.sp, GlanceTheme.colors.onSurfaceVariant, maxLines = 3)
                } else {
                    card.rows.take(shown).forEach { row ->
                        Row(modifier = GlanceModifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                            Label(row.title, 14.sp, GlanceTheme.colors.onSurface, modifier = GlanceModifier.defaultWeight())
                            Label(row.trailing, 14.sp, GlanceTheme.colors.onSurfaceVariant, maxLines = 1)
                        }
                    }
                    val more = card.rows.size - shown
                    if (more > 0) {
                        Label("+ $more more", 13.sp, GlanceTheme.colors.onSurfaceVariant, modifier = GlanceModifier.padding(top = 3.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun StartButton(button: NextUpButton) {
    PillButton(
        label = button.label,
        action = PulseActions.link(button.link),
        modifier = GlanceModifier.fillMaxWidth(),
        icon = HomeIcons.Play,
        description = button.description,
    )
}
