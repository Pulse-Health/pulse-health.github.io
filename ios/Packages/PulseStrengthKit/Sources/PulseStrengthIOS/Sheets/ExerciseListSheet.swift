#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Shared title bar of the exercise sheets

/// The 56 pt sheet header of the design: a centred 17 pt semibold title with an optional green text button on
/// each side ("Cancel" regular, "Done" / "Save" semibold). Used by the list, picker and create sheets.
struct ExerciseEditorTitleBar: View {
    let title: String
    let leadingTitle: String?
    let leadingAction: () -> Void
    let trailingTitle: String?
    let trailingAction: () -> Void

    init(
        title: String,
        leadingTitle: String? = nil,
        leadingAction: @escaping () -> Void = {},
        trailingTitle: String? = nil,
        trailingAction: @escaping () -> Void = {}
    ) {
        self.title = title
        self.leadingTitle = leadingTitle
        self.leadingAction = leadingAction
        self.trailingTitle = trailingTitle
        self.trailingAction = trailingAction
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(PulseFont.headline)
                .foregroundStyle(PulseTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 88)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                if let leadingTitle = leadingTitle {
                    barButton(leadingTitle, weight: .regular, alignment: .leading, action: leadingAction)
                }
                Spacer(minLength: 0)
                if let trailingTitle = trailingTitle {
                    barButton(trailingTitle, weight: .semibold, alignment: .trailing, action: trailingAction)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func barButton(
        _ label: String,
        weight: Font.Weight,
        alignment: Alignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: weight))
                .foregroundStyle(PulseTheme.green)
                .frame(minWidth: 44, minHeight: 44, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
    }
}

// MARK: - Sheets that hug their content

/// The natural height of a sheet's panel (everything under the title bar), reported by `reportsSheetPanelHeight()`.
struct SheetPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Reports the natural height of this view (the panel of a bottom sheet) to `sheetDetentsHuggingContent`.
    func reportsSheetPanelHeight() -> some View {
        background(
            GeometryReader { (proxy: GeometryProxy) in
                Color.clear.preference(key: SheetPanelHeightKey.self, value: proxy.size.height)
            }
        )
    }

    /// Makes the sheet this view is the content of exactly as tall as its content (title bar plus the panel that
    /// reports its height), like the design's bottom sheets; it can still be dragged up to the full height.
    /// A `.height` detent is the height of the content area, the system adds the bottom safe area to it, so the
    /// content is measured with the safe area respected. `estimate` is the height used until the panel has been measured.
    func sheetDetentsHuggingContent(titleBarHeight: CGFloat, estimate: CGFloat) -> some View {
        modifier(SheetHugsContentModifier(titleBarHeight: titleBarHeight, estimate: estimate))
    }
}

private struct SheetHugsContentModifier: ViewModifier {
    let titleBarHeight: CGFloat
    let estimate: CGFloat

    @State private var panelHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(SheetPanelHeightKey.self) { (height: CGFloat) in
                panelHeight = height
            }
            .presentationDetents(detents)
    }

    private var detents: Set<PresentationDetent> {
        let hugging: CGFloat = panelHeight > 0 ? (titleBarHeight + panelHeight).rounded(.up) : estimate
        return [.height(hugging), .large]
    }
}

// MARK: - Models

/// One row of the list, derived from a workout exercise.
private struct ExerciseListRowModel: Identifiable {
    let id: UUID
    let index: Int
    let exercise: Exercise
    /// "Superset A · 3 of 5 sets · Chest · Now"
    let subtitle: String
}

/// The sheets this sheet presents on top of itself.
private enum ExerciseListNestedSheet: Identifiable {
    case picker(PickerMode)
    case info(Exercise)
    case restSettings(UUID)

    var id: String {
        switch self {
        case .picker(let mode):
            switch mode {
            case .add:
                return "picker-add"
            case .replace(let exerciseID):
                return "picker-replace-" + exerciseID.uuidString
            }
        case .info(let exercise):
            return "info-" + exercise.id
        case .restSettings(let exerciseID):
            return "rest-" + exerciseID.uuidString
        }
    }
}

// MARK: - Sheet

/// "Exercises": the workout's exercises as reorderable rows (system drag handle, edit mode always on),
/// each with its form thumbnail, name, "3 of 5 sets" progress, superset label and an options button.
/// Tapping a row shows that exercise and closes the sheet; "Add Exercise" opens the picker.
/// The sheet owns the sheets it opens (picker, form information, rest timer) and the options dialog.
@MainActor
public struct ExerciseListSheet: View {
    @ObservedObject private var controller: WorkoutController
    private let store: StrengthStore

    @Environment(\.dismiss) private var dismiss
    @State private var optionsExerciseID: UUID?
    @State private var nestedSheet: ExerciseListNestedSheet?

    public init(controller: WorkoutController, store: StrengthStore) {
        self._controller = ObservedObject(wrappedValue: controller)
        self.store = store
    }

    // MARK: Body

    public var body: some View {
        let rows = makeRows()
        return VStack(spacing: 0) {
            ExerciseEditorTitleBar(
                title: "Exercises",
                trailingTitle: "Done",
                trailingAction: { dismiss() }
            )
            summaryLine(count: rows.count)
            exerciseList(rows)
            addExerciseButton
        }
        .background(PulseTheme.ground.ignoresSafeArea())
        .exerciseOptionsDialog(
            controller: controller,
            exerciseID: $optionsExerciseID,
            onShowInfo: { (exercise: Exercise) in
                presentAfterDismissal { nestedSheet = .info(exercise) }
            },
            onShowRestSettings: { (exerciseID: UUID) in
                presentAfterDismissal { nestedSheet = .restSettings(exerciseID) }
            },
            onReplace: { (exerciseID: UUID) in
                presentAfterDismissal { nestedSheet = .picker(.replace(exerciseID: exerciseID)) }
            }
        )
        .sheet(item: $nestedSheet) { (sheet: ExerciseListNestedSheet) in
            nestedContent(sheet)
        }
    }

    // MARK: Pieces

    private func summaryLine(count: Int) -> some View {
        let noun = count == 1 ? "exercise" : "exercises"
        let text = "\(count) \(noun) · Drag the handle to reorder. Superset exercises alternate their sets."
        return Text(text)
            .font(PulseFont.footnote)
            .foregroundStyle(PulseTheme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }

    private func exerciseList(_ rows: [ExerciseListRowModel]) -> some View {
        List {
            ForEach(rows) { (row: ExerciseListRowModel) in
                ExerciseListRowView(
                    row: row,
                    onOpen: { showExercise(row) },
                    onOptions: { optionsExerciseID = row.id }
                )
                .listRowInsets(EdgeInsets(top: 3, leading: 26, bottom: 3, trailing: 4))
                .listRowSeparator(.hidden)
                .listRowBackground(rowBackground)
            }
            .onMove { (source: IndexSet, destination: Int) in
                moveRows(from: source, to: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    /// The white 12 pt card behind a row (the list is full width, so the card is inset by the 16 pt gutter).
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(PulseTheme.card)
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
    }

    private var addExerciseButton: some View {
        Button {
            nestedSheet = .picker(.add)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text("Add Exercise")
            }
        }
        .buttonStyle(PulsePrimaryButtonStyle())
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: Nested sheets

    @ViewBuilder
    private func nestedContent(_ sheet: ExerciseListNestedSheet) -> some View {
        switch sheet {
        case .picker(let mode):
            styled(ExercisePickerSheet(store: store, controller: controller, mode: mode), detents: [.large])
        case .info(let exercise):
            // The same host as the workout card's form sheet: it adds the "History & records" row.
            styled(ActiveFormInfoHost(exercise: exercise, store: store), detents: [.large])
        case .restSettings(let exerciseID):
            // The rest sheet hugs its content and sets its own detents.
            styledHugging(RestSettingsSheet(controller: controller, exerciseID: exerciseID))
        }
    }

    /// The shared look of the sheets: 26 pt top corners, grouped-grey background, no grabber
    /// (each sheet has its own Done / Cancel button).
    private func styled<Content: View>(_ content: Content, detents: Set<PresentationDetent>) -> some View {
        content
            .presentationDetents(detents)
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(PulseTheme.sheetRadius)
            .presentationBackground(PulseTheme.ground)
    }

    /// The same look for a sheet that sizes itself to its content and sets its own detents.
    private func styledHugging<Content: View>(_ content: Content) -> some View {
        content
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(PulseTheme.sheetRadius)
            .presentationBackground(PulseTheme.ground)
    }

    /// Runs `work` once the options dialog that triggered it has finished dismissing, so a sheet opened from a
    /// dialog button is not dropped by SwiftUI's presentation machinery.
    private func presentAfterDismissal(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            work()
        }
    }

    // MARK: Data and actions

    private func makeRows() -> [ExerciseListRowModel] {
        guard let state = controller.state else { return [] }
        let current = state.clampedIndex
        var rows: [ExerciseListRowModel] = []
        for (offset, entry) in state.exercises.enumerated() {
            rows.append(
                ExerciseListRowModel(
                    id: entry.id,
                    index: offset,
                    exercise: entry.exercise,
                    subtitle: Self.subtitle(for: entry, isCurrent: offset == current)
                )
            )
        }
        return rows
    }

    private static func subtitle(for entry: WorkoutExercise, isCurrent: Bool) -> String {
        var text = ""
        if let group = entry.supersetGroup {
            text += "Superset " + group + " · "
        }
        text += "\(entry.doneCount) of \(entry.sets.count) sets · " + entry.exercise.muscle.title
        if isCurrent {
            text += " · Now"
        }
        return text
    }

    private func showExercise(_ row: ExerciseListRowModel) {
        controller.send(.goTo(index: row.index))
        dismiss()
    }

    /// SwiftUI reports the insertion point in the list as it was before the move; the reducer wants the final
    /// index of the moved exercise, which is one less when the row moves down.
    private func moveRows(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        let target = destination > from ? destination - 1 : destination
        guard target != from else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        controller.send(.moveExercise(from: from, to: target))
    }
}

// MARK: - Row

private struct ExerciseListRowView: View {
    let row: ExerciseListRowModel
    let onOpen: () -> Void
    let onOptions: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            openButton
            optionsButton
        }
        .frame(height: 64)
    }

    private var openButton: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ExerciseMediaView(mediaKey: row.exercise.mediaKey, cornerRadius: 10, animated: false)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.exercise.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PulseTheme.ink)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(PulseFont.caption)
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel(row.exercise.name)
        .accessibilityValue(row.subtitle)
        .accessibilityHint("Shows this exercise in the workout")
    }

    private var optionsButton: some View {
        Button(action: onOptions) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(PulseTheme.green)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel("Options for " + row.exercise.name)
    }
}
#endif
