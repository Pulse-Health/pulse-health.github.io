import Foundation

// MARK: - Plan

/// A training plan: saved workouts done in turn, not on fixed weekdays.
///
/// The plan is a rotation (Upper, Lower, Push, Pull, Legs, then Upper again). `nextIndex` says which workout is next. Doing a
/// workout of the plan moves it to the one after that workout, whatever day it is, so a missed day never leaves the plan
/// "behind"; `skip()` passes over the next workout. `daysPerWeek` is only a target that the hub shows next to what was done in the last
/// seven days, it never forces a day.
public struct WorkoutPlan: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// The ids of the saved templates in rotation order. An id whose template no longer exists is passed over.
    public var templateIDs: [UUID]
    /// Index into `templateIDs` of the workout that is next.
    public var nextIndex: Int
    /// How many workouts per week the plan aims for; nil = no target.
    public var daysPerWeek: Int?
    /// The plan the hub follows. At most one plan is active (`StrengthData.activatePlan`).
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        templateIDs: [UUID],
        nextIndex: Int = 0,
        daysPerWeek: Int? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.templateIDs = templateIDs
        self.nextIndex = nextIndex
        self.daysPerWeek = daysPerWeek
        self.isActive = isActive
    }
}

public extension WorkoutPlan {
    /// The plan's templates in rotation order, without the ones that no longer exist.
    func workouts(in templates: [WorkoutTemplate]) -> [WorkoutTemplate] {
        let byID = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return templateIDs.compactMap { byID[$0] }
    }

    /// The workout to do next: the one at `nextIndex`, or the first existing one after it (wrapping around). nil when no
    /// template of the plan exists.
    func nextWorkout(in templates: [WorkoutTemplate]) -> WorkoutTemplate? {
        guard !templateIDs.isEmpty else { return nil }
        let byID = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let start = ((nextIndex % templateIDs.count) + templateIDs.count) % templateIDs.count
        for offset in 0..<templateIDs.count {
            if let template = byID[templateIDs[(start + offset) % templateIDs.count]] { return template }
        }
        return nil
    }

    /// 1-based position of `nextWorkout` in the rotation ("workout 2 of 5"); nil when no template of the plan exists.
    func nextPosition(in templates: [WorkoutTemplate]) -> Int? {
        guard let next = nextWorkout(in: templates), let index = templateIDs.firstIndex(of: next.id) else { return nil }
        return index + 1
    }

    /// Takes every occurrence of `templateID` out of the rotation and keeps `nextIndex` on the workout that was next: when the next
    /// workout itself is removed, the one after it is next (the first one when that was the last); an empty rotation has `nextIndex` 0.
    /// Returns true when the plan held the template.
    @discardableResult
    mutating func removeTemplate(_ templateID: UUID) -> Bool {
        guard templateIDs.contains(templateID) else { return false }
        let start = templateIDs.isEmpty ? 0 : ((nextIndex % templateIDs.count) + templateIDs.count) % templateIDs.count
        let removedBefore = templateIDs[..<start].filter { $0 == templateID }.count
        templateIDs.removeAll { $0 == templateID }
        nextIndex = templateIDs.isEmpty ? 0 : (start - removedBefore) % templateIDs.count
        return true
    }

    /// Moves the rotation to the workout after `templateID`. Does nothing when the template is not in the plan.
    mutating func advance(after templateID: UUID) {
        guard let index = templateIDs.firstIndex(of: templateID) else { return }
        nextIndex = (index + 1) % templateIDs.count
    }

    /// Passes over the next workout without doing it (the rotation moves on, the workout stays in the plan).
    mutating func skip(in templates: [WorkoutTemplate]) {
        guard let next = nextWorkout(in: templates) else { return }
        advance(after: next.id)
    }

    /// How many workouts of this plan were finished in the `days` days before `now`.
    func completedCount(in history: [CompletedWorkout], now: Date, days: Int = 7) -> Int {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        let members = Set(templateIDs)
        return history.filter { workout in
            guard let id = workout.templateID else { return false }
            return members.contains(id) && workout.finishedAt > since && workout.finishedAt <= now
        }.count
    }
}

// MARK: - Rotation without a plan

/// The rotation the hub uses while no plan is active: over all saved templates, the one after the most recently performed.
public enum TemplateRotation {
    /// The template to do next: the one after the most recently performed template in the list, wrapping around
    /// (Upper A, Lower A, Upper B, then Upper A again). Without a performed template it is the first one; a single
    /// template recommends itself.
    public static func next(in templates: [WorkoutTemplate]) -> WorkoutTemplate? {
        guard !templates.isEmpty else { return nil }
        var latestIndex: Int?
        var latestDate = Date.distantPast
        for (index, template) in templates.enumerated() {
            if let date = template.lastPerformed, date > latestDate {
                latestDate = date
                latestIndex = index
            }
        }
        guard let last = latestIndex else { return templates[0] }
        return templates[(last + 1) % templates.count]
    }
}

// MARK: - Import bundle

/// A file that carries a plan with everything it needs: the plan, its workouts and the exercises that are not in the library.
///
/// `yt_workout.py` writes it (`pulse-import.json`) and the hub's "Import Plan" reads it. Ids make an import idempotent: importing the
/// same bundle again replaces the earlier copy instead of adding another one.
public struct PlanBundle: Codable, Equatable, Sendable {
    /// The only format version that exists so far.
    public static let currentVersion = 1

    public var version: Int
    public var plans: [WorkoutPlan]
    public var templates: [WorkoutTemplate]
    public var customExercises: [Exercise]

    public init(
        version: Int = PlanBundle.currentVersion,
        plans: [WorkoutPlan],
        templates: [WorkoutTemplate],
        customExercises: [Exercise] = []
    ) {
        self.version = version
        self.plans = plans
        self.templates = templates
        self.customExercises = customExercises
    }

    /// Reads a bundle from JSON (ISO-8601 dates, as every file of the feature).
    public static func decode(from data: Data) throws -> PlanBundle {
        let bundle: PlanBundle
        do {
            bundle = try StrengthJSON.makeDecoder().decode(PlanBundle.self, from: data)
        } catch {
            throw PlanImportError.unreadable
        }
        guard bundle.version <= currentVersion else { throw PlanImportError.newerVersion(bundle.version) }
        guard !bundle.templates.isEmpty else { throw PlanImportError.empty }
        return bundle
    }

    /// The bundle with every value brought into the range the app accepts, so a damaged or hand-edited file cannot
    /// produce a workout the app cannot run: names trimmed (a blank one becomes "Workout"), reps and weights clamped,
    /// rest within `0...WorkoutReducer.maximumRestSeconds`, a rep range only when its upper end is above the lower one,
    /// built-in exercises replaced by the library's current definition, and plan entries that name an unknown template dropped.
    func sanitized() -> PlanBundle {
        let maximumReps = 10_000
        var result = self
        result.templates = templates.map { template in
            var template = template
            template.name = Self.trimmed(template.name, fallback: "Workout")
            template.lastPerformed = nil
            template.entries = template.entries.map { entry in
                var entry = entry
                if let builtIn = ExerciseLibrary.exercise(id: entry.exercise.id) {
                    entry.exercise = builtIn
                } else {
                    entry.exercise = Self.carryingLoadIfRepsOnly(entry.exercise)
                }
                entry.restSeconds = min(max(entry.restSeconds, 0), WorkoutReducer.maximumRestSeconds)
                entry.plannedSets = entry.plannedSets.map { planned in
                    var planned = planned
                    planned.reps = min(max(planned.reps, 0), maximumReps)
                    planned.weightKg = planned.weightKg.isFinite
                        ? min(max(planned.weightKg, 0), WorkoutReducer.maximumWeightKg) : 0
                    if let upper = planned.repsMax.map({ min($0, maximumReps) }) {
                        planned.repsMax = upper > planned.reps ? upper : nil
                    }
                    return planned
                }
                if let note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    entry.note = note.isEmpty ? nil : note
                }
                return entry
            }
            return template
        }
        let known = Set(result.templates.map { $0.id })
        result.plans = plans.map { plan in
            var plan = plan
            plan.name = Self.trimmed(plan.name, fallback: "Plan")
            plan.templateIDs = plan.templateIDs.filter { known.contains($0) }
            plan.nextIndex = plan.templateIDs.isEmpty ? 0 : min(max(plan.nextIndex, 0), plan.templateIDs.count - 1)
            if let days = plan.daysPerWeek { plan.daysPerWeek = (1...7).contains(days) ? days : nil }
            return plan
        }.filter { !$0.templateIDs.isEmpty }
        result.customExercises = customExercises.filter { ExerciseLibrary.exercise(id: $0.id) == nil }.map(Self.carryingLoadIfRepsOnly)
        return result
    }

    /// Every custom reps-only exercise can carry an added or assisted load (`Exercise.custom` does the same); a file written before that
    /// flag existed does not say so.
    private static func carryingLoadIfRepsOnly(_ exercise: Exercise) -> Exercise {
        var result = exercise
        if result.tracking == .repsOnly { result.allowsAddedWeight = true }
        return result
    }

    private static func trimmed(_ text: String, fallback: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
}

/// Why a file could not be imported.
public enum PlanImportError: Error, Equatable, Sendable {
    /// Not a Pulse plan file (not JSON, or the wrong shape).
    case unreadable
    /// Written by a newer version of the tool than this app understands.
    case newerVersion(Int)
    /// The file holds no workouts.
    case empty

    /// A sentence for the user.
    public var message: String {
        switch self {
        case .unreadable: return "This file is not a Pulse plan."
        case .newerVersion: return "This plan was made for a newer version of the app. Update the app and try again."
        case .empty: return "This file contains no workouts."
        }
    }
}

/// What an import changed.
public struct PlanImportSummary: Equatable, Sendable {
    public var plans: Int
    public var templates: Int
    public var customExercises: Int

    public init(plans: Int, templates: Int, customExercises: Int) {
        self.plans = plans
        self.templates = templates
        self.customExercises = customExercises
    }

    /// "Imported 1 plan with 5 workouts and 18 new exercises."
    public var message: String {
        func count(_ value: Int, _ noun: String) -> String { "\(value) \(noun)\(value == 1 ? "" : "s")" }
        var text = "Imported "
        if plans > 0 { text += count(plans, "plan") + " with " }
        text += count(templates, "workout")
        if customExercises > 0 { text += " and " + count(customExercises, "new exercise") }
        return text + "."
    }
}
