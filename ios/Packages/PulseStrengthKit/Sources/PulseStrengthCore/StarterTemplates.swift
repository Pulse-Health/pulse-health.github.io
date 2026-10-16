import Foundation

/// Three ready-made templates (Push, Pull, Legs) for a user who has none.
///
/// They hold built-in exercises with the library defaults for sets, reps, weight and rest: the weights are only starting values
/// that the user is expected to change. They carry no history (no `lastPerformed`, no previous results). The ids are fixed, so adding
/// the starter templates twice never duplicates them.
public enum StarterTemplates {
    /// Push, Pull and Legs, in that order.
    public static let all: [WorkoutTemplate] = [
        template(1, "Push", ["bench", "ohp", "incline", "lateral", "pushdown", "ohtri"]),
        template(2, "Pull", ["pulldown", "brow", "crow", "facepull", "curl", "hammer"]),
        template(3, "Legs", ["squat", "rdl", "legpress", "legcurl", "legext", "calf"]),
    ]

    private static func template(_ number: Int, _ name: String, _ exerciseIDs: [String]) -> WorkoutTemplate {
        let entries = exerciseIDs.enumerated().compactMap { offset, exerciseID -> TemplateEntry? in
            guard let exercise = ExerciseLibrary.exercise(id: exerciseID) else { return nil }
            let defaults = exercise.defaults
            return TemplateEntry(
                id: fixedID(2, number * 0x100 + offset + 1),
                exercise: exercise,
                plannedSets: Array(
                    repeating: PlannedSet(type: .normal, weightKg: defaults.weightKg, reps: defaults.reps),
                    count: max(1, defaults.sets)
                ),
                restSeconds: defaults.restSeconds
            )
        }
        return WorkoutTemplate(id: fixedID(1, number), name: name, entries: entries)
    }

    /// A UUID that never changes: `57A2<group as 4 hex digits>-0000-4000-8000-<index as 12 hex digits>`. The prefix differs from the
    /// one of `SampleData`, so the two never collide.
    private static func fixedID(_ group: Int, _ index: Int) -> UUID {
        func byte(_ value: Int, _ shift: Int) -> UInt8 { UInt8(truncatingIfNeeded: value >> shift) }
        return UUID(uuid: (
            0x57, 0xA2, byte(group, 8), byte(group, 0), 0, 0, 0x40, 0x00,
            0x80, 0x00, 0, 0, byte(index, 24), byte(index, 16), byte(index, 8), byte(index, 0)
        ))
    }
}

public extension StrengthData {
    /// Appends the starter templates that are not stored yet (same id) and returns how many were added. A starter template that the
    /// user renamed or edited is kept as it is.
    @discardableResult
    mutating func addStarterTemplates() -> Int {
        let stored = Set(templates.map { $0.id })
        let missing = StarterTemplates.all.filter { !stored.contains($0.id) }
        templates.append(contentsOf: missing)
        return missing.count
    }
}

public extension StrengthDataModel {
    /// Adds the starter templates that are not there yet and saves the templates; the success value is how many were added (0 when
    /// they all exist; nothing is written then). `.failure` when the file could not be written (the templates are added in memory).
    @discardableResult
    func addStarterTemplates() -> Result<Int, Error> {
        let added = data.addStarterTemplates()
        guard added > 0 else { return .success(0) }
        return commit(templates: true).map { added }
    }
}
