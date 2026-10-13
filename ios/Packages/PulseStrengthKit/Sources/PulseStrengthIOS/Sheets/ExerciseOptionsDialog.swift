#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Public API

public extension View {
    /// The exercise options action sheet of the design ("Exercise options"): Form & instructions,
    /// Rest timer, Replace exercise, Superset with next / Remove from superset, Move up, Move down
    /// and Remove exercise (destructive), followed by Cancel. The title is the exercise name.
    ///
    /// The dialog is shown while `exerciseID` holds the id of a workout exercise (a `WorkoutExercise.id`)
    /// that exists in the controller's workout; it resets `exerciseID` to nil when it closes.
    /// "Superset", "Move up / down" and "Remove exercise" are applied to the controller here; the three
    /// follow-up presentations (information, rest timer, replace picker) are reported through the callbacks.
    func exerciseOptionsDialog(
        controller: WorkoutController,
        exerciseID: Binding<UUID?>,
        onShowInfo: @escaping (Exercise) -> Void,
        onShowRestSettings: @escaping (UUID) -> Void,
        onReplace: @escaping (UUID) -> Void
    ) -> some View {
        ExerciseOptionsDialogHost(
            content: self,
            controller: controller,
            exerciseID: exerciseID,
            onShowInfo: onShowInfo,
            onShowRestSettings: onShowRestSettings,
            onReplace: onReplace
        )
    }
}

// MARK: - Dialog data

/// Everything the dialog needs about one workout exercise, read when the dialog is built.
private struct ExerciseOptionsContext {
    let id: UUID
    let exercise: Exercise
    /// "Off" or "2:30".
    let restText: String
    let isInSuperset: Bool
    /// The superset item exists for exercises in a group and for every exercise that has a next one.
    let showsSuperset: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
}

// MARK: - Host

/// Wraps `content` and attaches the confirmation dialog. A `View` (not a `ViewModifier`) so that
/// everything that reads the main-actor controller runs inside `body` or in `@MainActor` helpers.
private struct ExerciseOptionsDialogHost<Content: View>: View {
    let content: Content
    let controller: WorkoutController
    @Binding var exerciseID: UUID?
    let onShowInfo: (Exercise) -> Void
    let onShowRestSettings: (UUID) -> Void
    let onReplace: (UUID) -> Void

    var body: some View {
        let context = makeContext()
        let title = context?.exercise.name ?? "Exercise options"
        return content.confirmationDialog(
            title,
            isPresented: presentationBinding(isAvailable: context != nil),
            titleVisibility: .visible,
            presenting: context
        ) { (item: ExerciseOptionsContext) in
            dialogActions(item)
        }
    }

    /// True while an id is set and that exercise still exists; closing the dialog clears the id.
    private func presentationBinding(isAvailable: Bool) -> Binding<Bool> {
        let idBinding = $exerciseID
        return Binding<Bool>(
            get: { isAvailable },
            set: { (newValue: Bool) in
                if !newValue {
                    idBinding.wrappedValue = nil
                }
            }
        )
    }

    @MainActor
    private func makeContext() -> ExerciseOptionsContext? {
        guard let id = exerciseID,
              let state = controller.state,
              let index = state.exerciseIndex(id: id) else {
            return nil
        }
        let entry = state.exercises[index]
        let isLast = index >= state.exercises.count - 1
        return ExerciseOptionsContext(
            id: entry.id,
            exercise: entry.exercise,
            restText: NumberText.rest(seconds: entry.restSeconds),
            isInSuperset: entry.supersetGroup != nil,
            showsSuperset: entry.supersetGroup != nil || !isLast,
            canMoveUp: index > 0,
            canMoveDown: !isLast
        )
    }

    @MainActor
    @ViewBuilder
    private func dialogActions(_ item: ExerciseOptionsContext) -> some View {
        Button("Form & instructions") {
            onShowInfo(item.exercise)
        }
        Button("Rest timer · " + item.restText) {
            onShowRestSettings(item.id)
        }
        Button("Replace exercise") {
            onReplace(item.id)
        }
        if item.showsSuperset {
            Button(item.isInSuperset ? "Remove from superset" : "Superset with next") {
                controller.send(.toggleSuperset(exerciseID: item.id))
            }
        }
        if item.canMoveUp {
            Button("Move up") {
                controller.send(.moveExerciseBy(exerciseID: item.id, delta: -1))
            }
        }
        if item.canMoveDown {
            Button("Move down") {
                controller.send(.moveExerciseBy(exerciseID: item.id, delta: 1))
            }
        }
        Button("Remove exercise", role: .destructive) {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            controller.send(.removeExercise(exerciseID: item.id))
        }
        Button("Cancel", role: .cancel) {}
    }
}
#endif
