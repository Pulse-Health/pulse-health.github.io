// WatchWidgetData.swift
//
// The time-dependent rules of the Watch widgets, written without SwiftUI and WidgetKit so that they read like the rules they implement:
//   * how the stored WidgetSnapshot is aged to a later moment (the Watch holds no strength data to rebuild it from, unlike the iPhone's
//     `WidgetSnapshotStore.loadForDisplay`);
//   * what the running workout is doing at a moment, from a widget's point of view;
//   * at which moments a timeline needs another entry and how relevant each entry is to the Smart Stack;
//   * the short English texts of the small complications.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import Foundation
import PulseStrengthCore

// MARK: - Aging

/// Brings a stored `WidgetSnapshot` forward to a later moment.
///
/// The Watch receives a snapshot only when the iPhone app publishes one, so a complication can be a few days old. Only what the Watch
/// widgets show and what changes with the calendar is adjusted: the day counters advance, a new week starts empty (a streak survives it
/// only when the week just ended met the goal), a personal record stops being fresh after 24 hours and a running-workout state whose end
/// never arrived is dropped. Per-day cells are cleared on a new week instead of being rebuilt: no Watch widget draws them.
enum WatchSnapshotAging {
    /// A running-workout state this old is treated as over (a Live Activity ends after 8 hours as well).
    static let activeLifetime: TimeInterval = 8 * 3600
    /// How long a personal record counts as fresh, the same 24 hours as `PRSummary.isFresh`.
    static let recordLifetime: TimeInterval = 24 * 3600

    /// `snapshot` as it reads at `date`. On the snapshot's own day (or before it) the day counters and the week stay as they are.
    static func aged(_ snapshot: WidgetSnapshot, to date: Date) -> WidgetSnapshot {
        var result = snapshot
        let calendar = WidgetContext(timeZoneID: snapshot.timeZoneID).calendar
        let from = calendar.startOfDay(for: snapshot.generatedAt)
        let to = calendar.startOfDay(for: date)
        let days = max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
        if days > 0 {
            result.week.daysSinceLastWorkout = snapshot.week.daysSinceLastWorkout.map { $0 + days }
            result.nextUp?.daysSince = snapshot.nextUp?.daysSince.map { $0 + days }
            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start, weekStart > snapshot.week.weekStart {
                startNewWeek(&result, after: snapshot, at: weekStart)
            }
        }
        if let record = snapshot.latestPR {
            result.latestPR?.isFresh = isFresh(record, at: date)
        }
        if snapshot.active != nil, date.timeIntervalSince(snapshot.generatedAt) >= activeLifetime {
            result.active = nil
        }
        return result
    }

    /// True from the moment of the record until 24 hours after it.
    static func isFresh(_ record: PRSummary, at date: Date) -> Bool {
        let age = date.timeIntervalSince(record.achievedAt)
        return age >= 0 && age <= recordLifetime
    }

    /// The week counters of a week that has not had a workout yet. The streak counts the weeks that met the goal; the week that just
    /// ended is the only one known to have met it, so the streak carries over after exactly one week and only if that week did.
    private static func startNewWeek(_ result: inout WidgetSnapshot, after snapshot: WidgetSnapshot, at weekStart: Date) {
        let weeks = Int((weekStart.timeIntervalSince(snapshot.week.weekStart) / (7 * 86_400)).rounded())
        let metGoal = snapshot.week.completed >= snapshot.week.goal
        result.week.weekStart = weekStart
        result.week.completed = 0
        result.week.streakWeeks = (weeks == 1 && metGoal) ? snapshot.week.streakWeeks : 0
        result.week.days = []
        let target = snapshot.weeklySets.totalTarget
        result.weeklySets = WeeklySetsSummary(muscles: [], totalSets: 0, totalTarget: target, setsToGo: target, laggingMuscle: nil)
    }
}

// MARK: - Running workout

/// What the running workout is doing at a moment, from a widget's point of view.
struct WatchLive {
    enum Stage {
        /// No workout is running.
        case idle
        /// A set waits to be logged.
        case logging
        /// The rest countdown is running (or frozen, while the workout is paused).
        case resting
        /// The countdown reached zero and the next set has not been logged.
        case restOver
        /// Every set is logged.
        case complete
    }

    let active: WorkoutSnapshot?
    let stage: Stage

    init(_ active: WorkoutSnapshot?, at date: Date) {
        self.active = active
        guard let active else {
            stage = .idle
            return
        }
        switch active.phase {
        case .complete: stage = .complete
        case .logging: stage = .logging
        case .restOver: stage = .restOver
        case .resting: stage = WatchLive.restRemaining(active, at: date) > 0 ? .resting : .restOver
        }
    }

    var isPaused: Bool { active?.isPaused ?? false }

    /// Seconds of rest left at `date` (0 without a rest); while the workout is paused the frozen value.
    func restRemaining(at date: Date) -> TimeInterval {
        guard let active else { return 0 }
        return WatchLive.restRemaining(active, at: date)
    }

    static func restRemaining(_ active: WorkoutSnapshot, at date: Date) -> TimeInterval {
        if active.isPaused { return Double(max(0, active.restFrozenRemaining ?? 0)) }
        guard let end = active.restEndsAt else { return 0 }
        return max(0, end.timeIntervalSince(date))
    }
}

extension WorkoutSnapshot {
    /// `restStartedAt ... restEndsAt` for the system timer views; nil when the dates are missing or inverted.
    var watchRestInterval: ClosedRange<Date>? {
        guard let end = restEndsAt else { return nil }
        let start = restStartedAt ?? end.addingTimeInterval(-Double(max(restTotalSeconds, 0)))
        guard start < end else { return nil }
        return start...end
    }

    /// A made-up third set of Bench Press for the widget gallery and the placeholders (the preview snapshot has no running workout): 84
    /// seconds left of a two-minute rest when `resting`, otherwise a set waiting to be logged. Never live data.
    static func watchSample(resting: Bool, now: Date) -> WorkoutSnapshot {
        WorkoutSnapshot(
            workoutID: UUID(uuidString: "00000000-0000-4000-8000-0000000000c0") ?? UUID(),
            revision: 1,
            workoutName: "Upper A · Push",
            activeStart: now.addingTimeInterval(-1500),
            isPaused: false,
            elapsedWhenPaused: 0,
            phase: resting ? .resting : .logging,
            exerciseName: "Bench Press",
            exerciseIndex: 0,
            exerciseCount: 6,
            targetExerciseID: UUID(uuidString: "00000000-0000-4000-8000-0000000000c1"),
            targetSetID: UUID(uuidString: "00000000-0000-4000-8000-0000000000c2"),
            setLabel: "Set 3 of 4",
            tracking: .weightReps,
            weightText: "80",
            repsText: "6",
            repsUnit: "reps",
            showsWeight: true,
            restStartedAt: resting ? now.addingTimeInterval(-36) : nil,
            restEndsAt: resting ? now.addingTimeInterval(84) : nil,
            restTotalSeconds: resting ? 120 : 0,
            heartRate: 112,
            volumeText: "2,340",
            loggedSets: 7,
            totalSets: 20,
            nextSetText: "Set 3 · 80 kg × 6",
            nextExerciseName: "Incline Dumbbell Press"
        )
    }
}

// MARK: - Loading

enum WatchSnapshotLoading {
    /// The snapshot the Watch app saved last, or the empty week when the iPhone has not sent one yet (or the extension is not entitled to the
    /// App Group). Unlike the iPhone's `WidgetSnapshotStore.loadForDisplay` it is never rebuilt from strength data, because the Watch has
    /// none; `WatchSnapshotAging` brings it forward instead.
    static func stored(now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshotStore.load() ?? WidgetSnapshot.empty(now: now)
    }
}

// MARK: - Timeline plan

/// The Watch widgets, by the part of the snapshot they show. `kind` is the WidgetKit kind of the widget.
enum WatchWidgetTopic: String, CaseIterable {
    case nextUp
    case goal
    case daysSince
    case start
    case streak
    case weeklySets
    case liftTrend
    case rest
    case restControls
    case logSet
    case record
    case heartRate

    var kind: String { "health.pulse.strength.watch." + rawValue }
}

/// The Smart Stack relevance of one timeline entry (`TimelineEntryRelevance`): `score` ranks the entry against the other entries of the
/// same widget, `duration` is how long it stays relevant (0: until the next entry).
struct WatchRelevance: Equatable {
    var score: Float
    var duration: TimeInterval

    init(_ score: Float, duration: TimeInterval = 0) {
        self.score = score
        self.duration = max(0, duration)
    }
}

/// One planned timeline entry: the snapshot as it reads at `date`.
struct WatchPlannedEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let relevance: WatchRelevance?
}

/// When a widget's timeline wakes up, and how relevant each moment is to the Smart Stack.
///
/// A rest or log card is most relevant while a workout runs (it is what the person needs on the wrist), the Next up card around the hour
/// the person usually trains (`WidgetSnapshot.tomorrow.plannedMinuteOfDay`, the median start time of the latest workouts), a record card for
/// 24 hours after the record and the heart-rate card for a few hours after a session. Entries are added exactly where the content changes by
/// itself: the end of a rest, the end of the record's 24 hours, the edges of the usual-hour window and midnight.
enum WatchTimelinePlan {
    /// The Next up card is relevant from this long before the usual hour ...
    static let usualHourLead: TimeInterval = 45 * 60
    /// ... until this long after it.
    static let usualHourTail: TimeInterval = 90 * 60
    /// How long after a finished session the heart-rate card is worth showing.
    static let heartRateWindow: TimeInterval = 3 * 3600
    /// A timeline longer than this adds nothing the next reload would not.
    static let maximumEntries = 12

    /// The entries from `now` on: one at `now` and one at every later moment the content or its relevance changes.
    static func entries(for topic: WatchWidgetTopic, raw: WidgetSnapshot, now: Date) -> [WatchPlannedEntry] {
        let dates = Array(Set([now] + moments(for: topic, raw: raw, now: now))).sorted()
        return dates.prefix(maximumEntries).map { date in
            let snapshot = WatchSnapshotAging.aged(raw, to: date)
            return WatchPlannedEntry(date: date, snapshot: snapshot, relevance: relevance(for: topic, snapshot: snapshot, at: date))
        }
    }

    /// The moments after `now` at which the widget needs a new entry, in no particular order.
    static func moments(for topic: WatchWidgetTopic, raw: WidgetSnapshot, now: Date) -> [Date] {
        var dates: [Date] = []
        func add(_ date: Date?) {
            if let date, date > now { dates.append(date) }
        }
        func addWorkoutMoments() {
            guard let active = raw.active else { return }
            if !active.isPaused { add(active.restEndsAt) }
            add(raw.generatedAt.addingTimeInterval(WatchSnapshotAging.activeLifetime))
        }
        add(nextMidnight(after: now, in: raw))
        switch topic {
        case .rest, .restControls, .logSet:
            addWorkoutMoments()
        case .nextUp:
            addWorkoutMoments()
            for window in usualWindows(raw, around: now) {
                add(window.lowerBound)
                add(window.upperBound)
            }
        case .record:
            // A record is fresh up to and including 24 hours after it: the card changes one second later.
            add(raw.latestPR?.achievedAt.addingTimeInterval(WatchSnapshotAging.recordLifetime + 1))
        case .heartRate:
            add(raw.lastSession?.finishedAt.addingTimeInterval(heartRateWindow))
        case .goal, .daysSince, .start, .streak, .weeklySets, .liftTrend:
            break
        }
        return dates
    }

    /// The first local midnight after `now` in the snapshot's time zone.
    static func nextMidnight(after now: Date, in snapshot: WidgetSnapshot) -> Date? {
        let calendar = WidgetContext(timeZoneID: snapshot.timeZoneID).calendar
        return calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)
    }

    /// When the system should ask for a new timeline: a minute after the next midnight, and within 6 hours at the latest.
    static func reloadDate(raw: WidgetSnapshot, now: Date) -> Date {
        let sixHours = now.addingTimeInterval(6 * 3600)
        guard let midnight = nextMidnight(after: now, in: raw) else { return sixHours }
        return min(midnight.addingTimeInterval(60), sixHours)
    }

    /// The window around the usual training hour of today and of tomorrow; none without a typical hour or without a next workout.
    static func usualWindows(_ snapshot: WidgetSnapshot, around date: Date) -> [ClosedRange<Date>] {
        guard let minute = snapshot.tomorrow?.plannedMinuteOfDay, snapshot.nextUp != nil else { return [] }
        let calendar = WidgetContext(timeZoneID: snapshot.timeZoneID).calendar
        let today = calendar.startOfDay(for: date)
        var windows: [ClosedRange<Date>] = []
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let planned = calendar.date(byAdding: .minute, value: min(max(minute, 0), 1439), to: day)
            else { continue }
            windows.append(planned.addingTimeInterval(-usualHourLead)...planned.addingTimeInterval(usualHourTail))
        }
        return windows
    }

    /// The relevance of the entry at `date` (`snapshot` already aged to it); nil for a widget that has no opinion.
    static func relevance(for topic: WatchWidgetTopic, snapshot: WidgetSnapshot, at date: Date) -> WatchRelevance? {
        let live = WatchLive(snapshot.active, at: date)
        switch topic {
        case .rest, .restControls:
            switch live.stage {
            case .resting: return WatchRelevance(100, duration: live.restRemaining(at: date))
            case .restOver: return WatchRelevance(60)
            case .logging, .complete: return WatchRelevance(20)
            case .idle: return WatchRelevance(0)
            }
        case .logSet:
            switch live.stage {
            case .logging, .restOver: return WatchRelevance(100)
            case .resting: return WatchRelevance(40)
            case .complete: return WatchRelevance(10)
            case .idle: return WatchRelevance(0)
            }
        case .nextUp:
            guard snapshot.nextUp != nil, live.stage == .idle, snapshot.week.daysSinceLastWorkout != 0 else { return WatchRelevance(0) }
            // The window ends at its upper bound: the entry at that moment is already outside it.
            if let window = usualWindows(snapshot, around: date).first(where: { $0.lowerBound <= date && date < $0.upperBound }) {
                return WatchRelevance(90, duration: window.upperBound.timeIntervalSince(date))
            }
            return WatchRelevance(10)
        case .record:
            guard let record = snapshot.latestPR, record.isFresh else { return WatchRelevance(0) }
            let end = record.achievedAt.addingTimeInterval(WatchSnapshotAging.recordLifetime)
            return WatchRelevance(90, duration: end.timeIntervalSince(date))
        case .heartRate:
            guard let session = snapshot.lastSession, !session.heartRateBars.isEmpty else { return WatchRelevance(0) }
            let age = date.timeIntervalSince(session.finishedAt)
            return age >= 0 && age < heartRateWindow ? WatchRelevance(60, duration: heartRateWindow - age) : WatchRelevance(5)
        case .goal, .daysSince, .start, .streak, .weeklySets, .liftTrend:
            return nil
        }
    }
}

// MARK: - Texts

/// The short English texts of the Watch widgets. Hand formatted like `WidgetText` and `NumberText`, so they do not depend on a locale.
enum WatchText {
    /// "Push day" gives "Push": the split without its trailing " day".
    static func splitName(_ label: String) -> String {
        let suffix = " day"
        return label.hasSuffix(suffix) ? String(label.dropLast(suffix.count)) : label
    }

    /// "PUSH": the first word of the split in capitals, at most 6 letters (a corner complication has room for little more).
    static func cornerSplit(_ label: String) -> String {
        let name = splitName(label)
        let word = name.split(separator: " ").first.map { String($0) } ?? name
        return String(word.uppercased().prefix(6))
    }

    /// "6 ex · ~55 min", "6 ex" when there is no estimate.
    static func nextUpMeta(exerciseCount: Int, minutes: Int) -> String {
        let exercises = "\(exerciseCount) ex"
        return minutes > 0 ? exercises + " · ~\(minutes) min" : exercises
    }

    /// When the split was last trained: "last 5 days ago", "done yesterday", "done today", "not done yet".
    static func lastTrained(days: Int?) -> String {
        guard let days else { return "not done yet" }
        switch days {
        case ...0: return "done today"
        case 1: return "done yesterday"
        default: return "last \(days) days ago"
        }
    }

    /// The same in a few characters: "5d ago", "yesterday", "today", "new".
    static func lastTrainedShort(days: Int?) -> String {
        guard let days else { return "new" }
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        default: return "\(days)d ago"
        }
    }

    /// The inline split reminder, longest wording first ("Push day · last 5 days ago", "Push · 5d ago", "Push day").
    static func splitReminder(label: String, days: Int?) -> [String] {
        let name = splitName(label)
        return [label + " · " + lastTrained(days: days), name + " · " + lastTrainedShort(days: days), label]
    }

    /// What a set asks for, without the unit of the weight: "80 × 6", "8 reps", "45 s".
    static func work(_ snapshot: WorkoutSnapshot) -> String {
        switch snapshot.tracking {
        case .weightReps: return snapshot.weightText + " × " + snapshot.repsText
        case .repsOnly: return snapshot.repsText + " reps"
        case .duration: return snapshot.repsText + " s"
        }
    }

    /// The position of a set in few characters: "Set 3 of 4" gives "3/4" and "Warm-up · Set 1 of 2" gives "Warm-up 1/2".
    static func setTag(_ label: String) -> String {
        let warmup = "Warm-up · "
        let set = "Set "
        var text = label
        if text.hasPrefix(warmup) {
            text = "Warm-up " + text.dropFirst(warmup.count).replacingOccurrences(of: set, with: "")
        } else if text.hasPrefix(set) {
            text = String(text.dropFirst(set.count))
        }
        return text.replacingOccurrences(of: " of ", with: "/")
    }

    /// "6-week streak", "No streak yet".
    static func streak(weeks: Int) -> String {
        weeks > 0 ? "\(weeks)-week streak" : "No streak yet"
    }

    /// "3d" for a count of days, "–" for none.
    static func daysShort(_ days: Int?) -> String {
        guard let days else { return "–" }
        return "\(max(0, days))d"
    }

    /// "Last workout 3 days ago", "Last workout today", "No workouts yet".
    static func lastWorkout(days: Int?) -> String {
        guard let days else { return "No workouts yet" }
        switch days {
        case ...0: return "Last workout today"
        case 1: return "Last workout yesterday"
        default: return "Last workout \(days) days ago"
        }
    }

    /// How long ago a record was set, in whole days and never less than one: "1d ago", "3d ago".
    static func recordAge(from achievedAt: Date, to date: Date) -> String {
        let days = Int(max(0, date.timeIntervalSince(achievedAt)) / 86_400)
        return "\(max(1, days))d ago"
    }
}

// MARK: - Gauges

/// The 0...1 values of the gauges.
enum WatchGauge {
    /// The share of a week since a split was last trained: full after 7 days, and for a split that was never trained.
    static func splitRecovery(daysSince: Int?) -> Double {
        guard let daysSince else { return 1 }
        return min(1, max(0, Double(daysSince) / 7))
    }

    /// `value` out of `total`, clamped to 0...1 (0 when there is no total).
    static func fraction(_ value: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(total)))
    }
}
#endif
