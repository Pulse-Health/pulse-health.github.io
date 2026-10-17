import Foundation

// MARK: - Presenter

/// Turns a `WorkoutState` into the display-ready `ActiveWorkoutPresentation` (port of `renderVals` in the design's Active.dc.html).
public enum WorkoutPresenter {
    /// Builds the presentation of `state` at `now`; `recovery` supplies the muscle recovery percentages (0...100). `recoveryHasData`
    /// is false when they are only the default of a history without a recent workout (`RecoveryEstimate.hasData`); the card then says
    /// so (`Card.recoveryHasData`).
    ///
    /// Weights are written in the unit of `state.settings.weightUnit` with the separators of `locale` (default: en_US, so a caller
    /// that passes nothing gets "82.5").
    ///
    /// `template` is the template the workout started from as it is saved now, and `templateUpdatePrompt` the user's choice of when
    /// to offer updating it (`StrengthPreferences.askToUpdateTemplate`): together they decide `FinishCheck.asksToUpdateTemplate` and
    /// its `diffMessage`. Without the template only the exercises added, removed or reordered can be told.
    public static func present(
        _ state: WorkoutState,
        now: Date,
        recovery: RecoveryProvider,
        recoveryHasData: Bool = true,
        locale: Locale = DisplayFormat.metric.locale,
        template: WorkoutTemplate? = nil,
        templateUpdatePrompt: TemplateUpdatePrompt = .whenChanged
    ) -> ActiveWorkoutPresentation {
        let totals = PresenterSupport.totals(of: state)
        let currentIndex = state.clampedIndex
        let diff = TemplateDiff.compute(for: state, against: template)
        let formatter = WeightFormatter(unit: state.settings.weightUnit, locale: locale)

        return ActiveWorkoutPresentation(
            header: makeHeader(state, now: now, totals: totals, currentIndex: currentIndex, formatter: formatter),
            navigator: makeNavigator(state, currentIndex: currentIndex),
            card: state.currentExercise.map { makeCard($0, state: state, recovery: recovery, recoveryHasData: recoveryHasData, formatter: formatter) },
            dock: makeDock(state, now: now, formatter: formatter),
            undoText: makeUndoText(state, now: now),
            isEmpty: state.exercises.isEmpty,
            totals: totals,
            finishCheck: makeFinishCheck(totals: totals, diff: diff, templateID: state.templateID, prompt: templateUpdatePrompt),
            timedSet: makeTimedSet(state, now: now)
        )
    }
}

// MARK: - Header, navigator, undo

private extension WorkoutPresenter {
    static func makeHeader(
        _ state: WorkoutState,
        now: Date,
        totals: ActiveWorkoutPresentation.Totals,
        currentIndex: Int,
        formatter: WeightFormatter
    ) -> ActiveWorkoutPresentation.Header {
        var clock = NumberText.clock(seconds: state.elapsedSeconds(now: now))
        if state.isPaused { clock = "Paused · " + clock }

        let segments = state.exercises.enumerated().map { index, entry in
            ActiveWorkoutPresentation.Segment(
                fraction: entry.sets.isEmpty ? 0 : Double(entry.doneCount) / Double(entry.sets.count),
                isCurrent: index == currentIndex
            )
        }

        let bpm = state.heartRate.flatMap { $0 > 0 ? $0 : nil }
        return ActiveWorkoutPresentation.Header(
            title: state.name,
            clockText: clock,
            isPaused: state.isPaused,
            volumeText: formatter.volume(kg: totals.volumeKg),
            setsText: "\(totals.loggedSets) of \(totals.totalSets)",
            heartRateText: bpm.map { String($0) } ?? "–",
            hasHeartRate: bpm != nil,
            segments: segments
        )
    }

    static func makeNavigator(_ state: WorkoutState, currentIndex: Int) -> ActiveWorkoutPresentation.Navigator? {
        guard !state.exercises.isEmpty else { return nil }
        return ActiveWorkoutPresentation.Navigator(
            position: currentIndex + 1,
            total: state.exercises.count,
            canGoPrevious: currentIndex > 0,
            canGoNext: currentIndex < state.exercises.count - 1
        )
    }

    static func makeUndoText(_ state: WorkoutState, now: Date) -> String? {
        guard let undo = state.undo, now <= undo.expiresAt else { return nil }
        return undo.title
    }
}

// MARK: - Card and rows

private extension WorkoutPresenter {
    static func makeCard(
        _ entry: WorkoutExercise,
        state: WorkoutState,
        recovery: RecoveryProvider,
        recoveryHasData: Bool,
        formatter: WeightFormatter
    ) -> ActiveWorkoutPresentation.Card {
        let exercise = entry.exercise
        let percent = max(0, min(100, recovery(exercise.muscle)))
        let analysis = PresenterSupport.analyse(entry)
        let level: ActiveWorkoutPresentation.RecoveryLevel = percent >= 80 ? .good : (percent >= 60 ? .fair : .low)

        let weightTitle: String
        switch exercise.tracking {
        case .weightReps: weightTitle = formatter.unit.symbol
        case .repsOnly: weightTitle = "Added"
        case .duration: weightTitle = ""
        }

        let group = entry.supersetGroup.flatMap { $0.isEmpty ? nil : $0 }
        return ActiveWorkoutPresentation.Card(
            exerciseID: entry.id,
            exercise: exercise,
            recoveryPercent: percent,
            recoveryLevel: level,
            recoveryHasData: recoveryHasData,
            supersetLabel: group.map { "Superset " + $0 },
            restSeconds: entry.restSeconds,
            restText: NumberText.rest(seconds: entry.restSeconds),
            note: entry.note,
            weightColumnTitle: weightTitle,
            repsColumnTitle: exercise.tracking == .duration ? "Sec" : "Reps",
            coachTip: state.rest == nil ? PresenterSupport.coachTip(for: entry, baseline: analysis.baseline, formatter: formatter) : nil,
            rows: makeRows(entry, analysis: analysis.sets, formatter: formatter)
        )
    }

    static func makeRows(
        _ entry: WorkoutExercise,
        analysis: [PresenterSupport.SetAnalysis],
        formatter: WeightFormatter
    ) -> [ActiveWorkoutPresentation.SetRow] {
        let exercise = entry.exercise
        let previousSets = PresenterSupport.matchedPreviousSets(entry)
        var workingNumber = 0
        var nextFound = false
        var rows: [ActiveWorkoutPresentation.SetRow] = []
        rows.reserveCapacity(entry.sets.count)

        for (index, set) in entry.sets.enumerated() {
            let number: String
            switch set.type {
            case .warmup: number = "W"
            case .drop: number = "D"
            case .failure: number = "F"
            case .normal:
                workingNumber += 1
                number = String(workingNumber)
            }
            let isNext = !set.isDone && !nextFound
            if isNext { nextFound = true }
            let info = analysis[index]

            rows.append(ActiveWorkoutPresentation.SetRow(
                id: set.id,
                number: number,
                type: set.type,
                previousText: PresenterSupport.previousText(previousSets[index], exercise: exercise, formatter: formatter),
                weightText: PresenterSupport.weightText(set, exercise: exercise, formatter: formatter),
                repsText: String(set.reps),
                weightEditable: exercise.hasEditableWeight,
                isDone: set.isDone,
                isNext: isNext,
                isPersonalRecord: info.isRecord,
                estimated1RM: info.kind == .estimated1RM ? PresenterSupport.wholeNumber(kg: info.e1RM, unit: formatter.unit) : nil,
                rir: set.rir,
                rirText: set.isDone ? set.rir.map(PresenterSupport.rirText) : nil,
                accessibilityLabel: PresenterSupport.accessibilityLabel(setIndex: index, set: set, exercise: exercise, formatter: formatter),
                prKind: info.kind,
                previousSet: previousSets[index]
            ))
        }
        return rows
    }
}

// MARK: - Rest dock

private extension WorkoutPresenter {
    static func makeDock(_ state: WorkoutState, now: Date, formatter: WeightFormatter) -> ActiveWorkoutPresentation.Dock? {
        // A rest never shows while a timed set runs (the reducer does not start one then, and a state that has both shows the timer).
        guard state.timedSet == nil, let rest = state.rest, let entry = state.currentExercise,
              let remaining = PresenterSupport.restRemainingSeconds(state, now: now) else { return nil }

        let finished = remaining == 0
        let total = rest.totalSeconds
        let fraction: Double
        if finished {
            fraction = 1
        } else if total > 0 {
            fraction = max(0, min(1, Double(remaining) / Double(total)))
        } else {
            fraction = 0
        }

        let lastSet = lastLoggedSet(in: state)
        let showsRIR = lastSet.map { $0.isDone && $0.type != .warmup } ?? false
        return ActiveWorkoutPresentation.Dock(
            phase: finished ? .finished : .running,
            remainingSeconds: remaining,
            totalSeconds: total,
            fraction: fraction,
            remainingText: finished ? "Go" : NumberText.rest(seconds: remaining),
            nextSetText: nextSetText(entry, formatter: formatter),
            showsRIR: showsRIR,
            rirSelection: showsRIR ? lastSet?.rir : nil,
            isPaused: state.isPaused
        )
    }

    /// The set `lastLogged` points at, when it still exists.
    static func lastLoggedSet(in state: WorkoutState) -> LoggedSet? {
        guard let ref = state.lastLogged,
              let entry = state.exercises.first(where: { $0.id == ref.exerciseID }) else { return nil }
        return entry.sets.first(where: { $0.id == ref.setID })
    }

    /// "Next · Set 2 · 82.5 kg × 6" for the first pending set of the card, or "All sets logged".
    static func nextSetText(_ entry: WorkoutExercise, formatter: WeightFormatter) -> String {
        var workingNumber = 0
        for set in entry.sets {
            var number = ""
            switch set.type {
            case .warmup: break
            case .drop: number = "D"
            case .failure: number = "F"
            case .normal:
                workingNumber += 1
                number = String(workingNumber)
            }
            if set.isDone { continue }
            let label = set.type == .warmup ? "Warm-up" : "Set " + number
            return "Next · " + label + " · " + PresenterSupport.workText(set, exercise: entry.exercise, formatter: formatter)
        }
        return "All sets logged"
    }
}

// MARK: - Timed set

private extension WorkoutPresenter {
    /// The running timed set; nil without one or when its set no longer exists (a state the reducer did not produce).
    static func makeTimedSet(_ state: WorkoutState, now: Date) -> ActiveWorkoutPresentation.TimedSetPresentation? {
        guard let timed = state.timedSet, let k = state.exerciseIndex(id: timed.setRef.exerciseID),
              let i = state.exercises[k].sets.firstIndex(where: { $0.id == timed.setRef.setID }) else { return nil }
        let elapsed = WorkoutReducer.wholeSeconds(timed.elapsed(now: now))
        let target = max(0, min(timed.targetSeconds, WorkoutReducer.maximumDurationSeconds))
        let remaining = max(0, target - elapsed)
        return ActiveWorkoutPresentation.TimedSetPresentation(
            exerciseID: timed.setRef.exerciseID,
            setID: timed.setRef.setID,
            setNumber: i + 1,
            elapsedSeconds: elapsed,
            targetSeconds: target,
            remainingSeconds: remaining,
            isOverTarget: target > 0 && elapsed >= target,
            isPaused: state.isPaused,
            elapsedText: NumberText.clock(seconds: elapsed),
            targetText: NumberText.clock(seconds: target),
            remainingText: NumberText.clock(seconds: remaining)
        )
    }
}

// MARK: - Finish check

private extension WorkoutPresenter {
    static func makeFinishCheck(
        totals: ActiveWorkoutPresentation.Totals,
        diff: TemplateDiff,
        templateID: UUID?,
        prompt: TemplateUpdatePrompt
    ) -> ActiveWorkoutPresentation.FinishCheck {
        let logged = totals.loggedSets
        let unlogged = max(0, totals.totalSets - logged)

        let title = logged == 0 ? "Nothing logged yet" : "Finish workout?"
        let message: String
        if logged == 0 {
            message = "Log at least one set to save this workout."
        } else if unlogged > 0 {
            message = "\(unlogged) " + (unlogged == 1 ? "set is" : "sets are") + " not logged yet and will be left out."
        } else {
            message = "All sets are logged. Nice work."
        }

        let asks: Bool
        switch prompt {
        case .whenChanged: asks = !diff.isEmpty
        case .structureOnly: asks = diff.hasStructureChanges
        case .never: asks = false
        }
        return ActiveWorkoutPresentation.FinishCheck(
            loggedSets: logged,
            unloggedSets: unlogged,
            canFinish: logged > 0,
            title: title,
            message: message,
            templateDiff: diff,
            diffMessage: "Changes: " + (prompt == .whenChanged ? diff.summary : diff.structureSummary) + ".",
            asksToUpdateTemplate: asks && templateID != nil
        )
    }
}

// MARK: - Shared helpers (presenter, summary and snapshot)

/// Calculations and texts shared by the presenter, the summary builder and the snapshot builder.
enum PresenterSupport {
    /// A personal record must beat the running best by more than this many kilograms (`RecordTracker.margin`).
    static let recordMargin = RecordTracker.margin

    /// Estimated 1RM and personal-record kind of one set.
    struct SetAnalysis: Equatable {
        /// The estimate (`Estimated1RM.estimate`: sets of 1...12 reps) for logged-or-pending non-warm-up sets of weight-tracking
        /// exercises, else 0.
        var e1RM: Double
        /// The record a logged set broke (see `RecordTracker`); nil for every other set, and for every set without history.
        var kind: PRKind?
        /// The record before the workout, in the unit of `kind` (0 without a kind).
        var previous: Double

        var isRecord: Bool { kind != nil }
    }

    // MARK: Totals

    static func totals(of state: WorkoutState) -> ActiveWorkoutPresentation.Totals {
        var logged = 0
        var all = 0
        var volume = 0.0
        var completed = 0
        for entry in state.exercises {
            all += entry.sets.count
            logged += entry.doneCount
            volume += entry.loggedVolumeKg
            if entry.isComplete { completed += 1 }
        }
        return ActiveWorkoutPresentation.Totals(
            loggedSets: logged,
            totalSets: all,
            volumeKg: volume,
            completedExercises: completed
        )
    }

    /// Largest whole number shown for an estimate; anything above (only possible for a state the reducer did not produce) clamps.
    private static let wholeNumberLimit = 1_000_000_000.0

    /// A weight in kilograms as a whole number of `unit` for display, never trapping: non-finite gives 0, huge values clamp.
    static func wholeNumber(kg: Double, unit: WeightUnit) -> Int {
        let value = unit.fromKg(kg)
        guard value.isFinite else { return 0 }
        return Int(max(-wholeNumberLimit, min(value.rounded(), wholeNumberLimit)))
    }

    // MARK: Personal records

    /// Per-set analysis in set order plus the final running estimated-1RM baseline (previous best raised by the logged sets).
    ///
    /// The records follow `RecordTracker`: the values start at what the exercise carries from earlier sessions
    /// (`previousBestE1RM`, `previousRecords`) and rise with every logged non-warm-up set, and a record needs its own earlier value, so
    /// without history no set is flagged.
    static func analyse(_ entry: WorkoutExercise) -> (sets: [SetAnalysis], baseline: Double) {
        let exercise = entry.exercise
        var tracker = RecordTracker(exercise)
        var result: [SetAnalysis] = []
        result.reserveCapacity(entry.sets.count)

        for set in entry.sets {
            let countsTowardRecords = set.type.countsTowardVolume
            let e1RM = exercise.tracksWeight && countsTowardRecords
                ? Estimated1RM.estimate(weightKg: set.weightKg, reps: set.reps) ?? 0
                : 0
            var broken: RecordTracker.Broken?
            if set.isDone, countsTowardRecords { broken = tracker.log(weightKg: set.weightKg, reps: set.reps) }
            result.append(SetAnalysis(e1RM: e1RM, kind: broken?.kind, previous: broken?.previous ?? 0))
        }
        return (result, tracker.e1RM)
    }

    // MARK: Coach tip

    /// "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg." or nil; in the unit of `formatter`.
    static func coachTip(for entry: WorkoutExercise, baseline: Double, formatter: WeightFormatter) -> String? {
        let exercise = entry.exercise
        guard exercise.tracksWeight, exercise.previousBestE1RM > 0 else { return nil }
        let pending = entry.sets.filter { !$0.isDone && $0.type != .warmup }
        guard let target = pending.last(where: { $0.type == .normal }) ?? pending.last else { return nil }
        guard target.reps > 0, let weight = lowestBeatingWeight(
            baseline: baseline, reps: target.reps, step: exercise.weightStep(in: formatter.unit), unit: formatter.unit
        ) else { return nil }
        return String(
            format: "%@ × %ld on your last set would beat your best estimated 1RM of %@.",
            formatter.textWithUnit(kg: weight), target.reps, formatter.volumeWithUnit(kg: baseline)
        )
    }

    /// The lowest multiple of `step` (in `unit`) whose Epley estimate with `reps` exceeds `baseline` (kilograms) by more than the
    /// record margin, as the kilograms a set stores for it (rounded to 0.01 kg like the reducer does, so that entering the weight
    /// the tip names really beats the record). nil for more reps than `Estimated1RM.maximumReliableReps`: such a set has no estimate.
    static func lowestBeatingWeight(baseline: Double, reps: Int, step: Double, unit: WeightUnit) -> Double? {
        guard baseline.isFinite, baseline > 0, reps > 0, reps <= Estimated1RM.maximumReliableReps, step > 0, step.isFinite else { return nil }
        let threshold = baseline + recordMargin
        func storedKg(_ multiples: Double) -> Double { WorkoutReducer.roundedWeight(unit.toKg(multiples * step)) ?? 0 }
        func beats(_ multiples: Double) -> Bool {
            (Estimated1RM.estimate(weightKg: storedKg(multiples), reps: reps) ?? 0) > threshold
        }

        let minimum = unit.fromKg(threshold / (1 + Double(reps) / 30))
        var multiples = (minimum / step).rounded(.up)
        guard multiples.isFinite, multiples < 1e9 else { return nil }
        multiples = max(1, multiples)
        // Correct a possible off-by-one from floating point rounding in either direction.
        var guardCount = 0
        while multiples > 1, beats(multiples - 1), guardCount < 8 {
            multiples -= 1
            guardCount += 1
        }
        while !beats(multiples), guardCount < 16 {
            multiples += 1
            guardCount += 1
        }
        return beats(multiples) ? storedKg(multiples) : nil
    }

    // MARK: Rest

    /// Whole seconds of rest left (rounded up, frozen while paused); nil without a rest.
    static func restRemainingSeconds(_ state: WorkoutState, now: Date) -> Int? {
        guard let rest = state.rest else { return nil }
        let seconds: TimeInterval
        if let frozen = rest.frozenRemaining {
            seconds = frozen
        } else {
            seconds = rest.endsAt.timeIntervalSince(state.pausedAt ?? now)
        }
        guard seconds.isFinite else { return 0 }
        // A tiny tolerance keeps floating-point noise (95.0000002 s) from showing one second too many.
        let rounded = (max(0, seconds) - 1e-6).rounded(.up)
        return Int(max(0, min(rounded, 1_000_000_000)))
    }

    // MARK: Previous sets

    /// The set of the previous session each set of the entry is matched to, in set order: the warm-ups with the previous warm-ups and
    /// the working sets (normal, drop, failure) with the previous working sets, each kind in order. A row with no previous set of its
    /// kind left has nil (no reuse of the last one). A previous set without a type counts as a working set.
    static func matchedPreviousSets(_ entry: WorkoutExercise) -> [PreviousSet?] {
        let previous = entry.exercise.previousSets
        let warmups = previous.filter { $0.isWarmup }
        let working = previous.filter { !$0.isWarmup }
        var warmupIndex = 0
        var workingIndex = 0
        return entry.sets.map { set -> PreviousSet? in
            if set.type == .warmup {
                defer { warmupIndex += 1 }
                return warmupIndex < warmups.count ? warmups[warmupIndex] : nil
            }
            defer { workingIndex += 1 }
            return workingIndex < working.count ? working[workingIndex] : nil
        }
    }

    // MARK: Texts

    /// "RIR 3" or "RIR 4+".
    static func rirText(_ rir: Int) -> String {
        rir >= 4 ? "RIR 4+" : "RIR " + String(max(0, rir))
    }

    /// "82.5" for weight-tracking exercises; for reps-only exercises "BW" (and "+10" / "−20" when the exercise allows an added load
    /// and the set has one); "–" for durations.
    static func weightText(_ set: LoggedSet, exercise: Exercise, formatter: WeightFormatter) -> String {
        switch exercise.tracking {
        case .weightReps: return formatter.text(kg: set.weightKg)
        case .repsOnly: return exercise.carriesLoad ? formatter.signedText(kg: set.weightKg) : "BW"
        case .duration: return "–"
        }
    }

    /// "82.5 kg × 6", "+10 kg × 8", "8 reps" or "45 s": what a set asks for.
    static func workText(_ set: LoggedSet, exercise: Exercise, formatter: WeightFormatter) -> String {
        switch exercise.tracking {
        case .weightReps: return String(format: "%@ × %ld", formatter.textWithUnit(kg: set.weightKg), set.reps)
        case .repsOnly: return repsOnlyText(weightKg: set.weightKg, reps: set.reps, exercise: exercise, formatter: formatter, unitSymbol: true)
        case .duration: return "\(set.reps) s"
        }
    }

    /// Text for the PREVIOUS column: "80 × 6", "+10 × 8", "8 reps", "45 s", or "–" without a matched previous set.
    static func previousText(_ previous: PreviousSet?, exercise: Exercise, formatter: WeightFormatter) -> String {
        guard let previous else { return "–" }
        switch exercise.tracking {
        case .weightReps: return formatter.text(kg: previous.weightKg) + " × \(previous.reps)"
        case .repsOnly:
            return repsOnlyText(weightKg: previous.weightKg, reps: previous.reps, exercise: exercise, formatter: formatter, unitSymbol: false)
        case .duration: return "\(previous.reps) s"
        }
    }

    /// The reps of a reps-only set, with the load in front when the exercise allows one and the set has one: "8 reps" or "+10 kg × 8".
    private static func repsOnlyText(weightKg: Double, reps: Int, exercise: Exercise, formatter: WeightFormatter, unitSymbol: Bool) -> String {
        guard exercise.carriesLoad, formatter.displayValue(kg: weightKg) != 0 else { return "\(reps) reps" }
        let load = formatter.signedText(kg: weightKg)
        return String(format: "%@ × %ld", unitSymbol ? load + " " + formatter.unit.symbol : load, reps)
    }

    /// "Set 3, working set, 82.5 kilograms, 6 reps, logged".
    static func accessibilityLabel(setIndex: Int, set: LoggedSet, exercise: Exercise, formatter: WeightFormatter) -> String {
        let typeName: String
        switch set.type {
        case .normal: typeName = "working set"
        case .warmup: typeName = "warm-up"
        case .drop: typeName = "drop set"
        case .failure: typeName = "failure set"
        }
        var parts = ["Set \(setIndex + 1)", typeName]
        switch exercise.tracking {
        case .weightReps:
            parts.append(formatter.accessibilityText(kg: set.weightKg))
            parts.append("\(set.reps)" + (set.reps == 1 ? " rep" : " reps"))
        case .repsOnly:
            parts.append(spokenLoad(weightKg: set.weightKg, exercise: exercise, formatter: formatter))
            parts.append("\(set.reps)" + (set.reps == 1 ? " rep" : " reps"))
        case .duration:
            parts.append("\(set.reps)" + (set.reps == 1 ? " second" : " seconds"))
        }
        parts.append(set.isDone ? "logged" : "not logged")
        return parts.joined(separator: ", ")
    }

    /// "bodyweight", "10 kilograms added" or "20 kilograms assisted".
    private static func spokenLoad(weightKg: Double, exercise: Exercise, formatter: WeightFormatter) -> String {
        guard exercise.carriesLoad else { return "bodyweight" }
        let shown = formatter.displayValue(kg: weightKg)
        if shown == 0 { return "bodyweight" }
        let spoken = formatter.accessibilityText(kg: abs(weightKg))
        return shown > 0 ? spoken + " added" : spoken + " assisted"
    }
}

public extension WorkoutExercise {
    /// The set of the previous session that the set at `index` is matched to, as in the PREVIOUS column (`SetRow.previousSet`);
    /// nil when there is none, or no such set.
    func matchedPreviousSet(at index: Int) -> PreviousSet? {
        let matched = PresenterSupport.matchedPreviousSets(self)
        return matched.indices.contains(index) ? matched[index] : nil
    }
}
