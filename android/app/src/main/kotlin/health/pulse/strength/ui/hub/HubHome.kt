package health.pulse.strength.ui.hub

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.AddCircleOutline
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Psychology
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.RecoveryProvider
import health.pulse.strength.core.StrengthData
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.ui.components.DumbbellGlyph
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulsePrimaryButton
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseCard
import health.pulse.strength.ui.theme.pulseClickable
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

// The home screen of the hub: the recommended template, "Start Empty Workout", the first three templates, muscle recovery, the last
// three workouts, this week and the library row (the body and the "Recommended card" part of StrengthHubView.swift).

/** What the sections of the home screen need to know about "now": the calendar day, its zone and the first day of the week. */
@Immutable
internal class HubTime(val today: LocalDate, val zone: ZoneId, val firstDayOfWeek: DayOfWeek)

/** Everything the home screen shows, derived from the stored data and the workout in progress. */
@Immutable
internal class HubHomeData(
    val templates: List<WorkoutTemplate>,
    val history: List<CompletedWorkout>,
    val recommended: WorkoutTemplate?,
    val exerciseCount: Int,
    /** Ids of the exercises the user really logged (see [HubCoach.message]). */
    val loggedExerciseIDs: Set<String>,
    val runningTemplateID: UUID?,
)

/**
 * The recovery of every muscle group at one moment, fixed. The recovery model reads the stored history and the clock, neither of
 * which Compose observes, so the home screen takes one snapshot (again whenever the data changes and every minute) and hands it to
 * all its sections: the ring, the chips, the coach note and the grid always agree, and equal snapshots let Compose skip them.
 */
@Immutable
internal class HubRecoverySnapshot private constructor(private val percents: Map<MuscleGroup, Int>) : RecoveryProvider {
    override fun invoke(muscle: MuscleGroup): Int = percents[muscle] ?: 100

    override fun equals(other: Any?): Boolean = other is HubRecoverySnapshot && other.percents == percents

    override fun hashCode(): Int = percents.hashCode()

    companion object {
        fun of(recovery: RecoveryProvider): HubRecoverySnapshot =
            HubRecoverySnapshot(MuscleGroup.entries.associateWith { HubMuscles.percent(it, recovery) })
    }
}

internal fun homeData(data: StrengthData, runningTemplateID: UUID?): HubHomeData = HubHomeData(
    templates = data.templates,
    history = data.history,
    recommended = HubRotation.next(data.templates),
    exerciseCount = ExerciseLibrary.builtIn.size + data.customExercises.size,
    loggedExerciseIDs = loggedExerciseIDs(data),
    runningTemplateID = runningTemplateID,
)

/** The exercises with a personal best or a logged set in the history. */
internal fun loggedExerciseIDs(data: StrengthData): Set<String> {
    val ids = HashSet<String>(data.personalBests.keys)
    for (workout in data.history) for (exercise in workout.exercises) if (exercise.sets.isNotEmpty()) ids.add(exercise.exerciseID)
    return ids
}

/** The things the screens can ask the hub to do. */
internal class HubActions(
    val push: (HubRoute) -> Unit,
    val pop: () -> Unit,
    /** Starts a workout (null = empty), or warns while another one runs. */
    val requestStart: (WorkoutTemplate?) -> Unit,
    val resume: () -> Unit,
    val edit: (HubEditorTarget) -> Unit,
) {
    /** The same actions with the back action of one page (see [HubNavigator.popIf]). */
    fun withPop(pop: () -> Unit): HubActions = HubActions(push, pop, requestStart, resume, edit)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun HubHome(
    store: StrengthStore,
    recovery: RecoveryProvider,
    home: HubHomeData,
    time: HubTime,
    actions: HubActions,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val scrollState = rememberScrollState()
    val density = LocalDensity.current
    val titleThresholdPx = with(density) { 36.dp.toPx() }
    val titleScrolledAway by remember(scrollState) { derivedStateOf { scrollState.value > titleThresholdPx } }
    // A short window (a phone on its side) has no room for a large title: the title stays in the top bar instead.
    val windowHeight = with(density) { LocalWindowInfo.current.containerSize.height.toDp() }
    val compactHeight = windowHeight < 480.dp

    Scaffold(
        modifier = modifier,
        containerColor = colors.ground,
        contentWindowInsets = WindowInsets.safeDrawing,
        topBar = {
            HubHomeTopBar(
                showsTitle = compactHeight || titleScrolledAway,
                onSettings = { actions.push(HubRoute.Settings) },
                onStartEmpty = { actions.requestStart(null) },
                onNewTemplate = { actions.edit(HubEditorTarget.New) },
                onLibrary = { actions.push(HubRoute.Library) },
            )
        },
    ) { inner ->
        BoxWithConstraints(Modifier.hubScreenPadding(inner).fillMaxSize()) {
            val twoColumns = maxWidth >= HUB_TWO_COLUMN_MIN_WIDTH_DP.dp
            val columnGap = 24.dp
            val contentWidth = if (twoColumns) HubColumnMaxWidth * 2 + columnGap else PulseMetrics.maxContentWidth
            val gutter = ((maxWidth - contentWidth) / 2).coerceAtLeast(PulseMetrics.screenInset)
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(scrollState)
                    .padding(start = gutter, end = gutter, top = if (compactHeight) 0.dp else 4.dp, bottom = hubBottomPadding(inner)),
            ) {
                if (!compactHeight) {
                    Text(
                        "Strength",
                        modifier = Modifier.padding(bottom = 10.dp).semantics { heading() },
                        style = PulseFont.largeTitle,
                        color = colors.ink,
                    )
                }
                if (twoColumns) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(columnGap)) {
                        Column(Modifier.weight(1f)) {
                            RecommendedOrWelcome(store, recovery, home, time, actions, topGap = 0.dp)
                            StartEmptyRow(actions, topGap = HubSectionSpacing)
                            TemplatesSection(home, actions, topGap = HubSectionSpacing)
                        }
                        Column(Modifier.weight(1f)) {
                            RecoverySection(recovery, actions, topGap = 0.dp, firstInColumn = true)
                            RecentSection(home, time, actions, topGap = HubSectionSpacing)
                            WeekSection(home, time, topGap = HubSectionSpacing)
                            LibraryRow(home, actions, topGap = HubSectionSpacing)
                        }
                    }
                } else {
                    RecommendedOrWelcome(store, recovery, home, time, actions, topGap = 0.dp)
                    StartEmptyRow(actions, topGap = HubSectionSpacing)
                    TemplatesSection(home, actions, topGap = HubSectionSpacing)
                    RecoverySection(recovery, actions, topGap = HubSectionSpacing, firstInColumn = false)
                    RecentSection(home, time, actions, topGap = HubSectionSpacing)
                    WeekSection(home, time, topGap = HubSectionSpacing)
                    LibraryRow(home, actions, topGap = HubSectionSpacing)
                }
            }
        }
    }
}

/** The gap above a section whose first row is a 48 dp header with an action: the header's own empty space makes up the rest. */
private fun gapAbove(topGap: Dp, hasAction: Boolean): Dp = if (hasAction && topGap > 8.dp) topGap - 12.dp else topGap

// region Top bar

@Composable
private fun HubHomeTopBar(
    showsTitle: Boolean,
    onSettings: () -> Unit,
    onStartEmpty: () -> Unit,
    onNewTemplate: () -> Unit,
    onLibrary: () -> Unit,
) {
    val colors = PulseTheme.colors
    var menuOpen by remember { mutableStateOf(false) }
    Row(
        Modifier
            .fillMaxWidth()
            .background(colors.ground)
            .hubTopInsets()
            .heightIn(min = 56.dp)
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f).padding(start = 12.dp)) {
            if (showsTitle) {
                Text(
                    "Strength",
                    modifier = Modifier.semantics { heading() },
                    style = PulseFont.text(20.sp, FontWeight.SemiBold),
                    color = colors.ink,
                    maxLines = 1,
                )
            }
        }
        IconButton(onClick = onSettings) {
            Icon(Icons.Rounded.Settings, contentDescription = "Settings", tint = colors.ink)
        }
        Box {
            IconButton(onClick = { menuOpen = true }) {
                Icon(Icons.Rounded.MoreVert, contentDescription = "More", tint = colors.ink)
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text("Start Empty Workout", style = PulseFont.body) },
                    leadingIcon = { Icon(Icons.Rounded.AddCircleOutline, contentDescription = null) },
                    onClick = {
                        menuOpen = false
                        onStartEmpty()
                    },
                )
                DropdownMenuItem(
                    text = { Text("New Template", style = PulseFont.body) },
                    leadingIcon = { Icon(Icons.Rounded.Add, contentDescription = null) },
                    onClick = {
                        menuOpen = false
                        onNewTemplate()
                    },
                )
                DropdownMenuItem(
                    text = { Text("Exercise Library", style = PulseFont.body) },
                    leadingIcon = { Icon(Icons.Rounded.Search, contentDescription = null) },
                    onClick = {
                        menuOpen = false
                        onLibrary()
                    },
                )
            }
        }
    }
}

// endregion

// region Recommended card and the first-run prompt

@Composable
private fun RecommendedOrWelcome(
    store: StrengthStore,
    recovery: RecoveryProvider,
    home: HubHomeData,
    time: HubTime,
    actions: HubActions,
    topGap: Dp,
) {
    val template = home.recommended
    Box(Modifier.padding(top = topGap)) {
        if (template == null) {
            HubFirstTemplateCard(onCreate = { actions.edit(HubEditorTarget.New) })
        } else {
            val runsThis = home.runningTemplateID == template.id
            val suffix = HubFormat.lastDoneSuffix(template, time.today, time.zone)
            HubRecommendedCard(
                template = template,
                subtitle = HubFormat.templateSubtitle(template, suffix),
                readiness = HubMuscles.readiness(recovery),
                chips = HubMuscles.chips(template, recovery),
                coach = HubCoach.message(
                    template = template,
                    recovery = recovery,
                    exercise = { store.exercise(it) },
                    hasResults = { it in home.loggedExerciseIDs },
                ),
                primaryTitle = if (runsThis) "Resume Workout" else "Start Workout",
                onPrimary = { if (runsThis) actions.resume() else actions.requestStart(template) },
                onEdit = { actions.edit(HubEditorTarget.Existing(template.id)) },
            )
        }
    }
}

/** The first-run counterpart of the recommended card: nothing to recommend yet, so it invites to create the first template. */
@Composable
internal fun HubFirstTemplateCard(onCreate: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Column(modifier.fillMaxWidth().pulseCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            HubIconBox(fill = colors.greenTint) { DumbbellGlyph(size = 18.dp, color = colors.green, strokeWidth = 2.dp) }
            Text(
                "Plan your training",
                modifier = Modifier.weight(1f).semantics { heading() },
                style = PulseFont.number(22.sp),
                color = colors.ink,
            )
        }
        Text(
            "Save the exercises, sets and weights you repeat as a template. The hub then recommends what to train next and tracks " +
                "your recovery and progress.",
            style = PulseFont.subhead,
            color = colors.inkSecondary,
        )
        PulsePrimaryButton(text = "Create Your First Template", onClick = onCreate)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun HubRecommendedCard(
    template: WorkoutTemplate,
    subtitle: String,
    readiness: Int,
    chips: List<HubMuscleChip>,
    coach: String?,
    primaryTitle: String,
    onPrimary: () -> Unit,
    onEdit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val larger = isLargerText()
    Column(modifier.fillMaxWidth().pulseCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Header: title block and the readiness ring (stacked at the largest font sizes).
        val titles: @Composable (Modifier) -> Unit = { titleModifier ->
            Column(titleModifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Today · Recommended", style = PulseFont.subhead, color = colors.inkSecondary)
                Text(
                    template.name,
                    modifier = Modifier.semantics { heading() },
                    style = PulseFont.number(28.sp),
                    color = colors.ink,
                    maxLines = if (larger) 3 else 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    subtitle,
                    style = PulseFont.footnote,
                    color = colors.inkSecondary,
                    maxLines = if (larger) Int.MAX_VALUE else 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (isAccessibilityText()) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                titles(Modifier.fillMaxWidth())
                HubReadinessRing(readiness)
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                titles(Modifier.weight(1f))
                HubReadinessRing(readiness)
            }
        }
        if (chips.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                for (chip in chips) HubMuscleChipView(chip)
            }
        }
        if (template.entries.isNotEmpty()) HubThumbnails(template)
        if (coach != null) HubCoachNote(coach)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                Modifier
                    .weight(1f)
                    .heightIn(min = 50.dp)
                    .pulseClickable(pressedAlpha = 0.8f, onClick = onPrimary)
                    .background(colors.green, RoundedCornerShape(12.dp))
                    .padding(horizontal = 8.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                DumbbellGlyph(size = 18.dp, color = colors.onGreen, strokeWidth = 2.2.dp)
                Text(primaryTitle, style = PulseFont.headline, color = colors.onGreen)
            }
            Box(
                Modifier
                    .size(50.dp)
                    .pulseClickable(onClick = onEdit)
                    .background(colors.cellFill, RoundedCornerShape(12.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.EditNote, contentDescription = "Edit plan", modifier = Modifier.size(26.dp), tint = colors.greenText)
            }
        }
    }
}

@Composable
private fun HubMuscleChipView(chip: HubMuscleChip) {
    val colors = PulseTheme.colors
    Row(
        Modifier.background(colors.cellFill, CircleShape).padding(horizontal = 10.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(fontScaledDp(7f)).background(colors.recoveryColor(HubMuscles.level(chip.percent)), CircleShape))
        Text(
            chip.title,
            style = PulseFont.text(12.sp, FontWeight.SemiBold),
            color = colors.ink,
            maxLines = if (isLargerText()) Int.MAX_VALUE else 1,
        )
    }
}

/** Up to six 46 dp form demos of the template's exercises; they shrink together on a narrow window instead of running out of the card. */
@Composable
private fun HubThumbnails(template: WorkoutTemplate) {
    val entries = template.entries.take(6)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val gap = 6.dp
        val side = minOf(46.dp, (maxWidth - gap * (entries.size - 1)) / entries.size)
        Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
            for (entry in entries) ExerciseMediaView(mediaKey = entry.exercise.mediaKey, modifier = Modifier.size(side), cornerRadius = 10.dp)
        }
    }
}

@Composable
private fun HubCoachNote(text: String) {
    val colors = PulseTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .background(colors.coachTipFill, RoundedCornerShape(10.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            Icons.Rounded.Psychology,
            contentDescription = null,
            modifier = Modifier.padding(top = 1.dp).size(fontScaledDp(20f)),
            tint = colors.green,
        )
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append("Coach · ") }
                append(text)
            },
            modifier = Modifier.weight(1f),
            style = PulseFont.text(13.sp),
            color = colors.ink,
        )
    }
}

/** The ring of the recommended card: the mean recovery of all muscle groups, coloured by level. The ring and its figure grow together. */
@Composable
internal fun HubReadinessRing(percent: Int, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    val ringSize = fontScaledDp(48f)
    val lineWidth = fontScaledDp(6f)
    val color = colors.recoveryColor(HubMuscles.level(percent))
    val title = HubMuscles.readinessTitle(percent)
    Column(
        modifier.clearAndSetSemantics {
            contentDescription = "Readiness"
            stateDescription = "$percent percent, $title"
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Box(Modifier.padding(4.dp).size(ringSize), contentAlignment = Alignment.Center) {
            val track = colors.progressTrack
            Canvas(Modifier.fillMaxSize()) {
                val stroke = lineWidth.toPx()
                val topLeft = Offset(stroke / 2, stroke / 2)
                val arcSize = Size(size.width - stroke, size.height - stroke)
                drawArc(track, 0f, 360f, useCenter = false, topLeft = topLeft, size = arcSize, style = Stroke(stroke))
                drawArc(
                    color,
                    startAngle = -90f,
                    sweepAngle = 360f * percent.coerceIn(0, 100) / 100f,
                    useCenter = false,
                    topLeft = topLeft,
                    size = arcSize,
                    style = Stroke(stroke, cap = StrokeCap.Round),
                )
            }
            Text("$percent", style = PulseFont.number(18.sp), color = colors.ink)
        }
        Text(title, style = PulseFont.caption2, color = colors.inkSecondary)
    }
}

// endregion

// region Sections

@Composable
private fun StartEmptyRow(actions: HubActions, topGap: Dp) {
    val colors = PulseTheme.colors
    Row(
        Modifier
            .padding(top = topGap)
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .pulseClickable(onClick = { actions.requestStart(null) })
            .hubRowBackground()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.AddCircle, contentDescription = null, modifier = Modifier.size(30.dp), tint = colors.green)
        Column(Modifier.weight(1f)) {
            Text("Start Empty Workout", style = PulseFont.headline, color = colors.ink)
            Text("Add exercises as you go", style = PulseFont.footnote, color = colors.inkSecondary)
        }
        HubChevron()
    }
}

@Composable
private fun TemplatesSection(home: HubHomeData, actions: HubActions, topGap: Dp) {
    val hasTemplates = home.templates.isNotEmpty()
    Column(Modifier.padding(top = gapAbove(topGap, hasTemplates))) {
        HubSectionHeader(
            title = "Templates",
            actionTitle = if (hasTemplates) "See All" else null,
            onAction = { actions.push(HubRoute.Templates) },
        )
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (template in home.templates.take(3)) {
                val isNext = template.id == home.recommended?.id
                HubTemplateRow(
                    template = template,
                    subtitle = HubFormat.templateSubtitle(template, if (isNext) "next up" else null),
                    onClick = { actions.push(HubRoute.Template(template.id)) },
                )
            }
            HubNewTemplateRow(onClick = { actions.edit(HubEditorTarget.New) })
        }
    }
}

@Composable
private fun RecoverySection(recovery: RecoveryProvider, actions: HubActions, topGap: Dp, firstInColumn: Boolean) {
    Column(Modifier.padding(top = if (firstInColumn) 0.dp else gapAbove(topGap, hasAction = true))) {
        HubSectionHeader(title = "Muscle Recovery", actionTitle = "View All", onAction = { actions.push(HubRoute.Recovery) })
        val order = HubMuscles.displayOrder
        if (isAccessibilityText()) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                for (muscle in order) HubRecoveryCard(muscle, HubMuscles.percent(muscle, recovery), Modifier.fillMaxWidth())
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                for (pair in order.chunked(2)) {
                    Row(
                        Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        for (muscle in pair) {
                            HubRecoveryCard(muscle, HubMuscles.percent(muscle, recovery), Modifier.weight(1f).fillMaxHeight())
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RecentSection(home: HubHomeData, time: HubTime, actions: HubActions, topGap: Dp) {
    if (home.history.isEmpty()) return
    Column(Modifier.padding(top = gapAbove(topGap, hasAction = true))) {
        HubSectionHeader(title = "Recent Workouts", actionTitle = "See All", onAction = { actions.push(HubRoute.History) })
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (workout in home.history.take(3)) {
                HubWorkoutRow(workout = workout, zone = time.zone, onClick = { actions.push(HubRoute.Workout(workout.id)) })
            }
        }
    }
}

@Composable
private fun WeekSection(home: HubHomeData, time: HubTime, topGap: Dp) {
    val week = remember(home.history, time) { HubFormat.weekStats(home.history, time.today, time.zone, time.firstDayOfWeek) }
    Column(Modifier.padding(top = topGap)) {
        HubSectionHeader(title = "This Week")
        HubWeekCard(week)
    }
}

@Composable
internal fun HubWeekCard(week: HubWeekStats, modifier: Modifier = Modifier) {
    HubStatRow(
        stats = listOf(
            HubStat("Sessions", "${week.sessions} of ${maxOf(HubFormat.SESSION_GOAL, week.sessions)}"),
            HubStat("Sets", "${week.sets}"),
            HubStat("Volume", HubFormat.volumeOrDash(week.volumeKg)),
        ),
        modifier = modifier.fillMaxWidth().hubRowBackground().padding(12.dp),
    )
}

@Composable
private fun LibraryRow(home: HubHomeData, actions: HubActions, topGap: Dp) {
    val colors = PulseTheme.colors
    Row(
        Modifier
            .padding(top = topGap)
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .pulseClickable(onClick = { actions.push(HubRoute.Library) })
            .hubRowBackground()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        HubIconBox(fill = colors.greenTint) {
            Icon(Icons.Rounded.Search, contentDescription = null, modifier = Modifier.size(18.dp), tint = colors.green)
        }
        Column(Modifier.weight(1f)) {
            Text("Exercise Library", style = PulseFont.body, color = colors.ink)
            Text(
                "${home.exerciseCount} exercises with form demos · create your own",
                style = PulseFont.footnote,
                color = colors.inkSecondary,
                maxLines = if (isLargerText()) Int.MAX_VALUE else 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        HubChevron()
    }
}

// endregion

/** The recovery card of the home grid: muscle name, bar and percentage. */
@Composable
internal fun HubRecoveryCard(muscle: MuscleGroup, percent: Int, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Column(
        modifier
            .hubRowBackground()
            .padding(12.dp)
            .clearAndSetSemantics {
                contentDescription = muscle.title + " recovery"
                stateDescription = "$percent percent"
            },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(muscle.title, style = PulseFont.text(12.sp, FontWeight.SemiBold), color = colors.ink)
        HubBar(fraction = percent / 100.0, color = colors.recoveryColor(HubMuscles.level(percent)))
        Text("$percent%", style = PulseFont.number(11.sp, FontWeight.Normal), color = colors.inkSecondary)
    }
}
