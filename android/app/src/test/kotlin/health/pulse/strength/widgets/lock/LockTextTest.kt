package health.pulse.strength.widgets.lock

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.widgets.WidgetFixtures
import org.junit.Test

/** Which text the lock screen and glanceable hub widgets (LS-01 ... LS-11) show for which snapshot. */
class LockTextTest {
    private val preview = WidgetFixtures.preview
    private val empty = WidgetFixtures.empty()

    // LS-01

    @Test
    fun theGaugeShowsCompletedOverGoal() {
        val gauge = LockText.weeklyGoal(preview.week)
        assertThat(gauge.label).isEqualTo("3/4")
        assertThat(gauge.fraction).isEqualTo(0.75f)
        assertThat(gauge.description).isEqualTo("3 of 4 workouts this week")
    }

    @Test
    fun theGaugeFillsUpAtTheGoalAndNeverOverflows() {
        assertThat(LockText.weeklyGoal(preview.week.copy(completed = 4)).fraction).isEqualTo(1f)
        val exceeded = LockText.weeklyGoal(preview.week.copy(completed = 5))
        assertThat(exceeded.fraction).isEqualTo(1f)
        assertThat(exceeded.label).isEqualTo("5/4")
    }

    @Test
    fun theGaugeSurvivesAGoalOfZeroAndSpeaksOfASingleWorkout() {
        assertThat(LockText.weeklyGoal(preview.week.copy(goal = 0, completed = 0)).fraction).isEqualTo(0f)
        assertThat(LockText.weeklyGoal(preview.week.copy(goal = 1, completed = 0)).description).isEqualTo("0 of 1 workout this week")
    }

    // LS-02

    @Test
    fun daysSinceCountsTheDaysOrSaysThereIsNoHistory() {
        val days = LockText.daysSince(preview.week)
        assertThat(days.value).isEqualTo("3d")
        assertThat(days.description).isEqualTo("3 days since your last workout")
        val none = LockText.daysSince(empty.week)
        assertThat(none.value).isEqualTo("–")
        assertThat(none.description).isEqualTo("No workouts logged yet")
        assertThat(LockText.daysSince(preview.week.copy(daysSinceLastWorkout = 0)).description).isEqualTo("You trained today")
        assertThat(LockText.daysSince(preview.week.copy(daysSinceLastWorkout = 1)).description).isEqualTo("1 day since your last workout")
    }

    // LS-03

    @Test
    fun theStreakIsInWeeksAndTheFlameDimsAtZero() {
        val streak = LockText.streak(preview.week)
        assertThat(streak.label).isEqualTo("6 wk")
        assertThat(streak.isActive).isTrue()
        assertThat(streak.description).isEqualTo("6-week streak")
        val none = LockText.streak(empty.week)
        assertThat(none.label).isEqualTo("0 wk")
        assertThat(none.isActive).isFalse()
        assertThat(none.description).isEqualTo("No week streak yet")
    }

    // LS-04

    @Test
    fun quickStartStartsTheNextWorkoutOpensTheRunningOneOrTheHub() {
        assertThat(LockText.quickStart(preview)).isEqualTo(QuickStartModel(DeepLinks.startNext, "Start Upper A · Push"))
        val running = preview.copy(active = WidgetFixtures.active())
        assertThat(LockText.quickStart(running)).isEqualTo(QuickStartModel(DeepLinks.workout, "Open the running workout"))
        assertThat(LockText.quickStart(empty).link).isEqualTo(DeepLinks.hub)
    }

    // LS-05

    @Test
    fun nextUpNamesTheTemplateAndWhatItHolds() {
        val card = LockText.nextUp(preview)
        assertThat(card.eyebrow).isEqualTo("Next up")
        assertThat(card.title).isEqualTo("Upper A · Push")
        assertThat(card.detail).isEqualTo("6 exercises · ~55 min")
        assertThat(card.link).isEqualTo(DeepLinks.startNext)
    }

    @Test
    fun nextUpLeavesOutAnUnknownDuration() {
        val next = preview.nextUp!!.copy(estimatedMinutes = 0, exerciseCount = 1)
        assertThat(LockText.nextUp(preview.copy(nextUp = next)).detail).isEqualTo("1 exercise")
    }

    @Test
    fun nextUpShowsTheRunningWorkoutWhileOneRuns() {
        val card = LockText.nextUp(preview.copy(active = WidgetFixtures.active()))
        assertThat(card.eyebrow).isEqualTo("In progress")
        assertThat(card.title).isEqualTo("Upper A · Push")
        assertThat(card.detail).isEqualTo("6 of 20 sets")
        assertThat(card.link).isEqualTo(DeepLinks.workout)
    }

    @Test
    fun nextUpWithoutTemplatesInvitesToCreateOne() {
        val card = LockText.nextUp(empty)
        assertThat(card.title).isEqualTo("No workout planned")
        assertThat(card.link).isEqualTo(DeepLinks.hub)
    }

    // LS-06

    @Test
    fun weeklySetsShowTheMeterAndTheLaggingMuscle() {
        val card = LockText.weeklySets(preview.weeklySets)
        assertThat(card.title).isEqualTo("Sets this week")
        assertThat(card.value).isEqualTo("37")
        assertThat(card.fraction).isWithin(0.0001f).of(37f / 48f)
        assertThat(card.detail).isEqualTo("11 to go · legs lagging")
    }

    @Test
    fun weeklySetsDropTheLaggingMuscleWhenAllReachTheirShare() {
        val summary = preview.weeklySets.copy(laggingMuscle = null)
        assertThat(LockText.weeklySets(summary).detail).isEqualTo("11 to go")
    }

    @Test
    fun weeklySetsSayWhenTheTargetIsReached() {
        val summary = preview.weeklySets.copy(totalSets = 52, setsToGo = 0, laggingMuscle = null)
        val card = LockText.weeklySets(summary)
        assertThat(card.detail).isEqualTo("Target reached")
        assertThat(card.fraction).isEqualTo(1f)
    }

    @Test
    fun weeklySetsBeforeTheFirstSetNameNoLaggingMuscle() {
        val card = LockText.weeklySets(empty.weeklySets)
        assertThat(card.value).isEqualTo("0")
        assertThat(card.fraction).isEqualTo(0f)
        assertThat(card.detail).isEqualTo("48 to go")
    }

    // LS-07

    @Test
    fun theLatestRecordShowsTheSetAndTheEstimatedMax() {
        val card = LockText.latestRecord(preview.latestPR)
        assertThat(card.eyebrow).isEqualTo("New PR")
        assertThat(card.title).isEqualTo("Bench Press")
        assertThat(card.titleSuffix).isEqualTo("85 × 5")
        assertThat(card.detail).isEqualTo("e1RM 99 kg · +4 kg")
        assertThat(card.link).isEqualTo(DeepLinks.exercise("bench"))
        assertThat(card.isHighlighted).isTrue()
    }

    @Test
    fun anOlderRecordIsLabelledLatestAndNotHighlighted() {
        val card = LockText.latestRecord(preview.latestPR!!.copy(isFresh = false, deltaKg = 0.0))
        assertThat(card.eyebrow).isEqualTo("Latest PR")
        assertThat(card.detail).isEqualTo("e1RM 99 kg")
        assertThat(card.isHighlighted).isFalse()
    }

    @Test
    fun withoutARecordTheCardSaysSo() {
        val card = LockText.latestRecord(null)
        assertThat(card.title).isEqualTo("No records yet")
        assertThat(card.link).isEqualTo(DeepLinks.hub)
    }

    // LS-08

    @Test
    fun overloadShowsTheTargetSetAndTheStepUp() {
        val card = LockText.overload(preview.overload)
        assertThat(card.eyebrow).isEqualTo("Today's target")
        assertThat(card.title).isEqualTo("Bench Press")
        assertThat(card.titleSuffix).isEqualTo("4 × 6")
        assertThat(card.detail).isEqualTo("82.5 kg · +2.5 vs last")
    }

    @Test
    fun overloadWithTheSameWeightAsksForMoreRepsOrNothing() {
        val sameWeight = preview.overload!!.copy(targetWeightKg = 80.0, deltaKg = 0.0, lastReps = 5, targetReps = 6)
        assertThat(LockText.overload(sameWeight).detail).isEqualTo("80 kg · +1 rep vs last")
        assertThat(LockText.overload(sameWeight.copy(targetReps = 7)).detail).isEqualTo("80 kg · +2 reps vs last")
        assertThat(LockText.overload(sameWeight.copy(lastReps = 6)).detail).isEqualTo("80 kg · same as last")
    }

    @Test
    fun overloadShowsALowerWeightWithARealMinus() {
        val lighter = preview.overload!!.copy(targetWeightKg = 77.5, deltaKg = -2.5)
        assertThat(LockText.overload(lighter).detail).isEqualTo("77.5 kg · −2.5 vs last")
    }

    @Test
    fun overloadWithoutHistoryHasNothingToBeat() {
        val card = LockText.overload(null)
        assertThat(card.title).isEqualTo("Nothing to beat yet")
        assertThat(card.link).isEqualTo(DeepLinks.hub)
    }

    // LS-09 / LS-10 / LS-11

    @Test
    fun theWeekLineCountsWorkoutsAgainstTheGoal() {
        val line = LockText.inlineStatus(InlineStatusWidget.Mode.WEEK, preview)
        assertThat(line.text).isEqualTo("3 of 4 workouts this week")
        assertThat(line.link).isEqualTo(DeepLinks.hub)
        assertThat(line.showsIcon).isTrue()
        val single = LockText.inlineStatus(InlineStatusWidget.Mode.WEEK, preview.copy(week = preview.week.copy(goal = 1, completed = 1)))
        assertThat(single.text).isEqualTo("1 of 1 workout this week")
    }

    @Test
    fun theSplitLineNamesTheSplitAndWhenItWasLastTrained() {
        val line = LockText.inlineStatus(InlineStatusWidget.Mode.SPLIT, preview)
        assertThat(line.text).isEqualTo("Push day · last 5 days ago")
        assertThat(line.link).isEqualTo(DeepLinks.startNext)
        assertThat(line.showsIcon).isFalse()
    }

    @Test
    fun theSplitLineHandlesEveryAgeOfTheLastSession() {
        fun text(days: Int?) = LockText.splitText(preview.copy(nextUp = preview.nextUp!!.copy(daysSince = days)))
        assertThat(text(0)).isEqualTo("Push day · last today")
        assertThat(text(1)).isEqualTo("Push day · last yesterday")
        assertThat(text(null)).isEqualTo("Push day · not done yet")
    }

    @Test
    fun theSplitLineOpensTheRunningWorkoutAndHandlesNoTemplates() {
        val running = LockText.inlineStatus(InlineStatusWidget.Mode.SPLIT, preview.copy(active = WidgetFixtures.active()))
        assertThat(running.link).isEqualTo(DeepLinks.workout)
        val none = LockText.inlineStatus(InlineStatusWidget.Mode.SPLIT, empty)
        assertThat(none.text).isEqualTo("No workout planned")
        assertThat(none.link).isEqualTo(DeepLinks.hub)
    }

    @Test
    fun theRestLineSaysWhenTrainingResumes() {
        val line = LockText.inlineStatus(InlineStatusWidget.Mode.REST, preview)
        assertThat(line.text).isEqualTo("Rest day · back on Sun")
        assertThat(line.link).isEqualTo(DeepLinks.hub)
    }

    @Test
    fun theRestLineWithoutTomorrowOrWithABlankWeekdayIsJustTheReason() {
        assertThat(LockText.restText(preview.copy(tomorrow = null))).isEqualTo("Rest day")
        assertThat(LockText.restText(preview.copy(tomorrow = preview.tomorrow!!.copy(weekday = "  ")))).isEqualTo("Rest day")
        assertThat(LockText.restText(preview.copy(restDay = preview.restDay!!.copy(reason = "")))).isEqualTo("Rest day · back on Sun")
    }

    @Test
    fun theRestLineFallsBackToTheSplitLineOnATrainingDay() {
        val trainingDay = preview.copy(restDay = null)
        assertThat(LockText.restText(trainingDay)).isNull()
        val line = LockText.inlineStatus(InlineStatusWidget.Mode.REST, trainingDay)
        assertThat(line.text).isEqualTo("Push day · last 5 days ago")
        assertThat(line.link).isEqualTo(DeepLinks.startNext)
    }

    @Test
    fun everyInlineModeHasItsOwnReceiver() {
        val receivers = InlineStatusWidget.Mode.entries.map { it.receiver }
        assertThat(receivers).containsNoDuplicates()
        assertThat(receivers.map { it.simpleName }).containsExactly(
            "InlineStatusWeekReceiver",
            "InlineStatusSplitReceiver",
            "InlineStatusRestReceiver",
        ).inOrder()
    }

    @Test
    fun theLaggingMuscleIsNamedInLowerCase() {
        val summary = preview.weeklySets.copy(laggingMuscle = MuscleGroup.SHOULDERS)
        assertThat(LockText.weeklySets(summary).detail).isEqualTo("11 to go · shoulders lagging")
    }

    @Test
    fun aRunningWorkoutInEveryPhaseKeepsTheNextUpCardOnTheWorkout() {
        for (phase in SnapshotPhase.entries) {
            val card = LockText.nextUp(preview.copy(active = WidgetFixtures.active(phase)))
            assertThat(card.link).isEqualTo(DeepLinks.workout)
        }
    }
}
