package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import health.pulse.strength.core.widgets.DayCell
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseActions
import health.pulse.strength.widgets.common.PulseWidget

/**
 * HS-10 Training week (4x4): the week strip, the last session, the latest record and the button for the next workout. The last session
 * and the record are dropped, in that order, when the widget is too short for them.
 */
class TrainingWeekWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        TrainingWeekContent(snapshot)
    }
}

class TrainingWeekReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TrainingWeekWidget()
}

internal enum class DayKind { DONE, TODAY, EMPTY }

/** One circle of the strip: [label] holds the initials of the workout on a [DayKind.DONE] day. */
internal data class WeekDay(val letter: String, val label: String?, val kind: DayKind)

internal data class SessionStat(val value: String, val unit: String?, val caption: String)

internal data class LastSessionCard(val name: String, val day: String, val stats: List<SessionStat>, val description: String)

internal data class RecordRow(val title: String, val figure: String)

/** The big button at the bottom: Start, Resume, or the way into the app when there is no template. */
internal data class WeekAction(val label: String, val link: String, val description: String, val primary: Boolean)

internal data class TrainingWeekCard(
    val progress: String,
    val days: List<WeekDay>,
    val session: LastSessionCard?,
    val record: RecordRow?,
    val action: WeekAction,
    val message: String?,
    val description: String,
)

/** Which optional blocks fit. */
internal data class WeekSections(val session: Boolean, val record: Boolean)

internal object TrainingWeekModel {
    const val EmptySessionTitle = "No sessions yet"
    const val EmptySessionText = "Your first workout shows up here."

    private const val BASE_DP = 14f + 6f + 22f + 64f + 10f + 48f
    private const val SESSION_DP = 108f
    private const val RECORD_DP = 38f

    /**
     * The last session (or the placeholder that stands in for it) needs 108 dp on top of the header, the strip and the button; the record
     * line another 38 dp, and only when there is a record.
     */
    fun sections(heightDp: Float, hasRecord: Boolean): WeekSections {
        val session = heightDp >= BASE_DP + SESSION_DP
        val record = hasRecord && heightDp >= BASE_DP + (if (session) SESSION_DP else 0f) + RECORD_DP
        return WeekSections(session = session, record = record)
    }

    fun card(snapshot: WidgetSnapshot): TrainingWeekCard {
        val week = snapshot.week
        val zone = HomeDates.zoneOf(snapshot)
        val session = snapshot.lastSession?.let { last ->
            val volume = volumeParts(last.volumeKg)
            LastSessionCard(
                name = last.name,
                day = HomeDates.dayLabel(last.finishedAt, snapshot.generatedAt, zone),
                stats = listOf(
                    SessionStat(last.durationMinutes.toString(), "min", "Duration"),
                    SessionStat(last.loggedSets.toString(), null, "Sets"),
                    SessionStat(volume.first, volume.second, "Volume"),
                ),
                description = "Last session: ${last.name}, ${HomeDates.dayLabel(last.finishedAt, snapshot.generatedAt, zone)}, " +
                    "${last.durationMinutes} minutes, ${HomeText.sets(last.loggedSets)}, ${HomeText.volume(last.volumeKg)}",
            )
        }
        val record = snapshot.latestPR?.let { RecordRow("${it.exerciseName} PR", HomeText.weightReps(it.weightKg, it.reps)) }
        val active = snapshot.active
        val next = snapshot.nextUp
        val action = when {
            active != null -> WeekAction("Resume ${active.workoutName}", DeepLinks.workout, "Resume ${active.workoutName}", primary = true)
            next != null -> WeekAction("Start ${next.name}", DeepLinks.startNext, "Start ${next.name}", primary = true)
            else -> WeekAction("Open Pulse Strength", DeepLinks.hub, "Open Pulse Strength", primary = false)
        }
        val progress = "${week.completed} of ${week.goal}"
        return TrainingWeekCard(
            progress = progress,
            days = week.days.map(::day),
            session = session,
            record = record,
            action = action,
            message = if (active == null && next == null) NextUpModel.EmptyMessage else null,
            description = "Training week: $progress workouts." +
                (session?.let { " ${it.description}." } ?: "") +
                (snapshot.latestPR?.let { " Latest record: ${it.exerciseName}, ${HomeText.kg(it.weightKg)} kilograms for ${it.reps} reps." } ?: ""),
        )
    }

    private fun day(cell: DayCell): WeekDay = when {
        cell.sessions > 0 -> WeekDay(cell.letter, cell.label ?: "WO", DayKind.DONE)
        cell.isToday -> WeekDay(cell.letter, null, DayKind.TODAY)
        else -> WeekDay(cell.letter, null, DayKind.EMPTY)
    }

    /** "8.4" and "t" from one tonne on, else "850" and "kg". */
    fun volumeParts(kg: Double): Pair<String, String> {
        val text = HomeText.volume(kg)
        val split = text.lastIndexOf(' ')
        return text.substring(0, split) to text.substring(split + 1)
    }
}

@Composable
internal fun TrainingWeekContent(snapshot: WidgetSnapshot) {
    val card = TrainingWeekModel.card(snapshot)
    val size = LocalSize.current
    val sections = TrainingWeekModel.sections(size.height.value, card.record != null)
    WidgetCard(padding = 14.dp, bottomPadding = 6.dp, description = card.description) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Label("This week", 17.sp, GlanceTheme.colors.onSurface, FontWeight.Bold, GlanceModifier.defaultWeight())
                Label(card.progress, 15.sp, GlanceTheme.colors.onPrimaryContainer, FontWeight.Medium)
            }
            WeekStrip(card.days, size.width - 28.dp)
            if (sections.session) {
                Spacer(GlanceModifier.height(10.dp))
                val session = card.session
                if (session != null) SessionCard(session) else EmptySessionCard()
            }
            if (sections.record && card.record != null) {
                Spacer(GlanceModifier.height(10.dp))
                RecordLine(card.record)
            }
            Spacer(GlanceModifier.defaultWeight())
            if (card.message != null) {
                Label(card.message, 13.sp, GlanceTheme.colors.onSurfaceVariant, align = TextAlign.Center, modifier = GlanceModifier.fillMaxWidth())
            }
            ActionButton(card.action)
        }
    }
}

@Composable
private fun WeekStrip(days: List<WeekDay>, width: Dp) {
    val circle = (width / 7 - 4.dp).coerceIn(24.dp, 36.dp)
    Row(modifier = GlanceModifier.fillMaxWidth().padding(top = 10.dp)) {
        days.forEach { day ->
            Column(modifier = GlanceModifier.defaultWeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                val today = day.kind == DayKind.TODAY
                Label(
                    day.letter,
                    11.sp,
                    if (today) GlanceTheme.colors.onSurface else GlanceTheme.colors.onSurfaceVariant,
                    if (today) FontWeight.Bold else FontWeight.Normal,
                )
                Spacer(GlanceModifier.height(4.dp))
                DayCircle(day, circle)
            }
        }
    }
}

@Composable
private fun DayCircle(day: WeekDay, size: Dp) {
    when (day.kind) {
        DayKind.DONE -> Box(
            modifier = GlanceModifier.size(size).background(GlanceTheme.colors.primary).cornerRadius(size / 2),
            contentAlignment = Alignment.Center,
        ) {
            Label(day.label.orEmpty(), 11.sp, GlanceTheme.colors.onPrimary, FontWeight.Bold)
        }
        DayKind.TODAY -> Box(
            modifier = GlanceModifier.size(size).background(GlanceTheme.colors.primary).cornerRadius(size / 2),
            contentAlignment = Alignment.Center,
        ) {
            Box(modifier = GlanceModifier.size(size - 4.dp).background(GlanceTheme.colors.surface).cornerRadius((size - 4.dp) / 2)) {}
        }
        DayKind.EMPTY -> Box(
            modifier = GlanceModifier.size(size).background(GlanceTheme.colors.surfaceVariant).cornerRadius(size / 2),
        ) {}
    }
}

@Composable
private fun SessionCard(session: LastSessionCard) {
    Column(
        modifier = GlanceModifier.fillMaxWidth().background(HomeColors.rowFill).cornerRadius(14.dp).padding(12.dp),
    ) {
        Label(HomeText.eyebrow("Last session"), 12.sp, GlanceTheme.colors.onSurfaceVariant, FontWeight.Bold)
        Row(modifier = GlanceModifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Label(session.name, 15.sp, GlanceTheme.colors.onSurface, FontWeight.Medium, GlanceModifier.defaultWeight())
            Label(session.day, 13.sp, GlanceTheme.colors.onSurfaceVariant)
        }
        Row(modifier = GlanceModifier.fillMaxWidth().padding(top = 8.dp)) {
            session.stats.forEach { stat ->
                Column(modifier = GlanceModifier.defaultWeight()) {
                    Row(verticalAlignment = Alignment.Bottom) {
                        Label(stat.value, 20.sp, GlanceTheme.colors.onSurface, FontWeight.Bold)
                        stat.unit?.let { Label(" $it", 12.sp, GlanceTheme.colors.onSurfaceVariant, modifier = GlanceModifier.padding(bottom = 2.dp)) }
                    }
                    Label(stat.caption, 11.sp, GlanceTheme.colors.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun EmptySessionCard() {
    Column(
        modifier = GlanceModifier.fillMaxWidth().background(HomeColors.rowFill).cornerRadius(14.dp).padding(12.dp),
    ) {
        Label(HomeText.eyebrow("Last session"), 12.sp, GlanceTheme.colors.onSurfaceVariant, FontWeight.Bold)
        Label(TrainingWeekModel.EmptySessionTitle, 15.sp, GlanceTheme.colors.onSurface, FontWeight.Medium, GlanceModifier.padding(top = 4.dp))
        Label(TrainingWeekModel.EmptySessionText, 13.sp, GlanceTheme.colors.onSurfaceVariant, maxLines = 2)
    }
}

@Composable
private fun RecordLine(record: RecordRow) {
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = GlanceModifier.size(28.dp).background(HomeColors.goldChip).cornerRadius(8.dp),
            contentAlignment = Alignment.Center,
        ) {
            Icon(HomeIcons.Trophy, HomeColors.goldText, 16.dp)
        }
        Spacer(GlanceModifier.width(10.dp))
        Label(record.title, 14.sp, GlanceTheme.colors.onSurface, modifier = GlanceModifier.defaultWeight())
        Label(record.figure, 14.sp, GlanceTheme.colors.onSurface, FontWeight.Bold)
    }
}

@Composable
private fun ActionButton(action: WeekAction) {
    PillButton(
        label = action.label,
        action = PulseActions.link(action.link),
        modifier = GlanceModifier.fillMaxWidth(),
        container = if (action.primary) GlanceTheme.colors.primary else GlanceTheme.colors.primaryContainer,
        content = if (action.primary) GlanceTheme.colors.onPrimary else GlanceTheme.colors.onPrimaryContainer,
        description = action.description,
    )
}
