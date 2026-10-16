// LockText.swift
//
// The words and figures of the Lock Screen accessory widgets (LS-01...LS-11) and the sentences VoiceOver reads for them. Pure functions of
// the WidgetSnapshot types, hand formatted and English like WidgetText, so a circle, a card and the inline line of one widget always agree
// and nothing here depends on the device's locale.

#if os(iOS)
import Foundation
import PulseStrengthCore

enum LockText {
    /// Characters the inline slot shows before the system cuts the line. The longest line of the design ("Push day · last 5 days ago") has 26.
    static let inlineBudget = 26

    // MARK: Weekly goal (LS-01, LS-09)

    /// "workout" for a goal of one, "workouts" otherwise.
    static func workoutNoun(goal: Int) -> String {
        goal == 1 ? "workout" : "workouts"
    }

    /// "3/4": the centre of the gauge.
    static func goalFraction(_ week: WeekSummary) -> String {
        "\(week.completed)/\(week.goal)"
    }

    /// "3 of 4 workouts this week": the inline line.
    static func weekLine(_ week: WeekSummary) -> String {
        "\(week.completed) of \(week.goal) \(workoutNoun(goal: week.goal)) this week"
    }

    /// "3 of 4 workouts this week. 1 to go." or "4 of 4 workouts this week. Goal reached."
    static func weekSentence(_ week: WeekSummary) -> String {
        if week.completed >= week.goal { return weekLine(week) + ". Goal reached." }
        return weekLine(week) + ". \(week.goal - week.completed) to go."
    }

    // MARK: Days since (LS-02)

    /// "You trained today", "1 day since your last workout", "No workouts yet".
    static func daysSinceSentence(_ days: Int?) -> String {
        guard let days else { return "No workouts yet" }
        switch days {
        case ...0: return "You trained today"
        case 1: return "1 day since your last workout"
        default: return "\(days) days since your last workout"
        }
    }

    // MARK: Week streak (LS-03)

    /// "6 wk".
    static func streakFigure(_ weeks: Int) -> String {
        "\(max(0, weeks)) wk"
    }

    /// "6 weeks in a row at your weekly goal", or what starts a streak.
    static func streakSentence(_ week: WeekSummary) -> String {
        guard week.streakWeeks > 0 else {
            return "No streak yet. Finish \(week.goal) \(workoutNoun(goal: week.goal)) in a week to start one."
        }
        let unit = week.streakWeeks == 1 ? "week" : "weeks"
        return "\(week.streakWeeks) \(unit) in a row at your weekly goal"
    }

    // MARK: Next workout (LS-04, LS-05, LS-10, LS-11)

    /// A template name the way VoiceOver should say it: "Upper A · Push" becomes "Upper A, Push".
    static func spoken(_ name: String) -> String {
        name.replacingOccurrences(of: " · ", with: ", ")
    }

    /// "6 exercises · ~55 min". The minutes are left out when the template has no estimate.
    static func nextUpDetail(_ next: NextUpSummary) -> String {
        guard next.exerciseCount > 0 else { return "No exercises yet" }
        var text = WidgetText.exercises(next.exerciseCount)
        if next.estimatedMinutes > 0 { text += " · " + WidgetText.minutes(next.estimatedMinutes) }
        return text
    }

    /// "Next workout: Upper A, Push. 6 exercises, about 55 minutes."
    static func nextUpSentence(_ next: NextUpSummary) -> String {
        var text = "Next workout: \(spoken(next.name)). \(WidgetText.exercises(next.exerciseCount))"
        if next.estimatedMinutes > 0 { text += ", about \(next.estimatedMinutes) minutes" }
        return text + "."
    }

    /// What the quick start circle says and does: the running workout, the suggested one, or how to get a first one.
    static func quickStartSentence(_ snapshot: WidgetSnapshot) -> String {
        if snapshot.active != nil { return "Open the workout in progress" }
        guard let next = snapshot.nextUp else { return "No workouts yet. Open Pulse Strength to add one." }
        return "Start \(spoken(next.name))"
    }

    /// "Push day · last 5 days ago" (LS-10). When that is longer than the inline slot, the days shrink to "12d ago" and the label is cut,
    /// so the part that changes stays visible.
    static func splitLine(_ next: NextUpSummary) -> String {
        let label = splitLabel(next)
        let suffix = splitSuffix(daysSince: next.daysSince)
        if label.count + 3 + suffix.long.count <= inlineBudget { return label + " · " + suffix.long }
        return clipped(label, to: inlineBudget - 3 - suffix.short.count) + " · " + suffix.short
    }

    /// "Next workout: Push day, last done 5 days ago." for VoiceOver.
    static func splitSentence(_ next: NextUpSummary) -> String {
        "Next workout: \(spoken(splitLabel(next))), \(splitSuffix(daysSince: next.daysSince).spoken)."
    }

    /// "Rest day · back on Sun" (LS-11): why today is a rest day and the weekday of the next session; just the reason when no session is planned.
    static func restLine(_ rest: RestDaySuggestion, tomorrow: TomorrowPlan?) -> String {
        let lead = restLead(rest)
        guard let weekday = tomorrow?.weekday, !weekday.isEmpty else { return lead }
        return lead + " · back on " + String(weekday.prefix(3))
    }

    /// "Rest day. Back on Sunday." for VoiceOver.
    static func restSentence(_ rest: RestDaySuggestion, tomorrow: TomorrowPlan?) -> String {
        let lead = restLead(rest)
        guard let weekday = tomorrow?.weekday, !weekday.isEmpty else { return lead + "." }
        return lead + ". Back on " + weekday + "."
    }

    /// `text` cut to `limit` characters, ending in "…" when it was longer.
    static func clipped(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit - 1))) + "…"
    }

    private static func splitLabel(_ next: NextUpSummary) -> String {
        next.splitLabel.isEmpty ? next.name : next.splitLabel
    }

    /// The words after the "·" of the inline line: the sentence form, a shorter form for a full slot and the spoken form.
    private static func splitSuffix(daysSince: Int?) -> (long: String, short: String, spoken: String) {
        guard let days = daysSince else { return ("not done yet", "new", "not done yet") }
        switch days {
        case ...0: return ("done today", "today", "done today")
        case 1: return ("done yesterday", "yesterday", "done yesterday")
        default: return ("last \(days) days ago", "\(days)d ago", "last done \(days) days ago")
        }
    }

    private static func restLead(_ rest: RestDaySuggestion) -> String {
        rest.reason.isEmpty ? "Rest day" : rest.reason
    }

    // MARK: Weekly sets (LS-06)

    /// "11 to go · legs lagging", "Target reached", or "No sets logged yet" before the first set of the week.
    static func setsDetail(_ sets: WeeklySetsSummary) -> String {
        guard sets.totalSets > 0 else { return "No sets logged yet" }
        var text = sets.setsToGo > 0 ? "\(sets.setsToGo) to go" : "Target reached"
        if let lagging = sets.laggingMuscle { text += " · \(lagging.title.lowercased()) lagging" }
        return text
    }

    /// Share of the weekly target that is done (0 for a target of zero); the meter clamps it to 0...1.
    static func setsFraction(_ sets: WeeklySetsSummary) -> Double {
        sets.totalTarget > 0 ? Double(sets.totalSets) / Double(sets.totalTarget) : 0
    }

    /// "37 of 48 sets this week. 11 to go. Lagging muscle group: legs."
    static func setsSentence(_ sets: WeeklySetsSummary) -> String {
        guard sets.totalSets > 0 else { return "No sets logged this week yet" }
        var text = "\(sets.totalSets) of \(sets.totalTarget) sets this week"
        text += sets.setsToGo > 0 ? ". \(sets.setsToGo) to go" : ". Weekly target reached"
        if let lagging = sets.laggingMuscle { text += ". Lagging muscle group: \(lagging.title.lowercased())" }
        return text + "."
    }

    // MARK: Latest record (LS-07)

    /// "e1RM 99 kg": the estimated one-rep max in whole kilograms, like the record banner of the Live Activity.
    static func prDetail(_ pr: PRSummary) -> String {
        "e1RM " + WidgetText.kg(pr.estimated1RM.rounded())
    }

    /// "Latest record: Bench Press, 85 kilograms for 5 reps. Estimated one-rep max 99 kilograms."
    static func prSentence(_ pr: PRSummary) -> String {
        "Latest record: \(pr.exerciseName), \(NumberText.kg(pr.weightKg)) kilograms for \(repsPhrase(pr.reps)). "
            + "Estimated one-rep max \(NumberText.kg(pr.estimated1RM.rounded())) kilograms."
    }

    // MARK: Overload target (LS-08)

    /// "4 × 6": planned working sets by target reps.
    static func overloadFigure(_ target: OverloadTarget) -> String {
        target.targetSets > 0 ? "\(target.targetSets) × \(target.targetReps)" : "\(target.targetReps) reps"
    }

    /// "82.5 kg · +2.5 vs last". At the same weight the progress is in reps: "80 kg · +1 rep vs last".
    static func overloadDetail(_ target: OverloadTarget) -> String {
        let weight = WidgetText.kg(target.targetWeightKg)
        if abs(target.deltaKg) >= 0.005 { return "\(weight) · \(WidgetText.signed(target.deltaKg)) vs last" }
        let extraReps = target.targetReps - target.lastReps
        if extraReps > 0 { return "\(weight) · +\(extraReps) \(extraReps == 1 ? "rep" : "reps") vs last" }
        return "\(weight) · same as last"
    }

    /// "Today's target: Bench Press, 4 sets of 6 reps at 82.5 kilograms, 2.5 kilograms more than last time."
    static func overloadSentence(_ target: OverloadTarget) -> String {
        let work = target.targetSets > 0 ? "\(target.targetSets) sets of \(repsPhrase(target.targetReps))" : repsPhrase(target.targetReps)
        var text = "Today's target: \(target.exerciseName), \(work) at \(NumberText.kg(target.targetWeightKg)) kilograms"
        let extraReps = target.targetReps - target.lastReps
        if target.deltaKg >= 0.005 {
            text += ", \(NumberText.kg(target.deltaKg)) kilograms more than last time"
        } else if target.deltaKg <= -0.005 {
            text += ", \(NumberText.kg(-target.deltaKg)) kilograms less than last time"
        } else if extraReps > 0 {
            text += ", \(repsPhrase(extraReps)) more than last time"
        } else {
            text += ", the same as last time"
        }
        return text + "."
    }

    private static func repsPhrase(_ reps: Int) -> String {
        reps == 1 ? "1 rep" : "\(reps) reps"
    }
}
#endif
