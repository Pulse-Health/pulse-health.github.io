#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Row model

/// One library row of the picker.
private struct ExercisePickerRowModel: Identifiable {
    let id: String
    let exercise: Exercise
    /// "Chest · Barbell", plus " · Already in workout" for an exercise that cannot be added twice.
    let subtitle: String
    let isSelected: Bool
    /// Add mode only: the exercise is already part of the workout (row dimmed and not selectable).
    let isUsed: Bool
}

// MARK: - Sheet

/// "Add Exercise" / "Replace Exercise": search field, muscle and equipment filter chips, the filtered library with
/// selection circles (several in add mode, exactly one in replace mode), a "Create ..." row that opens
/// `CreateExerciseSheet`, and the bottom action ("Select exercises", "Add 3 exercises", "Replace with <name>").
/// Confirming sends `.addExercises` / `.replaceExercise` to the controller and closes the sheet.
@MainActor
public struct ExercisePickerSheet: View {
    @ObservedObject private var store: StrengthStore
    @ObservedObject private var controller: WorkoutController
    private let mode: PickerMode

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var muscle: MuscleGroup? = nil
    @State private var equipment: Equipment? = nil
    /// Selected exercise ids in the order they were selected.
    @State private var selection: [String] = []
    /// Exercises created in this sheet (a fallback for lookups until the store has published them).
    @State private var createdExercises: [String: Exercise] = [:]
    @State private var showsCreateSheet = false
    @FocusState private var searchIsFocused: Bool

    /// The equipment chips of the design (no "Other").
    private static let equipmentChoices: [Equipment] = [.barbell, .dumbbell, .cable, .machine, .bodyweight]

    public init(store: StrengthStore, controller: WorkoutController, mode: PickerMode) {
        self._store = ObservedObject(wrappedValue: store)
        self._controller = ObservedObject(wrappedValue: controller)
        self.mode = mode
    }

    // MARK: Body

    public var body: some View {
        let rows = makeRows()
        return VStack(spacing: 0) {
            ExerciseEditorTitleBar(
                title: titleText,
                leadingTitle: "Cancel",
                leadingAction: { dismiss() }
            )
            searchField
            muscleChips
            equipmentChips
            countLabel(rows.count)
            resultsList(rows)
            actionBar
        }
        .background(PulseTheme.ground.ignoresSafeArea())
        .sheet(isPresented: $showsCreateSheet) {
            CreateExerciseSheet(initialName: trimmedQuery) { (exercise: Exercise) in
                handleCreated(exercise)
            }
        }
    }

    // MARK: Header controls

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PulseTheme.inkSecondary)
                .accessibilityHidden(true)
            TextField("Search", text: $query)
                .font(PulseFont.body)
                .foregroundStyle(PulseTheme.ink)
                .focused($searchIsFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .onSubmit {
                    searchIsFocused = false
                }
                .accessibilityLabel("Search exercises")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .frame(width: 36, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PulsePlainButtonStyle())
                .padding(.trailing, -6)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(PulseTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var muscleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PulseChip("All", isSelected: muscle == nil) {
                    muscle = nil
                }
                ForEach(MuscleGroup.allCases) { (group: MuscleGroup) in
                    PulseChip(group.title, isSelected: muscle == group) {
                        muscle = group
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
    }

    private var equipmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PulseChip("Any", isSelected: equipment == nil) {
                    equipment = nil
                }
                ForEach(Self.equipmentChoices) { (item: Equipment) in
                    PulseChip(item.title, isSelected: equipment == item) {
                        equipment = item
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    private func countLabel(_ count: Int) -> some View {
        let noun = count == 1 ? "exercise" : "exercises"
        return Text("\(count) \(noun)")
            .font(PulseFont.caption)
            .foregroundStyle(PulseTheme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }

    // MARK: Results

    private func resultsList(_ rows: [ExercisePickerRowModel]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                resultsCard(rows)
                if rows.isEmpty {
                    Text("No exercise matches. Create it as a custom exercise.")
                        .font(PulseFont.subhead)
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func resultsCard(_ rows: [ExercisePickerRowModel]) -> some View {
        LazyVStack(spacing: 0) {
            createRow
            ForEach(rows) { (row: ExercisePickerRowModel) in
                ExercisePickerRowView(row: row, onTap: { toggle(row) })
            }
        }
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var createRow: some View {
        Button {
            searchIsFocused = false
            showsCreateSheet = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(PulseTheme.green)
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(PulseTheme.onGreen)
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                Text(createTitle)
                    .font(PulseFont.headline)
                    .foregroundStyle(PulseTheme.greenText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel(createTitle)
        .accessibilityHint("Opens the new exercise form")
    }

    // MARK: Bottom action

    private var actionBar: some View {
        let enabled = !selection.isEmpty
        let foreground: Color = enabled ? PulseTheme.onGreen : PulseTheme.inkSecondary
        let fill: Color = enabled ? PulseTheme.green : PulseTheme.progressTrack
        return Button {
            confirm()
        } label: {
            Text(actionTitle)
                .font(PulseFont.headline)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .disabled(!enabled)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: Derived values

    private var titleText: String {
        mode == .add ? "Add Exercise" : "Replace Exercise"
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var createTitle: String {
        let text = trimmedQuery
        return text.isEmpty ? "Create custom exercise" : "Create “" + text + "”"
    }

    private var actionTitle: String {
        if selection.isEmpty {
            return "Select exercises"
        }
        switch mode {
        case .add:
            let noun = selection.count == 1 ? "exercise" : "exercises"
            return "Add \(selection.count) \(noun)"
        case .replace:
            return "Replace with " + (chosenExercises().first?.name ?? "exercise")
        }
    }

    private func makeRows() -> [ExercisePickerRowModel] {
        let matches = ExerciseLibrary.filter(store.exercises, query: query, muscle: muscle, equipment: equipment)
        let inWorkout = idsInWorkout()
        var rows: [ExercisePickerRowModel] = []
        for exercise in matches {
            let used = inWorkout.contains(exercise.id)
            var subtitle = exercise.muscle.title + " · " + exercise.equipment.title
            if used {
                subtitle += " · Already in workout"
            }
            rows.append(
                ExercisePickerRowModel(
                    id: exercise.id,
                    exercise: exercise,
                    subtitle: subtitle,
                    isSelected: selection.contains(exercise.id),
                    isUsed: used
                )
            )
        }
        return rows
    }

    /// Ids of the exercises already in the workout; only relevant in add mode.
    private func idsInWorkout() -> Set<String> {
        guard mode == .add, let state = controller.state else { return [] }
        var ids = Set<String>()
        for entry in state.exercises {
            ids.insert(entry.exercise.id)
        }
        return ids
    }

    /// The selected exercises, resolved against the store (previous sets and bests included), in selection order.
    private func chosenExercises() -> [Exercise] {
        var result: [Exercise] = []
        for id in selection {
            if let exercise = store.exercise(id: id) {
                result.append(exercise)
            } else if let created = createdExercises[id] {
                result.append(created)
            }
        }
        return result
    }

    // MARK: Actions

    private func toggle(_ row: ExercisePickerRowModel) {
        guard !row.isUsed else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch mode {
        case .replace:
            selection = [row.id]
        case .add:
            if let position = selection.firstIndex(of: row.id) {
                selection.remove(at: position)
            } else {
                selection.append(row.id)
            }
        }
    }

    /// A custom exercise came back from the create form: save it to the library, select it and clear the search.
    private func handleCreated(_ exercise: Exercise) {
        store.addCustomExercise(exercise)
        createdExercises[exercise.id] = exercise
        switch mode {
        case .replace:
            selection = [exercise.id]
        case .add:
            if !selection.contains(exercise.id) {
                selection.append(exercise.id)
            }
        }
        query = ""
    }

    private func confirm() {
        let chosen = chosenExercises()
        guard !chosen.isEmpty else { return }
        switch mode {
        case .add:
            controller.send(.addExercises(chosen))
        case .replace(let exerciseID):
            if let replacement = chosen.first {
                controller.send(.replaceExercise(exerciseID: exerciseID, with: replacement))
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Row

private struct ExercisePickerRowView: View {
    let row: ExercisePickerRowModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                selectionMark
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.exercise.name)
                        .font(PulseFont.body)
                        .foregroundStyle(PulseTheme.ink)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(PulseFont.caption)
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                ExerciseMediaView(mediaKey: row.exercise.mediaKey, cornerRadius: 10)
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .opacity(row.isUsed ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .disabled(row.isUsed)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PulseTheme.separator)
                .frame(height: 0.5)
        }
        .accessibilityLabel(row.exercise.name)
        .accessibilityValue(row.subtitle)
        .accessibilityAddTraits(row.isSelected ? .isSelected : [])
    }

    /// 24 pt circle: grey ring when not selected, green with a white check when selected.
    private var selectionMark: some View {
        ZStack {
            Circle()
                .fill(row.isSelected ? PulseTheme.green : Color.clear)
            Circle()
                .strokeBorder(row.isSelected ? PulseTheme.green : PulseTheme.inkTertiary, lineWidth: 2)
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(PulseTheme.onGreen)
                .opacity(row.isSelected ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}
#endif
