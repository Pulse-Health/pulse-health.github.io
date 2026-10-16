import Foundation

/// How recently and how much each muscle group was trained (widgets/SPEC.md section 2: freshness, weeklySets, bodyMap).
enum WidgetMuscles {
    /// The four groups that count toward the weekly volume target; arms and core are trained on the side.
    static let majors: [MuscleGroup] = [.chest, .back, .shoulders, .legs]

    /// Weekly sets that each major group should reach, and the total over the four.
    static let setsPerMajor = 12
    static let totalTarget = 48

    // MARK: Freshness

    /// All six groups in `MuscleGroup` order with the days since the latest workout that trained the group (a `muscleSets` entry with
    /// sets); nil when never. Status: nil or 4+ days is ready, 2 or 3 recovering, 0 or 1 worked.
    static func freshness(_ history: WidgetHistory) -> [MuscleFreshness] {
        MuscleGroup.allCases.map { muscle in
            var latest: Date?
            for entry in history.entries where entry.workout.muscleSets.contains(where: { $0.muscle == muscle && $0.sets > 0 }) {
                if let current = latest, current >= entry.workout.finishedAt { continue }
                latest = entry.workout.finishedAt
            }
            let days = latest.map { history.daysAgo($0) }
            let status: FreshnessStatus
            switch days {
            case .none: status = .ready
            case .some(let value) where value >= 4: status = .ready
            case .some(let value) where value >= 2: status = .recovering
            case .some: status = .worked
            }
            return MuscleFreshness(muscle: muscle, daysSince: days, status: status)
        }
    }

    // MARK: Weekly sets

    /// The sets of each group in this week's workouts (the sum of their `muscleSets`).
    static func setsThisWeek(_ history: WidgetHistory) -> [MuscleGroup: Int] {
        var sets: [MuscleGroup: Int] = [:]
        for entry in history.thisWeek {
            for item in entry.workout.muscleSets { sets[item.muscle, default: 0] += item.sets }
        }
        return sets
    }

    /// The weekly target range of a group: 10...14 sets for chest, back, shoulders and legs, 6...10 for arms and core.
    static func target(for muscle: MuscleGroup) -> ClosedRange<Int> {
        majors.contains(muscle) ? 10...14 : 6...10
    }

    /// This week's sets per group against its target. `totalSets` adds the four major groups against 48 (12 each); `laggingMuscle` is the
    /// major with the fewest sets (the first in `MuscleGroup` order on a tie), nil once every major reached 12.
    static func weeklySets(_ sets: [MuscleGroup: Int]) -> WeeklySetsSummary {
        let muscles = MuscleGroup.allCases.map { muscle -> MuscleSetsProgress in
            let count = sets[muscle] ?? 0
            let range = target(for: muscle)
            let status: SetsStatus = count < range.lowerBound ? .under : (count > range.upperBound ? .over : .onTarget)
            return MuscleSetsProgress(muscle: muscle, sets: count, targetLow: range.lowerBound, targetHigh: range.upperBound, status: status)
        }
        let total = majors.reduce(0) { $0 + (sets[$1] ?? 0) }
        var lagging: (muscle: MuscleGroup, sets: Int)?
        for muscle in MuscleGroup.allCases where majors.contains(muscle) {
            let count = sets[muscle] ?? 0
            guard count < setsPerMajor, count < (lagging?.sets ?? Int.max) else { continue }
            lagging = (muscle, count)
        }
        return WeeklySetsSummary(
            muscles: muscles,
            totalSets: total,
            totalTarget: totalTarget,
            setsToGo: max(0, totalTarget - total),
            laggingMuscle: lagging?.muscle
        )
    }

    // MARK: Body map

    /// How much of the week each group had (0 none, 1 up to 4 sets, 2 up to 9, 3 from 10), the groups without a set, and a sentence
    /// about the first major group left out.
    ///
    /// The sentence names that group ("Legs untouched.") and, when a saved template trains it, the one with the most non-warm-up planned
    /// sets of it: " Lower A is next in line." when that template is `nextUp`, else " Try Lower A." (the name up to " ·"). When every
    /// major group was trained: "Every major group has been trained this week."
    static func bodyMap(_ sets: [MuscleGroup: Int], templates: [WorkoutTemplate], nextUp: UUID?) -> BodyMap {
        let levels = MuscleGroup.allCases.map { muscle -> MuscleLevel in
            let count = sets[muscle] ?? 0
            return MuscleLevel(muscle: muscle, level: count == 0 ? 0 : (count < 5 ? 1 : (count < 10 ? 2 : 3)))
        }
        let untouched = MuscleGroup.allCases.filter { (sets[$0] ?? 0) == 0 }
        guard let missing = MuscleGroup.allCases.first(where: { majors.contains($0) && (sets[$0] ?? 0) == 0 }) else {
            return BodyMap(levels: levels, untouched: untouched, message: "Every major group has been trained this week.")
        }
        var message = missing.title + " untouched."
        if let template = templateTraining(missing, in: templates) {
            let name = WidgetText.shortName(of: template.name)
            message += template.id == nextUp ? " \(name) is next in line." : " Try \(name)."
        }
        return BodyMap(levels: levels, untouched: untouched, message: message)
    }

    /// The template with the most non-warm-up planned sets of `muscle` (the first in store order on a tie); nil when none has one.
    private static func templateTraining(_ muscle: MuscleGroup, in templates: [WorkoutTemplate]) -> WorkoutTemplate? {
        var best: (template: WorkoutTemplate, sets: Int)?
        for template in templates {
            let sets = template.entries.filter { $0.exercise.muscle == muscle }
                .reduce(0) { $0 + $1.plannedSets.filter { $0.type != .warmup }.count }
            if sets > (best?.sets ?? 0) { best = (template, sets) }
        }
        return best?.template
    }
}
