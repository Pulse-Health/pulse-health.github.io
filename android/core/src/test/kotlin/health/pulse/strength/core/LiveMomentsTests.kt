package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.widgets.CoachTipBrief
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.core.widgets.PRMoment
import health.pulse.strength.core.widgets.PlateBrief
import health.pulse.strength.core.widgets.SupersetBrief
import health.pulse.strength.core.widgets.WidFix
import java.time.Instant
import java.util.UUID
import org.junit.Test

/**
 * The live context of the live card (widgets/SPEC.md section 2, "Live moments"): what `SnapshotBuilder.make` derives from the state
 * (set dots, superset, plates, coach tip) and the two things the app asks for (`prMoment`, `finishBrief`). Mirrors the Swift
 * LiveMomentsTests.
 */
class LiveMomentsTests {
    // region Helpers

    private fun snapshot(state: WorkoutState, seconds: Number = 20): WorkoutSnapshot = SnapshotBuilder.make(state, PresFix.at(seconds.toDouble()))

    /** [state] after logging the next pending set [count] times, one second apart from [start]. */
    private fun logging(state: WorkoutState, count: Int, start: Double = 10.0): WorkoutState {
        var copy = state
        for (step in 0 until count) copy = WorkoutReducer.reduce(copy, WorkoutAction.LogNextSet, PresFix.at(start + step))
        return copy
    }

    /** A superset brief as one line: "A round 2/3: A1 9 × 14 done | A2 32.5 × 11 current". */
    private fun line(brief: SupersetBrief?): String {
        if (brief == null) return "none"
        val rows = brief.members.map { member ->
            listOf(member.tag, member.detail, if (member.isDone) "done" else "", if (member.isCurrent) "current" else "")
                .filter { it.isNotEmpty() }
                .joinToString(" ")
        }
        return "${brief.label} round ${brief.round}/${brief.rounds}: " + rows.joinToString(" | ")
    }

    private fun sets(vararg specs: Triple<SetType, Double, Int>): List<Triple<SetType, Double, Int>> = specs.toList()

    private fun normal(kg: Double, reps: Int) = Triple(SetType.NORMAL, kg, reps)

    /** Dumbbell raise + pushdown in superset "A", three sets each, no rest between the members. */
    private fun pair(): WorkoutState {
        val lateral = PresFix.entry(1, PresFix.lib("lateral"), sets(normal(8.0, 15), normal(9.0, 14), normal(10.0, 13)), rest = 60, group = "A")
        val pushdown = PresFix.entry(2, PresFix.lib("pushdown"), sets(normal(30.0, 12), normal(32.5, 11), normal(35.0, 10)), rest = 60, group = "A")
        return PresFix.workout(listOf(lateral, pushdown))
    }

    /** The bench press with [sets], a previous best of [best] (0 = no history). */
    private fun bench(best: Double, vararg specs: Triple<SetType, Double, Int>): WorkoutState =
        PresFix.single(PresFix.lib("bench", best), specs.toList())

    // endregion

    // region Set dots

    @Test
    fun testTheBuilderNeverSetsTheMomentOrTheFinishCard() {
        val states = listOf(
            PresFix.freshUpperA(), PresFix.goldenState(), PresFix.loggedEverything(PresFix.freshUpperA()), PresFix.workout(emptyList()),
        )
        for (state in states) {
            val snap = snapshot(state, 1458)
            assertThat(snap.moment).isNull()
            assertThat(snap.finish).isNull()
        }
    }

    @Test
    fun testSetDotsCountTheSetsOfTheShownExercise() {
        val fresh = snapshot(PresFix.freshUpperA())
        assertThat(fresh.exerciseDoneSets).isEqualTo(0)
        assertThat(fresh.exerciseSetCount).isEqualTo(5)

        // The design's opening state: two warm-ups and the first working set of the bench are logged.
        val golden = snapshot(PresFix.goldenState(), 1458)
        assertThat(golden.exerciseDoneSets).isEqualTo(3)
        assertThat(golden.exerciseSetCount).isEqualTo(5)
    }

    @Test
    fun testSetDotsFollowTheTargetToTheNextExercise() {
        // The bench has five sets; once they are logged the incline press (three sets) is next.
        val state = logging(PresFix.freshUpperA(), 5)
        val snap = snapshot(state)
        assertThat(snap.exerciseName).isEqualTo(state.exercises[1].exercise.name)
        assertThat(snap.exerciseDoneSets).isEqualTo(0)
        assertThat(snap.exerciseSetCount).isEqualTo(3)
    }

    @Test
    fun testSetDotsOfAFinishedWorkoutAreFull() {
        val state = PresFix.loggedEverything(PresFix.freshUpperA())
        val snap = snapshot(state)
        val shown = state.exercises[state.clampedIndex]
        assertThat(snap.phase).isEqualTo(SnapshotPhase.COMPLETE)
        assertThat(snap.exerciseDoneSets).isEqualTo(shown.sets.size)
        assertThat(snap.exerciseSetCount).isEqualTo(shown.sets.size)
    }

    @Test
    fun testAWorkoutWithoutExercisesHasNoLiveContext() {
        val snap = snapshot(PresFix.workout(emptyList()))
        assertThat(snap.exerciseDoneSets).isNull()
        assertThat(snap.exerciseSetCount).isNull()
        assertThat(snap.superset).isNull()
        assertThat(snap.plates).isNull()
        assertThat(snap.coachTip).isNull()
    }

    // endregion

    // region Superset

    @Test
    fun testSupersetFollowsTheRoundsOfAPair() {
        val state = pair()
        val lateral = state.exercises[0].exercise.name
        val pushdown = state.exercises[1].exercise.name

        val start = snapshot(state).superset!!
        assertThat(start.members.map { it.name }).containsExactly(lateral, pushdown).inOrder()
        assertThat(start.members.map { it.tag }).containsExactly("A1", "A2").inOrder()
        assertThat(line(start)).isEqualTo("A round 1/3: A1 8 × 15 current | A2 30 × 12")

        // The first member is logged: the second is next, in the same round; nothing rests between the members.
        val afterFirst = snapshot(logging(state, 1))
        assertThat(afterFirst.phase).isEqualTo(SnapshotPhase.LOGGING)
        assertThat(afterFirst.exerciseName).isEqualTo(pushdown)
        assertThat(line(afterFirst.superset)).isEqualTo("A round 1/3: A1 9 × 14 done | A2 30 × 12 current")

        // The round is complete: rest, then the first member again in round 2.
        val afterRound = snapshot(logging(state, 2))
        assertThat(afterRound.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(afterRound.exerciseName).isEqualTo(lateral)
        assertThat(line(afterRound.superset)).isEqualTo("A round 2/3: A1 9 × 14 current | A2 32.5 × 11")
    }

    @Test
    fun testTheRoundDoesNotMoveOnWhileTheSecondMemberIsStillDue() {
        // The first member has two sets logged and the second one: the pair is in round 2 (counting the first member's sets alone
        // would say round 3 here).
        val state = pair()
        assertThat(line(snapshot(logging(state, 3)).superset)).isEqualTo("A round 2/3: A1 10 × 13 done | A2 32.5 × 11 current")
        assertThat(line(snapshot(logging(state, 4)).superset)).isEqualTo("A round 3/3: A1 10 × 13 current | A2 35 × 10")
        assertThat(line(snapshot(logging(state, 5)).superset)).isEqualTo("A round 3/3: A1 10 × 13 done | A2 35 × 10 current")
    }

    @Test
    fun testAFinishedSupersetStaysOnTheLastRound() {
        val snap = snapshot(logging(pair(), 6))
        assertThat(snap.phase).isEqualTo(SnapshotPhase.COMPLETE)
        assertThat(line(snap.superset)).isEqualTo("A round 3/3: A1 10 × 13 done current | A2 35 × 10 done")
    }

    @Test
    fun testSupersetOfThreeExercisesIsTaggedByPosition() {
        val entries = listOf(
            PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(2, 8.0, 15), group = "B"),
            PresFix.entry(2, PresFix.lib("pushdown"), PresFix.normal(2, 30.0, 12), group = "B"),
            PresFix.entry(3, PresFix.lib("crossover"), PresFix.normal(2, 15.0, 12), group = "B"),
        )
        val state = PresFix.workout(entries)
        assertThat(line(snapshot(state).superset)).isEqualTo("B round 1/2: B1 8 × 15 current | B2 30 × 12 | B3 15 × 12")
        assertThat(line(snapshot(logging(state, 2)).superset)).isEqualTo("B round 1/2: B1 8 × 15 done | B2 30 × 12 done | B3 15 × 12 current")
        assertThat(line(snapshot(logging(state, 3)).superset)).isEqualTo("B round 2/2: B1 8 × 15 current | B2 30 × 12 | B3 15 × 12")
    }

    @Test
    fun testSupersetDetailOfRepsAndDurationExercises() {
        val entries = listOf(
            PresFix.entry(1, PresFix.lib("pushup"), PresFix.normal(1, 0.0, 12), group = "C"),
            PresFix.entry(2, PresFix.lib("plank"), PresFix.normal(1, 0.0, 45), group = "C"),
        )
        // No weight to put in front of the body weight ("BW × 12") and none for the plank, which shows its seconds.
        assertThat(line(snapshot(PresFix.workout(entries)).superset)).isEqualTo("C round 1/1: C1 BW × 12 current | C2 45 s")
    }

    @Test
    fun testSupersetUsesTheSetCountOfTheFirstMemberAsRounds() {
        val entries = listOf(
            PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(2, 8.0, 15), group = "A"),
            PresFix.entry(2, PresFix.lib("pushdown"), PresFix.normal(4, 30.0, 12), group = "A"),
        )
        // Both members have logged two sets: the round stays at the cap while the second member still has sets left.
        assertThat(line(snapshot(logging(PresFix.workout(entries), 4)).superset)).isEqualTo("A round 2/2: A1 8 × 15 done | A2 30 × 12 done current")
    }

    @Test
    fun testSupersetMemberWithoutSetsHasNothingToDo() {
        val entries = listOf(
            PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(3, 8.0, 15), group = "A"),
            PresFix.entry(2, PresFix.lib("pushdown"), emptyList(), group = "A"),
        )
        assertThat(line(snapshot(PresFix.workout(entries)).superset)).isEqualTo("A round 1/3: A1 8 × 15 current | A2 done")
    }

    @Test
    fun testSupersetShowsAMemberLoggedOutOfOrder() {
        val state = pair()
        val second = state.exercises[1]
        val reduced = PresFix.reduced(state, WorkoutAction.LogSet(second.id, second.sets[0].id), 10)
        assertThat(line(snapshot(reduced).superset)).isEqualTo("A round 1/3: A1 8 × 15 current | A2 32.5 × 11 done")
    }

    @Test
    fun testNoSupersetForOtherExercisesOrALoneGroup() {
        // The shown exercise (the bench) is not in a group, although the workout holds a superset.
        assertThat(snapshot(PresFix.freshUpperA()).superset).isNull()

        // Once the lateral raise is the shown exercise the superset of the template appears.
        val upper = PresFix.freshUpperA().copy(currentIndex = 3)
        assertThat(line(snapshot(upper).superset)).isEqualTo("A round 1/3: A1 8 × 15 current | A2 30 × 12")

        // A group of one is no superset, and neither is an empty group name.
        val lone = PresFix.workout(listOf(PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(3, 8.0, 15), group = "A")))
        assertThat(snapshot(lone).superset).isNull()
        val unnamed = PresFix.workout(
            listOf(
                PresFix.entry(1, PresFix.lib("lateral"), PresFix.normal(3, 8.0, 15), group = ""),
                PresFix.entry(2, PresFix.lib("pushdown"), PresFix.normal(3, 30.0, 12), group = ""),
            ),
        )
        assertThat(snapshot(unnamed).superset).isNull()
    }

    // endregion

    // region Plates

    @Test
    fun testPlatesOfABarbellSet() {
        val snap = snapshot(bench(0.0, normal(82.5, 6)))
        assertThat(snap.plates).isEqualTo(PlateBrief(totalKg = 82.5, barKg = 20.0, perSide = listOf(25.0, 5.0, 1.25), leftoverKg = 0.0, summary = "25 + 5 + 1.25"))
    }

    @Test
    fun testPlatesAlsoCoverWarmUpsAndTheRestingPhase() {
        // The first set of the upper workout is a 50 kg warm-up: one 15 kg plate per side.
        assertThat(snapshot(PresFix.freshUpperA()).plates).isEqualTo(PlateBrief(totalKg = 50.0, barKg = 20.0, perSide = listOf(15.0), leftoverKg = 0.0, summary = "15"))
        // While resting the target is the next working set of the bench, 82.5 kg.
        val resting = snapshot(PresFix.goldenState(), 1458)
        assertThat(resting.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(resting.plates?.summary).isEqualTo("25 + 5 + 1.25")
        assertThat(resting.plates?.totalKg).isEqualTo(82.5)
    }

    @Test
    fun testPlatesUseTheBarOfTheExercise() {
        val squat = PresFix.lib("squat").copy(barKg = 15.0)
        val snap = snapshot(PresFix.single(squat, sets(normal(100.0, 5))))
        assertThat(snap.plates).isEqualTo(PlateBrief(totalKg = 100.0, barKg = 15.0, perSide = listOf(25.0, 15.0, 2.5), leftoverKg = 0.0, summary = "25 + 15 + 2.5"))
    }

    @Test
    fun testPlatesReportWhatCannotBeLoaded() {
        val snap = snapshot(bench(0.0, normal(23.7, 5)))
        assertThat(snap.plates).isEqualTo(PlateBrief(totalKg = 23.7, barKg = 20.0, perSide = listOf(1.25), leftoverKg = 0.6, summary = "1.25"))
    }

    @Test
    fun testNoPlatesWhenNothingIsLoadedOnTheBar() {
        // The empty bar, below the bar, a weight smaller than the smallest plate on each side, and no weight at all.
        for (kilograms in listOf(20.0, 15.0, 21.0, 0.0)) {
            assertWithMessage("$kilograms kg").that(snapshot(bench(0.0, normal(kilograms, 5))).plates).isNull()
        }
    }

    @Test
    fun testNoPlatesForOtherEquipmentOrTracking() {
        val cases = listOf("incline" to normal(28.0, 10), "crossover" to normal(15.0, 12), "legpress" to normal(100.0, 10), "pushup" to normal(0.0, 12), "plank" to normal(0.0, 45))
        for ((id, spec) in cases) {
            assertWithMessage(id).that(snapshot(PresFix.single(PresFix.lib(id), listOf(spec))).plates).isNull()
        }
    }

    @Test
    fun testNoPlatesWhenEverySetIsLogged() {
        val snap = snapshot(logging(bench(0.0, normal(82.5, 6)), 1))
        assertThat(snap.phase).isEqualTo(SnapshotPhase.COMPLETE)
        assertThat(snap.plates).isNull()
    }

    @Test
    fun testDamagedWeightsGivePlatesNothingToShow() {
        for (kilograms in listOf(Double.NaN, Double.POSITIVE_INFINITY, -5.0, 1e15)) {
            assertWithMessage("$kilograms kg").that(snapshot(bench(0.0, normal(kilograms, 5))).plates).isNull()
        }
    }

    // endregion

    // region Coach tip

    /** The design's opening state with [rir] recorded on the last logged set. */
    private fun openingState(rir: Int?): WorkoutState {
        val state = PresFix.goldenState()
        val reference = state.lastLogged ?: return state
        val k = state.exercises.indexOfFirst { it.id == reference.exerciseID }
        val i = state.exercises[k].sets.indexOfFirst { it.id == reference.setID }
        return PresFix.editSet(state, k, i) { it.copy(rir = rir) }
    }

    @Test
    fun testCoachTipAfterAnEasySet() {
        // Warm-ups and the first 82.5 kg set (RIR 3) are logged and the rest runs: the next working set is 82.5 kg.
        val state = PresFix.goldenState()
        val snap = snapshot(state, 1458)
        assertThat(snap.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snap.coachTip).isEqualTo(
            CoachTipBrief(
                title = "Felt easy?",
                subtitle = "3 reps in reserve on set 3",
                text = "Try 85 kg on set 4.",
                suggestedWeightKg = 85.0,
                suggestedWeightText = "85 kg",
                keepWeightText = "Keep 82.5",
                targetSetID = state.exercises[0].sets[3].id.toString(),
                targetExerciseID = state.exercises[0].id.toString(),
            ),
        )
    }

    @Test
    fun testCoachTipNeedsThreeRepsInReserve() {
        assertThat(snapshot(openingState(null), 1458).coachTip).isNull()
        assertThat(snapshot(openingState(0), 1458).coachTip).isNull()
        assertThat(snapshot(openingState(2), 1458).coachTip).isNull()
        assertThat(snapshot(openingState(3), 1458).coachTip?.subtitle).isEqualTo("3 reps in reserve on set 3")
        // 4 stands for "4 or more".
        assertThat(snapshot(openingState(4), 1458).coachTip?.subtitle).isEqualTo("4+ reps in reserve on set 3")
    }

    @Test
    fun testCoachTipOnlyWhileResting() {
        val state = PresFix.goldenState()
        assertThat(snapshot(state, 1458).coachTip).isNotNull()
        // The rest is over (it ended at 1553), skipped, or switched off.
        assertThat(snapshot(state, 1600).phase).isEqualTo(SnapshotPhase.REST_OVER)
        assertThat(snapshot(state, 1600).coachTip).isNull()
        assertThat(snapshot(PresFix.reduced(state, WorkoutAction.SkipRest, 1410), 1458).coachTip).isNull()
        // A paused workout keeps its frozen rest, and with it the tip.
        val paused = PresFix.reduced(state, WorkoutAction.Pause, 1423)
        assertThat(snapshot(paused, 3000).phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snapshot(paused, 3000).coachTip).isNotNull()
    }

    @Test
    fun testCoachTipIgnoresWarmUpsAndPendingWarmUps() {
        // A warm-up with RIR 3 is no reason to add weight.
        var state = PresFix.reduced(PresFix.freshUpperA(), WorkoutAction.LogNextSet, 10)
        state = PresFix.reduced(state, WorkoutAction.ToggleLastSetRIR(3), 11)
        assertThat(snapshot(state, 12).phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snapshot(state, 12).coachTip).isNull()

        // The suggestion is for the next working set, whatever warm-up lies in between.
        val mixed = PresFix.single(PresFix.lib("bench"), sets(normal(80.0, 5), Triple(SetType.WARMUP, 40.0, 5), normal(82.5, 5)))
        var played = PresFix.reduced(mixed, WorkoutAction.LogNextSet, 10)
        played = PresFix.reduced(played, WorkoutAction.ToggleLastSetRIR(3), 11)
        assertThat(snapshot(played, 12).coachTip?.text).isEqualTo("Try 85 kg on set 3.")
        assertThat(snapshot(played, 12).coachTip?.keepWeightText).isEqualTo("Keep 82.5")

        // Only a warm-up is left: nothing to suggest.
        val onlyWarmUp = PresFix.single(PresFix.lib("bench"), sets(normal(80.0, 5), Triple(SetType.WARMUP, 40.0, 5)))
        var last = PresFix.reduced(onlyWarmUp, WorkoutAction.LogNextSet, 10)
        last = PresFix.reduced(last, WorkoutAction.ToggleLastSetRIR(3), 11)
        assertThat(snapshot(last, 12).coachTip).isNull()
    }

    @Test
    fun testCoachTipNeedsAPendingSetOfTheSameExercise() {
        val single = PresFix.single(PresFix.lib("bench"), sets(normal(80.0, 5), normal(80.0, 5)))
        var played = logging(single, 2)
        played = PresFix.reduced(played, WorkoutAction.ToggleLastSetRIR(3), 12)
        assertThat(snapshot(played, 13).phase).isEqualTo(SnapshotPhase.COMPLETE)
        assertThat(snapshot(played, 13).coachTip).isNull()

        // The next set has no weight yet: no sensible suggestion.
        val unweighted = PresFix.single(PresFix.lib("bench"), sets(normal(80.0, 5), normal(0.0, 5)))
        var afterOne = PresFix.reduced(unweighted, WorkoutAction.LogNextSet, 10)
        afterOne = PresFix.reduced(afterOne, WorkoutAction.ToggleLastSetRIR(3), 11)
        assertThat(snapshot(afterOne, 12).coachTip).isNull()
    }

    @Test
    fun testCoachTipOnlyForWeightExercises() {
        for (id in listOf("pushup", "plank")) {
            val exercise = PresFix.lib(id)
            val spec = normal(0.0, if (exercise.tracking == TrackingKind.DURATION) 45 else 12)
            var state = PresFix.reduced(PresFix.single(exercise, sets(spec, spec)), WorkoutAction.LogNextSet, 10)
            state = PresFix.reduced(state, WorkoutAction.ToggleLastSetRIR(4), 11)
            assertWithMessage(id).that(snapshot(state, 12).phase).isEqualTo(SnapshotPhase.RESTING)
            assertWithMessage(id).that(snapshot(state, 12).coachTip).isNull()
        }
    }

    @Test
    fun testCoachTipStepFollowsTheEquipment() {
        // Dumbbells go up by 2 kg, cables by 2.5 kg.
        for ((id, kilograms, expected) in listOf(Triple("incline", 28.0, "30 kg"), Triple("crossover", 15.0, "17.5 kg"))) {
            var state = PresFix.reduced(PresFix.single(PresFix.lib(id), sets(normal(kilograms, 10), normal(kilograms, 10))), WorkoutAction.LogNextSet, 10)
            state = PresFix.reduced(state, WorkoutAction.ToggleLastSetRIR(3), 11)
            assertWithMessage(id).that(snapshot(state, 12).coachTip?.suggestedWeightText).isEqualTo(expected)
        }
        // The sum is rounded to 0.01 kg.
        var state = PresFix.reduced(bench(0.0, normal(20.1, 5), normal(20.1, 5)), WorkoutAction.LogNextSet, 10)
        state = PresFix.reduced(state, WorkoutAction.ToggleLastSetRIR(3), 11)
        assertThat(snapshot(state, 12).coachTip?.suggestedWeightKg).isEqualTo(22.6)
    }

    @Test
    fun testCoachTipIsDroppedWhenTheLoggedSetIsUndoneOrGone() {
        val state = PresFix.goldenState()
        val reference = state.lastLogged!!
        val undone = PresFix.reduced(state, WorkoutAction.ToggleSet(reference.exerciseID, reference.setID), 1405)
        assertThat(snapshot(undone, 1458).coachTip).isNull()

        val stale = state.copy(lastLogged = SetRef(UUID.randomUUID(), UUID.randomUUID()))
        assertThat(snapshot(stale, 1458).coachTip).isNull()
        assertThat(snapshot(stale.copy(lastLogged = null), 1458).coachTip).isNull()
    }

    @Test
    fun testCoachTipOfASupersetNamesTheMemberJustLogged() {
        // Logging the second member starts the rest; the Log button then targets the first member again, but the suggestion is for the
        // second member's own next set.
        var state = logging(pair(), 2)
        state = PresFix.reduced(state, WorkoutAction.ToggleLastSetRIR(3), 12)
        val snap = snapshot(state, 13)
        val pushdown = state.exercises[1]
        val tip = snap.coachTip!!
        assertThat(snap.targetExerciseID).isEqualTo(state.exercises[0].id)
        assertThat(tip.targetExerciseID).isEqualTo(pushdown.id.toString())
        assertThat(tip.targetSetID).isEqualTo(pushdown.sets[1].id.toString())
        assertThat(tip.text).isEqualTo("Try 35 kg on set 2.")
        assertThat(tip.keepWeightText).isEqualTo("Keep 32.5")
        assertThat(tip.subtitle).isEqualTo("3 reps in reserve on set 1")
    }

    // endregion

    // region Record moment

    private val now: Instant = PresFix.at(100)

    /** 85 kg x 5 beats a previous best of 90 (estimate 99.17), 90 kg x 5 makes 105, 87.5 kg x 5 makes 102.08. */
    private val records: WorkoutState get() = bench(90.0, normal(85.0, 5), normal(90.0, 5), normal(87.5, 5))

    @Test
    fun testRecordMomentForTheSetThatBeatsTheBest() {
        val before = records
        val after = logging(before, 1)
        val moment = SnapshotBuilder.prMoment(before, after, now)
        assertThat(moment).isEqualTo(
            PRMoment(
                exerciseName = "Barbell bench press",
                weightText = "85",
                repsText = "5",
                estimated1RM = 99,
                deltaKg = 9,
                expiresAt = now.plusSeconds(4),
            ),
        )
    }

    @Test
    fun testASecondRecordReportsItsGainOverTheFirst() {
        val first = logging(records, 1)
        val second = logging(records, 2)
        val moment = SnapshotBuilder.prMoment(first, second, now)!!
        assertThat(moment.weightText).isEqualTo("90")
        assertThat(moment.estimated1RM).isEqualTo(105)
        assertThat(moment.deltaKg).isEqualTo(6)
        // The third set (102.08) is no record.
        assertThat(SnapshotBuilder.prMoment(second, logging(records, 3), now)).isNull()
    }

    @Test
    fun testNoRecordMomentWithoutAPreviousBest() {
        val before = bench(0.0, normal(85.0, 5))
        assertThat(SnapshotBuilder.prMoment(before, logging(before, 1), now)).isNull()
    }

    @Test
    fun testRecordMomentNeedsMoreThanTheMargin() {
        // 85 kg x 5 is worth 99.1667: a best of 99.12 is not beaten by more than 0.05, a best of 99.11 is.
        val close = bench(99.12, normal(85.0, 5))
        assertThat(SnapshotBuilder.prMoment(close, logging(close, 1), now)).isNull()
        val beaten = bench(99.11, normal(85.0, 5))
        val moment = SnapshotBuilder.prMoment(beaten, logging(beaten, 1), now)!!
        // Both estimates read 99 kg; a record never reads "+0 kg".
        assertThat(moment.estimated1RM).isEqualTo(99)
        assertThat(moment.deltaKg).isEqualTo(1)
    }

    @Test
    fun testWarmUpsAndNonWeightExercisesAreNeverRecords() {
        val warmUp = bench(90.0, Triple(SetType.WARMUP, 200.0, 5))
        assertThat(SnapshotBuilder.prMoment(warmUp, logging(warmUp, 1), now)).isNull()

        val pushUps = PresFix.single(PresFix.lib("pushup", 50.0), sets(normal(0.0, 30)))
        assertThat(SnapshotBuilder.prMoment(pushUps, logging(pushUps, 1), now)).isNull()
    }

    @Test
    fun testRecordMomentOnlyForTheChangeThatLoggedIt() {
        val before = records
        val after = logging(before, 1)
        // Nothing changed, or something else did: the record was already there.
        assertThat(SnapshotBuilder.prMoment(after, after, now)).isNull()
        assertThat(SnapshotBuilder.prMoment(before, before, now)).isNull()
        assertThat(SnapshotBuilder.prMoment(after, PresFix.reduced(after, WorkoutAction.UpdateHeartRate(150), 20), now)).isNull()
        assertThat(SnapshotBuilder.prMoment(after, PresFix.reduced(after, WorkoutAction.Pause, 20), now)).isNull()
        // Going back (the record is undone) is no record either, but logging it again is.
        val set = after.exercises[0].sets[0]
        val undone = PresFix.reduced(after, WorkoutAction.ToggleSet(after.exercises[0].id, set.id), 20)
        assertThat(SnapshotBuilder.prMoment(after, undone, now)).isNull()
        assertThat(SnapshotBuilder.prMoment(undone, after, now)).isNotNull()
    }

    @Test
    fun testEditingALoggedSetIntoARecordIsAMoment() {
        // 80 kg x 5 (93.3) is below a best of 95; raising the logged set to 85 kg makes it a record.
        val before = logging(bench(95.0, normal(80.0, 5)), 1)
        assertThat(SnapshotBuilder.prMoment(before, before, now)).isNull()
        val entry = before.exercises[0]
        val edited = PresFix.reduced(before, WorkoutAction.SetWeight(entry.id, entry.sets[0].id, 85.0), 20)
        val moment = SnapshotBuilder.prMoment(before, edited, now)!!
        assertThat(moment.weightText).isEqualTo("85")
    }

    @Test
    fun testTheBestOfSeveralNewRecordsIsReported() {
        // All three sets become logged at once: the 90 kg x 5 set has the highest estimate, measured against the running best.
        val before = records
        val after = PresFix.marking(before, 0, listOf(0, 1, 2))
        val moment = SnapshotBuilder.prMoment(before, after, now)!!
        assertThat(moment.weightText).isEqualTo("90")
        assertThat(moment.estimated1RM).isEqualTo(105)
        assertThat(moment.deltaKg).isEqualTo(6)
    }

    @Test
    fun testRecordMomentNamesTheExerciseThatGotTheRecord() {
        val entries = listOf(
            PresFix.entry(1, PresFix.lib("bench", 90.0), sets(normal(85.0, 5))),
            PresFix.entry(2, PresFix.lib("squat", 150.0), sets(normal(140.0, 5))),
        )
        val start = PresFix.workout(entries)
        val afterBench = logging(start, 1)
        val afterSquat = logging(start, 2)
        assertThat(SnapshotBuilder.prMoment(start, afterBench, now)!!.exerciseName).isEqualTo("Barbell bench press")
        val squat = SnapshotBuilder.prMoment(afterBench, afterSquat, now)!!
        assertThat(squat.exerciseName).isEqualTo("Back squat")
        assertThat(squat.weightText).isEqualTo("140")
        assertThat(squat.estimated1RM).isEqualTo(163)
        assertThat(squat.deltaKg).isEqualTo(13)
    }

    @Test
    fun testRecordMomentOfAnotherWorkoutIsNotShown() {
        val before = records
        val other = logging(before, 1).copy(id = UUID.randomUUID())
        assertThat(SnapshotBuilder.prMoment(before, other, now)).isNull()
    }

    @Test
    fun testRecordMomentLifetime() {
        val before = records
        val after = logging(before, 1)
        fun expiry(lifetime: Double): Instant = SnapshotBuilder.prMoment(before, after, now, lifetime)!!.expiresAt
        assertThat(SnapshotBuilder.prMoment(before, after, now)!!.expiresAt).isEqualTo(now.plusSeconds(4))
        assertThat(SnapshotBuilder.defaultMomentLifetime).isEqualTo(4.0)
        assertThat(expiry(10.0)).isEqualTo(now.plusSeconds(10))
        assertThat(expiry(0.0)).isEqualTo(now)
        assertThat(expiry(-3.0)).isEqualTo(now)
        assertThat(expiry(Double.NaN)).isEqualTo(now.plusSeconds(4))
        assertThat(expiry(Double.POSITIVE_INFINITY)).isEqualTo(now.plusSeconds(4))
    }

    // endregion

    // region Finish card

    private fun finished(seconds: Int = 2_730, volume: Double = 9_120.0, sets: Int = 21, records: Int = 2, name: String = "Upper A · Push"): CompletedWorkout {
        val marks = (0 until records).map {
            PersonalRecord(exerciseID = "bench$it", exerciseName = "Bench", weightKg = 85.0, reps = 5, estimated1RM = 99.0, previousBest = 95.0)
        }
        return WidFix.workout(1, name, at = WidFix.now, durationSeconds = seconds, volumeKg = volume, records = marks).copy(loggedSets = sets)
    }

    @Test
    fun testFinishBriefCarriesTheNumbersOfTheWorkout() {
        assertThat(SnapshotBuilder.finishBrief(finished(), savedToHealth = true)).isEqualTo(
            FinishBrief(workoutName = "Upper A · Push", durationMinutes = 46, sets = 21, volumeText = "9.1", personalRecordCount = 2, savedToHealth = true),
        )
        assertThat(SnapshotBuilder.finishBrief(finished(), savedToHealth = false).savedToHealth).isFalse()
    }

    @Test
    fun testFinishBriefRoundsTheDurationToMinutes() {
        val table = listOf(0 to 0, 29 to 0, 30 to 1, 89 to 1, 90 to 2, 2_729 to 45, 2_730 to 46, -5 to 0)
        for ((seconds, minutes) in table) {
            assertWithMessage("$seconds s").that(SnapshotBuilder.finishBrief(finished(seconds = seconds), savedToHealth = false).durationMinutes).isEqualTo(minutes)
        }
        assertThat(SnapshotBuilder.finishBrief(finished(seconds = Int.MAX_VALUE), savedToHealth = false).durationMinutes).isGreaterThan(0)
    }

    @Test
    fun testFinishBriefShowsTheVolumeInTonnes() {
        val table = listOf(
            9_120.0 to "9.1", 9_000.0 to "9", 9_049.0 to "9", 9_050.0 to "9.1", 49.0 to "0", 50.0 to "0.1", 0.0 to "0", 123_456.0 to "123.5",
            -100.0 to "0", Double.NaN to "0", Double.POSITIVE_INFINITY to "0",
        )
        for ((kilograms, text) in table) {
            assertWithMessage("$kilograms kg").that(SnapshotBuilder.finishBrief(finished(volume = kilograms), savedToHealth = false).volumeText).isEqualTo(text)
        }
    }

    @Test
    fun testFinishBriefCountsSetsAndRecords() {
        val brief = SnapshotBuilder.finishBrief(finished(sets = 0, records = 0), savedToHealth = false)
        assertThat(brief.sets).isEqualTo(0)
        assertThat(brief.personalRecordCount).isEqualTo(0)
        assertThat(SnapshotBuilder.finishBrief(finished(sets = -4, records = 3), savedToHealth = false).sets).isEqualTo(0)
        assertThat(SnapshotBuilder.finishBrief(finished(records = 3), savedToHealth = false).personalRecordCount).isEqualTo(3)
    }

    @Test
    fun testFinishBriefOfARealSummary() {
        // The summary of a workout played through the reducer: the numbers of the brief are those of the saved workout.
        val state = PresFix.loggedEverything(PresFix.freshUpperA(), start = 10.0)
        val completed = SummaryBuilder.build(state, PresFix.at(3_000))
        val brief = SnapshotBuilder.finishBrief(completed, savedToHealth = true)
        assertThat(brief.workoutName).isEqualTo(state.name)
        assertThat(brief.sets).isEqualTo(completed.loggedSets)
        assertThat(brief.durationMinutes).isEqualTo((completed.durationSeconds + 30) / 60)
        assertThat(brief.personalRecordCount).isEqualTo(completed.personalRecords.size)
    }

    // endregion

    // region Fuzz

    /** The relations between the live context and the state, whatever happened to the workout. */
    private fun checkLiveContext(snap: WorkoutSnapshot, state: WorkoutState, context: String) {
        assertWithMessage(context).that(snap.moment).isNull()
        assertWithMessage(context).that(snap.finish).isNull()
        if (state.exercises.isEmpty()) {
            assertWithMessage(context).that(snap.exerciseDoneSets).isNull()
            assertWithMessage(context).that(snap.exerciseSetCount).isNull()
            assertWithMessage(context).that(snap.superset).isNull()
            assertWithMessage(context).that(snap.plates).isNull()
            assertWithMessage(context).that(snap.coachTip).isNull()
            return
        }
        val target = WorkoutTargets.nextPending(state)
        val shown = state.exercises[target?.exerciseIndex ?: state.clampedIndex]
        assertWithMessage(context).that(snap.exerciseSetCount).isEqualTo(shown.sets.size)
        assertWithMessage(context).that(snap.exerciseDoneSets).isEqualTo(shown.doneCount)

        val group = shown.supersetGroup?.takeIf { it.isNotEmpty() }
        val members = if (group == null) emptyList() else state.exercises.filter { it.supersetGroup == group }
        val brief = snap.superset
        if (group != null && members.size >= 2) {
            assertWithMessage("missing superset: $context").that(brief).isNotNull()
            brief!!
            assertWithMessage(context).that(brief.label).isEqualTo(group)
            assertWithMessage(context).that(brief.members.map { it.name }).isEqualTo(members.map { it.exercise.name })
            assertWithMessage(context).that(brief.members.map { it.tag }).isEqualTo((1..members.size).map { group + it })
            assertWithMessage(context).that(brief.rounds).isAtLeast(1)
            assertWithMessage(context).that(brief.round).isIn(1..maxOf(1, brief.rounds))
            assertWithMessage(context).that(brief.members.count { it.isCurrent }).isEqualTo(1)
            assertWithMessage(context).that(brief.members.first { it.isCurrent }.name).isEqualTo(shown.exercise.name)
        } else {
            assertWithMessage(context).that(brief).isNull()
        }

        snap.plates?.let { plates ->
            assertWithMessage("plates without a target: $context").that(target).isNotNull()
            val entry = state.exercises[target!!.exerciseIndex]
            assertWithMessage(context).that(entry.exercise.supportsPlates).isTrue()
            assertWithMessage(context).that(plates.totalKg).isEqualTo(entry.sets[target.setIndex].weightKg)
            assertWithMessage(context).that(plates.perSide).isNotEmpty()
            assertWithMessage(context).that(plates.perSide).isEqualTo(plates.perSide.sortedDescending())
            assertWithMessage(context).that(plates.barKg + 2 * (plates.perSide.sum() + plates.leftoverKg)).isWithin(0.05).of(plates.totalKg)
        }

        snap.coachTip?.let { tip ->
            assertWithMessage(context).that(snap.phase).isEqualTo(SnapshotPhase.RESTING)
            assertWithMessage(context).that(state.lastLogged?.exerciseID?.toString()).isEqualTo(tip.targetExerciseID)
            val set = state.exercises.firstOrNull { it.id.toString() == tip.targetExerciseID }?.sets?.firstOrNull { it.id.toString() == tip.targetSetID }
            assertWithMessage(context).that(set).isNotNull()
            assertWithMessage(context).that(set!!.isDone).isFalse()
            assertWithMessage(context).that(set.type).isNotEqualTo(SetType.WARMUP)
            assertWithMessage(context).that(tip.suggestedWeightKg).isGreaterThan(set.weightKg)
        }
    }

    @Test
    fun testTheLiveContextHoldsUnderRandomPlay() {
        // A previous best on every exercise so that random sets often are records.
        val template = PresFix.upperA().let { upper ->
            upper.copy(entries = upper.entries.map { it.copy(exercise = it.exercise.copy(previousBestE1RM = 40.0)) })
        }
        for (seed in 1..12) {
            val rng = PresLCG(seed.toLong() + 4_200)
            var state = if (seed % 4 == 0) WorkoutFactory.makeEmpty("Fuzz", PresFix.t0) else WorkoutFactory.makeWorkout(template, PresFix.t0)
            var previous = state
            var clock = 0.0
            for (step in 0 until 150) {
                clock += rng.below(30) / 2.0
                val exercise = if (state.exercises.isEmpty()) null else state.exercises[rng.below(state.exercises.size)]
                val set = exercise?.let { if (it.sets.isEmpty()) null else it.sets[rng.below(it.sets.size)] }
                val action: WorkoutAction = when (rng.below(14)) {
                    0, 1, 2 -> WorkoutAction.LogNextSet
                    3 -> if (exercise != null && set != null) WorkoutAction.ToggleSet(exercise.id, set.id) else WorkoutAction.SkipRest
                    4 -> WorkoutAction.Pause
                    5 -> WorkoutAction.Resume
                    6 -> WorkoutAction.AdjustRest(if (rng.below(2) == 0) 15 else -15)
                    7 -> WorkoutAction.GoTo(rng.below(6))
                    8 -> WorkoutAction.NudgeNextSet(rng.below(5) - 2, rng.below(5) - 2)
                    9 -> WorkoutAction.SkipRest
                    10 -> WorkoutAction.AddExercises(listOf(PresFix.lib(listOf("bench", "plank", "squat", "lateral")[rng.below(4)])))
                    11 -> WorkoutAction.ToggleLastSetRIR(rng.below(5))
                    12 -> if (exercise != null) WorkoutAction.ToggleSuperset(exercise.id) else WorkoutAction.SkipRest
                    else -> if (exercise != null && set != null) WorkoutAction.SetWeight(exercise.id, set.id, rng.below(300) / 2.0) else WorkoutAction.SkipRest
                }
                state = WorkoutReducer.reduce(state, action, PresFix.at(clock))

                val at = PresFix.at(clock + rng.below(300) / 2.0)
                val context = "seed $seed step $step $action"
                checkLiveContext(SnapshotBuilder.make(state, at), state, context)

                SnapshotBuilder.prMoment(previous, state, at)?.let { moment ->
                    assertWithMessage(context).that(state.exercises.any { it.exercise.name == moment.exerciseName }).isTrue()
                    assertWithMessage(context).that(moment.estimated1RM).isGreaterThan(0)
                    assertWithMessage(context).that(moment.deltaKg).isAtLeast(1)
                    assertWithMessage(context).that(moment.expiresAt).isEqualTo(at.plusSeconds(4))
                }
                previous = state
            }
        }
    }

    // endregion
}
