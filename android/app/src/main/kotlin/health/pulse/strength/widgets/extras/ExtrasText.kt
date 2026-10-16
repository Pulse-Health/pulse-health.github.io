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
    private const val PARTNER_ROW_DP = 34f
    private const val PARTNER_CHROME_DP = 62f

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

    /** How many lines (yours included) fit in a widget [heightDp] tall: at least two, at most four. */
    fun partnerRowCapacity(heightDp: Float): Int = ((heightDp - PARTNER_CHROME_DP) / PARTNER_ROW_DP).toInt().coerceIn(2, 4)

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

    data class CueText(val eyebrow: String, val cue: String, val footer: String, val link: String)

    fun formCue(cue: FormCue?): CueText = if (cue == null) {
        CueText("Form cue", "Cues for your next workout show up here.", "", DeepLinks.hub)
    } else {
        CueText(
            eyebrow = "Form cue · ${cue.exerciseName}",
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

    /** [fraction] is the progress toward the goal ratio, or null when there is no ratio to draw a bar for. */
    data class RatioModel(
        val eyebrow: String,
        val figure: String,
        val fraction: Float?,
        val footer: String,
        val description: String,
    )

    /** The lift against bodyweight with a bar toward the goal ratio, or the reason there is no ratio yet. */
    fun strengthRatio(ratio: StrengthRatio?): RatioModel {
        if (ratio == null) {
            return RatioModel(
                eyebrow = "Strength ratio",
                figure = "–",
                fraction = null,
                footer = "Log bench, squat, deadlift or press to see your ratio.",
                description = "Strength ratio: no main lift logged yet",
            )
        }
        val eyebrow = "${ratio.exerciseName} / bodyweight"
        val value = ratio.ratio
        val bodyweight = ratio.bodyweightKg
        if (value == null || bodyweight == null) {
            val estimate = "${PulseFormat.kg(ratio.estimated1RM)} kg"
            return RatioModel(
                eyebrow = eyebrow,
                figure = estimate,
                fraction = null,
                footer = "Add your bodyweight in Health Connect",
                description = "${ratio.exerciseName}: estimated one-rep max $estimate. Add your bodyweight in Health Connect to see the ratio",
            )
        }
        val goal = PulseFormat.number(ratio.goalRatio, 2)
        val figure = PulseFormat.fixed(value, 2)
        return RatioModel(
            eyebrow = eyebrow,
            figure = "$figure×",
            fraction = if (ratio.goalRatio > 0) (value / ratio.goalRatio).toFloat().coerceIn(0f, 1f) else 0f,
            footer = "Goal $goal× · ${PulseFormat.kg(bodyweight)} kg",
            description = "${ratio.exerciseName} is $figure times your bodyweight of ${PulseFormat.kg(bodyweight)} kilograms. The goal is $goal times",
        )
    }

    // WI-08 year in iron

    data class YearBar(val fraction: Float, val isCurrent: Boolean)

    data class YearModel(
        val eyebrow: String,
        val tonnes: String,
        val caption: String,
        val bars: List<YearBar>,
        val description: String,
    )

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
        val caption = if (year.sessionCount > 0) "across $sessions" else "no sessions yet"
        return YearModel(
            eyebrow = "Lifted in ${year.year}",
            tonnes = total,
            caption = caption,
            bars = bars,
            description = "Lifted $total tonnes in ${year.year}, $caption",
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

    /** [kinds] are the kinds present, in legend order; [message] replaces the bar when there is none to draw. */
    data class TimelineModel(
        val name: String?,
        val hasBar: Boolean,
        val kinds: List<TimelineKind>,
        val headline: String,
        val tail: String,
        val message: String?,
        val description: String,
    )

    /** "51 min" in bold, then " · 38% under tension · 1 long break"; or why there is no bar to draw. */
    fun sessionTimeline(session: SessionSummary?): TimelineModel {
        if (session == null) {
            return TimelineModel(
                name = null,
                hasBar = false,
                kinds = emptyList(),
                headline = "",
                tail = "",
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
        val tail = details.joinToString("") { " · $it" }
        return TimelineModel(
            name = session.name,
            hasBar = hasBar,
            kinds = kinds,
            headline = headline,
            tail = tail,
            message = if (hasBar) null else "No set times were recorded for this workout.",
            description = "Session timeline for ${session.name}: $headline$tail",
        )
    }
}
