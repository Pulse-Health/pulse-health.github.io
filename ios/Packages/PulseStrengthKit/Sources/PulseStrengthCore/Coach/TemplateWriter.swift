import Foundation

/// The words for one recommendation: a short headline ("82.5 kg × 6") and an optional reason.
///
/// Kept as two plain strings so a screen can lay them out as it likes. All figures come from the `Recommendation`, never from
/// anywhere else, and the text is English only for now (the whole app is; see the proposal's localisation note).
public struct CoachLine: Equatable, Sendable {
    public var headline: String
    public var detail: String?

    public init(headline: String, detail: String? = nil) {
        self.headline = headline
        self.detail = detail
    }

    /// "82.5 kg × 6. Two clean sessions at RIR 2 or more."
    public var sentence: String {
        guard let detail, !detail.isEmpty else { return headline }
        return headline + ". " + detail
    }
}

/// Turns a `Recommendation` into a `CoachLine` with fixed sentences. The only writer in Phase 0; a model never writes coach text.
public enum TemplateWriter {
    /// Nil when the coach has nothing to say (`insufficientData`).
    ///
    /// `config` only supplies the figures that appear in the sentences (the effort threshold), so a changed threshold is never
    /// described with the old number.
    public static func line(for recommendation: Recommendation, config: CoachConfig = CoachConfig()) -> CoachLine? {
        let reasons = recommendation.reasons
        let minimumRIR = NumberText.kg(config.progressMinimumRIR)
        switch recommendation.verdict {
        case .insufficientData:
            return nil

        case .noEffortData:
            return CoachLine(headline: "Log RIR on your sets", detail: "Then this lift can get a suggestion.")

        case .progress:
            guard let target = target(recommendation) else { return nil }
            return CoachLine(headline: target, detail: "Two clean sessions at RIR \(minimumRIR) or more.")

        case .addRep:
            guard let target = target(recommendation) else { return nil }
            return CoachLine(headline: target, detail: "A heavier step would be a big jump, so add a rep instead.")

        case .reduce:
            guard let target = target(recommendation) else { return nil }
            let detail = reasons.contains(.lighterWeekDue)
                ? "A lighter week after several increases in a row."
                : "Reps fell at the same weight twice."
            return CoachLine(headline: target, detail: detail)

        case .hold:
            guard let target = target(recommendation) else { return nil }
            return CoachLine(headline: "Stay at " + target, detail: holdDetail(reasons, minimumRIR: minimumRIR))
        }
    }

    /// "82.5 kg × 6", or nil without both figures.
    private static func target(_ recommendation: Recommendation) -> String? {
        guard let weight = recommendation.targetWeightKg, let reps = recommendation.targetReps else { return nil }
        return NumberText.kg(weight) + " kg × " + String(reps)
    }

    private static func holdDetail(_ reasons: [ReasonCode], minimumRIR: String) -> String? {
        if reasons.contains(.returningAfterBreak) { return "It has been a while since your last session." }
        if reasons.contains(.lastSessionNearFailure) { return "Last session ended close to failure." }
        if reasons.contains(.repsFellAtSameLoad) { return "Reps have been dropping at this weight." }
        if reasons.contains(.awaitingSecondCleanSession) { return "One more clean session at this weight before moving up." }
        if reasons.contains(.moderateEffort) { return "Move up once sets feel easier (RIR \(minimumRIR) or more)." }
        // The two limits below end in a hold the person could otherwise never get out of without being told why.
        if reasons.contains(.stepExceedsCap) { return "The next step up is a big jump, so choose your own weight or keep adding reps." }
        if reasons.contains(.lighterWeekDue) { return "A lighter week is due, but the smallest step down is a big change, so choose your own weight." }
        if reasons.contains(.reduceExceedsCap) { return "The smallest step down is a big change, so choose your own weight." }
        return nil
    }
}
