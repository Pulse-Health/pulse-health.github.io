import Foundation

// MARK: - Sample data

/// What `removeSampleData()` took out.
public struct SampleDataRemoval: Equatable, Sendable {
    /// How many of the three sample templates were deleted.
    public var templates: Int
    /// How many of the five sample workouts were deleted.
    public var workouts: Int
    /// How many stored personal bests were the invented ones of the sample data (see `StrengthData.hasSampleData`) and were deleted.
    public var personalBests: Int

    public init(templates: Int, workouts: Int, personalBests: Int = 0) {
        self.templates = templates
        self.workouts = workouts
        self.personalBests = personalBests
    }

    /// True when nothing was deleted.
    public var isEmpty: Bool { templates == 0 && workouts == 0 && personalBests == 0 }
}

public extension StrengthData {
    /// True when a sample template, a sample workout (`SampleData.templateIDs`, `SampleData.workoutIDs`) or a sample personal best
    /// (`sampleBestIDs`) is stored. Builds that seeded demo data into real files left them behind; the app offers to remove them
    /// while this is true.
    var hasSampleData: Bool {
        let templateIDs = Set(SampleData.templateIDs)
        let workoutIDs = Set(SampleData.workoutIDs)
        return templates.contains { templateIDs.contains($0.id) }
            || history.contains { workoutIDs.contains($0.id) }
            || !sampleBestIDs.isEmpty
    }

    /// Deletes exactly the sample templates, the sample workouts (found by their fixed ids; a sample template that the user
    /// edited is deleted too) and the sample personal bests, and recomputes the personal bests from what is left, so the sample
    /// records go with them. Everything else stays: the user's templates, workouts, exercises, plans and weigh-ins, and the finished
    /// workouts that were started from a sample template. A plan is never deleted or switched off; a deleted sample template only
    /// leaves the rotation of the plans that held it (see `WorkoutPlan.removeTemplate`).
    ///
    /// While `historyIsIncomplete` the other stored bests are kept and only raised (see `recomputePersonalBests()`).
    mutating func removeSampleData() -> SampleDataRemoval {
        let templateIDs = Set(SampleData.templateIDs)
        let workoutIDs = Set(SampleData.workoutIDs)
        let templateCount = templates.filter { templateIDs.contains($0.id) }.count
        let workoutCount = history.filter { workoutIDs.contains($0.id) }.count
        let bestIDs = sampleBestIDs
        templates.removeAll { templateIDs.contains($0.id) }
        for id in templateIDs { removeFromPlans(templateID: id) }
        history.removeAll { workoutIDs.contains($0.id) }
        for id in bestIDs { personalBests[id] = nil }
        if workoutCount > 0 || !bestIDs.isEmpty { recomputePersonalBests() }
        return SampleDataRemoval(templates: templateCount, workouts: workoutCount, personalBests: bestIDs.count)
    }

    /// The exercise ids whose stored personal best is one that the demo seeding wrote (`SampleData.personalBests(now:)`); empty
    /// unless `historyIsIncomplete`. With a complete history `recomputePersonalBests()` replaces every best anyway, but with a
    /// damaged one the stored bests are kept (they may come from a workout that could not be read), so the invented ones need to
    /// be recognised.
    ///
    /// The estimate, weight and reps must equal the sample best's, and the dates must keep the sample's distances from the day that
    /// was "today" when it was seeded: every stored best that fits shares that one seeding time (to the second, files drop the
    /// fraction). At least two must agree on it, so a real best that happens to be the same lift is never taken for a sample.
    /// A sample best that a real set has beaten since is the user's and stays.
    private var sampleBestIDs: [String] {
        guard historyIsIncomplete else { return [] }
        let reference = SampleBests.reference.sorted { $0.key < $1.key }
        let matches = reference.compactMap { id, sample -> (id: String, shift: TimeInterval)? in
            guard sample.estimated1RM > 0, let stored = personalBests[id],
                  abs(stored.estimated1RM - sample.estimated1RM) < 1e-6,
                  abs(stored.weightKg - sample.weightKg) < 1e-6,
                  stored.reps == sample.reps
            else { return nil }
            return (id, stored.date.timeIntervalSince(sample.date))
        }
        let groups = matches.map { anchor in matches.filter { abs($0.shift - anchor.shift) <= 1 } }
        guard let seeded = groups.max(by: { $0.count < $1.count }), seeded.count >= 2, let shift = seeded.first?.shift else { return [] }
        // The samples without an estimate (the pull-up's reps, the lateral raise's weights) are recognised by their date and marks.
        let marksOnly = reference.compactMap { id, sample -> String? in
            guard sample.estimated1RM == 0, let stored = personalBests[id], stored.estimated1RM == 0,
                  abs(stored.date.timeIntervalSince(sample.date) - shift) <= 1, stored.marks == sample.marks
            else { return nil }
            return id
        }
        return seeded.map(\.id) + marksOnly
    }
}

/// The sample personal bests at a fixed "today", to compare the stored ones with.
private enum SampleBests {
    static let reference = SampleData.personalBests(now: Date(timeIntervalSinceReferenceDate: 0))
}

// MARK: - Reset

/// Which parts of the stored data `resetData(_:)` erases.
public struct ResetScope: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The saved workout templates.
    public static let templates = ResetScope(rawValue: 1)
    /// The finished workouts, the personal bests derived from them and the "last performed" date of the templates.
    public static let history = ResetScope(rawValue: 2)
    /// The exercises the user created. Templates keep their embedded copies of them and finished workouts keep their names.
    public static let customExercises = ResetScope(rawValue: 4)
    /// The weigh-ins, and the Health exchange is switched off (`syncWithHealth`): the copies in Apple Health are not touched, and with
    /// the exchange on the next read from Health would bring every weigh-in straight back.
    public static let bodyWeights = ResetScope(rawValue: 8)
    /// The user's preferences: back to their defaults (the weigh-in reminder and the workout preferences: unit, rest timer, goal, ...).
    public static let preferences = ResetScope(rawValue: 16)
    /// The training plans. The templates they rotate over are not touched.
    public static let plans = ResetScope(rawValue: 32)
    /// Everything above.
    public static let all: ResetScope = [.templates, .history, .customExercises, .bodyWeights, .preferences, .plans]
}

public extension StrengthData {
    /// Erases the parts named by `scope`. Clearing the history also clears the personal bests, the `lastPerformed` date of every
    /// template and the incomplete-history mark (there is nothing left to protect). Clearing the templates also takes them out of the
    /// rotation of every plan (the plans stay, see `WorkoutPlan.removeTemplate`). Clearing the weigh-ins also turns the Health exchange
    /// off, so they are not read back from Health.
    ///
    /// Clearing the preferences restores the defaults of a new install: the weight unit is the one `deviceLocale` calls for
    /// (kilograms without a locale), everything else as in `StrengthPreferences()`.
    mutating func resetData(_ scope: ResetScope, deviceLocale: Locale? = nil) {
        if scope.contains(.templates) {
            templates = []
            for index in plans.indices {
                plans[index].templateIDs = []
                plans[index].nextIndex = 0
            }
        }
        if scope.contains(.history) {
            history = []
            personalBests = [:]
            historyIsIncomplete = false
            for index in templates.indices { templates[index].lastPerformed = nil }
        }
        if scope.contains(.customExercises) { customExercises = [] }
        if scope.contains(.plans) { plans = [] }
        if scope.contains(.bodyWeights) {
            bodyWeights = []
            weighIn.syncWithHealth = false
        }
        if scope.contains(.preferences) { resetPreferences(deviceLocale: deviceLocale) }
    }

    /// Puts every stored user preference back to its default. New preference fields are reset here.
    private mutating func resetPreferences(deviceLocale: Locale?) {
        weighIn = WeighInPreferences()
        preferences = deviceLocale.map { StrengthPreferences(locale: $0) } ?? StrengthPreferences()
    }
}

// MARK: - Model

public extension StrengthDataModel {
    /// True when sample templates or sample workouts are stored (see `StrengthData.hasSampleData`).
    var hasSampleData: Bool { data.hasSampleData }

    /// Deletes the sample templates, workouts and personal bests, recomputes the personal bests and saves what changed; the success value says
    /// what was deleted (see `StrengthData.removeSampleData`). Nothing is written when there was nothing to delete.
    @discardableResult
    func removeSampleData() -> Result<SampleDataRemoval, Error> {
        let bestsBefore = data.personalBests
        let plansBefore = data.plans
        let removal = data.removeSampleData()
        cache = nil
        guard !removal.isEmpty else { return .success(removal) }
        return commit(
            templates: removal.templates > 0,
            history: removal.workouts > 0,
            personalBests: data.personalBests != bestsBefore,
            plans: data.plans != plansBefore
        ).map { removal }
    }

    /// Erases the parts of the data that `scope` names and saves it (see `StrengthData.resetData`). Safe while no workout is
    /// running; the screen must not offer it during one.
    ///
    /// The files of the erased parts are written empty (the weigh-in reminder file too when the weigh-ins go, because it holds the
    /// Health switch; the preferences file holds the defaults again). When `scope` is `.all`, every data file is removed instead
    /// (`FileStrengthPersistence.deleteAll()`), which also takes the saved active workout and the remembered Watch command ids with
    /// it. The result is `.failure` when a file could not be written or removed; the data stays erased in memory.
    @discardableResult
    func resetData(_ scope: ResetScope) -> Result<Void, Error> {
        guard !scope.isEmpty else { return .success(()) }
        let templatesBefore = data.templates
        let plansBefore = data.plans
        data.resetData(scope, deviceLocale: deviceLocale)
        cache = nil
        if scope.isSuperset(of: .all) { return removeAllFiles() }
        return commit(
            templates: scope.contains(.templates) || data.templates != templatesBefore,
            history: scope.contains(.history),
            customExercises: scope.contains(.customExercises),
            personalBests: scope.contains(.history),
            plans: scope.contains(.plans) || data.plans != plansBefore,
            bodyWeights: scope.contains(.bodyWeights),
            weighIn: scope.contains(.preferences) || scope.contains(.bodyWeights),
            preferences: scope.contains(.preferences),
            exercises: true
        )
    }
}
