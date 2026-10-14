#if os(iOS)
import SwiftUI
import PulseStrengthCore

/// One set of the exercise card (Active.dc.html `sets` rows): at least 48 pt tall (it grows when the text does), 10 pt radius.
///
/// Columns: type badge (36 pt) | previous + PR / RIR tags (flexible) | weight cell (68 pt) | reps cell (60 pt) |
/// check circle (44 pt tap target, flush with the row's trailing edge).
///
/// The row is a single VoiceOver element labelled with `row.accessibilityLabel`; activating it toggles the set and the
/// type, weight and reps editors are offered as custom actions. The visible controls keep 44 pt tall tap targets.
struct SetRowView: View {
    let row: ActiveWorkoutPresentation.SetRow
    let repsAccessibilityName: String
    let onToggle: () -> Void
    let onOpenDetail: () -> Void
    let onOpenKeypad: (KeypadField) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        row: ActiveWorkoutPresentation.SetRow,
        repsAccessibilityName: String = "reps",
        onToggle: @escaping () -> Void,
        onOpenDetail: @escaping () -> Void,
        onOpenKeypad: @escaping (KeypadField) -> Void
    ) {
        self.row = row
        self.repsAccessibilityName = repsAccessibilityName
        self.onToggle = onToggle
        self.onOpenDetail = onOpenDetail
        self.onOpenKeypad = onOpenKeypad
    }

    var body: some View {
        HStack(spacing: 6) {
            typeBadge
            infoColumn
            weightCell
            repsCell
            checkButton
        }
        .padding(.leading, 10)
        .frame(minHeight: 48)
        .background(rowFill, in: rowShape)
        .overlay {
            if row.isNext {
                rowShape.strokeBorder(PulseTheme.nextRowRing, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(accessibilityDetails)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { onToggle() }
        .accessibilityAction(named: Text("Change set type")) { onOpenDetail() }
        .modifier(SetRowWeightActionModifier(isEnabled: row.weightEditable) { onOpenKeypad(.weight) })
        .accessibilityAction(named: Text("Edit \(repsAccessibilityName)")) { onOpenKeypad(.reps) }
    }

    // MARK: Row chrome

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PulseTheme.rowRadius, style: .continuous)
    }

    private var rowFill: Color {
        row.isDone ? PulseTheme.doneRowFill : PulseTheme.rowFill
    }

    /// Fill of the weight and reps cells: white on a pending row, 75 % white on a logged (tinted) row.
    private var cellFill: Color {
        row.isDone ? PulseTheme.cellOnTint.opacity(0.75) : PulseTheme.cellOnTint
    }

    // MARK: Columns

    private var typeBadge: some View {
        Button(action: onOpenDetail) {
            Text(row.number)
                .pulseFont(15, .bold, relativeTo: .subheadline)
                .foregroundStyle(row.type.badgeForeground)
                .frame(width: 36, height: 36)
                .background(
                    row.type.badgeBackground,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.previousText)
                .pulseNumber(13, .regular, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if showsTags {
                tagLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsTags: Bool {
        row.isDone && (row.isPersonalRecord || row.rirText != nil)
    }

    private var tagLine: some View {
        HStack(spacing: 5) {
            if row.isPersonalRecord {
                personalRecordTag
            }
            if let rirText = row.rirText {
                Text(rirText)
                    .pulseFont(11, .semibold, relativeTo: .caption2)
                    .foregroundStyle(PulseTheme.ink.opacity(0.75))
            }
        }
        .lineLimit(1)
        .pulseShrinkWhenLarger(0.8)
    }

    private var personalRecordTag: some View {
        HStack(spacing: 2) {
            Image(systemName: "trophy")
                .pulseFont(9, .bold, relativeTo: .caption2)
            Text("PR")
                .pulseFont(11, .bold, relativeTo: .caption2)
        }
        .foregroundStyle(PulseTheme.prText)
    }

    @ViewBuilder
    private var weightCell: some View {
        if row.weightEditable {
            Button {
                onOpenKeypad(.weight)
            } label: {
                valueCell(row.weightText, width: 68)
            }
            .buttonStyle(PulsePlainButtonStyle())
        } else {
            valueCell(row.weightText, width: 68)
                .opacity(0.45)
        }
    }

    private var repsCell: some View {
        Button {
            onOpenKeypad(.reps)
        } label: {
            valueCell(row.repsText, width: 60)
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    /// A value cell (at least 40 pt tall) inside a tap target (at least 44 pt tall). The column widths stay fixed so the
    /// columns line up with the table header; a long figure shrinks (`minimumScaleFactor`) instead of overflowing.
    private func valueCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .pulseNumber(18, .semibold, relativeTo: .body)
            .foregroundStyle(PulseTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .frame(width: width)
            .frame(minHeight: 40)
            .background(cellFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: width)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private var checkButton: some View {
        Button(action: onToggle) {
            SetRowCheckCircle(isDone: row.isDone)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: row.isDone)
    }

    // MARK: Accessibility

    private var accessibilityHintText: String {
        row.isDone ? "Double tap to mark as not logged." : "Double tap to log this set."
    }

    /// Extra spoken detail that is not part of the sentence-style label: personal record with its estimated 1RM,
    /// and the recorded reps in reserve.
    private var accessibilityDetails: String {
        var parts: [String] = []
        if row.isPersonalRecord {
            if let e1rm = row.estimated1RM {
                parts.append("Personal record, estimated one rep max \(e1rm) kilograms")
            } else {
                parts.append("Personal record")
            }
        }
        if row.isDone, let rir = row.rir {
            if rir >= 4 {
                parts.append("4 or more reps in reserve")
            } else {
                parts.append("\(rir) reps in reserve")
            }
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Check circle

/// The 28 pt log toggle: grey ring while pending, solid green with a white check when logged.
private struct SetRowCheckCircle: View {
    let isDone: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isDone ? PulseTheme.green : Color.clear)
            Circle()
                .strokeBorder(isDone ? PulseTheme.green : PulseTheme.inkTertiary, lineWidth: 2)
            SetRowCheckmarkShape()
                .stroke(
                    PulseTheme.onGreen,
                    style: StrokeStyle(lineWidth: 3.2 * 16 / 24, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 16, height: 16)
                .opacity(isDone ? 1 : 0)
        }
        .frame(width: 28, height: 28)
    }
}

/// The design's check path ("M5 12.5l4.5 4.5L19 7.5" in a 24 x 24 box).
private struct SetRowCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 5 / 24, y: rect.minY + rect.height * 12.5 / 24))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 9.5 / 24, y: rect.minY + rect.height * 17 / 24))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 19 / 24, y: rect.minY + rect.height * 7.5 / 24))
        return path
    }
}

// MARK: - Conditional accessibility action

/// Adds the "Edit weight" VoiceOver action only for rows whose weight can be edited.
private struct SetRowWeightActionModifier: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    init(isEnabled: Bool, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityAction(named: Text("Edit weight")) { action() }
        } else {
            content
        }
    }
}
#endif
