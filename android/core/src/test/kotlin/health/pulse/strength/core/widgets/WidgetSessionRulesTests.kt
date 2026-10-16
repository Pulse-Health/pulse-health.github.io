package health.pulse.strength.core.widgets

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.HeartRateSample
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.addingTimeInterval
import org.junit.Test

/** widgets/SPEC.md section 2: lastSession (with its heart-rate bars and its timeline) and latestPR. */
class WidgetLastSessionRuleTests {
    private fun session(history: List<CompletedWorkout>): SessionSummary? = WidFix.snapshot(history = history).lastSession

    @Test
    fun testLastSessionIsTheWorkoutWithTheGreatestFinishedAtWhateverTheOrder() {
        val older = WidFix.workout(1, "Lower A · Quads", at = WidFix.date(2026, 10, 9, 18, 0))
        val newer = WidFix.workout(2, "Upper B · Pull", at = WidFix.date(2026, 10, 13, 9, 0))
        assertThat(session(listOf(older, newer))?.workoutID).isEqualTo(newer.id.toString())
        assertThat(session(listOf(newer, older))?.workoutID).isEqualTo(newer.id.toString())
        assertThat(session(emptyList())).isNull()
    }

    @Test
    fun testLastSessionTakesTheFirstWorkoutOfTheHistoryOnATie() {
        val at = WidFix.date(2026, 10, 13, 9, 0)
        assertThat(session(listOf(WidFix.workout(1, at = at), WidFix.workout(2, at = at)))?.workoutID).isEqualTo(WidFix.uuid(1).toString())
    }

    @Test
    fun testLastSessionCopiesTheWorkout() {
        val workout = WidFix.workout(
            1, "Upper B · Pull", at = WidFix.date(2026, 10, 13, 9, 0), durationSeconds = 3_125, volumeKg = 6_245.5,
            exercises = listOf(WidFix.lift("brow", listOf(WidFix.set(60.0, 8), WidFix.set(60.0, 8)), n = 1), WidFix.lift("curl", listOf(WidFix.set(30.0, 10)), n = 2)),
            records = listOf(PersonalRecord(exerciseID = "brow", exerciseName = "Barbell row", weightKg = 60.0, reps = 8, estimated1RM = 76.0, previousBest = 70.0)),
        ).copy(averageHeartRate = 124)
        val result = session(listOf(workout))!!
        assertThat(result.workoutID).isEqualTo(workout.id.toString())
        assertThat(result.name).isEqualTo("Upper B · Pull")
        assertThat(result.finishedAt).isEqualTo(WidFix.date(2026, 10, 13, 9, 0))
        assertThat(result.loggedSets).isEqualTo(3)
        assertThat(result.volumeKg).isEqualTo(6_245.5)
        assertThat(result.averageHeartRate).isEqualTo(124)
        assertThat(result.personalRecordCount).isEqualTo(1)
        assertThat(result.peakHeartRate).isNull()
        assertThat(result.heartRateBars).isEmpty()
        assertThat(result.timeline).isEmpty()
        assertThat(result.underTensionPercent).isNull()
        assertThat(result.longBreakCount).isEqualTo(0)
    }

    @Test
    fun testLastSessionDurationMinutesIsSecondsOver60RoundedHalfUp() {
        fun minutes(seconds: Int): Int? =
            session(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 13, 9, 0), durationSeconds = seconds)))?.durationMinutes
        assertThat(minutes(0)).isEqualTo(0)
        assertThat(minutes(29)).isEqualTo(0)
        assertWithMessage("half a minute rounds up").that(minutes(30)).isEqualTo(1)
        assertThat(minutes(89)).isEqualTo(1)
        assertThat(minutes(90)).isEqualTo(2)
        assertThat(minutes(3_000)).isEqualTo(50)
        assertThat(minutes(3_149)).isEqualTo(52)
        assertThat(minutes(3_150)).isEqualTo(53)
        assertWithMessage("never negative").that(minutes(-45)).isEqualTo(0)
    }

    // region Heart rate

    private fun samples(bpm: List<Int>): List<HeartRateSample> =
        bpm.mapIndexed { index, value -> HeartRateSample(value, WidFix.date(2026, 10, 13, 8, 0).addingTimeInterval(index * 30.0)) }

    private fun curve(bpm: List<Int>): SessionSummary? =
        session(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 13, 9, 0), heartRate = samples(bpm))))

    @Test
    fun testHeartRateBarsNeedAtLeastFourSamples() {
        for (count in 0..3) {
            val result = curve(List(count) { 120 })
            assertWithMessage("$count samples").that(result?.heartRateBars).isEmpty()
            assertWithMessage("$count samples").that(result?.peakHeartRate).isNull()
        }
        val four = curve(listOf(100, 110, 120, 130))
        assertWithMessage("four samples are four buckets of one").that(four?.heartRateBars?.map { it.bpm }).containsExactly(100, 110, 120, 130).inOrder()
        assertThat(four?.peakHeartRate).isEqualTo(130)
    }

    @Test
    fun testHeartRateBarsAreContiguousBucketsOfNearEqualSizeTheEarlierOnesTakingTheRemainder() {
        // 20 samples in 16 buckets: the first four buckets hold two samples, the other twelve one.
        val bpm = (0 until 20).map { 100 + it * 2 }
        val bars = curve(bpm)?.heartRateBars?.map { it.bpm }
        val expected = mutableListOf<Int>()
        var index = 0
        for (bucket in 0 until 16) {
            val size = if (bucket < 4) 2 else 1
            val values = bpm.subList(index, index + size)
            expected.add((2 * values.sum() + size) / (2 * size))
            index += size
        }
        assertThat(bars).isEqualTo(expected)
        assertThat(bars).hasSize(16)
        assertWithMessage("(100 + 102) / 2 and (104 + 106) / 2").that(bars!!.take(2)).containsExactly(101, 105).inOrder()
    }

    @Test
    fun testHeartRateBarsHaveAtMostSixteenBucketsAndFewerSamplesGiveOneBucketEach() {
        assertThat(curve((0 until 16).map { 100 + it })?.heartRateBars).hasSize(16)
        assertWithMessage("17 samples: the first bucket takes two").that(curve((0 until 17).map { 100 + it })?.heartRateBars?.map { it.bpm }?.first()).isEqualTo(101)
        assertThat(curve((0 until 300).map { 100 + it % 40 })?.heartRateBars).hasSize(16)
        assertThat(curve((0 until 7).map { 100 + it })?.heartRateBars).hasSize(7)
    }

    @Test
    fun testAHeartRateBarIsTheRoundedMeanOfItsBucketWithHalvesRoundingUp() {
        // 32 samples make 16 buckets of two: every bucket (100, 101) has the mean 100.5.
        val halves = (0 until 32).map { if (it % 2 == 0) 100 else 101 }
        assertThat(curve(halves)?.heartRateBars?.map { it.bpm }).isEqualTo(List(16) { 101 })
        // 17 samples: the first bucket takes two (100 and 101), the others one.
        val remainder = listOf(100, 101) + List(15) { 100 }
        assertThat(curve(remainder)?.heartRateBars?.map { it.bpm }).isEqualTo(listOf(101) + List(15) { 100 })
        // 48 samples make 16 buckets of three: (100, 100, 101) has the mean 100.33 and (100, 101, 101) the mean 100.67.
        val below = (0 until 48).map { if (it % 3 == 2) 101 else 100 }
        assertThat(curve(below)?.heartRateBars?.map { it.bpm }).isEqualTo(List(16) { 100 })
        val above = (0 until 48).map { if (it % 3 == 0) 100 else 101 }
        assertThat(curve(above)?.heartRateBars?.map { it.bpm }).isEqualTo(List(16) { 101 })
    }

    @Test
    fun testAHeartRateBarIsAnEffortWhenAboveTheRoundedMeanOfAllSamples() {
        // Samples 100, 100, 140, 140: the mean of all is 120; buckets of one sample each.
        assertThat(curve(listOf(100, 100, 140, 140))?.heartRateBars?.map { it.isEffort }).containsExactly(false, false, true, true).inOrder()
        // A bar equal to the rounded mean is not above it.
        assertWithMessage("the mean is 120: only 130 is above it")
            .that(curve(listOf(110, 130, 120, 120))?.heartRateBars?.map { it.isEffort })
            .containsExactly(false, true, false, false)
            .inOrder()
    }

    @Test
    fun testPeakHeartRateIsTheHighestSampleNotTheHighestBar() {
        // 20 samples: the 190 shares a bucket with 100, so the bar is 145 but the peak is 190.
        val bpm = MutableList(20) { 100 }
        bpm[1] = 190
        val result = curve(bpm)
        assertThat(result?.peakHeartRate).isEqualTo(190)
        assertThat(result?.heartRateBars?.first()?.bpm).isEqualTo(145)
    }

    // endregion

    // region Timeline

    private val start = WidFix.date(2026, 10, 13, 8, 0)

    /** The session of a workout that started at `start` and logged one set at each of [seconds] after it. */
    private fun timeline(vararg seconds: Double): SessionSummary? {
        val sets = seconds.map { WidFix.set(60.0, 8, at = start.addingTimeInterval(it)) }
        val exercises = if (sets.isEmpty()) emptyList() else listOf(WidFix.lift("brow", sets, n = 1))
        return session(listOf(WidFix.workout(1, at = start.addingTimeInterval(3_000.0), exercises = exercises, startedAt = start)))
    }

    private fun segment(kind: TimelineKind, seconds: Int) = TimelineSegment(kind, seconds)

    @Test
    fun testTimelineIsLiftingUpToFortyFiveSecondsPerGapAndRestForTheRest() {
        // Sets at +30 s, +90 s, +500 s and +520 s after the start.
        val result = timeline(30.0, 90.0, 500.0, 520.0)
        assertThat(result?.timeline).isEqualTo(
            listOf(
                segment(TimelineKind.LIFTING, 30), // 0 - 30: all lifting
                segment(TimelineKind.REST, 15), // 30 - 90: 60 s gap = 45 lifting + 15 rest, rest first
                segment(TimelineKind.LIFTING, 45),
                segment(TimelineKind.LONG_REST, 365), // 90 - 500: 410 s gap = 45 lifting + 365 rest
                segment(TimelineKind.LIFTING, 65), // 45 + 20, merged
            ),
        )
        assertWithMessage("140 of 520 s is 26.9 %").that(result?.underTensionPercent).isEqualTo(27)
        assertThat(result?.longBreakCount).isEqualTo(1)
    }

    @Test
    fun testTheGapBeforeTheFirstSetIsMeasuredFromTheStartOfTheWorkout() {
        val result = timeline(200.0, 230.0)
        assertThat(result?.timeline).isEqualTo(
            listOf(
                segment(TimelineKind.REST, 155), // 200 s = 45 + 155 (not above 180: a normal rest)
                segment(TimelineKind.LIFTING, 75),
            ),
        )
        assertThat(result?.longBreakCount).isEqualTo(0)
    }

    @Test
    fun testARestIsLongOnlyAboveThreeMinutes() {
        // Gap 225 s = 45 lifting + 180 rest: still a rest. Gap 226 s: 181 s, a long rest.
        assertThat(timeline(225.0, 226.0)?.timeline?.first()).isEqualTo(segment(TimelineKind.REST, 180))
        assertThat(timeline(226.0, 227.0)?.timeline?.first()).isEqualTo(segment(TimelineKind.LONG_REST, 181))
    }

    @Test
    fun testTimelineNeedsTheTimeOfAtLeastTwoSets() {
        assertThat(timeline(60.0)?.timeline).isEmpty()
        assertThat(timeline(60.0)?.underTensionPercent).isNull()
        assertThat(timeline(60.0)?.longBreakCount).isEqualTo(0)
        assertThat(timeline()?.timeline).isEmpty()
        assertThat(timeline(60.0, 120.0)?.timeline).isNotEmpty()
    }

    @Test
    fun testSetsWithoutATimeAreIgnoredAndOlderHistoryHasNoTimeline() {
        val mixed = WidFix.lift(
            "brow",
            listOf(WidFix.set(60.0, 8, at = start.addingTimeInterval(30.0)), WidFix.set(60.0, 8), WidFix.set(60.0, 8, at = start.addingTimeInterval(90.0))),
            n = 1,
        )
        val result = session(listOf(WidFix.workout(1, at = start.addingTimeInterval(3_000.0), exercises = listOf(mixed), startedAt = start)))
        assertWithMessage("two timed sets: the untimed one is not part of the gaps").that(result?.timeline?.sumOf { it.seconds }).isEqualTo(90)
        val untimed = WidFix.lift("brow", listOf(WidFix.set(60.0, 8), WidFix.set(60.0, 8)), n = 2)
        assertThat(session(listOf(WidFix.workout(2, at = start.addingTimeInterval(3_000.0), exercises = listOf(untimed), startedAt = start)))?.timeline).isEmpty()
    }

    @Test
    fun testTheLoggedSetsAreTakenInTimeOrderAcrossExercises() {
        val first = WidFix.lift("brow", listOf(WidFix.set(60.0, 8, at = start.addingTimeInterval(300.0)), WidFix.set(60.0, 8, at = start.addingTimeInterval(40.0))), n = 1)
        val second = WidFix.lift("curl", listOf(WidFix.set(30.0, 10, at = start.addingTimeInterval(100.0))), n = 2)
        val result = session(listOf(WidFix.workout(1, at = start.addingTimeInterval(3_000.0), exercises = listOf(first, second), startedAt = start)))
        // Times 40, 100, 300: gaps 40, 60, 200 -> lifting 40, rest 15 + lifting 45, rest 155 + lifting 45.
        assertThat(result?.timeline).isEqualTo(
            listOf(
                segment(TimelineKind.LIFTING, 40),
                segment(TimelineKind.REST, 15),
                segment(TimelineKind.LIFTING, 45),
                segment(TimelineKind.REST, 155),
                segment(TimelineKind.LIFTING, 45),
            ),
        )
    }

    @Test
    fun testStretchesOfNoTimeAreSkippedAndNeighboursOfTheSameKindMerge() {
        // Gaps of 20, 0 and 30 seconds are all lifting: one stretch of 50 s... and a set logged at the same moment adds nothing.
        assertThat(timeline(20.0, 20.0, 50.0)?.timeline).isEqualTo(listOf(segment(TimelineKind.LIFTING, 50)))
        // A gap of exactly 45 s has no rest; the next gap of 46 s starts with 1 s of rest.
        assertThat(timeline(45.0, 91.0)?.timeline).isEqualTo(
            listOf(segment(TimelineKind.LIFTING, 45), segment(TimelineKind.REST, 1), segment(TimelineKind.LIFTING, 45)),
        )
    }

    @Test
    fun testEveryLongRestIsOneBreak() {
        // Set two is logged at the same moment as set one (a gap of 0); set three follows 500 s later.
        val result = timeline(400.0, 400.0, 900.0)
        assertThat(result?.timeline?.map { it.kind })
            .containsExactly(TimelineKind.LONG_REST, TimelineKind.LIFTING, TimelineKind.LONG_REST, TimelineKind.LIFTING)
            .inOrder()
        assertThat(result?.timeline?.map { it.seconds }).containsExactly(355, 45, 455, 45).inOrder()
        assertThat(result?.longBreakCount).isEqualTo(2)
    }

    @Test
    fun testUnderTensionPercentIsTheShareOfLiftingRoundedHalfUp() {
        // A gap of 360 s is 45 s of lifting and 315 s of rest: 12.5 % rounds up to 13.
        assertThat(timeline(360.0, 360.0)?.underTensionPercent).isEqualTo(13)
        // 320 s: 45 of 320 is 14.06 %, which rounds down.
        assertThat(timeline(320.0, 320.0)?.underTensionPercent).isEqualTo(14)
        // Gaps of 45 s and 315 s: lifting 90 of 360 s.
        assertThat(timeline(45.0, 360.0)?.underTensionPercent).isEqualTo(25)
        // Gaps of 405 s and 45 s: 90 of 450 s.
        assertThat(timeline(405.0, 450.0)?.underTensionPercent).isEqualTo(20)
        // Only lifting: 100 %.
        assertThat(timeline(20.0, 40.0)?.underTensionPercent).isEqualTo(100)
    }

    @Test
    fun testTimesAreTakenInWholeSeconds() {
        // 30.4 s and 89.6 s round to 30 s and 90 s, so the gaps are 30 and 60 whole seconds.
        assertThat(timeline(30.4, 89.6)?.timeline).isEqualTo(
            listOf(segment(TimelineKind.LIFTING, 30), segment(TimelineKind.REST, 15), segment(TimelineKind.LIFTING, 45)),
        )
    }

    @Test
    fun testASetLoggedBeforeTheStartOfTheWorkoutHasAZeroGap() {
        // The first set predates the start (a clock that was set back): its gap is 0, the next one counts from it, 50 s.
        assertThat(timeline(-20.0, 30.0)?.timeline).isEqualTo(listOf(segment(TimelineKind.REST, 5), segment(TimelineKind.LIFTING, 45)))
    }

    // endregion
}

class WidgetLatestPersonalRecordRuleTests {
    private fun record(id: String, e1RM: Double, previousBest: Double = 90.0, weight: Double = 80.0, reps: Int = 5): PersonalRecord =
        PersonalRecord(exerciseID = id, exerciseName = id.replaceFirstChar { it.uppercase() }, weightKg = weight, reps = reps, estimated1RM = e1RM, previousBest = previousBest)

    private fun pr(history: List<CompletedWorkout>): PRSummary? = WidFix.snapshot(history = history).latestPR

    @Test
    fun testLatestPRIsFromTheNewestWorkoutThatSetRecords() {
        val history = listOf(
            WidFix.workout(3, at = WidFix.date(2026, 10, 14, 9, 0)), // newest, no record
            WidFix.workout(2, at = WidFix.date(2026, 10, 10, 9, 0), records = listOf(record("squat", e1RM = 120.0))),
            WidFix.workout(1, at = WidFix.date(2026, 10, 2, 9, 0), records = listOf(record("bench", e1RM = 110.0))),
        )
        val result = pr(history)
        assertThat(result?.exerciseID).isEqualTo("squat")
        assertThat(result?.achievedAt).isEqualTo(WidFix.date(2026, 10, 10, 9, 0))
        assertWithMessage("whatever the order of the history").that(pr(history.reversed())?.exerciseID).isEqualTo("squat")
        assertThat(pr(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 10, 9, 0))))).isNull()
        assertThat(pr(emptyList())).isNull()
    }

    @Test
    fun testLatestPRIsTheRecordWithTheHighestEstimatedOneRepMaxFirstOnATie() {
        val workout = WidFix.workout(
            1, at = WidFix.date(2026, 10, 10, 9, 0),
            records = listOf(record("bench", e1RM = 99.0), record("squat", e1RM = 130.0), record("ohp", e1RM = 130.0), record("curl", e1RM = 40.0)),
        )
        assertThat(pr(listOf(workout))?.exerciseID).isEqualTo("squat")
    }

    @Test
    fun testLatestPRCopiesTheRecordAndComputesTheDelta() {
        val result = pr(
            listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 10, 9, 0), records = listOf(record("bench", e1RM = 99.25, previousBest = 95.0, weight = 85.0, reps = 5)))),
        )
        assertThat(result?.exerciseName).isEqualTo("Bench")
        assertThat(result?.weightKg).isEqualTo(85.0)
        assertThat(result?.reps).isEqualTo(5)
        assertThat(result?.estimated1RM).isEqualTo(99.25)
        assertWithMessage("the estimate minus the previous best").that(result?.deltaKg).isEqualTo(4.25)
    }

    @Test
    fun testLatestPRDeltaIsZeroWithoutAPreviousBest() {
        val result = pr(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 10, 9, 0), records = listOf(record("bench", e1RM = 99.0, previousBest = 0.0)))))
        assertThat(result?.deltaKg).isEqualTo(0.0)
    }

    @Test
    fun testLatestPRIsFreshWithin24HoursOnly() {
        fun fresh(age: Double): Boolean? =
            pr(listOf(WidFix.workout(1, at = WidFix.now.addingTimeInterval(-age), records = listOf(record("bench", e1RM = 99.0)))))?.isFresh
        assertWithMessage("just now").that(fresh(0.0)).isTrue()
        assertThat(fresh(3_600.0)).isTrue()
        assertWithMessage("exactly 24 hours old is still fresh").that(fresh(24 * 3_600.0)).isTrue()
        assertThat(fresh(24 * 3_600.0 + 1)).isFalse()
        assertWithMessage("a record from the future is never fresh").that(fresh(-1.0)).isFalse()
    }
}
