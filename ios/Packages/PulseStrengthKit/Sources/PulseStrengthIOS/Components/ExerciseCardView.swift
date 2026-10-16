#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// The exercise card of the active-workout screen (Active.dc.html): media tile, name, recovery, superset pill,
/// options button, set table, "Add Set" / rest chip / note buttons, note field and coach tip.
///
/// The card renders `ActiveWorkoutPresentation.Card` and dispatches to the `WorkoutController`; sheets are opened
/// through `ExerciseCardActions`. It hugs its content but may use the whole height offered by its parent
/// (`frame(maxHeight: .infinity, alignment: .top)`): only the set rows shrink into a scroll view when there are many sets.
@MainActor
struct ExerciseCardView: View {
    let card: ActiveWorkoutPresentation.Card
    let controller: WorkoutController
    let actions: ExerciseCardActions

    /// What the host knows about the person; the coach is more careful when it is unknown.
    @Environment(\.coachAudience) private var audience
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whether the note text field is shown (the pencil button toggles it, as in the design).
    @State private var isNoteOpen: Bool = false
    @FocusState private var isNoteFocused: Bool

    init(card: ActiveWorkoutPresentation.Card, controller: WorkoutController, actions: ExerciseCardActions) {
        self.card = card
        self.controller = controller
        self.actions = actions
    }

    var body: some View {
        let entry = currentEntry
        let suggestion = coachSuggestion(for: entry)
        VStack(spacing: 10) {
            header
            SetTableView(
                weightColumnTitle: card.weightColumnTitle,
                repsColumnTitle: card.repsColumnTitle,
                rows: card.rows,
                onToggle: { row in toggle(row) },
                onOpenDetail: { row in actions.openSetDetail(setRef(for: row)) },
                onOpenKeypad: { row, field in actions.openKeypad(setRef(for: row), field) }
            )
            controlsRow
            noteSection
            suggestionSection(suggestion)
            // The record tip says "85 kg × 6 would beat your best" while the coach may say "stay at 80" or "go lighter": it is shown
            // only when the coach has no weight to name. It follows the audience and the muscles the person asked to avoid.
            tipSection(for: entry, suggestion: suggestion)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .pulseCard()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            mediaTile
            titleBlock
            optionsButton
        }
    }

    /// 60 pt demo tile; tapping opens the form & instructions sheet.
    private var mediaTile: some View {
        Button {
            actions.showInfo(card.exercise)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ExerciseMediaView(mediaKey: card.exercise.mediaKey, cornerRadius: 12)
                    .frame(width: 60, height: 60)
                expandBadge
                    .padding(4)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel("Show form demo")
    }

    private var expandBadge: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .pulseFont(8, .bold, relativeTo: .caption2)
            .foregroundStyle(Color.white)
            .frame(width: 18, height: 18)
            .background(Color.black.opacity(0.55), in: Circle())
            .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: card.exercise.name)
                .tracking(0.2)
                .pulseFont(20, .bold, relativeTo: .title3)
                .foregroundStyle(PulseTheme.ink)
                .pulseLineLimit(2, whenLarger: 3)
                .pulseShrinkWhenLarger(0.8)
                .fixedSize(horizontal: false, vertical: true)
            recoveryLine
            supersetPill
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recoveryLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(PulseTheme.recoveryColor(card.recoveryLevel))
                .frame(width: 8, height: 8)
            Text(verbatim: recoveryText)
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
                .pulseLineLimit(1, whenLarger: 2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Chest · 88% recovered"
    private var recoveryText: String {
        card.exercise.muscle.title + " · " + String(card.recoveryPercent) + "% recovered"
    }

    @ViewBuilder
    private var supersetPill: some View {
        if let label = card.supersetLabel {
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .pulseFont(11, .bold, relativeTo: .caption2)
                Text(verbatim: label)
                    .pulseFont(12, .semibold, relativeTo: .footnote)
            }
            .foregroundStyle(PulseTheme.blueText)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PulseTheme.supersetFill, in: Capsule())
            .fixedSize()
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
        }
    }

    /// The design's 44 pt "more" button overhangs the header by 6 pt at the top and 8 pt at the trailing edge.
    private var optionsButton: some View {
        Button {
            actions.showOptions(card.exerciseID)
        } label: {
            Image(systemName: "ellipsis.circle")
                .pulseFont(22, .regular, relativeTo: .title2)
                .foregroundStyle(PulseTheme.green)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .padding(.top, -6)
        .padding(.trailing, -8)
        .accessibilityLabel("Exercise options")
    }

    // MARK: Buttons under the table

    private var controlsRow: some View {
        HStack(spacing: 8) {
            addSetButton
            restChip
            noteButton
        }
    }

    private var addSetButton: some View {
        Button {
            controller.send(.addSet(exerciseID: card.exerciseID))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .pulseFont(14, .bold, relativeTo: .subheadline)
                Text("Add Set")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PulseTintButtonStyle())
    }

    /// Timer icon plus the exercise's rest time ("2:30" or "Off"); opens the rest timer settings.
    private var restChip: some View {
        Button {
            actions.showRestSettings(card.exerciseID)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .pulseFont(16, .semibold, relativeTo: .subheadline)
                Text(verbatim: card.restText)
                    .pulseNumber(15, .semibold, relativeTo: .subheadline)
            }
            .padding(.horizontal, 14)
        }
        .buttonStyle(PulseTintButtonStyle())
        .accessibilityLabel("Rest timer")
        .accessibilityValue(card.restText)
    }

    private var noteButton: some View {
        Button {
            toggleNote()
        } label: {
            Image(systemName: "pencil")
                .pulseFont(16, .semibold, relativeTo: .subheadline)
                .frame(width: 44)
        }
        .buttonStyle(ExerciseCardControlStyle(fill: noteButtonFill))
        .accessibilityLabel("Exercise note")
        .accessibilityAddTraits(isNoteOpen ? .isSelected : [])
    }

    private var noteButtonFill: Color {
        isNoteOpen ? PulseTheme.green.opacity(0.16) : PulseTheme.cellFill
    }

    // MARK: Note and tip

    @ViewBuilder
    private var noteSection: some View {
        if isNoteOpen {
            ExerciseCardNoteField(
                exerciseID: card.exerciseID,
                note: card.note,
                isFocused: $isNoteFocused,
                onCommit: { exerciseID, text in
                    controller.send(.setNote(exerciseID: exerciseID, note: text))
                }
            )
            .id(card.exerciseID)
        } else if !card.note.isEmpty {
            ExerciseCardNoteLine(text: card.note)
        }
    }

    @ViewBuilder
    private func tipSection(for entry: WorkoutExercise?, suggestion: WorkoutSuggestion?) -> some View {
        let allowed = entry.map { audience.allowsPersonalRecordTip(for: $0.exercise.muscle) } ?? audience.showsPersonalRecordTips
        if allowed, let tip = card.coachTip, !coachNamesAWeight(entry, suggestion: suggestion) {
            CoachTipView(text: tip)
        }
    }

    /// Whether the coach has a weight for this exercise, with or without something to apply: after "Apply", or when the plan already
    /// is what the coach says, the suggestion row is gone but the coach has not changed its mind. The engine is only asked when the
    /// tip would otherwise be shown.
    private func coachNamesAWeight(_ entry: WorkoutExercise?, suggestion: WorkoutSuggestion?) -> Bool {
        if suggestion?.recommendation.verdict.hasTarget == true { return true }
        guard let entry, let state = controller.state else { return false }
        let recommendation = CoachPlanner.recommendation(
            for: entry,
            history: controller.store.history(for: entry.exercise.id, now: state.startedAt),
            workoutName: state.name,
            audience: audience,
            now: state.startedAt
        )
        return recommendation?.verdict.hasTarget == true
    }

    /// "Next time · 82.5 kg × 6" from the progression engine, before the first set of the exercise is logged.
    @ViewBuilder
    private func suggestionSection(_ suggestion: WorkoutSuggestion?) -> some View {
        if let suggestion {
            CoachSuggestionView(
                line: suggestion.line,
                canApply: !suggestion.actions.isEmpty,
                isCompact: isCompactSuggestion,
                onApply: { applyCurrentSuggestion() }
            )
        }
    }

    /// A note without a button drops its reason line while a rest runs (the dock needs the room, as for the record tip), at large
    /// text sizes, and for exercises with many sets, where the extra line would push the last set row out of the table. A suggestion
    /// with an "Apply" button keeps it: the button sets the row's height anyway, and the reason says why the weight goes down.
    private var isCompactSuggestion: Bool {
        controller.state?.rest != nil || dynamicTypeSize >= .xLarge || card.rows.count > 4
    }

    private var currentEntry: WorkoutExercise? {
        controller.state?.exercises.first(where: { $0.id == card.exerciseID })
    }

    /// The suggestion for the card's exercise, or nil. The cheap checks come first so that a card whose exercise already has a
    /// logged set never reads the history. The date is the start of the workout, so the line does not change under the person's
    /// finger when the last session crosses the break threshold in the middle of a workout.
    private func coachSuggestion(for entry: WorkoutExercise?) -> WorkoutSuggestion? {
        guard let entry, entry.exercise.tracksWeight, entry.doneCount == 0, let state = controller.state else { return nil }
        return CoachPlanner.suggestion(
            for: entry,
            history: controller.store.history(for: entry.exercise.id, now: state.startedAt),
            workoutName: state.name,
            audience: audience,
            now: state.startedAt
        )
    }

    // MARK: Actions

    private func setRef(for row: ActiveWorkoutPresentation.SetRow) -> SetRef {
        SetRef(exerciseID: card.exerciseID, setID: row.id)
    }

    /// "Apply": sets the top group of the pending working sets to the suggested weight and reps through the normal actions.
    ///
    /// The suggestion is worked out again at the moment of the tap, so a set that was logged since the card was drawn (from the
    /// Watch, say) is never rewritten. It cannot be undone like a deleted set; the person edits the sets to go back. VoiceOver is
    /// told what changed, because the suggestion row disappears under the focused button.
    private func applyCurrentSuggestion() {
        guard let current = coachSuggestion(for: currentEntry), !current.actions.isEmpty else { return }
        ExerciseCardHaptics.impact(.light)
        for action in current.actions {
            controller.send(action)
        }
        var announcement = "Sets changed"
        if let weight = current.recommendation.targetWeightKg, let reps = current.recommendation.targetReps {
            announcement += " to \(NumberText.kg(weight)) kilograms, \(reps) reps"
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    /// Check circle: logs or un-logs the set with an impact haptic.
    private func toggle(_ row: ActiveWorkoutPresentation.SetRow) {
        ExerciseCardHaptics.impact(row.isDone ? .light : .medium)
        controller.send(.toggleSet(exerciseID: card.exerciseID, setID: row.id))
    }

    private func toggleNote() {
        if isNoteOpen {
            isNoteFocused = false
            isNoteOpen = false
        } else {
            isNoteOpen = true
            Task { @MainActor in
                // Wait for the text field to be inserted before asking for the keyboard.
                try? await Task.sleep(nanoseconds: 80_000_000)
                if isNoteOpen {
                    isNoteFocused = true
                }
            }
        }
    }
}

// MARK: - Note field

/// The note text field (44 pt tall, 10 pt radius). The text is kept in local state while typing and written to the
/// workout (`setNote`) on return, when the field loses focus and when it goes away (exercise change, pencil toggle).
private struct ExerciseCardNoteField: View {
    let exerciseID: UUID
    let note: String
    let isFocused: FocusState<Bool>.Binding
    let onCommit: (UUID, String) -> Void

    @State private var draft: String
    /// The value last handed to the workout (or received from it).
    @State private var committed: String

    init(
        exerciseID: UUID,
        note: String,
        isFocused: FocusState<Bool>.Binding,
        onCommit: @escaping (UUID, String) -> Void
    ) {
        self.exerciseID = exerciseID
        self.note = note
        self.isFocused = isFocused
        self.onCommit = onCommit
        self._draft = State(initialValue: note)
        self._committed = State(initialValue: note)
    }

    var body: some View {
        TextField("Add a note, e.g. seat height 4", text: $draft)
            .pulseFont(17, relativeTo: .body)
            .foregroundStyle(PulseTheme.ink)
            .submitLabel(.done)
            .focused(isFocused)
            .padding(.horizontal, 12)
            .pulseScaledFrame(minHeight: 44, relativeTo: PulseDynamicType.controlHeightStyle)
            .background(PulseTheme.cellFill, in: RoundedRectangle(cornerRadius: PulseTheme.rowRadius, style: .continuous))
            .onSubmit {
                commit()
                isFocused.wrappedValue = false
            }
            .onChange(of: isFocused.wrappedValue) { _, focused in
                if !focused {
                    commit()
                }
            }
            .onChange(of: note) { _, newNote in
                receive(newNote)
            }
            .onDisappear {
                commit()
            }
            .accessibilityLabel("Exercise note")
    }

    private func commit() {
        guard draft != committed else { return }
        committed = draft
        onCommit(exerciseID, draft)
    }

    /// The workout's note changed from outside (not by this field): adopt it unless the user is typing.
    private func receive(_ newNote: String) {
        if newNote == draft {
            committed = newNote
        } else if !isFocused.wrappedValue {
            draft = newNote
            committed = newNote
        }
    }
}

/// The saved note shown under the buttons while the text field is closed.
private struct ExerciseCardNoteLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "pencil")
                .pulseFont(12, .semibold, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .pulseFont(13, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.ink.opacity(0.75))
                .lineSpacing(2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Note: " + text)
    }
}

// MARK: - Styles and haptics

/// Grey 44 pt control with green text; `fill` changes while the note field is open.
private struct ExerciseCardControlStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pulseFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(PulseTheme.greenText)
            .pulseScaledFrame(minHeight: 44, relativeTo: PulseDynamicType.controlHeightStyle)
            .background(fill, in: RoundedRectangle(cornerRadius: PulseTheme.rowRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

@MainActor
private enum ExerciseCardHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}
#endif
