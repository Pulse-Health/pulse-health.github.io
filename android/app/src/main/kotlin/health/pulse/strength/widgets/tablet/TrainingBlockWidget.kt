package health.pulse.strength.widgets.tablet

import androidx.compose.runtime.Composable
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
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import health.pulse.strength.core.widgets.BlockCellState
import health.pulse.strength.core.widgets.TrainingBlock
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.home.Eyebrow
import health.pulse.strength.widgets.home.HomeColors
import health.pulse.strength.widgets.home.HomeIcons
import health.pulse.strength.widgets.home.HomeText
import health.pulse.strength.widgets.home.Icon
import health.pulse.strength.widgets.home.Label
import health.pulse.strength.widgets.home.NextUpModel
import health.pulse.strength.widgets.home.WidgetCard
import kotlin.math.abs

/**
 * SB-03 Training block (6x4, made for tablets): the derived four-week block as a grid of templates by weeks, and the three stat tiles
 * under it. Cells carry a glyph or a ring besides their colour, and the whole widget reads as one sentence to a screen reader.
 */
class TrainingBlockWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        TrainingBlockContent(snapshot)
    }
}

class TrainingBlockReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TrainingBlockWidget()
}

internal data class BlockStat(val value: String, val caption: String)

internal data class BlockRowCard(val label: String, val cells: List<BlockCellState>)

internal data class BlockCard(
    val title: String,
    /** The name of the training plan the next workout belongs to, when there is a plan. */
    val plan: String?,
    val weekHeaders: List<String>,
    val currentWeek: Int,
    val rows: List<BlockRowCard>,
    val stats: List<BlockStat>,
    val description: String,
)

internal object BlockModel {
    const val EmptyTitle = "No block yet"
    const val EmptyMessage = "Finish your first workout to start a four-week training block."
    private const val MAX_WEEKS = 8
    private const val CHROME_DP = 32f + 22f + 10f + 20f + 10f
    private const val STATS_DP = 62f
    private const val MIN_CELL_DP = 24f
    private const val MAX_CELL_DP = 40f

    /** Null without history (the snapshot has no block then). */
    fun card(block: TrainingBlock?, planName: String? = null): BlockCard? {
        block ?: return null
        val weeks = block.weekCount.coerceIn(1, MAX_WEEKS)
        val rows = block.rows.map { row ->
            BlockRowCard(row.label, List(weeks) { row.cells.getOrNull(it)?.state ?: BlockCellState.UPCOMING })
        }
        val lift = block.liftDeltaKg
        val stats = listOf(
            BlockStat("${block.sessionsDone} / ${block.sessionsPlanned}", "Sessions done"),
            BlockStat(
                value = if (lift == null) "–" else HomeText.signed(lift) + " kg",
                caption = (block.liftName ?: "Top lift") + " e1RM",
            ),
            BlockStat(block.sessionsMissed.toString(), "Missed"),
        )
        val title = "${block.name} · Week ${block.weekIndex} of ${block.weekCount}"
        return BlockCard(
            title = title,
            plan = planName?.takeIf { it.isNotBlank() },
            weekHeaders = List(weeks) { "Wk ${it + 1}" },
            currentWeek = block.weekIndex,
            rows = rows,
            stats = stats,
            description = "Training block, $title. ${block.sessionsDone} of ${block.sessionsPlanned} sessions done, " +
                "${block.sessionsMissed} missed. " +
                (if (lift == null) "" else "${block.liftName ?: "Top lift"} estimated one-rep max ${liftWords(lift)}. ") +
                rows.joinToString(". ") { row ->
                    row.label + ": " + row.cells.mapIndexed { index, state -> "week ${index + 1} ${stateWord(state)}" }.joinToString(", ")
                },
        )
    }

    fun stateWord(state: BlockCellState): String = when (state) {
        BlockCellState.DONE -> "done"
        BlockCellState.PLANNED -> "planned"
        BlockCellState.MISSED -> "missed"
        BlockCellState.UPCOMING -> "upcoming"
    }

    private fun liftWords(deltaKg: Double): String = when {
        abs(deltaKg) < 0.005 -> "unchanged"
        deltaKg > 0 -> "up ${HomeText.kilograms(deltaKg)}"
        else -> "down ${HomeText.kilograms(-deltaKg)}"
    }

    /** The stat tiles need 62 dp; without them (a short widget) the grid gets the room. */
    fun showStats(heightDp: Float): Boolean = heightDp >= 230f

    /** The height of a grid row: what is left after the padding, the title, the week headers and (when shown) the tiles. */
    fun cellHeight(heightDp: Float, rows: Int, stats: Boolean): Float =
        ((heightDp - CHROME_DP - (if (stats) STATS_DP else 0f)) / rows.coerceAtLeast(1)).coerceIn(MIN_CELL_DP, MAX_CELL_DP)
}

@Composable
internal fun TrainingBlockContent(snapshot: WidgetSnapshot) {
    val card = BlockModel.card(snapshot.block, snapshot.nextUp?.planName)
    if (card == null) {
        BlockEmpty(snapshot)
        return
    }
    val size = LocalSize.current
    val stats = BlockModel.showStats(size.height.value)
    val cellHeight = BlockModel.cellHeight(size.height.value, card.rows.size, stats).dp
    WidgetCard(padding = 16.dp, description = card.description) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Label(card.title, 17.sp, GlanceTheme.colors.onSurface, FontWeight.Bold, GlanceModifier.defaultWeight())
                card.plan?.let { Label(it, 13.sp, GlanceTheme.colors.onSurfaceVariant) }
            }
            Spacer(GlanceModifier.height(10.dp))
            WeekHeaders(card)
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                card.rows.forEach { row ->
                    Row(modifier = GlanceModifier.fillMaxWidth().height(cellHeight), verticalAlignment = Alignment.CenterVertically) {
                        Label(row.label, 12.sp, GlanceTheme.colors.onSurfaceVariant, modifier = GlanceModifier.width(LABEL_WIDTH))
                        row.cells.forEach { state -> BlockCell(state, GlanceModifier.defaultWeight()) }
                    }
                }
            }
            if (stats) {
                Spacer(GlanceModifier.defaultWeight())
                StatTiles(card.stats)
            }
        }
    }
}

private val LABEL_WIDTH = 56.dp

@Composable
private fun WeekHeaders(card: BlockCard) {
    Row(modifier = GlanceModifier.fillMaxWidth()) {
        Spacer(GlanceModifier.width(LABEL_WIDTH))
        card.weekHeaders.forEachIndexed { index, header ->
            val current = index + 1 == card.currentWeek
            Label(
                header,
                12.sp,
                if (current) GlanceTheme.colors.onSurface else GlanceTheme.colors.onSurfaceVariant,
                if (current) FontWeight.Bold else FontWeight.Normal,
                GlanceModifier.defaultWeight(),
                align = TextAlign.Center,
            )
        }
    }
}

/** A cell by state: done is solid with a check, planned is a ring, missed is grey with a cross, upcoming is faint. */
@Composable
private fun BlockCell(state: BlockCellState, modifier: GlanceModifier) {
    Box(modifier = modifier.fillMaxHeight().padding(3.dp)) {
        when (state) {
            BlockCellState.DONE -> Box(
                modifier = GlanceModifier.fillMaxSize().background(GlanceTheme.colors.primary).cornerRadius(8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(HomeIcons.Check, GlanceTheme.colors.onPrimary, 14.dp)
            }
            BlockCellState.PLANNED -> Box(
                modifier = GlanceModifier.fillMaxSize().background(GlanceTheme.colors.primary).cornerRadius(8.dp).padding(2.dp),
            ) {
                Box(modifier = GlanceModifier.fillMaxSize().background(GlanceTheme.colors.surface).cornerRadius(6.dp)) {}
            }
            BlockCellState.MISSED -> Box(
                modifier = GlanceModifier.fillMaxSize().background(HomeColors.trackStrong).cornerRadius(8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(HomeIcons.Close, GlanceTheme.colors.onSurface, 14.dp)
            }
            BlockCellState.UPCOMING -> Box(
                modifier = GlanceModifier.fillMaxSize().background(GlanceTheme.colors.surfaceVariant).cornerRadius(8.dp),
            ) {}
        }
    }
}

@Composable
private fun StatTiles(stats: List<BlockStat>) {
    Row(modifier = GlanceModifier.fillMaxWidth()) {
        stats.forEachIndexed { index, stat ->
            if (index > 0) Spacer(GlanceModifier.width(10.dp))
            Column(
                modifier = GlanceModifier.defaultWeight().background(HomeColors.rowFill).cornerRadius(12.dp).padding(10.dp),
            ) {
                Label(stat.value, 20.sp, GlanceTheme.colors.onSurface, FontWeight.Bold)
                Label(stat.caption, 11.sp, GlanceTheme.colors.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun BlockEmpty(snapshot: WidgetSnapshot) {
    val message = if (snapshot.templates.isEmpty()) NextUpModel.EmptyMessage else BlockModel.EmptyMessage
    WidgetCard(padding = 16.dp, description = "Training block. ${BlockModel.EmptyTitle}. $message") {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Eyebrow("Training block")
            Spacer(GlanceModifier.height(2.dp))
            Label(BlockModel.EmptyTitle, 17.sp, GlanceTheme.colors.onSurface, FontWeight.Bold)
            Label(message, 13.sp, GlanceTheme.colors.onSurfaceVariant, maxLines = 3)
        }
    }
}
