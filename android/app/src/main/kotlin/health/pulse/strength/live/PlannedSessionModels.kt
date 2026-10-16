package health.pulse.strength.live

import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot

/** A session the person planned: which template, and when it starts. */
internal data class PlannedSession(val templateId: String, val startsAtMillis: Long)

/** Where a plan is on its way to the start. */
internal enum class PlannedPhase {
    /** More than 30 minutes to go: nothing is shown yet. */
    WAITING,

    /** The countdown card runs. */
    COUNTDOWN,

    /** The start time has come: "Time to train". */
    DUE,

    /** Two hours after the start: the plan is forgotten. */
    EXPIRED,
}

/** LA-06: what the pre-workout notifications say (pure, unit-tested). */
internal object PlannedSessionModels {
    /** The countdown appears this long before the start (the canvas shows "in 25 min"). */
    const val COUNTDOWN_LEAD_MILLIS: Long = 30 * 60 * 1000L

    /** "Time to train" stays this long, then the plan is forgotten. */
    const val DUE_LIFETIME_MILLIS: Long = 2 * 60 * 60 * 1000L

    const val SNOOZE_MINUTES = 10

    fun phaseAt(plan: PlannedSession, nowMillis: Long): PlannedPhase = when {
        nowMillis < plan.startsAtMillis - COUNTDOWN_LEAD_MILLIS -> PlannedPhase.WAITING
        nowMillis < plan.startsAtMillis -> PlannedPhase.COUNTDOWN
        nowMillis < plan.startsAtMillis + DUE_LIFETIME_MILLIS -> PlannedPhase.DUE
        else -> PlannedPhase.EXPIRED
    }

    /**
     * The countdown to the start: the template, how long it takes, "Start now" and "Snooze 10 min". [startsAtText] is the local time,
     * "18:00". The card can be swiped away and leaves by itself at the start, even if the alarm for "Time to train" is late.
     */
    fun countdown(plan: PlannedSession, snapshot: WidgetSnapshot, startsAtText: String, nowMillis: Long): LiveCard {
        val template = describe(plan.templateId, snapshot)
        return LiveCard(
            kind = CardKind.PLANNED,
            title = template.name,
            text = template.detail ?: "Your planned workout",
            subText = "Planned $startsAtText",
            countdownToMillis = plan.startsAtMillis,
            actions = actions(plan),
            timeoutMillis = (plan.startsAtMillis - nowMillis).coerceAtLeast(1L),
        )
    }

    /** "Time to train": the one notification of this package that makes a sound. */
    fun due(plan: PlannedSession, snapshot: WidgetSnapshot, startsAtText: String): LiveCard {
        val template = describe(plan.templateId, snapshot)
        return LiveCard(
            kind = CardKind.PLANNED_DUE,
            title = "Time to train",
            text = template.name,
            subText = "Planned $startsAtText",
            detailLines = listOfNotNull(template.detail),
            actions = actions(plan),
            timeoutMillis = DUE_LIFETIME_MILLIS,
        )
    }

    private fun actions(plan: PlannedSession): List<LiveAction> = listOf(
        LiveAction(LiveActionId.START_PLANNED, "Start now", LiveTarget.Link(DeepLinks.start(plan.templateId))),
        LiveAction(LiveActionId.SNOOZE_PLANNED, "Snooze $SNOOZE_MINUTES min", LiveTarget.Snooze(SNOOZE_MINUTES)),
    )

    private class Template(val name: String, val detail: String?)

    /** The template's name and size from the snapshot; the next-up template also names its first exercise. */
    private fun describe(templateId: String, snapshot: WidgetSnapshot): Template {
        val nextUp = snapshot.nextUp?.takeIf { it.templateID == templateId }
        val summary = snapshot.templates.firstOrNull { it.templateID == templateId }
        val name = nextUp?.name ?: summary?.name ?: return Template("Planned workout", null)
        val exercises = nextUp?.exerciseCount ?: summary?.exerciseCount ?: 0
        val minutes = nextUp?.estimatedMinutes ?: summary?.estimatedMinutes ?: 0
        val parts = buildList {
            if (exercises > 0) add(if (exercises == 1) "1 exercise" else "$exercises exercises")
            if (minutes > 0) add("about $minutes min")
            nextUp?.exercises?.firstOrNull()?.let { add("starts with ${it.name}") }
        }
        return Template(name, parts.takeIf { it.isNotEmpty() }?.joinToString(" · "))
    }
}
