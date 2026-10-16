import Foundation

/// The most recent session and the newest personal record (widgets/SPEC.md section 2: lastSession, latestPR).
enum WidgetSessions {
    /// Fewest heart-rate samples that make a curve.
    static let minimumHeartRateSamples = 4
    /// Most bars of the heart-rate curve.
    static let maximumHeartRateBars = 16
    /// The longest time a set counts as lifting; the rest of the gap before it is rest.
    static let liftingSeconds = 45
    /// A rest longer than this many seconds is a long rest.
    static let longRestSeconds = 180

    // MARK: Last session

    /// The workout with the greatest `finishedAt` (the first one on a tie) as a session summary; nil without history.
    static func lastSession(_ history: WidgetHistory) -> SessionSummary? {
        guard let workout = history.latest?.workout else { return nil }
        let curve = heartRateCurve(workout.heartRateSeries ?? [])
        let stretches = timeline(of: workout)
        return SessionSummary(
            workoutID: workout.id,
            name: workout.name,
            finishedAt: workout.finishedAt,
            durationMinutes: roundedMinutes(workout.durationSeconds),
            loggedSets: workout.loggedSets,
            volumeKg: workout.volumeKg,
            averageHeartRate: workout.averageHeartRate,
            peakHeartRate: curve.peak,
            personalRecordCount: workout.personalRecords.count,
            timeline: stretches.segments,
            underTensionPercent: stretches.underTensionPercent,
            longBreakCount: stretches.longBreakCount,
            heartRateBars: curve.bars
        )
    }

    /// Whole minutes of `seconds`, a half rounding up (negative time counts as none).
    static func roundedMinutes(_ seconds: Int) -> Int {
        let time = max(0, seconds)
        return time / 60 + (time % 60 >= 30 ? 1 : 0)
    }

    // MARK: Heart rate

    /// The peak and the bars of a heart-rate series. With fewer than `minimumHeartRateSamples` samples there is neither.
    ///
    /// The samples (in the order recorded) are cut into `min(16, count)` contiguous buckets of near-equal size, the earlier buckets
    /// taking the remainder; a bar is the rounded mean of its bucket and is an effort when it is above the rounded mean of all
    /// samples. The peak is the highest sample.
    static func heartRateCurve(_ samples: [HeartRateSample]) -> (peak: Int?, bars: [HeartRateBar]) {
        guard samples.count >= minimumHeartRateSamples else { return (nil, []) }
        let overall = roundedMean(samples.map { $0.bpm })
        let buckets = min(maximumHeartRateBars, samples.count)
        let size = samples.count / buckets
        let remainder = samples.count % buckets
        var bars: [HeartRateBar] = []
        var start = 0
        for bucket in 0..<buckets {
            let end = start + size + (bucket < remainder ? 1 : 0)
            let mean = roundedMean(samples[start..<end].map { $0.bpm })
            bars.append(HeartRateBar(bpm: mean, isEffort: mean > overall))
            start = end
        }
        return (samples.map { $0.bpm }.max(), bars)
    }

    /// The mean of `values` rounded half up, in integers. A value is taken as 0...1,000 so a damaged sample cannot overflow the sum.
    private static func roundedMean(_ values: [Int]) -> Int {
        let count = values.count
        guard count > 0 else { return 0 }
        let sum = values.reduce(0) { $0 + min(max($1, 0), 1_000) }
        return (2 * sum + count) / (2 * count)
    }

    // MARK: Timeline

    /// The stretches of a session: lifting, rest and long rest, from the times its sets were logged.
    ///
    /// Needs `CompletedSet.loggedAt` on at least two sets; sets without a time are ignored, and without enough of them the timeline is
    /// empty. The logged sets are put in time order (the workout's own order on a tie) and times are taken in whole seconds. The gap
    /// before a set (to the previous set, to the start of the workout for the first) is lifting for up to 45 seconds and rest for
    /// the remainder: a long rest above 180 seconds. Per set the rest comes first, then the lifting; a stretch of no time is skipped and
    /// neighbours of the same kind are merged.
    static func timeline(of workout: CompletedWorkout)
        -> (segments: [TimelineSegment], underTensionPercent: Int?, longBreakCount: Int)
    {
        var logged: [(time: Int, order: Int)] = []
        for exercise in workout.exercises {
            for set in exercise.sets {
                guard let loggedAt = set.loggedAt, loggedAt.timeIntervalSince1970.isFinite else { continue }
                logged.append((wholeSeconds(loggedAt), logged.count))
            }
        }
        guard logged.count >= 2 else { return ([], nil, 0) }
        logged.sort { $0.time != $1.time ? $0.time < $1.time : $0.order < $1.order }

        var segments: [TimelineSegment] = []
        func add(_ kind: TimelineKind, _ seconds: Int) {
            guard seconds > 0 else { return }
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1].seconds += seconds
            } else {
                segments.append(TimelineSegment(kind: kind, seconds: seconds))
            }
        }
        var previous = wholeSeconds(workout.startedAt)
        for set in logged {
            let gap = max(0, set.time - previous)
            let lifting = min(gap, liftingSeconds)
            let rest = gap - lifting
            add(rest > longRestSeconds ? .longRest : .rest, rest)
            add(.lifting, lifting)
            previous = set.time
        }

        let total = segments.reduce(0) { $0 + $1.seconds }
        let lifting = segments.filter { $0.kind == .lifting }.reduce(0) { $0 + $1.seconds }
        return (
            segments,
            total > 0 ? (200 * lifting + total) / (2 * total) : nil,
            segments.filter { $0.kind == .longRest }.count
        )
    }

    private static func wholeSeconds(_ date: Date) -> Int {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, abs(seconds) < 1e15 else { return 0 }
        return Int(seconds.rounded())
    }

    // MARK: Latest record

    /// The newest personal record: the workout with the greatest `finishedAt` among those that set records (the first on a tie), and
    /// in it the record with the highest estimated 1RM (the first on a tie). `deltaKg` is the estimate minus the previous best (0 when
    /// there was none); the record is fresh when it is at most 24 hours old.
    static func latestPR(_ history: WidgetHistory) -> PRSummary? {
        var newest: CompletedWorkout?
        for entry in history.entries where !entry.workout.personalRecords.isEmpty {
            if let current = newest, current.finishedAt >= entry.workout.finishedAt { continue }
            newest = entry.workout
        }
        guard let workout = newest else { return nil }
        var best: PersonalRecord?
        for record in workout.personalRecords {
            if let current = best, current.estimated1RM >= record.estimated1RM { continue }
            best = record
        }
        guard let record = best else { return nil }
        let age = history.now.timeIntervalSince(workout.finishedAt)
        return PRSummary(
            exerciseID: record.exerciseID,
            exerciseName: record.exerciseName,
            weightKg: record.weightKg,
            reps: record.reps,
            estimated1RM: record.estimated1RM,
            deltaKg: record.previousBest == 0 ? 0 : record.estimated1RM - record.previousBest,
            achievedAt: workout.finishedAt,
            isFresh: age >= 0 && age <= 24 * 3_600
        )
    }
}
