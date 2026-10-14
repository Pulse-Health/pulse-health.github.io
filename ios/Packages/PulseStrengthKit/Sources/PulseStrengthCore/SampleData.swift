import Foundation

/// Demo templates, finished workouts and personal bests for `seedDemoData` and SwiftUI previews.
///
/// Everything is derived from one set of definitions, so it is consistent: `now` is "today"; "Upper A · Push" was last done 5 days ago;
/// bench sessions exist 5 days ago (W 50×8, W 70×5, 80×6, 80×6, 80×5), 10 days ago (W 50×8, W 70×5, 80×6, 82.5×5, 85×5, the personal
/// record with an estimated 1RM of 99) and 15 days ago (W 50×8, 77.5×6 ×3); "Lower A · Quads" was done 7 days ago and "Upper B · Pull"
/// 3 days ago. The personal bests are the best sets of that history (bench: 85 kg × 5, 10 days ago). Ids are fixed, so repeated calls
/// return equal values.
public enum SampleData {
    // MARK: Public API

    /// The three demo templates: "Upper A · Push", "Lower A · Quads" and "Upper B · Pull" (never performed).
    public static func templates() -> [WorkoutTemplate] {
        [upperPush(), lowerQuads(), upperPull()]
    }

    /// The demo templates with `lastPerformed` taken from the demo history of `now`.
    public static func templates(now: Date) -> [WorkoutTemplate] {
        let finished = history(now: now)
        return templates().map { template in
            var result = template
            result.lastPerformed = finished.first { $0.templateID == template.id }?.finishedAt
            return result
        }
    }

    /// The five demo workouts, newest first: Upper B (3 days ago), Upper A (5), Lower A (7), Upper A (10, bench record), Upper A (15).
    public static func history(now: Date) -> [CompletedWorkout] {
        // Best estimated 1RMs from before the demo window. The bench best is beaten 10 days ago (the one personal record of the
        // demo); the others are already at their level, so no other exercise is flagged.
        var baseline: [String: Double] = [
            "bench": 95, "incline": 38, "ohp": 58.4, "lateral": 12.6, "pushdown": 43, "crossover": 22,
        ]
        var workouts: [CompletedWorkout] = []
        for session in sessionDefinitions().sorted(by: { $0.daysAgo > $1.daysAgo }) {
            workouts.append(makeWorkout(session, now: now, baseline: &baseline))
        }
        return workouts.reversed()
    }

    /// The best set per exercise of the demo history (bench: 85 kg × 5, 10 days ago, estimated 1RM 99).
    public static func personalBests(now: Date) -> [String: PersonalBest] {
        var bests: [String: PersonalBest] = [:]
        for workout in history(now: now).reversed() {
            for entry in workout.exercises where entry.bestE1RM > 0 {
                if entry.bestE1RM > (bests[entry.exerciseID]?.estimated1RM ?? 0) + 1e-9 {
                    let best = bestSet(of: entry.sets)
                    bests[entry.exerciseID] = PersonalBest(
                        exerciseID: entry.exerciseID,
                        estimated1RM: entry.bestE1RM,
                        weightKg: best?.weightKg ?? 0,
                        reps: best?.reps ?? 0,
                        date: workout.finishedAt
                    )
                }
            }
        }
        return bests
    }
}

// MARK: - Templates

private extension SampleData {
    static func upperPush() -> WorkoutTemplate {
        WorkoutTemplate(
            id: fixedID(1, 1),
            name: "Upper A · Push",
            entries: [
                entry(1, "bench", [planned(.warmup, 50, 8), planned(.warmup, 70, 5), planned(.normal, 82.5, 6), planned(.normal, 82.5, 6), planned(.normal, 85, 6)], rest: 150),
                entry(2, "incline", straight(3, 28, 10), rest: 90),
                entry(3, "ohp", straight(3, 45, 8), rest: 120),
                entry(4, "lateral", straight(3, 8, 15), rest: 60, group: "A"),
                entry(5, "pushdown", straight(3, 30, 12), rest: 60, group: "A"),
                entry(6, "crossover", straight(3, 15, 12), rest: 60),
            ]
        )
    }

    static func lowerQuads() -> WorkoutTemplate {
        WorkoutTemplate(
            id: fixedID(1, 2),
            name: "Lower A · Quads",
            entries: [
                entry(11, "squat", [planned(.warmup, 40, 8), planned(.warmup, 60, 5), planned(.normal, 80, 6), planned(.normal, 80, 6), planned(.normal, 80, 6)], rest: 180),
                entry(12, "legpress", straight(3, 140, 10), rest: 120),
                entry(13, "lunge", straight(3, 12, 10), rest: 90),
                entry(14, "legext", straight(3, 45, 12), rest: 75),
                entry(15, "calf", straight(4, 60, 12), rest: 60),
            ]
        )
    }

    static func upperPull() -> WorkoutTemplate {
        WorkoutTemplate(
            id: fixedID(1, 3),
            name: "Upper B · Pull",
            entries: [
                entry(21, "pullup", straight(3, 0, 8), rest: 120),
                entry(22, "brow", [planned(.warmup, 40, 8), planned(.normal, 60, 8), planned(.normal, 60, 8), planned(.normal, 60, 8)], rest: 120),
                entry(23, "pulldown", straight(3, 55, 10), rest: 90),
                entry(24, "crow", straight(3, 50, 10), rest: 90),
                entry(25, "facepull", straight(3, 20, 15), rest: 60),
                entry(26, "curl", straight(3, 30, 10), rest: 75),
            ]
        )
    }

    static func entry(_ number: Int, _ exerciseID: String, _ sets: [PlannedSet], rest: Int, group: String? = nil) -> TemplateEntry {
        TemplateEntry(id: fixedID(2, number), exercise: libraryExercise(exerciseID), plannedSets: sets, restSeconds: rest, supersetGroup: group)
    }

    static func planned(_ type: SetType, _ kg: Double, _ reps: Int) -> PlannedSet {
        PlannedSet(type: type, weightKg: kg, reps: reps)
    }

    static func straight(_ count: Int, _ kg: Double, _ reps: Int) -> [PlannedSet] {
        Array(repeating: planned(.normal, kg, reps), count: count)
    }

    /// The built-in exercise `id`; the fallback only exists so a mistyped id can never crash a preview.
    static func libraryExercise(_ id: String) -> Exercise {
        if let exercise = ExerciseLibrary.exercise(id: id) { return exercise }
        return Exercise(
            id: id, name: id, muscle: .core, equipment: .other,
            defaults: ExerciseDefaults(sets: 3, weightKg: 0, reps: 10, restSeconds: 60)
        )
    }
}

// MARK: - History definitions

private struct SessionDefinition {
    var number: Int
    var name: String
    var templateID: UUID
    var daysAgo: Int
    var minutes: Int
    var averageHeartRate: Int?
    var lines: [(exerciseID: String, sets: [CompletedSet])]
}

private extension SampleData {
    static func warmup(_ kg: Double, _ reps: Int) -> CompletedSet {
        CompletedSet(type: .warmup, weightKg: kg, reps: reps)
    }

    static func work(_ kg: Double, _ reps: Int, rir: Int? = nil) -> CompletedSet {
        CompletedSet(type: .normal, weightKg: kg, reps: reps, rir: rir)
    }

    static func sessionDefinitions() -> [SessionDefinition] {
        let upperA = fixedID(1, 1)
        let lowerA = fixedID(1, 2)
        let upperB = fixedID(1, 3)
        return [
            SessionDefinition(number: 1, name: "Upper B · Pull", templateID: upperB, daysAgo: 3, minutes: 52, averageHeartRate: 124, lines: [
                ("pullup", [work(0, 8, rir: 2), work(0, 8, rir: 2), work(0, 7, rir: 1)]),
                ("brow", [warmup(40, 8), work(60, 8, rir: 3), work(60, 8, rir: 2), work(60, 7, rir: 1)]),
                ("pulldown", [work(55, 10), work(55, 10), work(55, 9)]),
                ("crow", [work(50, 10), work(50, 10), work(50, 10)]),
                ("facepull", [work(20, 15), work(20, 15), work(20, 15)]),
                ("curl", [work(30, 10), work(30, 10), work(30, 9)]),
            ]),
            SessionDefinition(number: 2, name: "Upper A · Push", templateID: upperA, daysAgo: 5, minutes: 49, averageHeartRate: 126, lines: [
                ("bench", [warmup(50, 8), warmup(70, 5), work(80, 6, rir: 3), work(80, 6, rir: 2), work(80, 5, rir: 1)]),
                ("incline", [work(26, 10), work(26, 10), work(26, 9)]),
                ("ohp", [work(45, 8), work(45, 8), work(45, 7)]),
                ("lateral", [work(8, 15), work(8, 15), work(8, 14)]),
                ("pushdown", [work(30, 12), work(30, 12), work(30, 11)]),
                ("crossover", [work(15, 12), work(15, 12), work(15, 11)]),
            ]),
            SessionDefinition(number: 3, name: "Lower A · Quads", templateID: lowerA, daysAgo: 7, minutes: 61, averageHeartRate: 118, lines: [
                ("squat", [warmup(40, 8), warmup(60, 5), work(80, 6, rir: 3), work(80, 6, rir: 2), work(80, 6, rir: 1)]),
                ("legpress", [work(140, 10), work(140, 10), work(140, 10)]),
                ("lunge", [work(12, 10), work(12, 10), work(12, 10)]),
                ("legext", [work(45, 12), work(45, 12), work(45, 12)]),
                ("calf", [work(60, 12), work(60, 12), work(60, 12), work(60, 12)]),
            ]),
            SessionDefinition(number: 4, name: "Upper A · Push", templateID: upperA, daysAgo: 10, minutes: 56, averageHeartRate: 131, lines: [
                ("bench", [warmup(50, 8), warmup(70, 5), work(80, 6, rir: 3), work(82.5, 5, rir: 2), work(85, 5, rir: 1)]),
                ("incline", [work(28, 10), work(30, 8), work(28, 9)]),
                ("ohp", [work(45, 8), work(47.5, 6), work(50, 5)]),
                ("lateral", [work(8, 15), work(8, 16), work(8, 17)]),
                ("pushdown", [work(30, 12), work(30, 13), work(30, 12)]),
                ("crossover", [work(15, 12), work(15, 13), work(15, 14)]),
            ]),
            SessionDefinition(number: 5, name: "Upper A · Push", templateID: upperA, daysAgo: 15, minutes: 51, averageHeartRate: nil, lines: [
                ("bench", [warmup(50, 8), work(77.5, 6), work(77.5, 6), work(77.5, 6)]),
                ("incline", [work(24, 10), work(24, 10), work(24, 10)]),
                ("ohp", [work(42.5, 8), work(42.5, 8), work(42.5, 8)]),
                ("lateral", [work(8, 14), work(8, 14), work(8, 14)]),
                ("pushdown", [work(27.5, 12), work(27.5, 12), work(27.5, 12)]),
                ("crossover", [work(15, 12), work(15, 12), work(15, 12)]),
            ]),
        ]
    }

    /// Builds one finished workout; `baseline` holds the best e1RM known before it and is raised by it (oldest workout first).
    static func makeWorkout(_ session: SessionDefinition, now: Date, baseline: inout [String: Double]) -> CompletedWorkout {
        var exercises: [CompletedExercise] = []
        var records: [PersonalRecord] = []
        var volume = 0.0
        var loggedSets = 0
        var rirValues: [Int] = []
        var muscleCounts: [MuscleGroup: Int] = [:]

        for (index, line) in session.lines.enumerated() {
            let exercise = libraryExercise(line.exerciseID)
            let workingSets = line.sets.filter { $0.type != .warmup }
            let best = exercise.tracksWeight ? bestSet(of: line.sets) : nil
            let bestValue = best?.e1RM ?? 0
            let previous = baseline[exercise.id] ?? 0
            let isRecord = previous > 0 && bestValue > previous + 0.05
            baseline[exercise.id] = max(previous, bestValue)

            if isRecord, let best {
                records.append(PersonalRecord(
                    exerciseID: exercise.id, exerciseName: exercise.name, weightKg: best.weightKg, reps: best.reps,
                    estimated1RM: bestValue, previousBest: previous
                ))
            }
            if exercise.tracksWeight {
                volume += workingSets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
            }
            loggedSets += line.sets.count
            rirValues.append(contentsOf: line.sets.compactMap { $0.rir })
            muscleCounts[exercise.muscle, default: 0] += workingSets.count

            exercises.append(CompletedExercise(
                id: fixedID(4, session.number * 100 + index + 1),
                exerciseID: exercise.id,
                name: exercise.name,
                muscle: exercise.muscle,
                mediaKey: exercise.mediaKey,
                tracking: exercise.tracking,
                sets: line.sets,
                isPersonalRecord: isRecord,
                bestE1RM: bestValue
            ))
        }

        let muscleSets = muscleCounts
            .filter { $0.value > 0 }
            .map { MuscleSets(muscle: $0.key, sets: $0.value) }
            .sorted { lhs, rhs in lhs.sets != rhs.sets ? lhs.sets > rhs.sets : lhs.muscle.rawValue < rhs.muscle.rawValue }

        let finishedAt = now.addingTimeInterval(-Double(session.daysAgo) * 86_400)
        let duration = session.minutes * 60
        return CompletedWorkout(
            id: fixedID(3, session.number),
            name: session.name,
            templateID: session.templateID,
            startedAt: finishedAt.addingTimeInterval(-Double(duration)),
            finishedAt: finishedAt,
            durationSeconds: duration,
            volumeKg: volume,
            loggedSets: loggedSets,
            averageHeartRate: session.averageHeartRate,
            averageRIR: rirValues.isEmpty ? nil : Double(rirValues.reduce(0, +)) / Double(rirValues.count),
            exercises: exercises,
            personalRecords: records,
            muscleSets: muscleSets
        )
    }

    /// The non-warm-up set with the highest Epley estimate (first on a tie).
    static func bestSet(of sets: [CompletedSet]) -> (e1RM: Double, weightKg: Double, reps: Int)? {
        var best: (e1RM: Double, weightKg: Double, reps: Int)?
        for set in sets where set.type != .warmup {
            let value = Estimated1RM.epley(weightKg: set.weightKg, reps: set.reps)
            if value > (best?.e1RM ?? 0) { best = (value, set.weightKg, set.reps) }
        }
        return best
    }

    /// A UUID that never changes: `5EED<group as 4 hex digits>-0000-4000-8000-<index as 12 hex digits>`.
    static func fixedID(_ group: Int, _ index: Int) -> UUID {
        let text = "5EED" + hex(group, 4) + "-0000-4000-8000-" + hex(index, 12)
        return UUID(uuidString: text) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: group), UInt8(truncatingIfNeeded: index)))
    }

    static func hex(_ value: Int, _ width: Int) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
