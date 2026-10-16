package health.pulse.strength.live

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import org.junit.Test

/** LA-01 ... LA-05 and LA-07 ... LA-10: what the decoration adds to the ongoing notification, for every state. */
class LiveDecorationsTest {
    private fun decoration(snapshot: WorkoutSnapshot, dismissedTip: String? = null) =
        LiveDecorations.of(snapshot, NOW, dismissedTip)

    private fun LiveDecoration.commandOf(id: LiveActionId): WidgetCommand =
        (actions!!.single { it.id == id }.target as LiveTarget.Command).command

    // region A workout without live moments changes nothing

    @Test
    fun aPlainLoggingSetOnlyGetsTheSetDotsAndTheProgressBar() {
        val d = decoration(loggingSnapshot())
        assertThat(d.title).isNull()
        assertThat(d.text).isNull()
        assertThat(d.bigText).isNull()
        assertThat(d.actions).isNull()
        assertThat(d.accent).isNull()
        assertThat(d.finish).isNull()
        assertThat(d.opensBenchMode).isFalse()
        // LA-08: set 4 of 5 of the shown exercise.
        assertThat(d.chipText).isEqualTo("4/5")
        // 9 earlier sets, the 5 sets of the shown exercise one by one, 6 later sets; 12 logged.
        assertThat(d.progress).isEqualTo(LiveProgress(12, listOf(9, 1, 1, 1, 1, 1, 6)))
        assertThat(d.progress!!.segments.sum()).isEqualTo(20)
    }

    @Test
    fun withoutSetCountsTheProgressIsOneSegmentAndTheChipIsEmpty() {
        val d = decoration(loggingSnapshot().copy(exerciseDoneSets = null, exerciseSetCount = null))
        assertThat(d.chipText).isNull()
        assertThat(d.progress).isEqualTo(LiveProgress(12, listOf(20)))
    }

    @Test
    fun aWorkoutWithoutSetsHasNoProgressBar() {
        val d = decoration(completeSnapshot().copy(totalSets = 0, loggedSets = 0, exerciseSetCount = null, exerciseDoneSets = null))
        assertThat(d.progress).isNull()
        assertThat(d.chipText).isNull()
    }

    @Test
    fun inconsistentSetCountsNeverProduceAnInvalidBar() {
        val d = decoration(loggingSnapshot().copy(loggedSets = 30, exerciseSetCount = 50, exerciseDoneSets = 9))
        assertThat(d.progress).isEqualTo(LiveProgress(20, listOf(20)))
        val clamped = decoration(loggingSnapshot().copy(loggedSets = 2, exerciseDoneSets = 5)).progress!!
        assertThat(clamped.segments.all { it >= 1 }).isTrue()
        assertThat(clamped.segments.sum()).isEqualTo(20)
    }

    // endregion

    // region Phases

    @Test
    fun restingOpensBenchModeAndLeavesTheChipToTheCountdown() {
        val d = decoration(restingSnapshot())
        assertThat(d.opensBenchMode).isTrue()
        assertThat(d.chipText).isNull()
        assertThat(d.actions).isNull()
    }

    @Test
    fun aRestWhoseTimeRanOutIsOverEvenIfTheEngineHasNotSaidSo() {
        val d = LiveDecorations.of(restingSnapshot(remaining = -3), NOW)
        assertThat(d.chipText).isEqualTo("Go")
        assertThat(d.opensBenchMode).isTrue()
    }

    @Test
    fun restOverSaysGo() {
        val d = decoration(loggingSnapshot().copy(phase = SnapshotPhase.REST_OVER))
        assertThat(d.chipText).isEqualTo("Go")
        assertThat(d.opensBenchMode).isTrue()
    }

    @Test
    fun pausedSaysPausedAndStaysOutOfBenchMode() {
        val d = decoration(pausedSnapshot().copy(moment = moment(), superset = superset(), plates = plates()))
        assertThat(d.chipText).isEqualTo("Paused")
        assertThat(d.opensBenchMode).isFalse()
        // Nothing live is drawn while the clock is frozen.
        assertThat(d.title).isNull()
        assertThat(d.bigText).isNull()
        assertThat(d.actions).isNull()
    }

    @Test
    fun completeSaysDoneUnlessThereAreNoSets() {
        assertThat(decoration(completeSnapshot()).chipText).isEqualTo("Done")
        assertThat(decoration(completeSnapshot().copy(totalSets = 0, loggedSets = 0)).chipText).isNull()
    }

    // endregion

    // region LA-01 PR moment

    @Test
    fun aPersonalRecordReplacesTitleAndTextAndFlashesPr() {
        val d = decoration(restingSnapshot().copy(moment = moment()))
        assertThat(d.title).isEqualTo("New record: Bench Press")
        assertThat(d.text).isEqualTo("85 × 5 · e1RM 99 kg (+4)")
        assertThat(d.chipText).isEqualTo("PR")
        assertThat(d.accent).isEqualTo(LiveAccent.GOLD)
    }

    @Test
    fun theRecordTextLeavesOutWhatItDoesNotKnow() {
        val d = decoration(restingSnapshot().copy(moment = moment().copy(estimated1RM = 0, deltaKg = 0)))
        assertThat(d.text).isEqualTo("85 × 5")
        val noDelta = decoration(restingSnapshot().copy(moment = moment().copy(deltaKg = 0)))
        assertThat(noDelta.text).isEqualTo("85 × 5 · e1RM 99 kg")
    }

    @Test
    fun anExpiredRecordIsGone() {
        val d = decoration(restingSnapshot().copy(moment = moment(expiresIn = 0)))
        assertThat(d.title).isNull()
        assertThat(d.text).isNull()
        assertThat(d.chipText).isNull()
        assertThat(LiveDecorations.flashEnd(restingSnapshot().copy(moment = moment(expiresIn = -1)), NOW)).isNull()
    }

    @Test
    fun theFlashEndsAtExpiresAt() {
        assertThat(LiveDecorations.flashEnd(restingSnapshot().copy(moment = moment()), NOW)).isEqualTo(NOW.plusSeconds(4))
        assertThat(LiveDecorations.flashEnd(restingSnapshot(), NOW)).isNull()
        assertThat(LiveDecorations.flashEnd(pausedSnapshot().copy(moment = moment()), NOW)).isNull()
        assertThat(LiveDecorations.flashEnd(restingSnapshot().copy(moment = moment(), finish = finishBrief()), NOW)).isNull()
    }

    @Test
    fun theRecordBeatsEveryOtherChip() {
        val d = decoration(loggingSnapshot().copy(moment = moment(), superset = superset(), heartRate = 142))
        assertThat(d.chipText).isEqualTo("PR")
    }

    // endregion

    // region LA-02 superset

    @Test
    fun aSupersetListsItsMembersAndOffersLogA2() {
        val d = decoration(loggingSnapshot().copy(superset = superset()))
        assertThat(d.bigText!!.lines()).containsExactly(
            "Set 4 of 5 · 82.5 kg × 6",
            "Superset · round 2/3",
            "A1 Lateral Raise · 10 × 12 (done)",
            "A2 Triceps Pushdown · 25 × 12 (now)",
            "12 of 20 sets · 4,980 kg",
        ).inOrder()
        assertThat(d.progress).isNull()
        assertThat(d.actions!!.map { it.title }).containsExactly("Log A2", "Weight −", "Weight +").inOrder()
        assertThat(d.commandOf(LiveActionId.LOG_SET)).isEqualTo(
            WidgetCommand.of(WidgetCommands.LOG_SET, WidgetCommands.ARG_EXERCISE_ID to EXERCISE_ID.toString(), WidgetCommands.ARG_SET_ID to SET_ID.toString()),
        )
        assertThat(d.commandOf(LiveActionId.NUDGE_UP)).isEqualTo(
            WidgetCommand.of(WidgetCommands.NUDGE, WidgetCommands.ARG_WEIGHT_STEPS to "1", WidgetCommands.ARG_REPS_STEPS to "0"),
        )
        // LA-09: the tag of the current member and the round.
        assertThat(d.chipText).isEqualTo("A2 2/3")
    }

    @Test
    fun theSupersetStepperMovesTheRepsOfABodyweightExercise() {
        val d = decoration(
            loggingSnapshot().copy(superset = superset(), tracking = TrackingKind.REPS_ONLY, showsWeight = false, weightText = "BW", repsUnit = "reps"),
        )
        assertThat(d.actions!!.map { it.title }).containsExactly("Log A2", "Reps −", "Reps +").inOrder()
        assertThat(d.commandOf(LiveActionId.NUDGE_DOWN)).isEqualTo(
            WidgetCommand.of(WidgetCommands.NUDGE, WidgetCommands.ARG_WEIGHT_STEPS to "0", WidgetCommands.ARG_REPS_STEPS to "-1"),
        )
    }

    @Test
    fun withoutATargetSetLogA2LogsTheNextSet() {
        val d = decoration(loggingSnapshot().copy(superset = superset(), targetExerciseID = null, targetSetID = null))
        assertThat(d.commandOf(LiveActionId.LOG_SET)).isEqualTo(WidgetCommand.of(WidgetCommands.LOG_NEXT_SET))
    }

    @Test
    fun whileRestingTheSupersetKeepsTheRestButtonsAndTheCountdownChip() {
        val d = decoration(restingSnapshot().copy(superset = superset()))
        assertThat(d.actions).isNull()
        assertThat(d.chipText).isNull()
        assertThat(d.bigText!!.lines().first()).isEqualTo("Next: Set 4 · 82.5 kg × 6")
        assertThat(d.bigText).contains("A2 Triceps Pushdown · 25 × 12 (now)")
    }

    @Test
    fun aLongRoundCountDropsTheTagFromTheChip() {
        val long = superset().copy(round = 10, rounds = 12)
        assertThat(decoration(loggingSnapshot().copy(superset = long)).chipText).isEqualTo("10/12")
        assertThat(decoration(loggingSnapshot().copy(superset = superset().copy(members = emptyList()))).bigText).isNull()
    }

    // endregion

    // region LA-03 plate math

    @Test
    fun thePlatesAreAPerSideLineOfTheBigText() {
        val d = decoration(loggingSnapshot().copy(plates = plates()))
        assertThat(d.bigText!!.lines()).containsExactly(
            "Set 4 of 5 · 82.5 kg × 6",
            "Per side: 20 + 10 + 2.5",
            "12 of 20 sets · 4,980 kg",
        ).inOrder()
        assertThat(d.actions).isNull()
        assertThat(d.progress).isNull()
    }

    @Test
    fun thePlatesAreAlsoShownWhileRestingBecauseThatIsWhenTheBarIsLoaded() {
        val d = decoration(restingSnapshot().copy(plates = plates()))
        assertThat(d.bigText).contains("Per side: 20 + 10 + 2.5")
    }

    @Test
    fun anEmptyBarAndALeftoverAreSaidInWords() {
        val bar = decoration(loggingSnapshot().copy(plates = plates().copy(perSide = emptyList(), summary = "", totalKg = 20.0)))
        assertThat(bar.bigText).contains("Per side: bar only")
        val short = decoration(loggingSnapshot().copy(plates = plates().copy(leftoverKg = 0.5)))
        assertThat(short.bigText).contains("Per side: 20 + 10 + 2.5 · 0.5 kg short")
        val computed = decoration(loggingSnapshot().copy(plates = plates().copy(summary = "")))
        assertThat(computed.bigText).contains("Per side: 20 + 10 + 2.5")
    }

    @Test
    fun noPlatesWhenEverySetIsLogged() {
        assertThat(decoration(completeSnapshot().copy(plates = plates())).bigText).isNull()
    }

    // endregion

    // region LA-04 coach tip

    @Test
    fun theCoachTipOffersTheSuggestionAKeepAndSkip() {
        val d = decoration(restingSnapshot().copy(coachTip = coachTip()))
        assertThat(d.text).isEqualTo("Coach: add 2.5 kg for set 3 to stay at 1–2 RIR.")
        val actions = d.actions!!
        assertThat(actions.map { it.title }).containsExactly("82.5 kg", "Keep 80", "Skip").inOrder()
        assertThat(d.commandOf(LiveActionId.APPLY_TIP)).isEqualTo(
            WidgetCommand.of(WidgetCommands.APPLY_COACH_TIP, WidgetCommands.ARG_SET_ID to SET_ID.toString(), WidgetCommands.ARG_WEIGHT_KG to "82.5"),
        )
        assertThat(actions.single { it.id == LiveActionId.KEEP_TIP }.target).isEqualTo(LiveTarget.KeepCoachTip(SET_ID.toString()))
        assertThat(d.commandOf(LiveActionId.SKIP_REST)).isEqualTo(WidgetCommand.of(WidgetCommands.SKIP_REST))
        val lines = d.bigText!!.lines()
        assertThat(lines).containsAtLeast("3 reps in reserve on set 2", "Next: Set 4 · 82.5 kg × 6")
        // The expanded card starts with the line the collapsed card shows.
        assertThat(lines.first()).isEqualTo(d.text)
    }

    @Test
    fun keepingTheSuggestionRemovesTheTipOnTheNextRefresh() {
        val d = decoration(restingSnapshot().copy(coachTip = coachTip()), dismissedTip = SET_ID.toString())
        assertThat(d.text).isNull()
        assertThat(d.actions).isNull()
        assertThat(d.bigText).isNull()
    }

    @Test
    fun aTipOnlyLivesWhileResting() {
        assertThat(decoration(loggingSnapshot().copy(coachTip = coachTip())).actions).isNull()
        assertThat(decoration(restingSnapshot(remaining = -1).copy(coachTip = coachTip())).actions).isNull()
        assertThat(decoration(pausedSnapshot().copy(phase = SnapshotPhase.RESTING, coachTip = coachTip())).actions).isNull()
    }

    // endregion

    // region LA-05 finish and the chip priority

    @Test
    fun aFinishedWorkoutBecomesTheSummaryCard() {
        val d = decoration(loggingSnapshot().copy(finish = finishBrief(), moment = moment()))
        val card = d.finish!!
        assertThat(card.title).isEqualTo("Upper A · Push done")
        assertThat(card.text).isEqualTo("52 min · 22 sets · 9.1 t · 1 PR")
        assertThat(card.subText).isEqualTo("Saved to Health")
        assertThat(card.ongoing).isFalse()
        assertThat(card.timeoutMillis).isEqualTo(2 * 60 * 60 * 1000L)
        assertThat(card.accent).isEqualTo(LiveAccent.GOLD)
        assertThat(card.actions.single().target).isEqualTo(LiveTarget.Share("Upper A · Push: 52 min, 22 sets, 9.1 t, 1 PR"))
        assertThat(d.chipText).isNull()
        assertThat(d.title).isNull()
    }

    @Test
    fun theHeartRateBeatsTheSetDotsInTheChip() {
        assertThat(decoration(loggingSnapshot().copy(heartRate = 142)).chipText).isEqualTo("142")
        assertThat(decoration(loggingSnapshot().copy(heartRate = null)).chipText).isEqualTo("4/5")
    }

    @Test
    fun theCompactPriorityIsMomentThenRestThenSupersetThenLogging() {
        val base = loggingSnapshot().copy(heartRate = 142, superset = superset())
        assertThat(decoration(base).chipText).isEqualTo("A2 2/3")
        assertThat(decoration(base.copy(superset = null)).chipText).isEqualTo("142")
        assertThat(decoration(base.copy(phase = SnapshotPhase.RESTING, restEndsAt = NOW.plusSeconds(30))).chipText).isNull()
        assertThat(decoration(base.copy(moment = moment())).chipText).isEqualTo("PR")
    }

    @Test
    fun everyChipFitsTheStatusBar() {
        val chips = listOf(
            decoration(loggingSnapshot()).chipText,
            decoration(loggingSnapshot().copy(heartRate = 188)).chipText,
            decoration(loggingSnapshot().copy(superset = superset())).chipText,
            decoration(loggingSnapshot().copy(moment = moment())).chipText,
            decoration(pausedSnapshot()).chipText,
            decoration(completeSnapshot()).chipText,
        )
        chips.filterNotNull().forEach { assertThat(it.length).isAtMost(LiveDecorations.MAX_CHIP_LENGTH) }
    }

    // endregion
}
