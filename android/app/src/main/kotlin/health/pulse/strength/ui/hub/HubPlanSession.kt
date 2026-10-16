package health.pulse.strength.ui.hub

import android.content.Context
import android.text.format.DateFormat
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.live.PlannedSessions
import health.pulse.strength.services.WorkoutNotifications
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.sheets.PulseSheet
import health.pulse.strength.ui.sheets.SegmentOption
import health.pulse.strength.ui.sheets.SegmentedOptions
import health.pulse.strength.ui.sheets.SheetBarButton
import health.pulse.strength.ui.sheets.SheetSectionLabel
import health.pulse.strength.ui.sheets.SheetTitleBar
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulsePrimaryButton
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Date
import java.util.Locale
import java.util.UUID

// "Plan a session" (widgets/SPEC.md LA-06), the Android counterpart of PlanSessionSheet.swift: a template and a start time. From then on
// the notification shelf shows a countdown (30 minutes before) and "Time to train" (at the start); the workout notification, the widgets
// and the tiles stay as they are. Planning again replaces the earlier plan, and a workout that starts ends it.

/** A session the person planned: which template starts when. */
@Immutable
internal class PlannedStart(val templateID: UUID, val startsAt: Instant)

/** Where plans live. The sheet talks to this; the app implements it with [PlannedSessions] (alarms and notifications). */
internal interface SessionPlanner {
    /** The plan that is waiting, or null. */
    fun current(): PlannedStart?

    fun schedule(templateID: UUID, startsAt: Instant)

    fun cancel()

    /** False while the notifications of the app are off: the countdown could not be shown. */
    val notificationsOn: Boolean
}

internal class AndroidSessionPlanner(private val context: Context) : SessionPlanner {
    override fun current(): PlannedStart? {
        val plan = PlannedSessions.current(context) ?: return null
        val id = runCatching { UUID.fromString(plan.templateId) }.getOrNull() ?: return null
        return PlannedStart(id, Instant.ofEpochMilli(plan.startsAtMillis))
    }

    override fun schedule(templateID: UUID, startsAt: Instant) {
        PlannedSessions.schedule(context, templateID.toString(), startsAt.toEpochMilli())
    }

    override fun cancel() {
        PlannedSessions.cancel(context)
    }

    override val notificationsOn: Boolean get() = WorkoutNotifications.canNotify(context)
}

@Composable
internal fun rememberSessionPlanner(): SessionPlanner {
    val context = LocalContext.current.applicationContext
    return remember(context) { AndroidSessionPlanner(context) }
}

/** The day and time arithmetic of the sheet (pure, so it can be tested without a screen). */
internal object HubPlanTimes {
    /** The next full hour that is at least half an hour away. */
    fun suggestedStart(now: Instant, zone: ZoneId): Instant {
        val earliest = now.plus(30, ChronoUnit.MINUTES)
        val floor = earliest.atZone(zone).truncatedTo(ChronoUnit.HOURS)
        return (if (floor.toInstant() == earliest) floor else floor.plusHours(1)).toInstant()
    }

    /** [start] moved to [date], keeping the time of day. */
    fun withDate(start: Instant, date: LocalDate, zone: ZoneId): Instant =
        ZonedDateTime.of(date, start.atZone(zone).toLocalTime(), zone).toInstant()

    /** [start] moved to [time] on its own day. */
    fun withTime(start: Instant, time: LocalTime, zone: ZoneId): Instant =
        ZonedDateTime.of(start.atZone(zone).toLocalDate(), time, zone).toInstant()

    fun dayOf(start: Instant, now: Instant, zone: ZoneId): PlanDay {
        val today = now.atZone(zone).toLocalDate()
        return when (start.atZone(zone).toLocalDate()) {
            today -> PlanDay.TODAY
            today.plusDays(1) -> PlanDay.TOMORROW
            else -> PlanDay.OTHER
        }
    }

    /** "Today", "Tomorrow", or "Sat, Oct 17" in the language of the phone. */
    fun dayText(start: Instant, now: Instant, zone: ZoneId, locale: Locale): String = when (dayOf(start, now, zone)) {
        PlanDay.TODAY -> "Today"
        PlanDay.TOMORROW -> "Tomorrow"
        PlanDay.OTHER -> {
            val pattern = DateFormat.getBestDateTimePattern(locale, "EEEMMMd")
            DateTimeFormatter.ofPattern(pattern, locale).format(start.atZone(zone))
        }
    }

    /** "18:00" or "6:00 PM", as the phone is set (the notifications read the same way). */
    fun timeText(context: Context, start: Instant): String = DateFormat.getTimeFormat(context).format(Date(start.toEpochMilli()))
}

internal enum class PlanDay { TODAY, TOMORROW, OTHER }

/**
 * The sheet of a template's "Plan a session" button: day, time and "Plan Session". A plan that is waiting is shown at the bottom
 * with a way to cancel it. [templateName] names the template of that earlier plan.
 */
@Composable
internal fun HubPlanSessionSheet(
    template: WorkoutTemplate,
    planner: SessionPlanner,
    templateName: (UUID) -> String?,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val clock = LocalPulseClock.current
    val zone = remember { ZoneId.systemDefault() }
    val locale = remember { Locale.getDefault() }
    val haptics = rememberPulseHaptics()
    var startsAtMillis by rememberSaveable { mutableStateOf(HubPlanTimes.suggestedStart(clock.now(), zone).toEpochMilli()) }
    var showsDatePicker by rememberSaveable { mutableStateOf(false) }
    var showsTimePicker by rememberSaveable { mutableStateOf(false) }
    val existing = remember(planner) { planner.current() }

    val now = clock.now()
    val startsAt = Instant.ofEpochMilli(startsAtMillis)

    PulseSheet(onDismiss = onDismiss) { dismiss ->
        HubPlanSessionContent(
            templateName = template.name,
            day = HubPlanTimes.dayOf(startsAt, now, zone),
            dayText = HubPlanTimes.dayText(startsAt, now, zone, locale),
            timeText = HubPlanTimes.timeText(context, startsAt),
            canPlan = startsAt.isAfter(now),
            notificationsOn = planner.notificationsOn,
            existing = existing?.let { plan ->
                val name = templateName(plan.templateID) ?: "Workout"
                "$name, ${HubPlanTimes.dayText(plan.startsAt, now, zone, locale)} ${HubPlanTimes.timeText(context, plan.startsAt)}"
            },
            onClose = dismiss,
            onSelectDay = { day ->
                val today = now.atZone(zone).toLocalDate()
                when (day) {
                    PlanDay.TODAY -> startsAtMillis = HubPlanTimes.withDate(startsAt, today, zone).toEpochMilli()
                    PlanDay.TOMORROW -> startsAtMillis = HubPlanTimes.withDate(startsAt, today.plusDays(1), zone).toEpochMilli()
                    PlanDay.OTHER -> showsDatePicker = true
                }
            },
            onPickTime = { showsTimePicker = true },
            onPlan = {
                // The clock may have moved on while the sheet was open: a start that has passed is not planned.
                if (startsAt.isAfter(clock.now())) {
                    planner.schedule(template.id, startsAt)
                    haptics.success()
                    dismiss()
                }
            },
            onCancelPlan = {
                planner.cancel()
                dismiss()
            },
        )
    }

    if (showsDatePicker) {
        PlanDatePickerDialog(
            current = startsAt.atZone(zone).toLocalDate(),
            today = now.atZone(zone).toLocalDate(),
            onPick = { date ->
                startsAtMillis = HubPlanTimes.withDate(startsAt, date, zone).toEpochMilli()
                showsDatePicker = false
            },
            onDismiss = { showsDatePicker = false },
        )
    }
    if (showsTimePicker) {
        PlanTimePickerDialog(
            initial = startsAt.atZone(zone).toLocalTime(),
            is24Hour = DateFormat.is24HourFormat(context),
            onPick = { time ->
                startsAtMillis = HubPlanTimes.withTime(startsAt, time, zone).toEpochMilli()
                showsTimePicker = false
            },
            onDismiss = { showsTimePicker = false },
        )
    }
}

/** The body of the sheet (separate from the sheet so it can be rendered and tested on its own). */
@Composable
internal fun HubPlanSessionContent(
    templateName: String,
    day: PlanDay,
    dayText: String,
    timeText: String,
    canPlan: Boolean,
    notificationsOn: Boolean,
    existing: String?,
    onClose: () -> Unit,
    onSelectDay: (PlanDay) -> Unit,
    onPickTime: () -> Unit,
    onPlan: () -> Unit,
    onCancelPlan: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    Column(modifier.fillMaxWidth()) {
        SheetTitleBar(title = "Plan a session", leading = SheetBarButton("Close", semibold = false, onClick = onClose))
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(start = PulseMetrics.screenInset, end = PulseMetrics.screenInset, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SheetSectionLabel(templateName)
                SegmentedOptions(
                    options = listOf(
                        SegmentOption(PlanDay.TODAY, "Today"),
                        SegmentOption(PlanDay.TOMORROW, "Tomorrow"),
                        SegmentOption(
                            PlanDay.OTHER,
                            title = if (day == PlanDay.OTHER) dayText else "Pick date",
                            spoken = if (day == PlanDay.OTHER) "Another day, $dayText. Change" else "Pick another day",
                        ),
                    ),
                    selection = day,
                    onSelect = onSelectDay,
                    groupLabel = "Day",
                )
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(colors.card, HubRowShape)
                        .pulseMinHeight(52.dp)
                        .semantics(mergeDescendants = true) { contentDescription = "Start time, $timeText. Change" }
                        .pulseClickable(role = Role.Button, onClick = onPickTime)
                        .padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Starts at", style = PulseFont.body, color = colors.ink)
                    Text(timeText, style = PulseFont.number(17.sp, FontWeight.SemiBold), color = colors.greenText)
                }
                Text(
                    "A countdown appears in your notifications 30 minutes before the start, and a notification tells you when it is " +
                        "time. Planning again replaces the earlier plan, and a workout that starts ends it.",
                    style = PulseFont.footnote,
                    color = colors.inkSecondary,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
                if (!notificationsOn) {
                    Text(
                        "Notifications are off for Pulse Strength, so the countdown cannot show. Turn them on in Settings.",
                        style = PulseFont.footnote,
                        color = colors.destructive,
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                }
            }
            PulsePrimaryButton(text = "Plan Session", onClick = onPlan, enabled = canPlan)
            if (existing != null) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .background(colors.card, HubRowShape)
                            .pulseMinHeight(52.dp)
                            .pulseClickable(role = Role.Button, onClick = onCancelPlan)
                            .padding(horizontal = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Cancel the planned session", style = PulseFont.body, color = colors.destructive)
                    }
                    Text("Planned: $existing.", style = PulseFont.footnote, color = colors.inkSecondary, modifier = Modifier.padding(horizontal = 4.dp))
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlanDatePickerDialog(current: LocalDate, today: LocalDate, onPick: (LocalDate) -> Unit, onDismiss: () -> Unit) {
    val todayMillis = today.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    val state = rememberDatePickerState(
        initialSelectedDateMillis = current.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        selectableDates = object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean = utcTimeMillis >= todayMillis

            override fun isSelectableYear(year: Int): Boolean = year >= today.year
        },
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = {
                    val picked = state.selectedDateMillis
                    if (picked == null) onDismiss() else onPick(Instant.ofEpochMilli(picked).atZone(ZoneOffset.UTC).toLocalDate())
                },
            ) { Text("OK") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    ) { DatePicker(state = state) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlanTimePickerDialog(initial: LocalTime, is24Hour: Boolean, onPick: (LocalTime) -> Unit, onDismiss: () -> Unit) {
    val state = rememberTimePickerState(initialHour = initial.hour, initialMinute = initial.minute, is24Hour = is24Hour)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Start time") },
        text = { TimePicker(state = state) },
        confirmButton = { TextButton(onClick = { onPick(LocalTime.of(state.hour, state.minute)) }) { Text("OK") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
