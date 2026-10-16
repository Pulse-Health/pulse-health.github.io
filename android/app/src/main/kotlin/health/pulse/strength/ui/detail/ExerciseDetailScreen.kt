package health.pulse.strength.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.ExerciseHistory
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.ui.components.ExerciseMediaStore
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.components.rememberNow
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import java.time.Instant

/**
 * "History & records" of one exercise (port of `ExerciseDetailView`): a scrolling page with the title (muscles and equipment), the
 * looping form demo, three figure tiles (estimated 1RM with its trend, best set, 30-day volume), the estimated-1RM chart with a
 * range menu, the records table, the recent sessions, the "How To" cues and the photo attribution.
 *
 * Everything numeric comes from `StrengthStore.history(exerciseID, now)`; the screen only renders it. Full screen with its own top
 * bar (the back arrow calls [onBack]); the content scrolls and is centred in a column of at most
 * [PulseMetrics.maxContentWidth]. The screen draws edge to edge: its insets use the standard modifiers, so it also fits a bottom
 * sheet that has already consumed the top inset.
 */
@Composable
fun ExerciseDetailScreen(exercise: Exercise, store: StrengthStore, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val data by store.data.collectAsState()
    // The history is relative to "now" (the 30-day totals, the chart window); once a minute is enough.
    val now by rememberNow(periodMillis = 60_000L)
    val history = remember(exercise.id, data, now) { store.history(exercise.id, now) }
    ExerciseDetailContent(exercise = exercise, history = history, now = now, onBack = onBack, modifier = modifier)
}

/** The stateless screen: [history] is whatever `StrengthStore.history` returned for [exercise] at [now]. */
@Composable
internal fun ExerciseDetailContent(
    exercise: Exercise,
    history: ExerciseHistory,
    now: Instant,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var range by rememberSaveable { mutableStateOf(ExerciseDetailRange.TWELVE_WEEKS) }
    var showsAllSessions by rememberSaveable { mutableStateOf(false) }
    val expandedSessions = rememberSaveable(saver = ExpandedSessionsSaver) { mutableStateOf(emptySet<String>()) }
    val progress = remember(history.e1RMSeries, range, now) { ExerciseDetailProgress(history.e1RMSeries, range, now) }

    // A build without the demo photos (the release) has no form demo to show: no tile, badge or photo credit.
    val photosShipped = ExerciseMediaStore.isShipped(LocalContext.current)
    val hasMedia = photosShipped && !exercise.mediaKey.isNullOrEmpty()
    val tiles = statTiles(exercise, history, progress, now)
    val sessions = history.sessions
    val visibleSessions = if (showsAllSessions) sessions else sessions.take(COLLAPSED_SESSION_COUNT)
    val hasSeeAll = sessions.size > COLLAPSED_SESSION_COUNT

    Column(modifier.fillMaxSize().background(PulseTheme.colors.ground)) {
        ExerciseDetailTopBar(onBack)
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            // In a short window (a phone on its side) the form demo must not fill the whole screen.
            val mediaMaxHeight = (maxHeight * 0.55f).coerceAtLeast(160.dp)
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal)),
                contentPadding = PaddingValues(top = 2.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                item(key = "title", contentType = "title") {
                    ExerciseDetailTitle(exercise, Modifier.page(top = 0.dp))
                }
                if (photosShipped) {
                    item(key = "media", contentType = "media") {
                        ExerciseDetailMedia(exercise, hasMedia, mediaMaxHeight, Modifier.page())
                    }
                }
                item(key = "tiles", contentType = "tiles") {
                    ExerciseDetailStatTiles(tiles, Modifier.page())
                }
                if (exercise.tracksWeight) {
                    item(key = "chart", contentType = "chart") {
                        ExerciseDetailChartCard(
                            progress = progress,
                            hasSeries = history.e1RMSeries.isNotEmpty(),
                            range = range,
                            onRangeChange = { range = it },
                            modifier = Modifier.page(),
                        )
                    }
                }
                if (history.records.isNotEmpty()) {
                    item(key = "records", contentType = "records") {
                        ExerciseDetailRecordsSection(history.records, now, Modifier.page())
                    }
                }
                if (sessions.isEmpty()) {
                    item(key = "noSessions", contentType = "noSessions") {
                        ExerciseDetailNoSessions(Modifier.page())
                    }
                } else {
                    item(key = "sessionsHeading", contentType = "sessionsHeading") {
                        // The heading row is 48 dp tall with "See All" (its touch target); the surrounding space makes up for it.
                        ExerciseDetailSessionsHeading(
                            hasSeeAll = hasSeeAll,
                            showsAll = showsAllSessions,
                            onToggleAll = { showsAllSessions = !showsAllSessions },
                            modifier = Modifier.page(top = if (hasSeeAll) 8.dp else 20.dp, bottom = if (hasSeeAll) 0.dp else 12.dp),
                        )
                    }
                    items(visibleSessions, key = { it.id.toString() }, contentType = { "session" }) { session ->
                        ExerciseDetailSessionRow(
                            session = session,
                            tracking = exercise.tracking,
                            now = now,
                            isExpanded = session.id.toString() in expandedSessions.value,
                            onToggle = {
                                val id = session.id.toString()
                                expandedSessions.value =
                                    if (id in expandedSessions.value) expandedSessions.value - id else expandedSessions.value + id
                            },
                            modifier = Modifier.page(top = 0.dp, bottom = 8.dp),
                        )
                    }
                }
                if (exercise.cues.isNotEmpty()) {
                    item(key = "cues", contentType = "cues") {
                        ExerciseDetailCuesSection(exercise.cues, Modifier.page(top = if (sessions.isEmpty()) 20.dp else 12.dp))
                    }
                }
                if (hasMedia) {
                    item(key = "attribution", contentType = "attribution") {
                        ExerciseDetailAttribution(Modifier.page())
                    }
                }
                item(key = "bottom", contentType = "bottom") {
                    Spacer(Modifier.windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom)).height(40.dp))
                }
            }
        }
    }
}

private const val COLLAPSED_SESSION_COUNT = 3

/** The set of expanded session ids survives a configuration change (rotation, folding). */
private val ExpandedSessionsSaver = listSaver<MutableState<Set<String>>, String>(
    save = { it.value.toList() },
    restore = { mutableStateOf(it.toSet()) },
)

/** One section of the page: centred, at most [PulseMetrics.maxContentWidth] wide, with the screen gutter. */
private fun Modifier.page(top: Dp = 20.dp, bottom: Dp = 0.dp): Modifier =
    this
        .widthIn(max = PulseMetrics.maxContentWidth)
        .fillMaxWidth()
        .padding(start = PulseMetrics.screenInset, end = PulseMetrics.screenInset, top = top, bottom = bottom)

// region Top bar

/** The navigation bar of the page: just the back arrow (the design's title is empty). */
@Composable
private fun ExerciseDetailTopBar(onBack: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
            .heightIn(min = 56.dp)
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(
            onClick = onBack,
            colors = IconButtonDefaults.iconButtonColors(contentColor = PulseTheme.colors.ink),
        ) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Back")
        }
    }
}

// endregion

// region Title and media

@Composable
private fun ExerciseDetailTitle(exercise: Exercise, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = exercise.name,
            style = PulseFont.text(30.sp, FontWeight.Bold).copy(letterSpacing = 0.3.sp),
            color = colors.ink,
            modifier = Modifier.semantics { heading() },
        )
        Text(text = subtitle(exercise), style = PulseFont.text(15.sp), color = colors.inkSecondary)
    }
}

/** "Chest · Shoulders · Triceps · Barbell" */
internal fun subtitle(exercise: Exercise): String {
    val parts = mutableListOf(exercise.muscle.title)
    if (exercise.secondary.isNotEmpty() && exercise.secondary != "Custom") parts.add(exercise.secondary)
    parts.add(exercise.equipment.title)
    return parts.joinToString(" · ")
}

/** 358 x 239 in the design: full width, 3 : 2, radius 20; narrower when the window is too short for that. */
@Composable
private fun ExerciseDetailMedia(exercise: Exercise, hasMedia: Boolean, maxHeight: Dp, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(20.dp)
    val aspect = 358f / 239f
    val label = if (hasMedia) {
        "Form demo for " + exercise.name + ", alternating between the start and the end position"
    } else {
        "No form demo for this exercise yet"
    }
    BoxWithConstraints(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val width = minOf(maxWidth, maxHeight * aspect)
        Box(
            Modifier
                .width(width)
                .aspectRatio(aspect)
                .shadow(4.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.07f), spotColor = Color.Black.copy(alpha = 0.07f))
                .clip(shape)
                .clearAndSetSemantics {
                    contentDescription = label
                    role = Role.Image
                },
        ) {
            ExerciseMediaView(mediaKey = exercise.mediaKey, modifier = Modifier.fillMaxSize(), cornerRadius = 20.dp)
            if (hasMedia) {
                Text(
                    text = "Form demo",
                    style = PulseFont.text(12.sp, FontWeight.SemiBold),
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(12.dp)
                        .background(Color.Black.copy(alpha = 0.55f), CircleShape)
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                )
            }
        }
    }
}

// endregion

// region Figure tiles

/**
 * Value and trend of the estimated-1RM tile come from the same window as the chart: the best estimate of the visible sessions and
 * its gain over the first one. Without a session in the window the all-time best is shown, without a trend.
 */
@Composable
private fun statTiles(exercise: Exercise, history: ExerciseHistory, progress: ExerciseDetailProgress, now: Instant): List<DetailTile> {
    val colors = PulseTheme.colors
    val bestSet = DetailTile(
        title = "Best set",
        value = ExerciseDetailFormat.bestSet(history.bestSetText),
        detail = history.bestSetDate
            ?.takeIf { history.bestSetText != null }
            ?.let { "PR · " + StrengthResultText.monthDay(it, now) }
            ?: "–",
        detailColor = colors.prText,
        detailBold = true,
    )
    if (!exercise.tracksWeight) {
        return listOf(
            bestSet,
            DetailTile(
                title = "Sessions · 30d",
                value = history.sessionsLast30Days.toString(),
                detail = "Last 30 days",
                detailColor = colors.inkSecondary,
                detailBold = false,
            ),
        )
    }
    return listOf(
        DetailTile(
            title = "Est. 1RM",
            value = ExerciseDetailFormat.e1RM(progress.best ?: history.bestE1RM),
            detail = progress.trendText,
            detailColor = if (progress.direction == ExerciseDetailProgress.Direction.UP) colors.green else colors.inkSecondary,
            detailBold = true,
            arrow = when (progress.direction) {
                ExerciseDetailProgress.Direction.UP -> TileArrow.UP
                ExerciseDetailProgress.Direction.DOWN -> TileArrow.DOWN
                else -> TileArrow.NONE
            },
            spokenDetail = progress.spokenTrend,
        ),
        bestSet,
        DetailTile(
            title = "Volume · 30d",
            value = ExerciseDetailFormat.volume(history.volumeLast30Days),
            detail = ExerciseDetailFormat.sessionCount(history.sessionsLast30Days),
            detailColor = colors.inkSecondary,
            detailBold = false,
        ),
    )
}

// endregion
