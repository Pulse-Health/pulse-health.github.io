package health.pulse.strength.ui.detail

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.History
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.ExerciseRecordRow
import health.pulse.strength.core.ExerciseSession
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.ui.theme.LocalReduceMotion
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.badgeBackground
import health.pulse.strength.ui.theme.badgeForeground
import health.pulse.strength.ui.theme.pulseClickable
import java.time.Instant

// The building blocks of the exercise detail page below the chart: figure tiles, records, sessions, cues.

/** The 12 % green wash behind the cue numbers. */
@Composable
@ReadOnlyComposable
internal fun greenWash(): Color =
    if (PulseTheme.colors.isDark) Color(0xFF30D158).copy(alpha = 0.18f) else Color(0xFF1B8448).copy(alpha = 0.12f)

@Composable
internal fun ExerciseDetailSectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = PulseFont.text(17.sp, FontWeight.SemiBold),
        color = PulseTheme.colors.ink,
        modifier = modifier.semantics { heading() },
    )
}

// region Figure tiles

internal enum class TileArrow { NONE, UP, DOWN }

internal class DetailTile(
    val title: String,
    val value: String,
    val detail: String,
    val detailColor: Color,
    val detailBold: Boolean,
    val arrow: TileArrow = TileArrow.NONE,
    /** What TalkBack reads instead of [detail] ("up 6 kilograms over 12 weeks"). */
    val spokenDetail: String? = null,
)

/**
 * Side by side as designed while they fit, otherwise stacked (large fonts, narrow windows): the counterpart of the iOS
 * `ViewThatFits`. A tile needs about 72 dp of text width times the font scale.
 */
@Composable
internal fun ExerciseDetailStatTiles(tiles: List<DetailTile>, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val scale = LocalDensity.current.fontScale.coerceAtLeast(1f)
        val textWidth = (maxWidth - 10.dp * (tiles.size - 1)) / tiles.size - 24.dp
        val inRow = textWidth >= 72.dp * scale && !isLargeFontScale()
        if (inRow) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (tile in tiles) ExerciseDetailStatTile(tile, singleLine = true, modifier = Modifier.weight(1f))
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (tile in tiles) ExerciseDetailStatTile(tile, singleLine = !isLargeFontScale(), modifier = Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
private fun ExerciseDetailStatTile(tile: DetailTile, singleLine: Boolean, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Column(
        modifier
            .background(colors.card, RoundedCornerShape(PulseMetrics.listRadius))
            // TalkBack focuses the whole card, so the semantics come before the padding.
            .semantics(mergeDescendants = true) {}
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(
            text = tile.title,
            style = PulseFont.text(12.sp).copy(lineHeight = 16.sp),
            color = colors.inkSecondary,
            maxLines = if (singleLine) 1 else Int.MAX_VALUE,
            overflow = TextOverflow.Ellipsis,
        )
        FitText(
            text = tile.value,
            style = PulseFont.number(22.sp).copy(lineHeight = 28.sp),
            color = colors.ink,
            minScale = 0.7f,
            singleLine = singleLine,
        )
        val detailModifier = if (tile.spokenDetail != null) {
            Modifier.clearAndSetSemantics { contentDescription = tile.spokenDetail }
        } else {
            Modifier
        }
        Row(
            detailModifier,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val arrow = when (tile.arrow) {
                TileArrow.NONE -> null
                TileArrow.UP -> Icons.Rounded.ArrowUpward
                TileArrow.DOWN -> Icons.Rounded.ArrowDownward
            }
            if (arrow != null) {
                Icon(arrow, contentDescription = null, tint = tile.detailColor, modifier = Modifier.size(scaledDp(12.dp, 1.5f)))
            }
            FitText(
                text = tile.detail,
                style = PulseFont.text(12.sp, if (tile.detailBold) FontWeight.SemiBold else FontWeight.Normal).copy(lineHeight = 16.sp),
                color = tile.detailColor,
                minScale = 0.8f,
                singleLine = singleLine,
                modifier = Modifier.weight(1f, fill = false),
            )
        }
    }
}

// endregion

// region Records

@Composable
internal fun ExerciseDetailRecordsSection(rows: List<ExerciseRecordRow>, now: Instant, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ExerciseDetailSectionTitle("Personal Records")
        Column(
            Modifier
                .fillMaxWidth()
                .background(PulseTheme.colors.card, RoundedCornerShape(PulseMetrics.listRadius))
                .padding(horizontal = 12.dp, vertical = 4.dp),
        ) {
            rows.forEachIndexed { index, row ->
                if (index > 0) StrengthHairline()
                ExerciseDetailRecordRow(row, now)
            }
        }
    }
}

/** Label, value and date in one row; at the biggest font sizes the label gets its own line. */
@Composable
private fun ExerciseDetailRecordRow(row: ExerciseRecordRow, now: Instant) {
    val colors = PulseTheme.colors
    val dateText = row.date?.let { StrengthResultText.monthDay(it, now) } ?: ""
    val dateWidth = scaledDp(54.dp)
    val label: @Composable (Modifier) -> Unit = { modifier ->
        Text(row.label, style = PulseFont.text(15.sp), color = colors.ink, modifier = modifier)
    }
    val value: @Composable () -> Unit = {
        Text(row.value, style = PulseFont.number(15.sp, FontWeight.SemiBold), color = colors.ink, maxLines = 1)
    }
    val date: @Composable () -> Unit = {
        Text(
            dateText,
            style = PulseFont.text(12.sp),
            color = colors.inkSecondary,
            textAlign = TextAlign.End,
            modifier = Modifier.widthIn(min = dateWidth),
        )
    }
    val rowModifier = Modifier
        .fillMaxWidth()
        .semantics(mergeDescendants = true) {}
        .heightIn(min = 48.dp)
        .padding(vertical = 6.dp)
    if (isLargeFontScale()) {
        Column(rowModifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            label(Modifier.fillMaxWidth())
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                value()
                Spacer(Modifier.weight(1f))
                date()
            }
        }
    } else {
        Row(rowModifier, horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            label(Modifier.weight(1f))
            value()
            date()
        }
    }
}

// endregion

// region Sessions

/** "Recent Sessions" with "See All" on the right; at the biggest font sizes the button moves under the title. */
@Composable
internal fun ExerciseDetailSessionsHeading(
    hasSeeAll: Boolean,
    showsAll: Boolean,
    onToggleAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (isLargeFontScale()) {
        Column(modifier.fillMaxWidth()) {
            ExerciseDetailSectionTitle("Recent Sessions")
            if (hasSeeAll) SeeAllButton(showsAll, onToggleAll)
        }
    } else {
        Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            ExerciseDetailSectionTitle("Recent Sessions")
            Spacer(Modifier.weight(1f))
            if (hasSeeAll) SeeAllButton(showsAll, onToggleAll)
        }
    }
}

/** "See All" in the design: 12 sp blue text with a 48 dp touch target. */
@Composable
private fun SeeAllButton(showsAll: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .sizeIn(minWidth = 48.dp, minHeight = 48.dp)
            .clickable(
                onClickLabel = if (showsAll) "Show fewer sessions" else "Show all sessions",
                role = Role.Button,
                onClick = onClick,
            ),
        contentAlignment = Alignment.CenterEnd,
    ) {
        Text(
            text = if (showsAll) "Show Less" else "See All",
            style = PulseFont.text(12.sp),
            color = PulseTheme.colors.blue,
        )
    }
}

/**
 * One session: "Oct 8 · Upper A · Push", an optional PR tag and the sets on one line. The row opens in place to list every set
 * with its type and reps in reserve.
 */
@Composable
internal fun ExerciseDetailSessionRow(
    session: ExerciseSession,
    tracking: TrackingKind,
    now: Instant,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val reduceMotion = LocalReduceMotion.current
    val chevronAngle by animateFloatAsState(
        targetValue = if (isExpanded) 90f else 0f,
        animationSpec = if (reduceMotion) snap() else tween(200),
        label = "sessionChevron",
    )
    val title = StrengthResultText.monthDay(session.date, now) + " · " + session.workoutName
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(PulseMetrics.listRadius))
            .background(colors.card),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .pulseClickable(
                    onClickLabel = if (isExpanded) "Hide the sets of this session" else "Show every set of this session",
                    role = Role.Button,
                    onClick = onToggle,
                )
                .semantics { stateDescription = if (isExpanded) "Expanded" else "Collapsed" }
                .heightIn(min = 48.dp)
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                val titleText: @Composable (Modifier) -> Unit = { titleModifier ->
                    Text(title, style = PulseFont.text(15.sp, FontWeight.SemiBold), color = colors.ink, modifier = titleModifier)
                }
                if (isLargeFontScale()) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        titleText(Modifier)
                        if (session.isPersonalRecord) StrengthPRChip(horizontal = 7.dp, vertical = 2.dp)
                    }
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        titleText(Modifier.weight(1f, fill = false))
                        if (session.isPersonalRecord) StrengthPRChip(horizontal = 7.dp, vertical = 2.dp)
                    }
                }
                Text(
                    text = StrengthResultText.setsLine(session.sets, tracking),
                    style = PulseFont.number(13.sp, FontWeight.Normal),
                    color = colors.inkSecondary,
                )
            }
            Icon(
                Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                contentDescription = null,
                tint = colors.inkTertiary,
                modifier = Modifier
                    .size(scaledDp(22.dp, 1.5f))
                    .rotate(chevronAngle),
            )
        }
        AnimatedVisibility(
            visible = isExpanded,
            enter = if (reduceMotion) EnterTransition.None else fadeIn(tween(200)) + expandVertically(tween(200)),
            exit = if (reduceMotion) ExitTransition.None else fadeOut(tween(200)) + shrinkVertically(tween(200)),
        ) {
            ExerciseDetailSetLines(StrengthResultText.setLines(session.sets, tracking))
        }
    }
}

@Composable
private fun ExerciseDetailSetLines(lines: List<StrengthSetLine>) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(start = 12.dp, end = 12.dp, bottom = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        for (line in lines) ExerciseDetailSetLineRow(line)
    }
}

/** Badge, set and reps in reserve in one row; at the biggest font sizes the reps in reserve move to their own line. */
@Composable
private fun ExerciseDetailSetLineRow(line: StrengthSetLine) {
    val colors = PulseTheme.colors
    val side = scaledDp(24.dp)
    val badge: @Composable () -> Unit = {
        Box(
            Modifier
                .size(side)
                .background(line.type.badgeBackground(), RoundedCornerShape(6.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Text(line.badge, style = PulseFont.number(12.sp, FontWeight.Bold), color = line.type.badgeForeground())
        }
    }
    val detail: @Composable () -> Unit = {
        Text(line.detailText, style = PulseFont.number(15.sp, FontWeight.SemiBold), color = colors.ink)
    }
    val rir: @Composable () -> Unit = {
        if (line.rirText != null) Text(line.rirText, style = PulseFont.text(12.sp), color = colors.inkSecondary)
    }
    val rowModifier = Modifier
        .fillMaxWidth()
        .clearAndSetSemantics { contentDescription = line.spokenText }
    if (isLargeFontScale()) {
        Column(rowModifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                badge()
                detail()
            }
            rir()
        }
    } else {
        Row(rowModifier, horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            badge()
            detail()
            Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
            rir()
        }
    }
}

/** A new user's view of the session list: the section is there, and says what will fill it. */
@Composable
internal fun ExerciseDetailNoSessions(modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ExerciseDetailSectionTitle("Recent Sessions")
        Row(
            Modifier
                .fillMaxWidth()
                .background(colors.card, RoundedCornerShape(PulseMetrics.listRadius))
                .semantics(mergeDescendants = true) {}
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(scaledDp(44.dp, 1.4f))
                    .background(colors.cellFill, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.History, contentDescription = null, tint = colors.inkTertiary, modifier = Modifier.size(scaledDp(24.dp, 1.4f)))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("No sessions yet", style = PulseFont.text(15.sp, FontWeight.SemiBold), color = colors.ink)
                Text(
                    "Log this exercise in a workout and your sessions and personal records appear here.",
                    style = PulseFont.text(13.sp),
                    color = colors.inkSecondary,
                )
            }
        }
    }
}

// endregion

// region How to

@Composable
internal fun ExerciseDetailCuesSection(cues: List<String>, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ExerciseDetailSectionTitle("How To")
        Column(
            Modifier
                .fillMaxWidth()
                .background(PulseTheme.colors.card, RoundedCornerShape(PulseMetrics.listRadius))
                .padding(horizontal = 12.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            cues.forEachIndexed { index, cue -> ExerciseDetailCueRow(number = index + 1, text = cue) }
        }
    }
}

@Composable
private fun ExerciseDetailCueRow(number: Int, text: String) {
    val colors = PulseTheme.colors
    val side = scaledDp(24.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = "Step $number. $text" },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(Modifier.size(side).background(greenWash(), CircleShape), contentAlignment = Alignment.Center) {
            Text(number.toString(), style = PulseFont.number(13.sp, FontWeight.Bold), color = colors.greenText)
        }
        Text(
            text,
            style = PulseFont.text(15.sp).copy(lineHeight = 21.sp),
            color = colors.ink,
            modifier = Modifier.weight(1f),
        )
    }
}

// endregion

/** "Demo photos: Free Exercise DB (public domain)." */
@Composable
internal fun ExerciseDetailAttribution(modifier: Modifier = Modifier) {
    Text(
        "Demo photos: Free Exercise DB (public domain).",
        style = PulseFont.text(11.sp),
        color = PulseTheme.colors.inkSecondary,
        modifier = modifier,
    )
}
