// HomeFormatting.swift
//
// Text and date helpers of the Home Screen widgets that WidgetText (Common) does not cover: relative days in running text, a session's
// volume, the weekday of a date in the snapshot's time zone, and the seven days of a week. English and locale independent, like WidgetText.

#if os(iOS)
import Foundation
import PulseStrengthCore

enum HomeText {
    /// "6 exercises · ~55 min" ("6 exercises" for a template without a time estimate).
    static func planDetail(exerciseCount: Int, estimatedMinutes: Int) -> String {
        let exercises = WidgetText.exercises(exerciseCount)
        guard estimatedMinutes > 0 else { return exercises }
        return exercises + " · " + WidgetText.minutes(estimatedMinutes)
    }

    /// The same for VoiceOver: "6 exercises, about 55 minutes".
    static func spokenPlanDetail(exerciseCount: Int, estimatedMinutes: Int) -> String {
        let exercises = WidgetText.exercises(exerciseCount)
        guard estimatedMinutes > 0 else { return exercises }
        return exercises + ", about " + (estimatedMinutes == 1 ? "1 minute" : "\(estimatedMinutes) minutes")
    }

    /// "Last done 5 days ago", "Last done yesterday", "Not done yet".
    static func lastDone(daysSince: Int?) -> String {
        guard let daysSince else { return "Not done yet" }
        return "Last done " + WidgetText.daysAgo(daysSince).lowercased()
    }

    /// "today", "yesterday", "5d ago"; nil when there is no date (never done).
    static func sinceShort(daysSince: Int?) -> String? {
        guard let daysSince else { return nil }
        switch daysSince {
        case ...0: return "today"
        case 1: return "yesterday"
        default: return "\(daysSince)d ago"
        }
    }

    /// A session's volume as a value and a unit: 8400 kg is ("8.4", "t"), 640 kg is ("640", "kg").
    static func volume(kg: Double) -> (value: String, unit: String) {
        if kg < 1000 { return (NumberText.thousands(kg), "kg") }
        return (NumberText.kg((kg / 100).rounded() / 10), "t")
    }

    /// The unit of `volume(kg:)` spelled out for VoiceOver.
    static func spokenVolumeUnit(_ unit: String) -> String {
        unit == "t" ? "tonnes" : "kilograms"
    }

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    /// "1 session" / "7 sessions".
    static func sessions(_ count: Int) -> String {
        count == 1 ? "1 session" : "\(count) sessions"
    }

    /// "1 rep" / "6 reps".
    static func reps(_ count: Int) -> String {
        count == 1 ? "1 rep" : "\(count) reps"
    }

    /// How a muscle group's recovery reads in a sentence.
    static func spoken(_ status: FreshnessStatus) -> String {
        switch status {
        case .ready: return "ready to train"
        case .recovering: return "still recovering"
        case .worked: return "just worked"
        }
    }

    /// How a muscle group's weekly sets compare with the target range, in a sentence.
    static func spoken(_ status: SetsStatus) -> String {
        switch status {
        case .under: return "below target"
        case .onTarget: return "on target"
        case .over: return "above target"
        }
    }
}

enum HomeDates {
    private static let weekdayAbbreviations = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Monday first, the order of `WeekSummary.days`.
    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// A Gregorian calendar in the time zone the snapshot buckets its days in.
    static func gregorian(in timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar
    }

    /// Local midnights between `date` and `now`: 23:50 yesterday is 1 day ago, a date in the future is 0 (the rule of the snapshot). The widgets
    /// pass the snapshot's `generatedAt` as `now`: every day count inside the snapshot is relative to it, the store rebuilds the snapshot on a new
    /// day, and the views then depend on the snapshot alone, whatever the wall clock says in a preview.
    static func daysBetween(_ date: Date, and now: Date, timeZoneID: String) -> Int {
        let calendar = gregorian(in: timeZoneID)
        let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
        return max(0, components.day ?? 0)
    }

    /// "Mon" ... "Sun" for the day of `date` in the snapshot's time zone.
    static func weekday(of date: Date, timeZoneID: String) -> String {
        let index = gregorian(in: timeZoneID).component(.weekday, from: date) - 1
        return weekdayAbbreviations[min(max(index, 0), 6)]
    }

    /// The seven cells of `week`, Monday first: the snapshot's own, or empty ones while the snapshot has none (the empty snapshot).
    static func weekDays(of week: WeekSummary) -> [DayCell] {
        if week.days.count == 7 { return week.days }
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return letters.indices.map { index in
            DayCell(date: week.weekStart.addingTimeInterval(Double(index) * 86_400), letter: letters[index])
        }
    }
}
#endif
