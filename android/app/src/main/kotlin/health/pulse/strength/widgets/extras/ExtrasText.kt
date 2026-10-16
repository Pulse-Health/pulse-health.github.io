package health.pulse.strength.widgets.extras

import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.widgets.BodyMap
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.FormCue
import health.pulse.strength.core.widgets.LoadedBar
import health.pulse.strength.core.widgets.PartnerWeek
import health.pulse.strength.core.widgets.PlateauFlag
import health.pulse.strength.core.widgets.ReadinessSummary
import health.pulse.strength.core.widgets.SessionSummary
import health.pulse.strength.core.widgets.StrengthRatio
import health.pulse.strength.core.widgets.TimelineKind
import health.pulse.strength.core.widgets.TimelineSegment
import health.pulse.strength.core.widgets.TrendStatus
import health.pulse.strength.core.widgets.WeekSummary
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.YearSummary
import health.pulse.strength.widgets.lock.LockText
import health.pulse.strength.widgets.lock.PulseFormat
import health.pulse.strength.widgets.lock.TextFit
import java.time.DateTimeException
import java.time.ZoneId
import java.time.ZoneOffset

internal enum class ReadinessTier { GOOD, FAIR, LOW }

/**
 * What the "wilder idea" widgets (WI-01 ... WI-11) show for a snapshot, as plain values. The widgets only lay these out, so the rules
 * (which text, which fraction, which bars) are unit-tested without a launcher. The log-a-set widget's states are in [LogSetModel].
 */
internal object ExtrasText {
    private const val MIN_BAR = 0.12f

    /** Below this height (dp) the widgets that have a compact layout use it. */
    const val COMPACT_BELOW_DP = 130f

    // WI-01 body map

    data class BodyMapMessage(val headline: String, val detail: String)

    private fun levelWord(level: Int): String = when (level) {
        0 -> "untouched"
        1 -> "light"
        2 -> "medium"
        else -> "high"
    }

    /** What a screen reader says for the silhouettes: the information of the shading, in words. */
    fun bodyDescription(bodyMap: BodyMap): String {
        val levels = BodyMapShapes.levels(bodyMap)
        return "Body map, front and back. " + MuscleGroup.entries.joinToString(" ") { "${it.title}: ${levelWord(levels.getValue(it))}." }
    }

    /** "Legs untouched." in bold and "Lower A is next in line." below it: the snapshot's message split after its first sentence. */
    fun bodyMessage(bodyMap: BodyMap): BodyMapMessage {
        val text = bodyMap.message.trim()
        if (text.isEmpty()) return BodyMapMessage("No sets yet.", "Train a muscle group to colour the map.")
        val end = text.indexOf(". ")
        return if (end < 0) BodyMapMessage(text, "") else BodyMapMessage(text.substring(0, end + 1), text.substring(end + 2).trim())
    }

    // WI-03 gym partner

    /** One line of the partner widget: the avatar [label], the week's progress and its [fraction] of the goal. */
    data class PartnerRow(val label: String, val completed: Int, val goal: Int, val fraction: Float, val isYou: Boolean)

    private fun fraction(done: Int, goal: Int): Float = if (goal > 0) (done.toFloat() / goal).coerceIn(0f, 1f) else 0f

    /** You first, then the partners in order; [maxRows] lines in all, and always yours. */
    fun partnerRows(week: WeekSummary, partners: List<PartnerWeek>, maxRows: Int): List<PartnerRow> {
        val you = PartnerRow("You", week.completed, week.goal, fraction(week.completed, week.goal), isYou = true)
        val others = partners.take((maxRows - 1).coerceAtLeast(0)).map {
            PartnerRow(it.initials.ifBlank { it.name.take(1) }, it.completed, it.goal, fraction(it.completed, it.goal), isYou = false)
        }
        return listOf(you) + others
    }

    /**
     * How the partner widget is laid out in [heightDp]: below 130 dp it uses smaller avatars and drops the sentence under the bars, so
     * that you and one partner always fit; above, it fits as many lines (yours included) as the height allows, at most four.
     */
    data class PartnerLayout(
        val padding: Float,
        val avatar: Float,
        val rowSlot: Float,
        val rows: Int,
        val showsFooter: Boolean,
    )

    fun partnerLayout(heightDp: Float): PartnerLayout {
        if (heightDp < COMPACT_BELOW_DP) {
            val rows = ((heightDp - 20f - TextFit.height(14f) - 4f) / 32f).toInt().coerceIn(2, 4)
            return PartnerLayout(padding = 10f, avatar = 28f, rowSlot = 32f, rows = rows, showsFooter = false)
        }
        val chrome = 28f + TextFit.height(15f) + 8f + TextFit.height(13f) + 4f
        return PartnerLayout(padding = 14f, avatar = 30f, rowSlot = 34f, rows = ((heightDp - chrome) / 34f).toInt().coerceIn(2, 4), showsFooter = true)
    }

    /** The sentence under the bars: who closed their week, or where the leading partner stands. It never ranks anyone. */
    fun partnerFooter(week: WeekSummary, partners: List<PartnerWeek>): String {
        val closed = partners.filter { it.closedWeek }
        val youDone = week.completed >= week.goal
        return when {
            partners.isEmpty() -> ""
            closed.isNotEmpty() && !youDone ->
                if (closed.size == 1) "${closed.first().name} closed their week. Your turn." else "${closed.size} partners closed their week. Your turn."
            closed.isNotEmpty() ->
                if (closed.size == 1) "You and ${closed.first().name} closed the week." else "You and ${closed.size} partners closed the week."
            else -> {
                val leader = partners.maxBy { it.completed }
                "${leader.name} is at ${leader.completed} of ${leader.goal} this week."
            }
        }
    }

    // WI-04 form cue

    /** [shortEyebrow] is the lift alone, for a widget too small for "Form cue · Bench Press" on two lines. */
    data class CueText(val eyebrow: String, val shortEyebrow: String, val cue: String, val footer: String, val link: String)

    /** The type sizes (sp) a cue may be set in, largest first: the short cues of the canvas are big, a long one is set smaller so more of it shows. */
    fun cueTextSizes(roomy: Boolean): List<Float> = if (roomy) listOf(17f, 15f, 14f, 13f, 12f) else listOf(15f, 14f, 13f, 12f)

    fun formCue(cue: FormCue?): CueText = if (cue == null) {
        CueText("Form cue", "Form cue", "Cues for your next workout show up here.", "", DeepLinks.hub)
    } else {
        CueText(
            eyebrow = "Form cue · ${cue.exerciseName}",
            shortEyebrow = cue.exerciseName,
            cue = cue.cue,
            footer = "${cue.index} of ${cue.count} ${if (cue.count == 1) "cue" else "cues"}",
            link = DeepLinks.exercise(cue.exerciseID),
        )
    }

    // WI-05 loaded bar

    data class LoadedBarModel(
        val layout: BarbellLayout,
        val total: String,
        val perSide: String,
        val note: String?,
        val description: String,
    )

    /** The loaded bar of the top set, or null when no barbell lift is planned (the widget then shows an empty bar). */
    fun loadedBar(bar: LoadedBar?): LoadedBarModel? {
        if (bar == null) return null
        val plates = bar.summary.ifBlank { bar.platesPerSide.joinToString(" + ") { PulseFormat.kg(it) } }
        val perSide = if (plates.isEmpty()) "Bar only" else "$plates a side"
        val note = if (bar.leftoverKg >= 0.005) "${PulseFormat.kg(bar.leftoverKg)} kg can't be loaded" else null
        return LoadedBarModel(
            layout = Barbell.layout(bar.platesPerSide),
            total = "${PulseFormat.kg(bar.totalKg)} kg",
            perSide = perSide,
            note = note,
            description = "Top set ${bar.exerciseName}, ${PulseFormat.kg(bar.totalKg)} kilograms: $perSide" + (note?.let { ". $it" } ?: ""),
        )
    }

    // WI-06 rest day

    sealed interface RestDayCard {
        val link: String

        data class Rest(val reason: String, val title: String, val focus: String, override val link: String) : RestDayCard

        data class Training(val name: String, val detail: String, override val link: String) : RestDayCard

        data object Empty : RestDayCard {
            override val link: String = DeepLinks.hub
        }
    }

    /** A recovery routine on a rest day (Start opens an empty workout named after it); the next template on a training day. */
    fun restDayCard(snapshot: WidgetSnapshot): RestDayCard {
        val rest = snapshot.restDay
        val next = snapshot.nextUp
        return when {
            rest != null -> RestDayCard.Rest(
                reason = rest.reason.ifBlank { "Rest day" },
                title = rest.title,
                focus = rest.focus,
                link = DeepLinks.startEmpty(rest.title),
            )
            next != null -> RestDayCard.Training(next.name, LockText.templateDetail(next), LockText.startLink(snapshot))
            else -> RestDayCard.Empty
        }
    }

    // WI-07 strength ratio

    /**
     * [fraction] is the progress toward the goal ratio, or null when there is no ratio to draw a bar for. [shortEyebrow] is the lift
     * alone, for a widget too small for "Bench Press / bodyweight" on two lines.
     */
    data class RatioModel(
        val eyebrow: String,
        val shortEyebrow: String,
        val figure: String,
        val fraction: Float?,
        val footers: List<String>,
        val description: String,
        val link: String,
    ) {
        /** The line under the figure in its longest wording; [footers] run from the longest to the shortest, and the widget shows the first that fits. */
        val footer: String get() = footers.first()
    }

    /** The lift against bodyweight with a bar toward the goal ratio, or the reason there is no ratio yet. */
    fun strengthRatio(ratio: StrengthRatio?): RatioModel {
        if (ratio == null) {
            return RatioModel(
                eyebrow = "Strength ratio",
                shortEyebrow = "Strength",
                figure = "–",
                fraction = null,
                footers = listOf(
                    "Log bench, squat, deadlift or press to see your ratio.",
                    "Log a main lift to see your ratio.",
                    "Log a main lift.",
                ),
                description = "Strength ratio: no main lift logged yet",
                link = DeepLinks.hub,
            )
        }
        val eyebrow = "${ratio.exerciseName} / bodyweight"
        val value = ratio.ratio
        val bodyweight = ratio.bodyweightKg
        if (value == null || bodyweight == null) {
            val estimate = "${PulseFormat.kg(ratio.estimated1RM)} kg"
            return RatioModel(
                eyebrow = eyebrow,
                shortEyebrow = ratio.exerciseName,
                figure = estimate,
                fraction = null,
                footers = listOf("Add your bodyweight in Health Connect", "Add your bodyweight"),
                description = "${ratio.exerciseName}: estimated one-rep max $estimate. Add your bodyweight in Health Connect to see the ratio",
                link = DeepLinks.weight,
            )
        }
        val goal = PulseFormat.number(ratio.goalRatio, 2)
        val figure = PulseFormat.fixed(value, 2)
        return RatioModel(
            eyebrow = eyebrow,
            shortEyebrow = ratio.exerciseName,
            figure = "$figure×",
            fraction = if (ratio.goalRatio > 0) (value / ratio.goalRatio).toFloat().coerceIn(0f, 1f) else 0f,
            footers = listOf("Goal $goal× · ${PulseFormat.kg(bodyweight)} kg", "Goal $goal×"),
            description = "${ratio.exerciseName} is $figure times your bodyweight of ${PulseFormat.kg(bodyweight)} kilograms. The goal is $goal times",
            link = DeepLinks.exercise(ratio.exerciseID),
        )
    }

    // WI-08 year in iron

    data class YearBar(val fraction: Float, val isCurrent: Boolean)

    /** [captions] are the sentence under the figure from the longest to the shortest wording; the widget shows the first that fits. */
    data class YearModel(
        val eyebrow: String,
        val tonnes: String,
        val captions: List<String>,
        val bars: List<YearBar>,
        val description: String,
    ) {
        val caption: String get() = captions.first()
    }

    /** The 0-based month of the snapshot in its own time zone, or -1 when the snapshot is from another calendar year than the totals. */
    fun currentMonthIndex(snapshot: WidgetSnapshot): Int {
        val zone = try {
            ZoneId.of(snapshot.timeZoneID)
        } catch (_: DateTimeException) {
            ZoneOffset.UTC
        }
        val date = snapshot.generatedAt.atZone(zone)
        return if (date.year == snapshot.year.year) date.monthValue - 1 else -1
    }

    /** Twelve monthly bars scaled to the biggest month; a month with any tonnage gets at least a sliver, an empty month none. */
    fun yearInIron(year: YearSummary, currentMonth: Int): YearModel {
        val months = List(12) { year.monthlyTonnes.getOrElse(it) { 0.0 } }
        val biggest = months.max()
        val bars = months.mapIndexed { index, tonnes ->
            val scaled = if (biggest > 0) (tonnes / biggest).toFloat() else 0f
            YearBar(if (tonnes > 0) scaled.coerceAtLeast(MIN_BAR) else 0f, isCurrent = index == currentMonth)
        }
        val total = PulseFormat.number(year.tonnes, 1)
        val sessions = if (year.sessionCount == 1) "1 session" else "${year.sessionCount} sessions"
        val captions = if (year.sessionCount > 0) listOf("across $sessions", sessions) else listOf("no sessions yet")
        return YearModel(
            eyebrow = "Lifted in ${year.year}",
            tonnes = total,
            captions = captions,
            bars = bars,
            description = "Lifted $total tonnes in ${year.year}, ${captions.first()}",
        )
    }

    // WI-09 readiness

    /** Thirds of the 0...100 score: from 67 good, from 34 fair, below that low. */
    fun readinessTier(score: Int): ReadinessTier = when {
        score >= 67 -> ReadinessTier.GOOD
        score >= 34 -> ReadinessTier.FAIR
        else -> ReadinessTier.LOW
    }

    data class ReadinessModel(
        val tier: ReadinessTier?,
        val score: String,
        val caption: String,
        val eyebrow: String,
        val headline: String,
        val detail: String,
        val fraction: Float,
        val description: String,
    )

    /** The Pulse readiness ring and message, or the invitation to connect Pulse when the host provides none. */
    fun readiness(readiness: ReadinessSummary?): ReadinessModel {
        if (readiness == null) {
            return ReadinessModel(
                tier = null,
                score = "–",
                caption = "",
                eyebrow = "Pulse readiness",
                headline = "Connect Pulse",
                detail = "See today's sleep and recovery advice here.",
                fraction = 0f,
                description = "Pulse readiness: not connected. Connect Pulse to see today's advice",
            )
        }
        val headline = readiness.message.ifBlank { readiness.label }
        return ReadinessModel(
            tier = readinessTier(readiness.score),
            score = readiness.score.toString(),
            caption = readiness.label.lowercase(),
            eyebrow = "Pulse readiness",
            headline = headline,
            detail = "From ${readiness.source}",
            fraction = (readiness.score / 100f).coerceIn(0f, 1f),
            description = "Pulse readiness ${readiness.score} out of 100, ${readiness.label.lowercase()}. $headline",
        )
    }

    /** The type size of the eyebrow over the readiness advice, and the gap between the eyebrow, the advice and the line under it. */
    const val READINESS_EYEBROW_SP = 12f
    const val READINESS_GAP_DP = 4f

    /** The most lines the line under the advice (its source, or the invitation to connect) may take. */
    private const val MAX_DETAIL_LINES = 2

    /** How the readiness advice is set: its type size, and the type size of the line under it (null: that line is left out). */
    data class AdviceStyle(val adviceSp: Float, val detailSp: Float?)

    /** The ways to set the advice from the most generous to the tightest: the advice is made smaller, and only then the line under it goes. */
    val adviceStyles: List<AdviceStyle> = listOf(
        AdviceStyle(17f, 13f),
        AdviceStyle(15f, 12f),
        AdviceStyle(15f, null),
        AdviceStyle(13f, null),
        AdviceStyle(12f, null),
    )

    /** [maxLines] is the number of lines the advice is allowed in [style]. */
    data class AdviceLayout(val style: AdviceStyle, val maxLines: Int)

    /**
     * The first of [adviceStyles] in which the eyebrow, the whole advice and the line under it fit [room] dp of height. [adviceLines] and
     * [detailLines] say how many lines the advice and the line under it take at a type size. When nothing fits, the tightest style is
     * used with as many lines as the room holds, and the advice is cut with an ellipsis.
     */
    fun adviceLayout(room: Float, adviceLines: (Float) -> Int, detailLines: (Float) -> Int): AdviceLayout {
        val fixed = TextFit.height(READINESS_EYEBROW_SP) + READINESS_GAP_DP
        for (style in adviceStyles) {
            val advice = adviceLines(style.adviceSp)
            val detailSp = style.detailSp
            val detail = if (detailSp == null) 0 else detailLines(detailSp)
            val detailHeight = if (detailSp == null) 0f else READINESS_GAP_DP + TextFit.height(detailSp, detail)
            if (detail <= MAX_DETAIL_LINES && fixed + TextFit.height(style.adviceSp, advice) + detailHeight <= room) return AdviceLayout(style, advice)
        }
        val tightest = adviceStyles.last()
        return AdviceLayout(tightest, ((room - fixed) / TextFit.height(tightest.adviceSp)).toInt().coerceAtLeast(1))
    }

    // WI-10 plateau watch

    data class PlateauRow(val name: String, val status: TrendStatus, val statusText: String)

    data class PlateauModel(val rows: List<PlateauRow>, val tip: String?, val description: String)

    /** "rising", "flat 3×" or "falling": the state in words, so colour is never the only signal. */
    fun plateauStatusText(flag: PlateauFlag): String = when (flag.status) {
        TrendStatus.RISING -> "rising"
        TrendStatus.FLAT -> "flat ${flag.flatSessions}×"
        TrendStatus.FALLING -> "falling"
    }

    /** The first [maxRows] lifts in order, but always including the lift the tip is about (it replaces the last row if need be). */
    fun plateau(plateaus: List<PlateauFlag>, maxRows: Int): PlateauModel {
        val limit = maxRows.coerceAtLeast(1)
        val tipped = plateaus.indexOfFirst { !it.tip.isNullOrBlank() }
        val shown = plateaus.take(limit).toMutableList()
        if (tipped >= limit) shown[limit - 1] = plateaus[tipped]
        val tip = plateaus.getOrNull(tipped)?.tip
        val rows = shown.map { PlateauRow(it.name, it.status, plateauStatusText(it)) }
        val description = if (rows.isEmpty()) {
            "Plateau watch: not enough history yet"
        } else {
            "Plateau watch: " + rows.joinToString(", ") { "${it.name} ${it.statusText}" } + (tip?.let { ". Tip: $it" } ?: "")
        }
        return PlateauModel(rows, tip, description)
    }

    // WI-11 session timeline

    /** A stretch of the timeline bar in pixels: [start] inclusive, [end] exclusive. */
    data class BarSpan(val kind: TimelineKind, val start: Int, val end: Int)

    /** The segments laid across [widthPx] in proportion to their seconds. Boundaries are rounded cumulatively, so the spans tile the bar exactly. */
    fun timelineSpans(segments: List<TimelineSegment>, widthPx: Int): List<BarSpan> {
        val timed = segments.filter { it.seconds > 0 }
        val total = timed.sumOf { it.seconds.toLong() }
        if (total <= 0 || widthPx <= 0) return emptyList()
        var elapsed = 0L
        var start = 0
        return timed.map { segment ->
            elapsed += segment.seconds
            val end = (widthPx * elapsed / total).toInt()
            BarSpan(segment.kind, start, end).also { start = end }
        }
    }

    /** The legend word of a stretch kind. */
    fun timelineLabel(kind: TimelineKind): String = when (kind) {
        TimelineKind.LIFTING -> "Lifting"
        TimelineKind.REST -> "Rest"
        TimelineKind.LONG_REST -> "Long rest"
    }

    /**
     * [kinds] are the kinds present, in legend order; [message] replaces the bar when there is none to draw. [tails] are the details after
     * the headline from the most to the least ("· 38% under tension · 1 long break" ... ""), for the widget to pick the longest that fits.
     */
    data class TimelineModel(
        val name: String?,
        val hasBar: Boolean,
        val kinds: List<TimelineKind>,
        val headline: String,
        val tails: List<String>,
        val message: String?,
        val description: String,
    ) {
        val tail: String get() = tails.first()
    }

    /** "51 min" in bold, then " · 38% under tension · 1 long break"; or why there is no bar to draw. */
    fun sessionTimeline(session: SessionSummary?): TimelineModel {
        if (session == null) {
            return TimelineModel(
                name = null,
                hasBar = false,
                kinds = emptyList(),
                headline = "",
                tails = listOf(""),
                message = "Finish a workout to see how its time was spent.",
                description = "Session timeline: no workout finished yet",
            )
        }
        val hasBar = session.timeline.any { it.seconds > 0 }
        val kinds = TimelineKind.entries.filter { kind -> session.timeline.any { it.kind == kind && it.seconds > 0 } }
        val headline = "${session.durationMinutes} min"
        val details = if (hasBar) {
            listOfNotNull(
                session.underTensionPercent?.let { "$it% under tension" },
                session.longBreakCount.takeIf { it > 0 }?.let { if (it == 1) "1 long break" else "$it long breaks" },
            )
        } else {
            listOf(if (session.loggedSets == 1) "1 set" else "${session.loggedSets} sets")
        }
        // Every prefix of the details, longest first: dropping the last detail first keeps the more important ones.
        val tails = (details.size downTo 0).map { count -> details.take(count).joinToString("") { " · $it" } }
        return TimelineModel(
            name = session.name,
            hasBar = hasBar,
            kinds = kinds,
            headline = headline,
            tails = tails,
            message = if (hasBar) null else "No set times were recorded for this workout.",
            description = "Session timeline for ${session.name}: $headline${tails.first()}",
        )
    }
}
