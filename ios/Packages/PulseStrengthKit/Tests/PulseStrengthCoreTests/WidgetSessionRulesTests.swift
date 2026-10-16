import Foundation
import XCTest
@testable import PulseStrengthCore

/// widgets/SPEC.md section 2: lastSession (with its heart-rate bars and its timeline) and latestPR.
final class WidgetLastSessionRuleTests: XCTestCase {
    private func session(_ history: [CompletedWorkout]) -> SessionSummary? {
        WidFix.snapshot(history: history).lastSession
    }

    func testLastSessionIsTheWorkoutWithTheGreatestFinishedAtWhateverTheOrder() {
        let older = WidFix.workout(1, "Lower A · Quads", at: WidFix.date(2026, 10, 9, 18, 0))
        let newer = WidFix.workout(2, "Upper B · Pull", at: WidFix.date(2026, 10, 13, 9, 0))
        XCTAssertEqual(session([older, newer])?.workoutID, newer.id)
        XCTAssertEqual(session([newer, older])?.workoutID, newer.id)
        XCTAssertNil(session([]))
    }

    func testLastSessionTakesTheFirstWorkoutOfTheHistoryOnATie() {
        let at = WidFix.date(2026, 10, 13, 9, 0)
        XCTAssertEqual(session([WidFix.workout(1, at: at), WidFix.workout(2, at: at)])?.workoutID, WidFix.uuid(1))
    }

    func testLastSessionCopiesTheWorkout() {
        var workout = WidFix.workout(
            1, "Upper B · Pull", at: WidFix.date(2026, 10, 13, 9, 0), durationSeconds: 3_125, volumeKg: 6_245.5,
            exercises: [WidFix.lift("brow", [WidFix.set(60, 8), WidFix.set(60, 8)], n: 1), WidFix.lift("curl", [WidFix.set(30, 10)], n: 2)],
            records: [PersonalRecord(exerciseID: "brow", exerciseName: "Barbell row", weightKg: 60, reps: 8, estimated1RM: 76, previousBest: 70)]
        )
        workout.averageHeartRate = 124
        let result = session([workout])
        XCTAssertEqual(result?.workoutID, workout.id)
        XCTAssertEqual(result?.name, "Upper B · Pull")
        XCTAssertEqual(result?.finishedAt, WidFix.date(2026, 10, 13, 9, 0))
        XCTAssertEqual(result?.loggedSets, 3)
        XCTAssertEqual(result?.volumeKg, 6_245.5)
        XCTAssertEqual(result?.averageHeartRate, 124)
        XCTAssertEqual(result?.personalRecordCount, 1)
        XCTAssertNil(result?.peakHeartRate)
        XCTAssertEqual(result?.heartRateBars, [])
        XCTAssertEqual(result?.timeline, [])
        XCTAssertNil(result?.underTensionPercent)
        XCTAssertEqual(result?.longBreakCount, 0)
    }

    func testLastSessionDurationMinutesIsSecondsOver60RoundedHalfUp() {
        let minutes = { (seconds: Int) in self.session([WidFix.workout(1, at: WidFix.date(2026, 10, 13, 9, 0), durationSeconds: seconds)])?.durationMinutes }
        XCTAssertEqual(minutes(0), 0)
        XCTAssertEqual(minutes(29), 0)
        XCTAssertEqual(minutes(30), 1, "half a minute rounds up")
        XCTAssertEqual(minutes(89), 1)
        XCTAssertEqual(minutes(90), 2)
        XCTAssertEqual(minutes(3_000), 50)
        XCTAssertEqual(minutes(3_149), 52)
        XCTAssertEqual(minutes(3_150), 53)
        XCTAssertEqual(minutes(-45), 0, "never negative")
    }

    // MARK: Heart rate

    private func samples(_ bpm: [Int]) -> [HeartRateSample] {
        bpm.enumerated().map { HeartRateSample(bpm: $0.element, at: WidFix.date(2026, 10, 13, 8, 0).addingTimeInterval(Double($0.offset) * 30)) }
    }

    private func curve(_ bpm: [Int]) -> SessionSummary? {
        session([WidFix.workout(1, at: WidFix.date(2026, 10, 13, 9, 0), heartRate: samples(bpm))])
    }

    func testHeartRateBarsNeedAtLeastFourSamples() {
        for count in 0...3 {
            let result = curve(Array(repeating: 120, count: count))
            XCTAssertEqual(result?.heartRateBars, [], "\(count) samples")
            XCTAssertNil(result?.peakHeartRate, "\(count) samples")
        }
        let four = curve([100, 110, 120, 130])
        XCTAssertEqual(four?.heartRateBars.map { $0.bpm }, [100, 110, 120, 130], "four samples are four buckets of one")
        XCTAssertEqual(four?.peakHeartRate, 130)
    }

    func testHeartRateBarsAreContiguousBucketsOfNearEqualSizeTheEarlierOnesTakingTheRemainder() {
        // 20 samples in 16 buckets: the first four buckets hold two samples, the other twelve one.
        let bpm = (0..<20).map { 100 + $0 * 2 }
        let bars = curve(bpm)?.heartRateBars.map { $0.bpm }
        var expected: [Int] = []
        var index = 0
        for bucket in 0..<16 {
            let size = bucket < 4 ? 2 : 1
            let values = bpm[index..<(index + size)]
            expected.append((2 * values.reduce(0, +) + size) / (2 * size))
            index += size
        }
        XCTAssertEqual(bars, expected)
        XCTAssertEqual(bars?.count, 16)
        XCTAssertEqual(Array((bars ?? []).prefix(2)), [101, 105], "(100 + 102) / 2 and (104 + 106) / 2")
    }

    func testHeartRateBarsHaveAtMostSixteenBucketsAndFewerSamplesGiveOneBucketEach() {
        XCTAssertEqual(curve((0..<16).map { 100 + $0 })?.heartRateBars.count, 16)
        XCTAssertEqual(curve((0..<17).map { 100 + $0 })?.heartRateBars.map { $0.bpm }.first, 101, "17 samples: the first bucket takes two")
        XCTAssertEqual(curve((0..<300).map { 100 + $0 % 40 })?.heartRateBars.count, 16)
        XCTAssertEqual(curve((0..<7).map { 100 + $0 })?.heartRateBars.count, 7)
    }

    func testAHeartRateBarIsTheRoundedMeanOfItsBucketWithHalvesRoundingUp() {
        // 32 samples make 16 buckets of two: every bucket (100, 101) has the mean 100.5.
        let halves = (0..<32).map { $0 % 2 == 0 ? 100 : 101 }
        XCTAssertEqual(curve(halves)?.heartRateBars.map { $0.bpm }, Array(repeating: 101, count: 16))
        // 17 samples: the first bucket takes two (100 and 101), the others one.
        let remainder = [100, 101] + Array(repeating: 100, count: 15)
        XCTAssertEqual(curve(remainder)?.heartRateBars.map { $0.bpm }, [101] + Array(repeating: 100, count: 15))
        // 48 samples make 16 buckets of three: (100, 100, 101) has the mean 100.33 and (100, 101, 101) the mean 100.67.
        let below = (0..<48).map { $0 % 3 == 2 ? 101 : 100 }
        XCTAssertEqual(curve(below)?.heartRateBars.map { $0.bpm }, Array(repeating: 100, count: 16))
        let above = (0..<48).map { $0 % 3 == 0 ? 100 : 101 }
        XCTAssertEqual(curve(above)?.heartRateBars.map { $0.bpm }, Array(repeating: 101, count: 16))
    }

    func testAHeartRateBarIsAnEffortWhenAboveTheRoundedMeanOfAllSamples() {
        // Samples 100, 100, 140, 140: the mean of all is 120; buckets of one sample each.
        let bars = curve([100, 100, 140, 140])?.heartRateBars
        XCTAssertEqual(bars?.map { $0.isEffort }, [false, false, true, true])
        // A bar equal to the rounded mean is not above it.
        let equal = curve([110, 130, 120, 120])?.heartRateBars
        XCTAssertEqual(equal?.map { $0.isEffort }, [false, true, false, false], "the mean is 120: only 130 is above it")
    }

    func testPeakHeartRateIsTheHighestSampleNotTheHighestBar() {
        // 20 samples: the 190 shares a bucket with 100, so the bar is 145 but the peak is 190.
        var bpm = Array(repeating: 100, count: 20)
        bpm[1] = 190
        let result = curve(bpm)
        XCTAssertEqual(result?.peakHeartRate, 190)
        XCTAssertEqual(result?.heartRateBars.first?.bpm, 145)
    }

    // MARK: Timeline

    private let start = WidFix.date(2026, 10, 13, 8, 0)

    /// The session of a workout that started at `start` and logged one set at each of `seconds` after it.
    private func timeline(_ seconds: [Double]) -> SessionSummary? {
        let sets = seconds.map { WidFix.set(60, 8, at: start.addingTimeInterval($0)) }
        let exercises = sets.isEmpty ? [] : [WidFix.lift("brow", sets, n: 1)]
        return session([WidFix.workout(1, at: start.addingTimeInterval(3_000), exercises: exercises, startedAt: start)])
    }

    func testTimelineIsLiftingUpToFortyFiveSecondsPerGapAndRestForTheRest() {
        // Sets at +30 s, +90 s, +500 s and +520 s after the start.
        let result = timeline([30, 90, 500, 520])
        XCTAssertEqual(result?.timeline, [
            TimelineSegment(kind: .lifting, seconds: 30),                // 0 - 30: all lifting
            TimelineSegment(kind: .rest, seconds: 15),                   // 30 - 90: 60 s gap = 45 lifting + 15 rest, rest first
            TimelineSegment(kind: .lifting, seconds: 45),
            TimelineSegment(kind: .longRest, seconds: 365),              // 90 - 500: 410 s gap = 45 lifting + 365 rest
            TimelineSegment(kind: .lifting, seconds: 65),                // 45 + 20, merged
        ])
        XCTAssertEqual(result?.underTensionPercent, 27, "140 of 520 s is 26.9 %")
        XCTAssertEqual(result?.longBreakCount, 1)
    }

    func testTheGapBeforeTheFirstSetIsMeasuredFromTheStartOfTheWorkout() {
        let result = timeline([200, 230])
        XCTAssertEqual(result?.timeline, [
            TimelineSegment(kind: .rest, seconds: 155),                  // 200 s = 45 + 155 (not above 180: a normal rest)
            TimelineSegment(kind: .lifting, seconds: 75),
        ])
        XCTAssertEqual(result?.longBreakCount, 0)
    }

    func testARestIsLongOnlyAboveThreeMinutes() {
        // Gap 225 s = 45 lifting + 180 rest: still a rest. Gap 226 s: 181 s, a long rest.
        XCTAssertEqual(timeline([225, 226])?.timeline.first, TimelineSegment(kind: .rest, seconds: 180))
        XCTAssertEqual(timeline([226, 227])?.timeline.first, TimelineSegment(kind: .longRest, seconds: 181))
    }

    func testTimelineNeedsTheTimeOfAtLeastTwoSets() {
        XCTAssertEqual(timeline([60])?.timeline, [])
        XCTAssertNil(timeline([60])?.underTensionPercent)
        XCTAssertEqual(timeline([60])?.longBreakCount, 0)
        XCTAssertEqual(timeline([])?.timeline, [])
        XCTAssertFalse(timeline([60, 120])?.timeline.isEmpty ?? true)
    }

    func testSetsWithoutATimeAreIgnoredAndOlderHistoryHasNoTimeline() {
        let mixed = WidFix.lift("brow", [WidFix.set(60, 8, at: start.addingTimeInterval(30)), WidFix.set(60, 8), WidFix.set(60, 8, at: start.addingTimeInterval(90))], n: 1)
        let result = session([WidFix.workout(1, at: start.addingTimeInterval(3_000), exercises: [mixed], startedAt: start)])
        XCTAssertEqual(result?.timeline.map { $0.seconds }.reduce(0, +), 90, "two timed sets: the untimed one is not part of the gaps")
        let untimed = WidFix.lift("brow", [WidFix.set(60, 8), WidFix.set(60, 8)], n: 2)
        XCTAssertEqual(session([WidFix.workout(2, at: start.addingTimeInterval(3_000), exercises: [untimed], startedAt: start)])?.timeline, [])
    }

    func testTheLoggedSetsAreTakenInTimeOrderAcrossExercises() {
        let first = WidFix.lift("brow", [WidFix.set(60, 8, at: start.addingTimeInterval(300)), WidFix.set(60, 8, at: start.addingTimeInterval(40))], n: 1)
        let second = WidFix.lift("curl", [WidFix.set(30, 10, at: start.addingTimeInterval(100))], n: 2)
        let result = session([WidFix.workout(1, at: start.addingTimeInterval(3_000), exercises: [first, second], startedAt: start)])
        // Times 40, 100, 300: gaps 40, 60, 200 -> lifting 40, rest 15 + lifting 45, rest 155 + lifting 45.
        XCTAssertEqual(result?.timeline, [
            TimelineSegment(kind: .lifting, seconds: 40),
            TimelineSegment(kind: .rest, seconds: 15),
            TimelineSegment(kind: .lifting, seconds: 45),
            TimelineSegment(kind: .rest, seconds: 155),
            TimelineSegment(kind: .lifting, seconds: 45),
        ])
    }

    func testStretchesOfNoTimeAreSkippedAndNeighboursOfTheSameKindMerge() {
        // Gaps of 20, 0 and 30 seconds are all lifting: one stretch of 50 s... and a set logged at the same moment adds nothing.
        XCTAssertEqual(timeline([20, 20, 50])?.timeline, [TimelineSegment(kind: .lifting, seconds: 50)])
        // A gap of exactly 45 s has no rest; the next gap of 46 s starts with 1 s of rest.
        XCTAssertEqual(timeline([45, 91])?.timeline, [
            TimelineSegment(kind: .lifting, seconds: 45),
            TimelineSegment(kind: .rest, seconds: 1),
            TimelineSegment(kind: .lifting, seconds: 45),
        ])
    }

    func testEveryLongRestIsOneBreak() {
        // Set two is logged at the same moment as set one (a gap of 0); set three follows 500 s later.
        let result = timeline([400, 400, 900])
        XCTAssertEqual(result?.timeline.map { $0.kind }, [.longRest, .lifting, .longRest, .lifting])
        XCTAssertEqual(result?.timeline.map { $0.seconds }, [355, 45, 455, 45])
        XCTAssertEqual(result?.longBreakCount, 2)
    }

    func testUnderTensionPercentIsTheShareOfLiftingRoundedHalfUp() {
        // A gap of 360 s is 45 s of lifting and 315 s of rest: 12.5 % rounds up to 13.
        XCTAssertEqual(timeline([360, 360])?.underTensionPercent, 13)
        // 320 s: 45 of 320 is 14.06 %, which rounds down.
        XCTAssertEqual(timeline([320, 320])?.underTensionPercent, 14)
        // Gaps of 45 s and 315 s: lifting 90 of 360 s.
        XCTAssertEqual(timeline([45, 360])?.underTensionPercent, 25)
        // Gaps of 405 s and 45 s: 90 of 450 s.
        XCTAssertEqual(timeline([405, 450])?.underTensionPercent, 20)
        // Only lifting: 100 %.
        XCTAssertEqual(timeline([20, 40])?.underTensionPercent, 100)
    }

    func testTimesAreTakenInWholeSeconds() {
        // 30.4 s and 89.6 s round to 30 s and 90 s, so the gaps are 30 and 60 whole seconds.
        XCTAssertEqual(timeline([30.4, 89.6])?.timeline, [
            TimelineSegment(kind: .lifting, seconds: 30),
            TimelineSegment(kind: .rest, seconds: 15),
            TimelineSegment(kind: .lifting, seconds: 45),
        ])
    }

    func testASetLoggedBeforeTheStartOfTheWorkoutHasAZeroGap() {
        // The first set predates the start (a clock that was set back): its gap is 0, the next one counts from it, 50 s.
        let result = timeline([-20, 30])
        XCTAssertEqual(result?.timeline, [TimelineSegment(kind: .rest, seconds: 5), TimelineSegment(kind: .lifting, seconds: 45)])
    }
}

final class WidgetLatestPersonalRecordRuleTests: XCTestCase {
    private func record(_ id: String, e1RM: Double, previousBest: Double = 90, weight: Double = 80, reps: Int = 5) -> PersonalRecord {
        PersonalRecord(exerciseID: id, exerciseName: id.capitalized, weightKg: weight, reps: reps, estimated1RM: e1RM, previousBest: previousBest)
    }

    private func pr(_ history: [CompletedWorkout]) -> PRSummary? {
        WidFix.snapshot(history: history).latestPR
    }

    func testLatestPRIsFromTheNewestWorkoutThatSetRecords() {
        let history = [
            WidFix.workout(3, at: WidFix.date(2026, 10, 14, 9, 0)),                                                                      // newest, no record
            WidFix.workout(2, at: WidFix.date(2026, 10, 10, 9, 0), records: [record("squat", e1RM: 120)]),
            WidFix.workout(1, at: WidFix.date(2026, 10, 2, 9, 0), records: [record("bench", e1RM: 110)]),
        ]
        let result = pr(history)
        XCTAssertEqual(result?.exerciseID, "squat")
        XCTAssertEqual(result?.achievedAt, WidFix.date(2026, 10, 10, 9, 0))
        XCTAssertEqual(pr(history.reversed())?.exerciseID, "squat", "whatever the order of the history")
        XCTAssertNil(pr([WidFix.workout(1, at: WidFix.date(2026, 10, 10, 9, 0))]))
        XCTAssertNil(pr([]))
    }

    func testLatestPRIsTheRecordWithTheHighestEstimatedOneRepMaxFirstOnATie() {
        let workout = WidFix.workout(1, at: WidFix.date(2026, 10, 10, 9, 0), records: [
            record("bench", e1RM: 99), record("squat", e1RM: 130), record("ohp", e1RM: 130), record("curl", e1RM: 40),
        ])
        XCTAssertEqual(pr([workout])?.exerciseID, "squat")
    }

    func testLatestPRCopiesTheRecordAndComputesTheDelta() {
        let result = pr([WidFix.workout(1, at: WidFix.date(2026, 10, 10, 9, 0), records: [record("bench", e1RM: 99.25, previousBest: 95, weight: 85, reps: 5)])])
        XCTAssertEqual(result?.exerciseName, "Bench")
        XCTAssertEqual(result?.weightKg, 85)
        XCTAssertEqual(result?.reps, 5)
        XCTAssertEqual(result?.estimated1RM, 99.25)
        XCTAssertEqual(result?.deltaKg, 4.25, "the estimate minus the previous best")
    }

    func testLatestPRDeltaIsZeroWithoutAPreviousBest() {
        let result = pr([WidFix.workout(1, at: WidFix.date(2026, 10, 10, 9, 0), records: [record("bench", e1RM: 99, previousBest: 0)])])
        XCTAssertEqual(result?.deltaKg, 0)
    }

    func testLatestPRIsFreshWithin24HoursOnly() {
        let achieved = WidFix.now.addingTimeInterval(-24 * 3_600)
        let fresh = { (age: TimeInterval) in
            self.pr([WidFix.workout(1, at: WidFix.now.addingTimeInterval(-age), records: [self.record("bench", e1RM: 99)])])?.isFresh
        }
        XCTAssertEqual(fresh(0), true, "just now")
        XCTAssertEqual(fresh(3_600), true)
        XCTAssertEqual(fresh(24 * 3_600), true, "exactly 24 hours old is still fresh")
        XCTAssertEqual(fresh(24 * 3_600 + 1), false)
        XCTAssertEqual(fresh(-1), false, "a record from the future is never fresh")
        XCTAssertEqual(achieved, WidFix.now.addingTimeInterval(-86_400))
    }
}
