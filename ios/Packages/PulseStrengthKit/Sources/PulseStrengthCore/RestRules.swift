import Foundation

/// How long the rest after a set lasts. Pure: the reducer starts rests with it and `WorkoutTemplate.estimatedMinutes` adds them up.
///
/// * An exercise rest of 0 means the timer is off: no rest after a set of any type.
/// * After a normal or a failure set: the exercise's rest.
/// * After a warm-up: 40 % of the exercise's rest, rounded to 5 seconds, at least 30 seconds.
/// * After a drop set: nothing when the NEXT set of the same exercise is also a drop set (the drops follow each other at once),
///   else the exercise's rest. The last set of an exercise has no next set.
public enum RestRules {
    /// The seconds of rest after the set at `index` of an exercise whose sets have the types `types` (in order) and whose rest is
    /// `exerciseRest` seconds (counted as the nearest value of 0...`WorkoutReducer.maximumRestSeconds`, so a state the reducer did not
    /// produce cannot overflow the arithmetic). An index outside `types` counts as a normal set.
    public static func seconds(afterSetAt index: Int, types: [SetType], exerciseRest: Int) -> Int {
        let base = max(0, min(exerciseRest, WorkoutReducer.maximumRestSeconds))
        guard base > 0 else { return 0 }
        guard types.indices.contains(index) else { return base }
        switch types[index] {
        case .normal, .failure:
            return base
        case .warmup:
            let scaled = (Double(base) * 0.4 / 5).rounded(.toNearestOrAwayFromZero) * 5
            return max(30, Int(scaled))
        case .drop:
            let next = index + 1
            return types.indices.contains(next) && types[next] == .drop ? 0 : base
        }
    }
}
