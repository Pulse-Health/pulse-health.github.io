import Foundation

/// Day, week and month arithmetic in the snapshot's time zone (widgets/SPEC.md section 2, "Calendar").
///
/// A date is reduced to a day number: the days since 1970-01-01 of its local date. Everything that counts days, weeks or months works on
/// those integers, so the buckets stay exact across a daylight saving change (a day may have 23 or 25 hours) and are the same as the
/// Kotlin implementation's, which counts on `LocalDate`. Only turning a day number back into the start of that day needs the calendar.
struct WidgetCalendar {
    private let timeZone: TimeZone
    private let calendar: Calendar

    init(context: WidgetContext) {
        timeZone = context.timeZone
        calendar = context.calendar
    }

    // MARK: Dates and day numbers

    /// The day number of the local date of `date`. A date that is not finite counts as 1970-01-01.
    func day(of date: Date) -> Int {
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        guard local.isFinite, abs(local) < 1e15 else { return 0 }
        return Int((local / 86_400).rounded(.down))
    }

    /// The first moment of local day `day` (an hour later than midnight where daylight saving skips midnight).
    func startOfDay(_ day: Int) -> Date {
        let civil = Self.civil(fromDay: day)
        var components = DateComponents()
        components.year = civil.year
        components.month = civil.month
        components.day = civil.day
        components.hour = 12
        let noon = calendar.date(from: components) ?? Date(timeIntervalSince1970: Double(day) * 86_400 + 43_200)
        return calendar.startOfDay(for: noon)
    }

    /// Minutes after local midnight of `date` (0...1439).
    func minuteOfDay(_ date: Date) -> Int {
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        guard local.isFinite, abs(local) < 1e15 else { return 0 }
        let secondsIntoDay = local - (local / 86_400).rounded(.down) * 86_400
        return min(1_439, Int(secondsIntoDay) / 60)
    }

    /// The calendar days from `earlier` to `later`: the local midnights crossed (23:50 yesterday is 1 day ago). A `later` that is not
    /// after `earlier` counts as 0.
    func daysBetween(_ earlier: Date, _ later: Date) -> Int {
        max(0, day(of: later) - day(of: earlier))
    }

    // MARK: Weekdays and civil dates (proleptic Gregorian)

    /// 0 for Monday ... 6 for Sunday. Day 0, 1970-01-01, was a Thursday.
    static func weekdayIndex(ofDay day: Int) -> Int {
        ((day + 3) % 7 + 7) % 7
    }

    /// The Monday on or before `day`: the first day of its week.
    static func monday(onOrBefore day: Int) -> Int {
        day - weekdayIndex(ofDay: day)
    }

    /// Year, month (1...12) and day of month of day number `days`.
    static func civil(fromDay days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPart = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPart + 2) / 5 + 1
        let month = monthPart < 10 ? monthPart + 3 : monthPart - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    /// The day number of a civil date.
    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// 28...31.
    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// 1...366.
    static func dayOfYear(ofDay day: Int) -> Int {
        day - dayNumber(year: civil(fromDay: day).year, month: 1, day: 1) + 1
    }

    // MARK: English names

    /// One letter per weekday, Monday first.
    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    /// Weekday names, Monday first.
    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// Month names, January first.
    static let monthNames = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
    ]
}

/// The finished workouts of a snapshot with the local day each one belongs to (the day of its `finishedAt`), computed once.
struct WidgetHistory {
    struct Entry {
        var workout: CompletedWorkout
        var day: Int
    }

    let calendar: WidgetCalendar
    let now: Date
    /// The day number of `now`.
    let today: Int
    /// The Monday of the current week (day number).
    let weekStart: Int
    /// The workouts in the order of `StrengthData.history` (newest first).
    let entries: [Entry]

    init(workouts: [CompletedWorkout], calendar: WidgetCalendar, now: Date) {
        self.calendar = calendar
        self.now = now
        today = calendar.day(of: now)
        weekStart = WidgetCalendar.monday(onOrBefore: today)
        entries = workouts.map { Entry(workout: $0, day: calendar.day(of: $0.finishedAt)) }
    }

    /// The workout with the greatest `finishedAt` (the first one on a tie).
    var latest: Entry? {
        var best: Entry?
        for entry in entries {
            if let current = best, current.workout.finishedAt >= entry.workout.finishedAt { continue }
            best = entry
        }
        return best
    }

    /// The workouts whose day lies in `days`.
    func entries(inDays days: Range<Int>) -> [Entry] {
        entries.filter { days.contains($0.day) }
    }

    /// The workouts of the current week, Monday to Sunday.
    var thisWeek: [Entry] {
        entries(inDays: weekStart..<(weekStart + 7))
    }

    /// Calendar days from `date` to now (0 for a date in the future).
    func daysAgo(_ date: Date) -> Int {
        calendar.daysBetween(date, now)
    }
}
