import Foundation
@testable import PulseStrengthCore

/// Builders for the widget snapshot tests: dates in a named time zone, finished workouts, templates and plans with fixed ids.
enum WidFix {
    /// 2026-10-16T09:41:00Z, a Friday: the `now` of the demo data and of the golden file.
    static let now = Date(timeIntervalSince1970: 1_792_143_660)

    static func context(_ zone: String = "UTC", goal: Int = 4, bodyweightKg: Double? = nil) -> WidgetContext {
        WidgetContext(weeklyGoal: goal, bodyweightKg: bodyweightKg, timeZoneID: zone)
    }

    /// The moment of a civil date and time in `zone`.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0, zone: String = "UTC") -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    static func uuid(_ n: Int) -> UUID { SvcSyncFix.uuid(n) }

    // MARK: Finished workouts

    static func set(_ kg: Double, _ reps: Int, _ type: SetType = .normal, at loggedAt: Date? = nil) -> CompletedSet {
        CompletedSet(type: type, weightKg: kg, reps: reps, loggedAt: loggedAt)
    }

    /// A completed exercise of the library with the best Epley estimate of its working sets as `bestE1RM` unless `best` says otherwise.
    static func lift(_ exerciseID: String, _ sets: [CompletedSet], best: Double? = nil, n: Int = 0) -> CompletedExercise {
        SvcDataFix.entry(exerciseID, sets, best: best, n: n)
    }

    static func workout(
        _ n: Int,
        _ name: String = "Upper A · Push",
        at finishedAt: Date,
        templateID: UUID? = nil,
        durationSeconds: Int = 3_000,
        volumeKg: Double = 1_000,
        exercises: [CompletedExercise] = [],
        muscles: [MuscleSets] = [],
        records: [PersonalRecord] = [],
        heartRate: [HeartRateSample]? = nil,
        startedAt: Date? = nil
    ) -> CompletedWorkout {
        CompletedWorkout(
            id: uuid(n),
            name: name,
            templateID: templateID,
            startedAt: startedAt ?? finishedAt.addingTimeInterval(-Double(durationSeconds)),
            finishedAt: finishedAt,
            durationSeconds: durationSeconds,
            volumeKg: volumeKg,
            loggedSets: exercises.reduce(0) { $0 + $1.sets.count },
            averageHeartRate: nil,
            averageRIR: nil,
            exercises: exercises,
            personalRecords: records,
            muscleSets: muscles,
            heartRateSeries: heartRate
        )
    }

    /// A workout `daysAgo` days before `now`, at the same time of day.
    static func workout(_ n: Int, _ name: String = "Upper A · Push", daysAgo: Double, templateID: UUID? = nil, volumeKg: Double = 1_000) -> CompletedWorkout {
        workout(n, name, at: now.addingTimeInterval(-daysAgo * 86_400), templateID: templateID, volumeKg: volumeKg)
    }

    // MARK: Templates and plans

    static func entry(_ exerciseID: String, _ sets: [PlannedSet], rest: Int = 90) -> TemplateEntry {
        TemplateEntry(exercise: ExerciseLibrary.exercise(id: exerciseID)!, plannedSets: sets, restSeconds: rest)
    }

    static func planned(_ count: Int, _ kg: Double, _ reps: Int, repsMax: Int? = nil) -> [PlannedSet] {
        Array(repeating: PlannedSet(weightKg: kg, reps: reps, repsMax: repsMax), count: count)
    }

    static func template(_ n: Int, _ name: String, _ entries: [TemplateEntry] = [], last: Date? = nil) -> WorkoutTemplate {
        WorkoutTemplate(id: uuid(1_000 + n), name: name, entries: entries, lastPerformed: last)
    }

    static func plan(_ templates: [WorkoutTemplate], name: String = "Upper / Lower", nextIndex: Int = 0, daysPerWeek: Int? = nil, active: Bool = true) -> WorkoutPlan {
        WorkoutPlan(id: uuid(3_000), name: name, templateIDs: templates.map { $0.id }, nextIndex: nextIndex, daysPerWeek: daysPerWeek, isActive: active)
    }

    // MARK: Snapshots

    static func snapshot(_ data: StrengthData, context: WidgetContext = WidFix.context(), now: Date = WidFix.now) -> WidgetSnapshot {
        WidgetSnapshotBuilder.build(data: data, context: context, now: now)
    }

    static func snapshot(history: [CompletedWorkout], templates: [WorkoutTemplate] = [], context: WidgetContext = WidFix.context(), now: Date = WidFix.now) -> WidgetSnapshot {
        snapshot(StrengthData(templates: templates, history: history), context: context, now: now)
    }
}

extension CompletedWorkout {
    /// The workout with `exercises` and the set count that goes with them.
    func with(exercises: [CompletedExercise]) -> CompletedWorkout {
        var copy = self
        copy.exercises = exercises
        copy.loggedSets = exercises.reduce(0) { $0 + $1.sets.count }
        return copy
    }

    /// The workout with `muscles` as its sets per muscle group.
    func with(muscles: [MuscleSets]) -> CompletedWorkout {
        var copy = self
        copy.muscleSets = muscles
        return copy
    }
}
