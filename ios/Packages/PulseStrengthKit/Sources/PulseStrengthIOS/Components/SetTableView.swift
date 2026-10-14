#if os(iOS)
import SwiftUI
import PulseStrengthCore

/// Column titles plus the set rows of the exercise card.
///
/// The rows take their natural height. When the space left in the card is smaller than that (many sets),
/// the rows move into a vertical `ScrollView` without indicators that fills the remaining space instead,
/// so the header, "Add Set", rest chip, note and coach tip around the table never move.
struct SetTableView: View {
    let weightColumnTitle: String
    let repsColumnTitle: String
    let rows: [ActiveWorkoutPresentation.SetRow]
    let onToggle: (ActiveWorkoutPresentation.SetRow) -> Void
    let onOpenDetail: (ActiveWorkoutPresentation.SetRow) -> Void
    let onOpenKeypad: (ActiveWorkoutPresentation.SetRow, KeypadField) -> Void

    init(
        weightColumnTitle: String,
        repsColumnTitle: String,
        rows: [ActiveWorkoutPresentation.SetRow],
        onToggle: @escaping (ActiveWorkoutPresentation.SetRow) -> Void,
        onOpenDetail: @escaping (ActiveWorkoutPresentation.SetRow) -> Void,
        onOpenKeypad: @escaping (ActiveWorkoutPresentation.SetRow, KeypadField) -> Void
    ) {
        self.weightColumnTitle = weightColumnTitle
        self.repsColumnTitle = repsColumnTitle
        self.rows = rows
        self.onToggle = onToggle
        self.onOpenDetail = onOpenDetail
        self.onOpenKeypad = onOpenKeypad
    }

    var body: some View {
        VStack(spacing: 3) {
            SetTableColumnHeader(weightTitle: weightColumnTitle, repsTitle: repsColumnTitle)
            ViewThatFits(in: .vertical) {
                rowList
                ScrollView(showsIndicators: false) {
                    rowList
                }
            }
        }
    }

    private var rowList: some View {
        VStack(spacing: 3) {
            ForEach(rows) { row in
                SetRowView(
                    row: row,
                    repsAccessibilityName: repsAccessibilityName,
                    onToggle: { onToggle(row) },
                    onOpenDetail: { onOpenDetail(row) },
                    onOpenKeypad: { field in onOpenKeypad(row, field) }
                )
            }
        }
    }

    /// "Sec" (duration exercises) is spoken as seconds, everything else as reps.
    private var repsAccessibilityName: String {
        repsColumnTitle.lowercased() == "sec" ? "seconds" : "reps"
    }
}

// MARK: - Column titles

/// "SET  PREVIOUS  KG  REPS" in 11 pt semibold caps (the text grows with Dynamic Type, a long title shrinks to its column).
/// The columns use the same geometry as `SetRowView`
/// (10 pt leading inset, 36 / flexible / 68 / 60 pt columns, 44 pt check column) so every title sits over its cells.
private struct SetTableColumnHeader: View {
    let weightTitle: String
    let repsTitle: String

    var body: some View {
        HStack(spacing: 6) {
            title("Set")
                .frame(width: 36, alignment: .leading)
            title("Previous")
                .frame(maxWidth: .infinity, alignment: .leading)
            title(weightTitle)
                .frame(width: 68)
            title(repsTitle)
                .frame(width: 60)
            Color.clear
                .frame(width: 44, height: 16)
        }
        .padding(.leading, 10)
        .frame(minHeight: 16)
        .accessibilityHidden(true)
    }

    private func title(_ text: String) -> some View {
        Text(verbatim: text)
            .tracking(0.4)
            .pulseFont(11, .semibold, relativeTo: .caption2)
            .textCase(.uppercase)
            .foregroundStyle(PulseTheme.inkSecondary)
            .lineLimit(1)
            .pulseShrinkWhenLarger(0.7)
    }
}
#endif
