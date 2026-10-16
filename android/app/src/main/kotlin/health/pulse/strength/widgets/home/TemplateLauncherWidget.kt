package health.pulse.strength.widgets.home

import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.unit.ColorProvider
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.TemplateSummary
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseActions
import health.pulse.strength.widgets.common.PulseWidget

/**
 * HS-11 Template launcher (4x4): a Start button for each saved template (the suggested one first and filled) and one for an empty
 * workout. As many templates as the height allows are listed; the rest are named in a "more" line that opens the app.
 */
class TemplateLauncherWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        TemplateLauncherContent(snapshot)
    }
}

class TemplateLauncherReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TemplateLauncherWidget()
}

internal data class LauncherRow(
    val templateId: String,
    val name: String,
    val subtitle: String,
    val suggested: Boolean,
    val link: String,
    val description: String,
)

/** Which templates are listed, how many are left out, and whether the caption that explains the filled button fits. */
internal data class LauncherPlan(val rows: List<LauncherRow>, val hidden: Int, val showCaption: Boolean, val message: String?)

internal object LauncherModel {
    const val EmptyWorkoutName = "Empty workout"
    const val EmptyWorkoutHint = "Add exercises as you go"
    const val Caption = "Filled button: next in your rotation"

    /** The name the engine gives a workout started without a template. */
    const val DefaultWorkoutName = "Workout"

    private const val ROW_DP = 56f
    private const val MORE_DP = 28f
    private const val CAPTION_DP = 18f
    private const val CHROME_DP = 28f + 28f + ROW_DP // padding, heading, the always present "Empty workout" row
    private const val MAX_TEMPLATES = 6

    /** The suggested template first, the others in store order. */
    fun ordered(templates: List<TemplateSummary>): List<TemplateSummary> = templates.sortedByDescending { it.isSuggested }

    fun row(template: TemplateSummary): LauncherRow = LauncherRow(
        templateId = template.templateID,
        name = template.name,
        subtitle = HomeText.dotted(
            HomeText.exercises(template.exerciseCount),
            template.estimatedMinutes.takeIf { it > 0 }?.let { HomeText.minutes(it) },
            template.daysSince?.let { HomeDates.shortAgo(it) },
        ),
        suggested = template.isSuggested,
        link = DeepLinks.start(template.templateID),
        description = "Start ${template.name}" + if (template.isSuggested) ", next in your rotation" else "",
    )

    fun plan(snapshot: WidgetSnapshot, heightDp: Float): LauncherPlan {
        val templates = ordered(snapshot.templates)
        if (templates.isEmpty()) return LauncherPlan(emptyList(), 0, showCaption = false, message = NextUpModel.EmptyMessage)
        val room = heightDp - CHROME_DP
        var shown = HomeLayout.rowsThatFit(room, ROW_DP, max = MAX_TEMPLATES).coerceAtMost(templates.size)
        if (shown < templates.size) {
            shown = HomeLayout.rowsThatFit(room, ROW_DP, reserveDp = MORE_DP, max = MAX_TEMPLATES).coerceAtMost(templates.size)
        }
        shown = shown.coerceAtLeast(1)
        val hidden = templates.size - shown
        val spare = room - shown * ROW_DP - (if (hidden > 0) MORE_DP else 0f)
        return LauncherPlan(
            rows = templates.take(shown).map(::row),
            hidden = hidden,
            showCaption = templates.any { it.isSuggested } && hidden == 0 && spare >= CAPTION_DP,
            message = null,
        )
    }

    /** The rows are buttons of their own with their own descriptions, so the card only names itself. */
    fun description(plan: LauncherPlan): String = "Start a workout" + (plan.message?.let { ". $it" } ?: "")
}

@Composable
internal fun TemplateLauncherContent(snapshot: WidgetSnapshot) {
    val plan = LauncherModel.plan(snapshot, LocalSize.current.height.value)
    WidgetCard(padding = 14.dp, description = LauncherModel.description(plan)) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Label("Start a workout", 17.sp, GlanceTheme.colors.onSurface, FontWeight.Bold, GlanceModifier.padding(bottom = 4.dp))
            plan.message?.let {
                Label(it, 14.sp, GlanceTheme.colors.onSurfaceVariant, maxLines = 3, modifier = GlanceModifier.padding(bottom = 8.dp))
            }
            plan.rows.forEach { row ->
                LauncherLine(
                    title = row.name,
                    subtitle = row.subtitle,
                    action = PulseActions.link(row.link),
                    icon = HomeIcons.Play,
                    container = if (row.suggested) GlanceTheme.colors.primary else GlanceTheme.colors.primaryContainer,
                    tint = if (row.suggested) GlanceTheme.colors.onPrimary else GlanceTheme.colors.onPrimaryContainer,
                    description = row.description,
                    rule = true,
                )
            }
            if (plan.hidden > 0) {
                Label(
                    "+ ${plan.hidden} more in Pulse Strength",
                    13.sp,
                    GlanceTheme.colors.onSurfaceVariant,
                    modifier = GlanceModifier.fillMaxWidth().height(28.dp).padding(top = 6.dp),
                )
            }
            LauncherLine(
                title = LauncherModel.EmptyWorkoutName,
                subtitle = LauncherModel.EmptyWorkoutHint,
                action = PulseActions.link(DeepLinks.startEmpty(LauncherModel.DefaultWorkoutName)),
                icon = HomeIcons.Plus,
                container = GlanceTheme.colors.surfaceVariant,
                tint = GlanceTheme.colors.onSurface,
                description = "Start an empty workout",
                rule = false,
            )
            if (plan.showCaption) {
                Spacer(GlanceModifier.defaultWeight())
                Label(LauncherModel.Caption, 12.sp, GlanceTheme.colors.onSurfaceVariant)
            }
        }
    }
}

/** A launcher row: the whole row is the click target (and is read as one button); the circle on the right is its picture. */
@Composable
private fun LauncherLine(
    title: String,
    subtitle: String,
    action: Action,
    @DrawableRes icon: Int,
    container: ColorProvider,
    tint: ColorProvider,
    description: String,
    rule: Boolean,
) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Row(
            modifier = GlanceModifier.fillMaxWidth().height(55.dp).clickable(action).describe(description),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = GlanceModifier.defaultWeight()) {
                Label(title, 15.sp, GlanceTheme.colors.onSurface, FontWeight.Medium)
                Label(subtitle, 13.sp, GlanceTheme.colors.onSurfaceVariant)
            }
            Spacer(GlanceModifier.width(12.dp))
            IconBadge(icon, container, tint, size = 44.dp, radius = 22.dp, iconSize = 14.dp)
        }
        if (rule) HorizontalRule()
    }
}
