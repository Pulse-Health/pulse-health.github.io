package health.pulse.strength.widgets.extras

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import health.pulse.strength.R
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.Commands
import health.pulse.strength.widgets.common.PulseActions
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.lock.Eyebrow
import health.pulse.strength.widgets.lock.FitSafety
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.TextFit
import health.pulse.strength.widgets.lock.WidgetCard
import health.pulse.strength.widgets.lock.rememberTextMeter
import health.pulse.strength.widgets.lock.textHeight

/**
 * WI-02 Log from the Home Screen (4x2, interactive): follows the running workout so a set can be adjusted and logged, and the rest timer
 * controlled, without opening the app. Every button sends a widget command; the runtime applies it and redraws the widget.
 *
 * * logging: the exercise and set, a stepper for the weight (or the reps of a bodyweight / timed exercise) and "Log set"; on a tall
 *   widget a second stepper for the reps of a weight exercise
 * * resting: a countdown that a system `Chronometer` keeps ticking, "+15 s" and "Skip"
 * * rest over, paused, all sets logged: one line and the button that fits; with no workout, "Start" for the next template
 */
class LogSetWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val view = LogSetModel.of(snapshot, System.currentTimeMillis())
        val size = LocalSize.current
        val height = textHeight()
        val padding = if (height < ExtrasText.COMPACT_BELOW_DP.dp) 10.dp else 12.dp
        val layout = Metrics(size.width, padding, tall = height >= 150.dp, showsEyebrow = (height - padding * 2).value >= MESSAGE_WITH_EYEBROW_DP)
        WidgetCard(
            description = null,
            link = if (view is LogSetView.Idle) DeepLinks.hub else DeepLinks.workout,
            padding = padding,
            contentAlignment = Alignment.TopStart,
        ) {
            when (view) {
                is LogSetView.Idle -> Message(
                    eyebrow = "Next up",
                    title = view.title,
                    detail = view.detail,
                    button = if (view.canStart) ButtonSpec("Start", Commands.startNext(), R.drawable.ic_extras_play) else null,
                    metrics = layout,
                )
                is LogSetView.Logging -> Logging(view, layout)
                is LogSetView.Resting -> Resting(view, layout)
                is LogSetView.RestOver -> Message(
                    eyebrow = "Rest over",
                    title = view.exercise,
                    detail = view.nextSet,
                    button = ButtonSpec("Log set", Commands.logNextSet()),
                    metrics = layout,
                )
                is LogSetView.Paused -> Message(
                    eyebrow = "Paused",
                    title = view.workout,
                    detail = view.detail,
                    button = ButtonSpec("Resume", PulseActions.command(WidgetCommands.RESUME)),
                    metrics = layout,
                )
                is LogSetView.Complete -> Message(
                    eyebrow = "All sets logged",
                    title = view.workout,
                    detail = view.summary,
                    button = ButtonSpec("Open", PulseActions.link(DeepLinks.workout)),
                    metrics = layout,
                )
            }
        }
    }

    /**
     * Sizes that depend on the width and height the launcher gave the widget. [showsEyebrow] is false when the height (counted for text
     * at its default size) cannot hold the eyebrow, the title and a two-line detail of a one-button message together.
     */
    private class Metrics(width: Dp, padding: Dp, val tall: Boolean, val showsEyebrow: Boolean) {
        private val wide = width >= 300.dp
        val innerWidth: Dp = width - padding * 2
        val primaryButton: Dp = if (wide) 104.dp else 80.dp
        val smallButton: Dp = if (wide) 72.dp else 64.dp
        val countdownSp: Float = if (wide) 32f else 26f

        /** What is left of a control row after the big button and the gap before it. */
        val stepperWidth: Dp = innerWidth - primaryButton - 8.dp
    }

    private class ButtonSpec(val label: String, val action: Action, val icon: Int? = null)

    /** One short text block with at most one button to its right: the states that have a single thing to do. */
    @Composable
    private fun Message(eyebrow: String, title: String, detail: String, button: ButtonSpec?, metrics: Metrics) {
        Row(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                if (metrics.showsEyebrow) Eyebrow(eyebrow)
                PulseText(title, 17.sp, weight = FontWeight.Bold)
                PulseText(detail, 13.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 2)
            }
            if (button != null) {
                Spacer(GlanceModifier.width(12.dp))
                PillButton(button.label, button.action, GlanceModifier.width(metrics.primaryButton), icon = button.icon)
            }
        }
    }

    @Composable
    private fun Logging(view: LogSetView.Logging, metrics: Metrics) {
        val weight = view.weight
        val adjusted = weight ?: view.reps
        val lighter = if (weight != null) Commands.nudge(-1, 0) else Commands.nudge(0, -1)
        val heavier = if (weight != null) Commands.nudge(1, 0) else Commands.nudge(0, 1)
        val footerMeter = rememberTextMeter(12.sp, bold = false)
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                PulseText(view.exercise, 15.sp, GlanceModifier.defaultWeight(), FontWeight.Bold)
                PulseText(" ${view.setLabel}", 13.sp, color = GlanceTheme.colors.onSurfaceVariant)
            }
            Spacer(GlanceModifier.defaultWeight())
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                StepperPill(adjusted, lighter, heavier, metrics.stepperWidth)
                Spacer(GlanceModifier.width(8.dp))
                PillButton("Log set", Commands.logNextSet(), GlanceModifier.width(metrics.primaryButton))
            }
            Spacer(GlanceModifier.defaultWeight())
            if (metrics.tall && weight != null) {
                // The reps get a stepper of their own; the dots and the progress sit under the big button's column.
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    StepperPill(view.reps, Commands.nudge(0, -1), Commands.nudge(0, 1), metrics.stepperWidth)
                    Spacer(GlanceModifier.width(8.dp))
                    Column(modifier = GlanceModifier.width(metrics.primaryButton)) {
                        SetDots(view.dots, LogSetModel.dotWidth(view.dots.size, metrics.primaryButton.value).dp)
                        val progress = TextFit.firstFitting(view.progress, metrics.primaryButton.value - FitSafety.value, footerMeter)
                        PulseText(progress, 12.sp, color = GlanceTheme.colors.onSurfaceVariant)
                    }
                }
            } else {
                val dotWidth = LogSetModel.dotWidth(view.dots.size, metrics.innerWidth.value * 0.4f)
                val dotsWidth = view.dots.size * (dotWidth + LogSetModel.DOT_GAP_DP)
                val gap = if (view.dots.isEmpty()) 0f else 8f
                val room = metrics.innerWidth.value - dotsWidth - gap - FitSafety.value
                // A weight exercise's reps are not in a stepper here, so they lead the line.
                val repsNote = if (weight != null) "${view.reps.label} · " else ""
                val lines = view.progress.map { repsNote + it } + listOf(if (weight != null) view.reps.label else "")
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    SetDots(view.dots, dotWidth.dp)
                    if (view.dots.isNotEmpty()) Spacer(GlanceModifier.width(gap.dp))
                    PulseText(TextFit.firstFitting(lines, room, footerMeter), 12.sp, GlanceModifier.defaultWeight(), color = GlanceTheme.colors.onSurfaceVariant)
                }
            }
        }
    }

    @Composable
    private fun Resting(view: LogSetView.Resting, metrics: Metrics) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Eyebrow("Rest", modifier = GlanceModifier.defaultWeight())
                PulseText(view.exercise, 13.sp, color = GlanceTheme.colors.onSurfaceVariant)
            }
            Spacer(GlanceModifier.defaultWeight())
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                RestCountdown(view.remainingMillis, metrics.countdownSp, GlanceModifier.defaultWeight())
                PillButton(
                    label = "+15 s",
                    action = Commands.adjustRest(15),
                    modifier = GlanceModifier.width(metrics.smallButton),
                    fill = GlanceTheme.colors.surfaceVariant,
                    textColor = GlanceTheme.colors.onSurface,
                    description = "Add 15 seconds of rest",
                )
                Spacer(GlanceModifier.width(8.dp))
                PillButton("Skip", Commands.skipRest(), GlanceModifier.width(metrics.smallButton), description = "Skip the rest")
            }
            Spacer(GlanceModifier.defaultWeight())
            PulseText("Next: ${view.nextSet}", 13.sp, color = GlanceTheme.colors.onSurfaceVariant)
        }
    }

    private companion object {
        /** The eyebrow, a title and a two-line detail at their default size: what a message needs to show all three. */
        val MESSAGE_WITH_EYEBROW_DP = TextFit.height(12f) + TextFit.height(17f) + TextFit.height(13f, 2)
    }
}

class LogSetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = LogSetWidget()
}
