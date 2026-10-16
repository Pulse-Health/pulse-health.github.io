import Foundation

/// What the host adds to the strength data when it builds a `WidgetSnapshot` (widgets/SPEC.md section 2).
public struct WidgetContext: Equatable, Sendable {
    /// Workouts per week the user aims for, 1...7.
    public var weeklyGoal: Int
    /// Latest body mass from Health, nil when unknown.
    public var bodyweightKg: Double?
    /// Readiness from the wider Pulse app; nil in the standalone build.
    public var readiness: ReadinessSummary?
    /// Training partners from the wider Pulse app; empty in the standalone build.
    public var partners: [PartnerWeek]
    /// The running workout (the Live Activity content), nil when none.
    public var active: WorkoutSnapshot?
    /// IANA identifier of the time zone that defines the day and week buckets.
    public var timeZoneID: String

    public static let defaultWeeklyGoal = 4

    public init(
        weeklyGoal: Int = WidgetContext.defaultWeeklyGoal,
        bodyweightKg: Double? = nil,
        readiness: ReadinessSummary? = nil,
        partners: [PartnerWeek] = [],
        active: WorkoutSnapshot? = nil,
        timeZoneID: String = TimeZone.current.identifier
    ) {
        self.weeklyGoal = min(7, max(1, weeklyGoal))
        self.bodyweightKg = bodyweightKg
        self.readiness = readiness
        self.partners = partners
        self.active = active
        self.timeZoneID = timeZoneID
    }

    /// The time zone named by `timeZoneID` (UTC when the identifier is unknown).
    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)! }

    /// A calendar for the day and week buckets: Gregorian, Monday first, in `timeZone`.
    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}
