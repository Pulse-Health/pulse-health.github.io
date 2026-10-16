package health.pulse.strength.live

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import org.junit.Test

/** LA-06 Pre-workout countdown: the phases of a plan and what its two notifications say. */
class PlannedSessionModelsTest {
    private val snapshot = WidgetSnapshot.preview
    private val nextUp = snapshot.nextUp!!
    private val start = NOW.toEpochMilli() + 25 * 60_000L
    private val plan = PlannedSession(nextUp.templateID, start)

    @Test
    fun aPlanIsWaitingThenCountingDownThenDueThenForgotten() {
        val minute = 60_000L
        assertThat(PlannedSessionModels.phaseAt(plan, start - 31 * minute)).isEqualTo(PlannedPhase.WAITING)
        assertThat(PlannedSessionModels.phaseAt(plan, start - 30 * minute)).isEqualTo(PlannedPhase.COUNTDOWN)
        assertThat(PlannedSessionModels.phaseAt(plan, start - 1)).isEqualTo(PlannedPhase.COUNTDOWN)
        assertThat(PlannedSessionModels.phaseAt(plan, start)).isEqualTo(PlannedPhase.DUE)
        assertThat(PlannedSessionModels.phaseAt(plan, start + 119 * minute)).isEqualTo(PlannedPhase.DUE)
        assertThat(PlannedSessionModels.phaseAt(plan, start + 120 * minute)).isEqualTo(PlannedPhase.EXPIRED)
    }

    @Test
    fun theCountdownCountsToTheStartAndOffersStartNowAndSnooze() {
        val card = PlannedSessionModels.countdown(plan, snapshot, "18:00", NOW.toEpochMilli())
        assertThat(card.kind).isEqualTo(CardKind.PLANNED)
        assertThat(card.title).isEqualTo("Upper A · Push")
        assertThat(card.text).isEqualTo("6 exercises · about 55 min · starts with Bench Press")
        assertThat(card.subText).isEqualTo("Planned 18:00")
        assertThat(card.countdownToMillis).isEqualTo(start)
        assertThat(card.ongoing).isFalse()
        // The system removes the countdown at the start, even if the alarm for "Time to train" comes late.
        assertThat(card.timeoutMillis).isEqualTo(25 * 60_000L)
        assertThat(card.actions.map { it.title }).containsExactly("Start now", "Snooze 10 min").inOrder()
        assertThat(card.actions[0].target).isEqualTo(LiveTarget.Link(DeepLinks.start(nextUp.templateID)))
        assertThat(card.actions[1].target).isEqualTo(LiveTarget.Snooze(10))
        assertThat(card.contentLink).isEqualTo(DeepLinks.hub)
    }

    @Test
    fun timeToTrainMakesASoundAndStaysTwoHours() {
        val card = PlannedSessionModels.due(plan, snapshot, "18:00")
        assertThat(card.kind).isEqualTo(CardKind.PLANNED_DUE)
        assertThat(card.kind.channel).isEqualTo(LiveChannel.REMINDER)
        assertThat(card.title).isEqualTo("Time to train")
        assertThat(card.text).isEqualTo("Upper A · Push")
        assertThat(card.detailLines).containsExactly("6 exercises · about 55 min · starts with Bench Press")
        assertThat(card.ongoing).isFalse()
        assertThat(card.timeoutMillis).isEqualTo(2 * 60 * 60 * 1000L)
        assertThat(card.actions.map { it.title }).containsExactly("Start now", "Snooze 10 min").inOrder()
    }

    @Test
    fun anotherTemplateIsDescribedByItsSummary() {
        val other = snapshot.templates.first { it.templateID != nextUp.templateID }
        val card = PlannedSessionModels.countdown(PlannedSession(other.templateID, start), snapshot, "7:00 AM", NOW.toEpochMilli())
        assertThat(card.title).isEqualTo(other.name)
        assertThat(card.text).isEqualTo("${other.exerciseCount} exercises · about ${other.estimatedMinutes} min")
    }

    @Test
    fun anUnknownTemplateStillGetsACard() {
        val card = PlannedSessionModels.countdown(PlannedSession("not-a-template", start), snapshot, "18:00", NOW.toEpochMilli())
        assertThat(card.title).isEqualTo("Planned workout")
        assertThat(card.text).isEqualTo("Your planned workout")
        assertThat(PlannedSessionModels.due(PlannedSession("not-a-template", start), snapshot, "18:00").detailLines).isEmpty()
    }

    @Test
    fun aCountdownNeverHasANonPositiveTimeout() {
        val late = PlannedSessionModels.countdown(plan, snapshot, "18:00", start + 5_000L)
        assertThat(late.timeoutMillis).isEqualTo(1L)
    }
}
