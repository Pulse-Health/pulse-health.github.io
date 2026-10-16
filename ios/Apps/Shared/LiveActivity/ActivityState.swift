// ActivityState.swift
//
// What the Live Activity draws for a snapshot: which Lock Screen card and which compact Dynamic Island mode (the priorities of
// widgets/SPEC.md section 1 and LA-01...LA-10), plus the short texts and the spoken labels of the live moments. Pure functions of the
// snapshot, so the snapshot tests can assert the priorities without drawing anything.

#if os(iOS)
import Foundation
import PulseStrengthCore

// MARK: - Lock Screen card

/// The Lock Screen card to draw; the first matching case wins.
enum LockScreenLayout: Equatable {
    /// LA-05: the workout is finished (`finish`), four stat tiles.
    case finish
    /// LA-01: a record was just logged (`moment`), the gold banner above a compact rest / logging line.
    case moment
    /// LA-04: resting with a suggestion (`coachTip`).
    case coachTip
    /// LA-02: logging a set of a superset.
    case superset
    /// LA-03: logging a barbell set, the plates beside the Log set button.
    case plates
    /// Logging, resting, rest over and complete as before.
    case standard
}

// MARK: - Compact Dynamic Island

/// What the compact (and minimal) island shows. The priority of widgets/SPEC.md section 1: a record, then the rest countdown, then the
/// superset, then plain logging (leading set dots, trailing heart rate or the elapsed clock).
enum IslandCompactMode: Equatable {
    /// LA-07: the trophy and a gold "PR".
    case record
    /// The draining ring and the countdown ("Go" when the rest is over).
    case rest
    /// LA-09: the current member's tag ("A2") and the round ("2/3").
    case superset
    /// LA-08 / LA-10: the set dots and the heart rate (or the elapsed clock).
    case logging
    /// Every set is logged, or the workout has no set; the finished workout.
    case complete
}

extension WorkoutSnapshot {
    /// The card for `phase` (`displayPhase`, so a stale rest already counts as over).
    func lockLayout(phase: SnapshotPhase) -> LockScreenLayout {
        if finish != nil { return .finish }
        if moment != nil { return .moment }
        switch phase {
        case .resting:
            return coachTip != nil ? .coachTip : .standard
        case .logging:
            if let superset = superset, !superset.members.isEmpty { return .superset }
            return plates != nil ? .plates : .standard
        case .restOver, .complete:
            return .standard
        }
    }

    func compactMode(phase: SnapshotPhase) -> IslandCompactMode {
        if finish != nil { return .complete }
        if moment != nil { return .record }
        switch phase {
        case .resting, .restOver:
            return .rest
        case .complete:
            return .complete
        case .logging:
            if let superset = superset, !superset.members.isEmpty { return .superset }
            return .logging
        }
    }

    /// Logged and total sets of the shown exercise for the compact dots; nil when the snapshot does not say (an older payload).
    var setProgress: (done: Int, total: Int)? {
        guard let total = exerciseSetCount, total > 0 else { return nil }
        return (min(max(exerciseDoneSets ?? 0, 0), total), total)
    }

    /// "Log set", or "Log A2" while a superset is running.
    var logTitle: String {
        if let tag = superset?.currentMember?.tag { return "Log " + tag }
        return "Log set"
    }

    /// The spoken name of the Log button.
    var logSpokenTitle: String {
        if let tag = superset?.currentMember?.tag { return "Log set " + tag }
        return "Log set"
    }

    /// The next set for the StandBy layout: ("Next: set 4", "82.5 kg × 6") from "Set 4 · 82.5 kg × 6". Without a pending set the text
    /// stands alone ("All sets logged").
    var benchNext: (title: String, detail: String?) {
        guard targetSetID != nil else { return (nextSetText, nil) }
        let parts = nextSetText.components(separatedBy: " \u{00B7} ")
        guard parts.count >= 2 else { return ("Next: " + nextSetText, nil) }
        return ("Next: " + parts[0].lowercased(), parts.dropFirst().joined(separator: " \u{00B7} "))
    }
}

// MARK: - Record

extension PRMoment {
    /// "85 × 5"
    var workText: String {
        weightText + " \u{00D7} " + repsText
    }

    /// "e1RM +4", or just "e1RM" when the estimate did not rise.
    var deltaText: String {
        deltaKg > 0 ? "e1RM +" + String(deltaKg) : "e1RM"
    }

    var spokenText: String {
        var sentence = "New personal record: " + exerciseName + ", " + weightText + " kilograms for " + repsText + " reps."
        if estimated1RM > 0 {
            sentence += " Estimated one-rep max " + String(estimated1RM) + " kilograms"
            sentence += deltaKg > 0 ? ", up " + String(deltaKg) + "." : "."
        }
        return sentence
    }
}

// MARK: - Superset

extension SupersetBrief {
    /// The member the Log button logs.
    var currentMember: SupersetMember? {
        members.first(where: { $0.isCurrent })
    }

    /// "Superset A · round 2/3"
    var chipText: String {
        "Superset " + label + " \u{00B7} round " + compactRound
    }

    var spokenChip: String {
        "Superset " + label + ", round " + String(round) + " of " + String(rounds)
    }

    /// "2/3"
    var compactRound: String {
        String(round) + "/" + String(rounds)
    }

    /// "A2" for the compact island; the group's letter when no member is marked current.
    var compactTag: String {
        currentMember?.tag ?? label
    }
}

extension SupersetMember {
    /// "A2, Triceps Pushdown, 25 by 12, up next"
    var spokenRow: String {
        var sentence = tag + ", " + name
        if !detail.isEmpty {
            sentence += ", " + detail.replacingOccurrences(of: "\u{00D7}", with: "by")
        }
        sentence += isDone ? ", done" : (isCurrent ? ", up next" : ", waiting")
        return sentence
    }
}

// MARK: - Plates

extension PlateBrief {
    /// "20 + 10 + 2.5", or "Bar only" without plates.
    var displaySummary: String {
        if !summary.isEmpty { return summary }
        if perSide.isEmpty { return "Bar only" }
        return perSide.map { NumberText.kg($0) }.joined(separator: " + ")
    }

    /// "per side", with what the plates cannot make up, or the bar for a bare bar.
    var caption: String {
        if perSide.isEmpty { return NumberText.kg(barKg) + " kg bar" }
        if leftoverKg > 0.004 { return "per side \u{00B7} " + NumberText.kg(leftoverKg) + " kg short" }
        return "per side"
    }

    var spokenText: String {
        let bar = NumberText.kg(barKg) + " kilogram bar"
        if perSide.isEmpty { return "No plates, just the " + bar + "." }
        var sentence = "Per side: " + ActivitySpeech.list(perSide.map { NumberText.kg($0) }) + " kilogram plates on a " + bar + "."
        if leftoverKg > 0.004 {
            sentence += " " + NumberText.kg(leftoverKg) + " kilograms short per side."
        }
        return sentence
    }
}

/// Helpers for the spoken labels.
enum ActivitySpeech {
    /// "20", "20 and 10", "20, 10 and 2.5".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

// MARK: - Coach tip

extension CoachTipBrief {
    /// The tip without a leading "Coach:"; the card draws that label itself.
    var bodyText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("coach:") else { return trimmed }
        return String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var applySpokenTitle: String {
        "Use " + NumberText.kg(suggestedWeightKg) + " kilograms for the next set"
    }

    var spokenText: String {
        "Coach tip. " + title + " " + subtitle + ". " + bodyText
    }
}

// MARK: - Finish

extension FinishBrief {
    /// "Upper A · Push done"
    var title: String {
        (workoutName.isEmpty ? "Workout" : workoutName) + " done"
    }

    /// "PR" for one record, "PRs" otherwise.
    var recordLabel: String {
        personalRecordCount == 1 ? "PR" : "PRs"
    }

    var spokenText: String {
        var sentence = (workoutName.isEmpty ? "Workout" : workoutName) + " finished. "
        sentence += String(durationMinutes) + (durationMinutes == 1 ? " minute, " : " minutes, ")
        sentence += String(sets) + (sets == 1 ? " set, " : " sets, ")
        sentence += volumeText + " tonnes, "
        sentence += String(personalRecordCount) + (personalRecordCount == 1 ? " personal record." : " personal records.")
        if savedToHealth { sentence += " Saved to Health." }
        return sentence
    }
}
#endif
