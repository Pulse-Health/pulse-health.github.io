import Foundation

/// The weight arithmetic behind "beat your best estimated 1RM": the in-workout coach tip and the hub note both use it.
///
/// It used to exist twice (the presenter's `lowestBeatingWeight` and a private copy in the hub screen). This is the one copy; it is
/// public so the iOS target can call it.
public enum TargetWeight {
    /// A record must beat the running best by more than this many kilograms of estimated 1RM.
    public static let recordMargin = 0.05

    /// The lowest multiple of `step` whose Epley estimate with `reps` exceeds `baseline` by more than `recordMargin`.
    ///
    /// Nil for input that cannot produce a meaningful answer: a baseline that is not finite or not positive, reps or step that are
    /// not positive, a step that is not finite, or a result of a billion steps or more.
    public static func lowestBeating(baseline: Double, reps: Int, step: Double) -> Double? {
        guard baseline.isFinite, baseline > 0, reps > 0, step > 0, step.isFinite else { return nil }
        let threshold = baseline + recordMargin
        func beats(_ weight: Double) -> Bool { Estimated1RM.epley(weightKg: weight, reps: reps) > threshold }

        let minimum = threshold / (1 + Double(reps) / 30)
        var multiples = (minimum / step).rounded(.up)
        guard multiples.isFinite, multiples < 1e9 else { return nil }
        multiples = max(1, multiples)
        // Correct a possible off-by-one from floating point rounding in either direction.
        var guardCount = 0
        while multiples > 1, beats((multiples - 1) * step), guardCount < 8 {
            multiples -= 1
            guardCount += 1
        }
        while !beats(multiples * step), guardCount < 16 {
            multiples += 1
            guardCount += 1
        }
        let weight = multiples * step
        return beats(weight) ? weight : nil
    }
}
