import Foundation

/// The coach note on the hub's recommended-template card, moved out of the iOS screen so it can be tested on every platform:
/// "Chest and shoulders are recovered. Aim for 85 kg × 6 on your last bench press set."
///
/// The weight comes from `TargetWeight`, the same function the in-workout tip uses. The readiness sentence is only built when a
/// `RecoveryProvider` is given: the standalone build's provider is demo data, so its caller passes nil.
public enum HubNoteBuilder {
    public static func message(
        template: WorkoutTemplate,
        exercise: (String) -> Exercise?,
        recovery: RecoveryProvider?
    ) -> String? {
        var sentences: [String] = []
        if let recovery, let readiness = readinessSentence(template: template, recovery: recovery) {
            sentences.append(readiness)
        }
        if let target = targetSentence(template: template, exercise: exercise) {
            sentences.append(target)
        }
        if sentences.isEmpty { return nil }
        return sentences.joined(separator: " ")
    }

    // MARK: Sentences

    private static func readinessSentence(template: WorkoutTemplate, recovery: RecoveryProvider) -> String? {
        let lead = Array(musclesUsed(by: template).prefix(2))
        if lead.isEmpty { return nil }
        let tired = lead.filter { max(0, min(100, recovery($0))) < 60 }
        if tired.isEmpty {
            return sentenceSubject(lead) + (isPlural(lead) ? " are recovered." : " is recovered.")
        }
        return sentenceSubject(tired) + (isPlural(tired) ? " are still recovering." : " is still recovering.")
    }

    /// The first weight exercise with a history: the lightest weight on its last working set that beats the best estimated 1RM.
    private static func targetSentence(template: WorkoutTemplate, exercise lookup: (String) -> Exercise?) -> String? {
        for entry in template.entries {
            let exercise = lookup(entry.exercise.id) ?? entry.exercise
            guard exercise.tracksWeight, exercise.previousBestE1RM > 0 else { continue }
            let normal = entry.plannedSets.last(where: { $0.type == .normal })
            let working = normal ?? entry.plannedSets.last(where: { $0.type != .warmup })
            guard let planned = working, planned.reps > 0 else { continue }
            guard let weight = TargetWeight.lowestBeating(
                baseline: exercise.previousBestE1RM, reps: planned.reps, step: exercise.weightStepKg
            ) else { continue }
            return "Aim for \(NumberText.kg(weight)) kg × \(planned.reps) on your last \(shortName(exercise)) set."
        }
        return nil
    }

    // MARK: Helpers (shared with the hub screen's muscle chips)

    /// The template's muscle groups, most exercises first (ties keep the order of first use).
    public static func musclesUsed(by template: WorkoutTemplate) -> [MuscleGroup] {
        var counts: [MuscleGroup: Int] = [:]
        var firstUse: [MuscleGroup] = []
        for entry in template.entries {
            let muscle = entry.exercise.muscle
            if counts[muscle] == nil {
                firstUse.append(muscle)
            }
            counts[muscle, default: 0] += 1
        }
        let indexed = Array(firstUse.enumerated())
        let sorted = indexed.sorted { lhs, rhs in
            let left = counts[lhs.element] ?? 0
            let right = counts[rhs.element] ?? 0
            if left != right { return left > right }
            return lhs.offset < rhs.offset
        }
        return sorted.map { $0.element }
    }

    /// "Chest" or "Chest and shoulders".
    public static func sentenceSubject(_ muscles: [MuscleGroup]) -> String {
        guard let first = muscles.first else { return "" }
        if muscles.count > 1 {
            return first.title + " and " + muscles[1].title.lowercased()
        }
        return first.title
    }

    /// True when `sentenceSubject(_:)` takes "are": two groups, or one group whose name is a plural noun
    /// ("Legs are recovered", "Chest is recovered").
    public static func isPlural(_ muscles: [MuscleGroup]) -> Bool {
        if muscles.count > 1 { return true }
        guard let only = muscles.first else { return false }
        switch only {
        case .shoulders, .arms, .legs:
            return true
        case .chest, .back, .core:
            return false
        }
    }

    /// The exercise name without its equipment prefix, lower case: "Barbell bench press" -> "bench press".
    public static func shortName(_ exercise: Exercise) -> String {
        var name = exercise.name
        let prefix = exercise.equipment.title.lowercased() + " "
        if name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return name.lowercased()
    }
}
