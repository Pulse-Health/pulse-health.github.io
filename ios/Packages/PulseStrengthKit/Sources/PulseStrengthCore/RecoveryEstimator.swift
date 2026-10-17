import Foundation

/// How recovered one muscle group is, as `RecoveryEstimator` works it out.
public struct RecoveryEstimate: Equatable, Sendable {
    /// 0...100. 100 means fully recovered (or not trained lately).
    public var percent: Int
    /// False when the history has no workout in the last `RecoveryEstimator.dataWindowDays` days: the percent is then only the
    /// default 100 and a screen should not present it as a measurement.
    public var hasData: Bool

    public init(percent: Int, hasData: Bool) {
        self.percent = percent
        self.hasData = hasData
    }
}

/// Estimates the recovery of each muscle group from the finished workouts. A heuristic, not a measurement.
///
/// For every finished workout of the last `lookbackDays` days (5) and every muscle group it trained with `n` working sets
/// (`CompletedWorkout.muscleSets`, warm-up sets excluded):
///
///     hoursNeeded = 24 + 6 * min(n, 12)                       (30 h for 1 set ... 96 h for 12 or more)
///     recovered   = clamp(hoursSinceFinish / hoursNeeded, 0...1)
///
/// The percent of a muscle group is the MINIMUM of `recovered` over those workouts (it is still fatigued from the most demanding
/// one), times 100 and rounded; 100 when no workout in the window trained it. A workout that finished after `now` counts as
/// finished now (0 %). `hasData` is true when the history has at least one workout that finished at most `dataWindowDays` (21)
/// days before `now`; without one every group reads 100 and `hasData` is false.
public enum RecoveryEstimator {
    /// Only workouts that finished at most this many days ago can leave a muscle group fatigued (the longest recovery is 4 days).
    public static let lookbackDays = 5
    /// `hasData` needs a workout at most this many days old.
    public static let dataWindowDays = 21
    /// Hours of recovery needed even after a single set.
    public static let baseHours = 24.0
    /// Extra hours of recovery per working set.
    public static let hoursPerSet = 6.0
    /// Working sets beyond this many do not lengthen the recovery.
    public static let setCap = 12

    /// True when `history` has a workout that finished at most `dataWindowDays` days before `now`.
    public static func hasData(history: [CompletedWorkout], now: Date) -> Bool {
        let dataStart = now.addingTimeInterval(-Double(dataWindowDays) * 86_400)
        return history.contains { $0.finishedAt >= dataStart }
    }

    /// The estimate of every muscle group (all six are present) for `history` at `now`.
    public static func estimates(history: [CompletedWorkout], now: Date) -> [MuscleGroup: RecoveryEstimate] {
        let lookback = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        let hasData = hasData(history: history, now: now)

        var fraction: [MuscleGroup: Double] = [:]
        for workout in history where workout.finishedAt >= lookback {
            let hours = max(0, now.timeIntervalSince(workout.finishedAt) / 3_600)
            for item in workout.muscleSets where item.sets > 0 {
                let needed = baseHours + hoursPerSet * Double(min(item.sets, setCap))
                let recovered = min(1, hours / needed)
                fraction[item.muscle] = min(fraction[item.muscle] ?? 1, recovered)
            }
        }

        var result: [MuscleGroup: RecoveryEstimate] = [:]
        for muscle in MuscleGroup.allCases {
            let percent = Int(((fraction[muscle] ?? 1) * 100).rounded())
            result[muscle] = RecoveryEstimate(percent: percent, hasData: hasData)
        }
        return result
    }

    /// The estimates as a `RecoveryProvider` (percent per muscle group), fixed at `now`.
    public static func provider(history: [CompletedWorkout], now: Date) -> RecoveryProvider {
        let table = estimates(history: history, now: now)
        return { muscle in table[muscle]?.percent ?? 100 }
    }

    /// The mean of the six percents (every group counts the same), rounded; nil without data (`RecoveryEstimate.hasData` is false).
    public static func readinessPercent(history: [CompletedWorkout], now: Date) -> Int? {
        let table = estimates(history: history, now: now)
        guard table.values.allSatisfy({ $0.hasData }) else { return nil }
        let total = table.values.reduce(0) { $0 + $1.percent }
        return Int((Double(total) / Double(table.count)).rounded())
    }
}

// MARK: - Data, model, store

public extension StrengthData {
    /// The recovery estimate of every muscle group at `now` (see `RecoveryEstimator`).
    func recoveryEstimates(now: Date) -> [MuscleGroup: RecoveryEstimate] {
        RecoveryEstimator.estimates(history: history, now: now)
    }

    /// The overall readiness: the mean recovery of the muscle groups, nil without a workout in the last 21 days.
    func readinessPercent(now: Date) -> Int? {
        RecoveryEstimator.readinessPercent(history: history, now: now)
    }

    /// The recovery of each muscle group at `now` as a `RecoveryProvider`.
    func recoveryProvider(now: Date) -> RecoveryProvider {
        RecoveryEstimator.provider(history: history, now: now)
    }

    /// False when the estimates at `now` are only the default 100 (no workout in the last 21 days).
    func recoveryHasData(now: Date) -> Bool {
        RecoveryEstimator.hasData(history: history, now: now)
    }
}

public extension StrengthDataModel {
    /// The recovery estimate of every muscle group at `now`, from the finished workouts.
    func recoveryEstimates(now: Date) -> [MuscleGroup: RecoveryEstimate] {
        data.recoveryEstimates(now: now)
    }

    /// The mean recovery of the muscle groups at `now`; nil without a workout in the last 21 days.
    func readinessPercent(now: Date) -> Int? {
        data.readinessPercent(now: now)
    }

    /// The recovery of each muscle group at `now` as a `RecoveryProvider`: the default of the active-workout screen.
    func recoveryProvider(now: Date) -> RecoveryProvider {
        data.recoveryProvider(now: now)
    }

    /// False when the estimates at `now` are only the default 100 (no workout in the last 21 days).
    func recoveryHasData(now: Date) -> Bool {
        data.recoveryHasData(now: now)
    }
}
