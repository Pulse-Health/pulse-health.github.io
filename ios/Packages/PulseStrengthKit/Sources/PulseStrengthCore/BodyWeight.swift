import Foundation

// MARK: - Entry

/// One weigh-in: the user's body weight on a day.
///
/// Body weight is kept in kilograms like every other weight of the feature. It is separate from the weights of the
/// logged sets (`LoggedSet.weightKg`), which are loads on the bar.
public struct BodyWeightEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kg: Double

    public init(id: UUID = UUID(), date: Date, kg: Double) {
        self.id = id
        self.date = date
        self.kg = kg
    }
}

// MARK: - Rules

/// What counts as a body weight, and how typed text becomes one.
public enum BodyWeightRules {
    /// The lightest body weight that is accepted (kg).
    public static let minimumKg: Double = 20
    /// The heaviest body weight that is accepted (kg).
    public static let maximumKg: Double = 500

    /// `kg` rounded to 0.1, or nil when it is not a plausible body weight (NaN, infinite, outside `minimumKg...maximumKg`).
    public static func normalised(_ kg: Double) -> Double? {
        guard kg.isFinite else { return nil }
        let rounded = (kg * 10).rounded() / 10
        guard rounded >= minimumKg, rounded <= maximumKg else { return nil }
        return rounded
    }

    /// The body weight in typed text: "82.5", "82,5", " 82.5 kg ". nil for anything else (empty text, two separators,
    /// letters other than a trailing "kg", a value outside the accepted range).
    public static func parse(_ text: String) -> Double? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasSuffix("kg") {
            trimmed = String(trimmed.dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return nil }
        // Digits and at most one decimal separator ("." or ","). Double("0x50"), "inf" and "nan" are never reached.
        let separators = trimmed.filter { $0 == "." || $0 == "," }.count
        guard separators <= 1, trimmed.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return normalised(value)
    }
}

// MARK: - Reminder preferences

/// How often the app asks the user to update their weight.
public enum WeighInInterval: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case weekly
    case everyTwoWeeks
    case monthly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .weekly: return "Every week"
        case .everyTwoWeeks: return "Every 2 weeks"
        case .monthly: return "Every month"
        }
    }

    /// `date` moved forward by `count` intervals (calendar arithmetic, so the wall-clock time survives a DST change).
    /// A month is added to the reference date itself each time, so the 31st does not drift to the 28th for good.
    public func advance(_ date: Date, by count: Int = 1, calendar: Calendar) -> Date? {
        switch self {
        case .weekly: return calendar.date(byAdding: .day, value: 7 * count, to: date)
        case .everyTwoWeeks: return calendar.date(byAdding: .day, value: 14 * count, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: count, to: date)
        }
    }
}

/// The user's choices for the weigh-in reminder. Off until the user turns it on.
public struct WeighInPreferences: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var interval: WeighInInterval
    /// Time of day of the reminder (0...23 and 0...59).
    public var hour: Int
    public var minute: Int
    /// When the reminder was last turned on: the first reminder counts from here while there is no weigh-in yet.
    public var enabledAt: Date?

    public init(
        isEnabled: Bool = false,
        interval: WeighInInterval = .weekly,
        hour: Int = 8,
        minute: Int = 0,
        enabledAt: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.interval = interval
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.enabledAt = enabledAt
    }

    // A missing key reads as its default, so a file written by an older version keeps the choices it does contain.
    private enum CodingKeys: String, CodingKey {
        case isEnabled, interval, hour, minute, enabledAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
            interval: try container.decodeIfPresent(WeighInInterval.self, forKey: .interval) ?? .weekly,
            hour: try container.decodeIfPresent(Int.self, forKey: .hour) ?? 8,
            minute: try container.decodeIfPresent(Int.self, forKey: .minute) ?? 0,
            enabledAt: try container.decodeIfPresent(Date.self, forKey: .enabledAt)
        )
    }

    /// Turns the reminder on or off. Turning it on from off remembers `now` as the start of the first interval.
    public mutating func setEnabled(_ enabled: Bool, now: Date) {
        if enabled, !isEnabled { enabledAt = now }
        isEnabled = enabled
    }
}

// MARK: - Schedule

/// When the weigh-in reminder is due and when its notifications fire. Pure: the caller passes the clock and the calendar.
///
/// The reminder is rolling: it counts from the latest weigh-in (or, before the first one, from the moment the reminder was
/// turned on) and fires one interval later at the chosen time of day. Logging a weight therefore moves the next reminder out,
/// and nobody is reminded the day after they weighed in. When the user ignores a reminder, the next one comes one interval
/// later, not the next morning.
public enum WeighInSchedule {
    /// How many future reminders are kept scheduled with the system, so a user who ignores them and does not open the app
    /// still hears from it a few times before it goes quiet.
    public static let maximumReminders = 3

    /// When the weigh-in is (or was) due: one interval after the latest weigh-in, at the chosen time of day.
    /// nil while the reminder is off, or when there is neither a weigh-in nor a start date to count from.
    public static func dueDate(lastWeighIn: Date?, preferences: WeighInPreferences, calendar: Calendar) -> Date? {
        guard preferences.isEnabled, let reference = lastWeighIn ?? preferences.enabledAt else { return nil }
        guard let moved = preferences.interval.advance(reference, calendar: calendar) else { return nil }
        return atReminderTime(moved, preferences: preferences, calendar: calendar)
    }

    /// True when the app should ask for a weight now: the reminder is on and there is no weigh-in yet, or the interval
    /// since the latest one is over.
    public static func isDue(lastWeighIn: Date?, preferences: WeighInPreferences, now: Date, calendar: Calendar) -> Bool {
        guard preferences.isEnabled else { return false }
        guard lastWeighIn != nil else { return true }
        guard let due = dueDate(lastWeighIn: lastWeighIn, preferences: preferences, calendar: calendar) else { return false }
        return now >= due
    }

    /// The next notification times after `now`, soonest first, at most `count` (and `maximumReminders`).
    /// Empty while the reminder is off.
    ///
    /// The first is the due date when that is still ahead. When it has passed, the series continues one interval at a
    /// time from it. Without a due date (no weigh-in and no start date) it starts at the next time of day.
    public static func reminders(
        lastWeighIn: Date?,
        preferences: WeighInPreferences,
        now: Date,
        calendar: Calendar,
        count: Int = WeighInSchedule.maximumReminders
    ) -> [Date] {
        guard preferences.isEnabled else { return [] }
        let wanted = min(max(count, 0), maximumReminders)
        guard wanted > 0 else { return [] }

        guard let due = dueDate(lastWeighIn: lastWeighIn, preferences: preferences, calendar: calendar) else {
            guard let first = nextTimeOfDay(after: now, preferences: preferences, calendar: calendar) else { return [] }
            return series(from: first, interval: preferences.interval, now: now, wanted: wanted, calendar: calendar)
        }
        return series(from: due, interval: preferences.interval, now: now, wanted: wanted, calendar: calendar)
    }

    // MARK: Helpers

    /// `due`, `due + 1 interval`, ... keeping only the dates after `now`. Every date is counted from `due` (not from the
    /// previous one) so that a month-end date does not drift.
    private static func series(from due: Date, interval: WeighInInterval, now: Date, wanted: Int, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var step = 0
        // Ten years of weekly steps at most, however old the latest weigh-in is.
        while result.count < wanted, step < 600 {
            guard let date = interval.advance(due, by: step, calendar: calendar) else { break }
            if date > now { result.append(date) }
            step += 1
        }
        return result
    }

    private static func atReminderTime(_ date: Date, preferences: WeighInPreferences, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: date)
    }

    private static func nextTimeOfDay(after date: Date, preferences: WeighInPreferences, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.hour = preferences.hour
        components.minute = preferences.minute
        components.second = 0
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
    }
}

// MARK: - Changes to the stored data

public extension StrengthData {
    /// The newest weigh-in (by date).
    var latestBodyWeight: BodyWeightEntry? { bodyWeights.first }

    /// True when the app should ask for a weight now (see `WeighInSchedule.isDue`).
    func isWeighInDue(now: Date, calendar: Calendar = .current) -> Bool {
        WeighInSchedule.isDue(lastWeighIn: latestBodyWeight?.date, preferences: weighIn, now: now, calendar: calendar)
    }

    /// Stores a weigh-in, newest first (an entry with the same id is replaced). The weight is rounded to 0.1.
    /// Returns the stored entry, or nil (nothing changed) when `kg` is not a plausible body weight.
    @discardableResult
    mutating func recordBodyWeight(kg: Double, date: Date, id: UUID = UUID()) -> BodyWeightEntry? {
        guard let normalised = BodyWeightRules.normalised(kg) else { return nil }
        let entry = BodyWeightEntry(id: id, date: date, kg: normalised)
        bodyWeights.removeAll { $0.id == id }
        let index = bodyWeights.firstIndex { $0.date <= date } ?? bodyWeights.endIndex
        bodyWeights.insert(entry, at: index)
        return entry
    }

    /// Removes a weigh-in; false when there is none with that id.
    @discardableResult
    mutating func deleteBodyWeight(id: UUID) -> Bool {
        let before = bodyWeights.count
        bodyWeights.removeAll { $0.id == id }
        return bodyWeights.count != before
    }
}
