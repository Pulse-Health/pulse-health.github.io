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

    /// The ids of the three demo templates. `StrengthStore.removeSampleData()` deletes exactly these.
    public static let templateIDs: [UUID] = [fixedID(1, 1), fixedID(1, 2), fixedID(1, 3)]

    /// The ids of the five demo workouts. `StrengthStore.removeSampleData()` deletes exactly these.
    public static let workoutIDs: [UUID] = (1...5).map { fixedID(3, $0) }

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

    /// The best set per exercise of the demo history (bench: 85 kg × 5, 10 days ago, estimated 1RM 99) with the record marks, as
    /// `StrengthData.recomputedPersonalBests()` makes them from `history(now:)`.
    public static func personalBests(now: Date) -> [String: PersonalBest] {
        StrengthData(history: history(now: now)).recomputedPersonalBests()
    }
}

// MARK: - Templates

private extension SampleData {
    static func upperPush() -> WorkoutTemplate {
        WorkoutTemplate(
            id: templateIDs[0],
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
            id: templateIDs[1],
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
            id: templateIDs[2],
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

    /// The built-in exercise `id` with its demo previous results; the fallback only exists so a mistyped id can never crash a preview.
    static func libraryExercise(_ id: String) -> Exercise {
        if let exercise = ExerciseLibrary.exercise(id: id) { return DemoPreviousResults.applying(to: exercise) }
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
        let upperA = templateIDs[0]
        let lowerA = templateIDs[1]
        let upperB = templateIDs[2]
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

            var sets = line.sets
            if isRecord, let best {
                records.append(PersonalRecord(
                    exerciseID: exercise.id, exerciseName: exercise.name, weightKg: best.weightKg, reps: best.reps,
                    estimated1RM: bestValue, previousBest: previous
                ))
                if let index = sets.firstIndex(where: { $0.type != .warmup && $0.weightKg == best.weightKg && $0.reps == best.reps }) {
                    sets[index].prKind = .estimated1RM
                }
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
                sets: sets,
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
            id: workoutIDs[session.number - 1],
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

    /// The non-warm-up set with the highest estimate (sets of 1...12 reps; first on a tie).
    static func bestSet(of sets: [CompletedSet]) -> (e1RM: Double, weightKg: Double, reps: Int)? {
        var best: (e1RM: Double, weightKg: Double, reps: Int)?
        for set in sets where set.type != .warmup {
            guard let value = Estimated1RM.estimate(weightKg: set.weightKg, reps: set.reps) else { continue }
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

// MARK: - Demo previous results

/// The invented "previous" numbers of the demo data: a best estimated 1RM and last sets for 25 library exercises. The estimates count
/// sets of up to `Estimated1RM.maximumReliableReps` reps only (the lateral raise sets of 14 to 17 reps give none).
///
/// The built-in library carries none of this (see `ExerciseLibrary.builtIn`). Previews, UI tests and the tests of the demo data use
/// `ExerciseLibrary.demoBuiltIn` or `applying(to:)`; `StrengthData` applies them only after the demo data was seeded (see
/// `StrengthData.usesDemoPreviousResults`). The values are consistent with `SampleData.history(now:)`.
public enum DemoPreviousResults {
    /// The previous results of one exercise.
    public struct Entry: Equatable, Sendable {
        /// Best estimated 1RM in kg; 0 when the demo gives none (bodyweight and timed exercises, sets above the rep cap).
        public var bestE1RM: Double
        /// The last session's sets.
        public var sets: [PreviousSet]

        /// `warmups` is how many of the first `sets` are warm-ups.
        init(bestE1RM: Double, warmups: Int = 0, sets: [(Double, Int)]) {
            self.bestE1RM = bestE1RM
            self.sets = sets.enumerated().map { index, set in
                PreviousSet(weightKg: set.0, reps: set.1, type: index < warmups ? .warmup : nil)
            }
        }
    }

    /// The demo previous results by exercise id.
    public static let byExerciseID: [String: Entry] = [
        "bench": Entry(bestE1RM: 99, warmups: 2, sets: [(50, 8), (70, 5), (80, 6), (80, 6), (80, 5)]),
        "incline": Entry(bestE1RM: 38, sets: [(26, 10), (26, 10), (26, 9)]),
        "crossover": Entry(bestE1RM: 21, sets: [(15, 12), (15, 12), (15, 11)]),
        "pushup": Entry(bestE1RM: 0, sets: [(0, 15)]),
        "pullup": Entry(bestE1RM: 0, sets: [(0, 8)]),
        "pulldown": Entry(bestE1RM: 0, sets: [(55, 10)]),
        "brow": Entry(bestE1RM: 0, sets: [(60, 8)]),
        "crow": Entry(bestE1RM: 0, sets: [(50, 10)]),
        "deadlift": Entry(bestE1RM: 0, sets: [(100, 5)]),
        "facepull": Entry(bestE1RM: 0, sets: [(20, 15)]),
        "ohp": Entry(bestE1RM: 58, sets: [(45, 8), (45, 8), (45, 7)]),
        "lateral": Entry(bestE1RM: 0, sets: [(8, 15), (8, 15), (8, 14)]),
        "curl": Entry(bestE1RM: 0, sets: [(30, 10)]),
        "dbcurl": Entry(bestE1RM: 0, sets: [(12, 10)]),
        "pushdown": Entry(bestE1RM: 42, sets: [(30, 12), (30, 12), (30, 11)]),
        "skull": Entry(bestE1RM: 0, sets: [(25, 10)]),
        "squat": Entry(bestE1RM: 0, sets: [(80, 6)]),
        "legpress": Entry(bestE1RM: 0, sets: [(140, 10)]),
        "rdl": Entry(bestE1RM: 0, sets: [(70, 8)]),
        "legext": Entry(bestE1RM: 0, sets: [(45, 12)]),
        "legcurl": Entry(bestE1RM: 0, sets: [(35, 12)]),
        "calf": Entry(bestE1RM: 0, sets: [(60, 12)]),
        "hipthrust": Entry(bestE1RM: 0, sets: [(80, 8)]),
        "plank": Entry(bestE1RM: 0, sets: [(0, 45)]),
        "cablecrunch": Entry(bestE1RM: 0, sets: [(35, 15)]),
    ]

    /// `exercise` with the demo best e1RM and last sets of its id; an exercise without a demo entry is returned unchanged.
    public static func applying(to exercise: Exercise) -> Exercise {
        guard let entry = byExerciseID[exercise.id] else { return exercise }
        var result = exercise
        result.previousBestE1RM = entry.bestE1RM
        result.previousSets = entry.sets
        return result
    }

    /// `exercises` with the demo previous results applied (see `applying(to:)`).
    public static func applying(to exercises: [Exercise]) -> [Exercise] {
        exercises.map { applying(to: $0) }
    }
}

public extension ExerciseLibrary {
    /// The built-in library with the demo previous results (`DemoPreviousResults`), for previews, UI tests and tests of the demo data.
    static let demoBuiltIn: [Exercise] = DemoPreviousResults.applying(to: builtIn)
}
