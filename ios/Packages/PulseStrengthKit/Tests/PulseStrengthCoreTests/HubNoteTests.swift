import XCTest
@testable import PulseStrengthCore

/// `HubNoteBuilder` replaced the hub screen's private `HubCoach`. The old code had no test and could not have one (it lived in the
/// iOS-only target), so `OldHubCoach` below is a verbatim port of it, used as an oracle: the extracted code must say exactly what
/// the old code said for every input the app can produce, and the documented differences are pinned separately.
private enum OldHubCoach {
    static func message(template: WorkoutTemplate, lookup: (String) -> Exercise?, recovery: RecoveryProvider) -> String? {
        var sentences: [String] = []
        if let readiness = readinessSentence(template: template, recovery: recovery) {
            sentences.append(readiness)
        }
        if let target = targetSentence(template: template, lookup: lookup) {
            sentences.append(target)
        }
        if sentences.isEmpty { return nil }
        return sentences.joined(separator: " ")
    }

    private static func percent(_ muscle: MuscleGroup, _ recovery: RecoveryProvider) -> Int {
        max(0, min(100, recovery(muscle)))
    }

    private static func musclesUsed(by template: WorkoutTemplate) -> [MuscleGroup] {
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

    private static func sentenceSubject(_ muscles: [MuscleGroup]) -> String {
        guard let first = muscles.first else { return "" }
        if muscles.count > 1 {
            return first.title + " and " + muscles[1].title.lowercased()
        }
        return first.title
    }

    private static func isPlural(_ muscles: [MuscleGroup]) -> Bool {
        if muscles.count > 1 { return true }
        guard let only = muscles.first else { return false }
        switch only {
        case .shoulders, .arms, .legs:
            return true
        case .chest, .back, .core:
            return false
        }
    }

    private static func shortName(_ exercise: Exercise) -> String {
        var name = exercise.name
        let prefix = exercise.equipment.title.lowercased() + " "
        if name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        return name.lowercased()
    }

    private static func readinessSentence(template: WorkoutTemplate, recovery: RecoveryProvider) -> String? {
        let lead = Array(musclesUsed(by: template).prefix(2))
        if lead.isEmpty { return nil }
        let tired = lead.filter { percent($0, recovery) < 60 }
        if tired.isEmpty {
            return sentenceSubject(lead) + (isPlural(lead) ? " are recovered." : " is recovered.")
        }
        return sentenceSubject(tired) + (isPlural(tired) ? " are still recovering." : " is still recovering.")
    }

    private static func targetSentence(template: WorkoutTemplate, lookup: (String) -> Exercise?) -> String? {
        for entry in template.entries {
            let exercise = lookup(entry.exercise.id) ?? entry.exercise
            guard exercise.tracksWeight, exercise.previousBestE1RM > 0 else { continue }
            let normal = entry.plannedSets.last(where: { $0.type == .normal })
            let working = normal ?? entry.plannedSets.last(where: { $0.type != .warmup })
            guard let planned = working, planned.reps > 0 else { continue }
            let weight = beatingWeight(for: exercise, reps: planned.reps)
            return "Aim for \(NumberText.kg(weight)) kg × \(planned.reps) on your last \(shortName(exercise)) set."
        }
        return nil
    }

    private static func beatingWeight(for exercise: Exercise, reps: Int) -> Double {
        let step = max(0.5, exercise.weightStepKg)
        let target = exercise.previousBestE1RM + 0.05
        let factor = 1 + Double(reps) / 30
        var weight = max(step, (target / factor / step).rounded(.down) * step)
        var iterations = 0
        while Estimated1RM.epley(weightKg: weight, reps: reps) <= target && iterations < 400 {
            weight += step
            iterations += 1
        }
        return weight
    }
}

final class HubNoteTests: XCTestCase {
    private let now = CoachFix.now

    private var demo: StrengthData {
        StrengthData(
            templates: SampleData.templates(now: now),
            history: SampleData.history(now: now),
            personalBests: SampleData.personalBests(now: now)
        )
    }

    private func both(_ template: WorkoutTemplate, data: StrengthData, recovery: @escaping RecoveryProvider) -> (old: String?, new: String?) {
        (
            OldHubCoach.message(template: template, lookup: { data.exercise(id: $0) }, recovery: recovery),
            HubNoteBuilder.message(template: template, exercise: { data.exercise(id: $0) }, recovery: recovery)
        )
    }

    // MARK: Pinned output

    func testTheDemoNoteIsUnchanged() {
        let data = demo
        let result = both(data.templates[0], data: data, recovery: DemoRecovery.provider)
        XCTAssertEqual(result.new, "Chest and shoulders are recovered. Aim for 85 kg × 6 on your last bench press set.")
        XCTAssertEqual(result.old, result.new)
    }

    func testWithoutARealRecoveryModelThereIsNoReadinessSentence() {
        let data = demo
        let note = HubNoteBuilder.message(template: data.templates[0], exercise: { data.exercise(id: $0) }, recovery: nil)
        XCTAssertEqual(note, "Aim for 85 kg × 6 on your last bench press set.")
    }

    func testNoNoteWithoutAnythingToSay() {
        let empty = WorkoutTemplate(name: "Empty", entries: [])
        XCTAssertNil(HubNoteBuilder.message(template: empty, exercise: { _ in nil }, recovery: nil))
        XCTAssertNil(HubNoteBuilder.message(template: empty, exercise: { _ in nil }, recovery: DemoRecovery.provider))
    }

    func testTiredMusclesAreNamedInsteadOfRecovered() {
        let data = demo
        let tired: RecoveryProvider = { $0 == .chest ? 40 : 90 }
        let note = HubNoteBuilder.message(template: data.templates[0], exercise: { data.exercise(id: $0) }, recovery: tired)
        XCTAssertEqual(note, "Chest is still recovering. Aim for 85 kg × 6 on your last bench press set.")
        let both = HubNoteBuilder.message(template: data.templates[0], exercise: { data.exercise(id: $0) }, recovery: { _ in 10 })
        XCTAssertEqual(both, "Chest and shoulders are still recovering. Aim for 85 kg × 6 on your last bench press set.")
        // Out-of-range values are clamped, not trapped.
        XCTAssertNotNil(HubNoteBuilder.message(template: data.templates[0], exercise: { data.exercise(id: $0) }, recovery: { _ in -500 }))
        XCTAssertNotNil(HubNoteBuilder.message(template: data.templates[0], exercise: { data.exercise(id: $0) }, recovery: { _ in 5_000 }))
    }

    // MARK: Oracle

    func testEveryDemoTemplateMatchesTheOldCodeForSeveralRecoveryModels() {
        let data = demo
        let models: [RecoveryProvider] = [DemoRecovery.provider, { _ in 0 }, { _ in 59 }, { _ in 60 }, { _ in 100 }, { Int($0.rawValue.utf8.count) * 13 }]
        for template in data.templates {
            for model in models {
                let result = both(template, data: data, recovery: model)
                XCTAssertEqual(result.new, result.old, template.name)
            }
        }
    }

    func testRandomTemplatesMatchTheOldCodeExactly() {
        let library = ExerciseLibrary.builtIn
        var rng = RedLCG(seed: 424_242)
        for index in 0..<4_000 {
            var entries: [TemplateEntry] = []
            for _ in 0..<rng.int(0...6) {
                var exercise = rng.pick(library)
                exercise.previousBestE1RM = rng.chance(25) ? 0 : (rng.chance(50) ? exercise.previousBestE1RM : Double(rng.int(5...2_500)) / 10)
                var sets: [PlannedSet] = []
                for _ in 0..<rng.int(0...5) {
                    let type: SetType = rng.pick([.normal, .normal, .warmup, .drop, .failure])
                    sets.append(PlannedSet(type: type, weightKg: Double(rng.int(0...800)) / 4, reps: rng.int(0...25)))
                }
                entries.append(TemplateEntry(exercise: exercise, plannedSets: sets, restSeconds: 90))
            }
            let template = WorkoutTemplate(name: "Random \(index)", entries: entries)
            let recoveries = MuscleGroup.allCases.map { _ in rng.int(-10...110) }
            let recovery: RecoveryProvider = { muscle in recoveries[MuscleGroup.allCases.firstIndex(of: muscle) ?? 0] }
            let old = OldHubCoach.message(template: template, lookup: { _ in nil }, recovery: recovery)
            let new = HubNoteBuilder.message(template: template, exercise: { _ in nil }, recovery: recovery)
            XCTAssertEqual(new, old, "case \(index): \(template.entries.map { $0.exercise.id })")
        }
    }

    // MARK: Documented differences

    func testAnInfiniteBestNoLongerProducesANonsenseWeight() {
        var bench = CoachFix.lib("bench")
        bench.previousBestE1RM = .infinity
        let entry = TemplateEntry(exercise: bench, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90)
        let template = WorkoutTemplate(name: "T", entries: [entry])
        let old = OldHubCoach.message(template: template, lookup: { _ in nil }, recovery: DemoRecovery.provider)
        let new = HubNoteBuilder.message(template: template, exercise: { _ in nil }, recovery: nil)
        XCTAssertEqual(old, "Chest is recovered. Aim for 0 kg × 6 on your last bench press set.")
        XCTAssertNil(new, "the shared function refuses a baseline that is not finite, so the exercise is skipped")
    }

    func testAnUnusableExerciseIsSkippedAndTheNextOneIsUsed() {
        var broken = CoachFix.lib("squat")
        broken.previousBestE1RM = .infinity
        var bench = CoachFix.lib("bench")
        bench.previousBestE1RM = 99 // the library carries no previous results any more: they come from the user's own history
        let template = WorkoutTemplate(name: "T", entries: [
            TemplateEntry(exercise: broken, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
            TemplateEntry(exercise: bench, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
        ])
        let note = HubNoteBuilder.message(template: template, exercise: { _ in nil }, recovery: nil)
        XCTAssertEqual(note, "Aim for 85 kg × 6 on your last bench press set.")
    }

    // MARK: Helpers

    func testShortNameDropsTheEquipmentPrefix() {
        XCTAssertEqual(HubNoteBuilder.shortName(CoachFix.lib("bench")), "bench press")
        var custom = Exercise.custom(name: "Zercher squat", muscle: .legs, equipment: .barbell, tracking: .weightReps)
        XCTAssertEqual(HubNoteBuilder.shortName(custom), "zercher squat")
        custom.name = "Barbell"
        XCTAssertEqual(HubNoteBuilder.shortName(custom), "barbell")
    }

    func testTheSharedTargetWeightIsTheOneThePresenterUses() {
        for (baseline, reps, step) in [(99.0, 6, 2.5), (38.0, 10, 2.0), (99.0, 6, 1.0), (12.6, 15, 2.0)] {
            XCTAssertEqual(
                TargetWeight.lowestBeating(baseline: baseline, reps: reps, step: step),
                PresenterSupport.lowestBeatingWeight(baseline: baseline, reps: reps, step: step)
            )
        }
        XCTAssertEqual(TargetWeight.lowestBeating(baseline: 99, reps: 6, step: 2.5), 85)
        XCTAssertEqual(TargetWeight.lowestBeating(baseline: 12.6, reps: 15, step: 2), 10)
        XCTAssertNil(TargetWeight.lowestBeating(baseline: 0, reps: 6, step: 2.5))
        XCTAssertNil(TargetWeight.lowestBeating(baseline: .nan, reps: 6, step: 2.5))
        XCTAssertNil(TargetWeight.lowestBeating(baseline: 99, reps: 0, step: 2.5))
        XCTAssertNil(TargetWeight.lowestBeating(baseline: 99, reps: 6, step: 0))
        XCTAssertNil(TargetWeight.lowestBeating(baseline: 99, reps: 6, step: .infinity))
    }
}
