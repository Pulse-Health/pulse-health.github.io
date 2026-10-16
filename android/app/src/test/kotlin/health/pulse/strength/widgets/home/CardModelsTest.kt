package health.pulse.strength.widgets.home

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.FreshnessStatus
import health.pulse.strength.core.widgets.MuscleFreshness
import java.time.Instant
import org.junit.Test

/** The texts and the choices of the small cards: PR spotlight, muscle freshness and beat last time. */
class CardModelsTest {
    private val preview = HomeFixtures.preview

    // region PR spotlight

    @Test
    fun aFreshRecordIsAnnouncedWithItsWeightRepsAndEstimate() {
        val card = PrModel.card(preview)
        assertThat(card.header).isEqualTo("New PR")
        assertThat(card.age).isNull()
        assertThat(card.exercise).isEqualTo("Bench Press")
        assertThat(card.figure).isEqualTo("85 × 5")
        assertThat(card.detail).isEqualTo("e1RM 99 kg · +4")
        assertThat(card.link).isEqualTo(DeepLinks.exercise("bench"))
        assertThat(card.description).isEqualTo(
            "New PR: Bench Press, 85 kilograms for 5 reps. Estimated one-rep max 99 kilograms, up 4 kilograms",
        )
    }

    @Test
    fun anOlderRecordSaysHowLongAgoItWasSet() {
        val pr = preview.latestPR!!.copy(isFresh = false, achievedAt = Instant.parse("2026-10-14T10:00:00Z"))
        val card = PrModel.card(preview.copy(latestPR = pr))
        assertThat(card.header).isEqualTo("Latest PR")
        assertThat(card.age).isEqualTo("3d ago")
    }

    @Test
    fun aFirstRecordHasNoDeltaAndKeepsFractionalWeights() {
        val pr = preview.latestPR!!.copy(deltaKg = 0.0, weightKg = 82.5, estimated1RM = 96.25)
        val card = PrModel.card(preview.copy(latestPR = pr))
        assertThat(card.figure).isEqualTo("82.5 × 5")
        assertThat(card.detail).isEqualTo("e1RM 96.25 kg")
    }

    @Test
    fun withoutARecordTheCardSaysSoAndOpensTheHub() {
        val card = PrModel.card(HomeFixtures.empty)
        assertThat(card.exercise).isEqualTo("No records yet")
        assertThat(card.figure).isNull()
        assertThat(card.detail).isEqualTo("Your first record shows up here.")
        assertThat(card.link).isEqualTo(DeepLinks.hub)
    }

    // endregion

    // region Muscle freshness

    @Test
    fun theFourGroupsTrainedLongestAgoAreListedLongestFirst() {
        val card = FreshnessModel.card(preview, maxRows = 4)
        // Core was never trained, then Legs (7 days), then Chest and Shoulders (both 5: the order of the groups breaks the tie).
        assertThat(card.rows.map { it.muscle }).containsExactly("Core", "Legs", "Chest", "Shoulders").inOrder()
        assertThat(card.rows.map { it.days }).containsExactly("never", "7d", "5d", "5d").inOrder()
        assertThat(card.header).isEqualTo("Ready to train")
    }

    @Test
    fun theRowLimitCutsTheListFromTheEnd() {
        assertThat(FreshnessModel.card(preview, maxRows = 3).rows.map { it.muscle }).containsExactly("Core", "Legs", "Chest").inOrder()
        assertThat(FreshnessModel.card(preview, maxRows = 0).rows).isEmpty()
    }

    @Test
    fun theHeadingTurnsToRecoveringWhenNoneOfThemIsReady() {
        val tired = MuscleGroup.entries.map { MuscleFreshness(it, daysSince = 1, status = FreshnessStatus.WORKED) }
        val card = FreshnessModel.card(preview.copy(freshness = tired), maxRows = 4)
        assertThat(card.header).isEqualTo("Recovering")
        assertThat(card.rows.map { it.status }.distinct()).containsExactly(FreshnessStatus.WORKED)
    }

    @Test
    fun everyRowIsDescribedInWordsSoColourIsNotTheOnlyCarrier() {
        val card = FreshnessModel.card(preview, maxRows = 4)
        assertThat(card.rows[0].description).isEqualTo("Core: ready, not trained yet")
        assertThat(card.rows[1].description).isEqualTo("Legs: ready, 7 days ago")
        assertThat(card.description).startsWith("Ready to train. Core: ready, not trained yet.")
        val arms = MuscleFreshness(MuscleGroup.ARMS, daysSince = 1, status = FreshnessStatus.WORKED)
        assertThat(FreshnessModel.card(preview.copy(freshness = listOf(arms)), 4).rows.single().description)
            .isEqualTo("Arms: worked recently, yesterday")
    }

    @Test
    fun withoutFreshnessDataTheCardIsEmptyButSaysSo() {
        val card = FreshnessModel.card(preview.copy(freshness = emptyList()), maxRows = 4)
        assertThat(card.rows).isEmpty()
        assertThat(card.description).isEqualTo("No recovery data yet")
    }

    @Test
    fun theRowCountFollowsTheHeight() {
        assertThat(FreshnessModel.rowCount(146f)).isEqualTo(4)
        assertThat(FreshnessModel.rowCount(125f)).isEqualTo(3)
        assertThat(FreshnessModel.rowCount(110f)).isEqualTo(2)
        assertThat(FreshnessModel.rowCount(400f)).isEqualTo(4)
    }

    // endregion

    // region Beat last time

    @Test
    fun aHeavierTargetIsShownAsTheWeightToTry() {
        val card = OverloadModel.card(preview)
        assertThat(card.age).isEqualTo("5d ago")
        assertThat(card.label).isEqualTo("Last time")
        assertThat(card.exercise).isEqualTo("Bench Press")
        assertThat(card.last).isEqualTo("80 × 6")
        assertThat(card.target).isEqualTo("Try 82.5 today")
        assertThat(card.link).isEqualTo(DeepLinks.exercise("bench"))
        assertThat(card.description).isEqualTo(
            "Beat last time. Bench Press: 80 kilograms for 6 reps, 5 days ago. Today: 82.5 kilograms for 6 reps in 4 sets.",
        )
    }

    @Test
    fun whenTheWeightStaysTheTargetIsOneMoreRep() {
        val overload = preview.overload!!.copy(targetWeightKg = 80.0, targetReps = 7, deltaKg = 0.0)
        assertThat(OverloadModel.card(preview.copy(overload = overload)).target).isEqualTo("Try 80 × 7 today")
    }

    @Test
    fun theAgeIsOmittedWhenUnknownAndSpelledForToday() {
        val unknown = preview.overload!!.copy(lastDaysAgo = null)
        assertThat(OverloadModel.card(preview.copy(overload = unknown)).age).isNull()
        val today = preview.overload!!.copy(lastDaysAgo = 0)
        assertThat(OverloadModel.card(preview.copy(overload = today)).age).isEqualTo("today")
    }

    @Test
    fun withoutATargetTheCardExplainsHowToGetOne() {
        val card = OverloadModel.card(HomeFixtures.empty)
        assertThat(card.exercise).isEqualTo("No target yet")
        assertThat(card.last).isNull()
        assertThat(card.target).isEqualTo("Finish a workout to get one")
        assertThat(card.link).isEqualTo(DeepLinks.hub)
    }

    // endregion
}
