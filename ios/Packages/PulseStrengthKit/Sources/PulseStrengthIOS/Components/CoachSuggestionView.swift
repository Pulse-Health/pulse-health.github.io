#if os(iOS)
import SwiftUI
import Foundation
import PulseStrengthCore

/// The "Next time · 82.5 kg × 6" suggestion at the bottom of an exercise card, with an "Apply" button that sets the pending working
/// sets to it. Styled like `CoachTipView`; shown before the first set of the exercise is logged.
///
/// Without something to apply (the "Log RIR" hint) there is no button.
struct CoachSuggestionView: View {
    let line: CoachLine
    let canApply: Bool
    let onApply: () -> Void

    /// The 13 pt text and the 13 pt button label grow with Dynamic Type like the coach tip.
    @PulseScaled(13, relativeTo: .footnote) private var textSize: CGFloat

    init(line: CoachLine, canApply: Bool, onApply: @escaping () -> Void) {
        self.line = line
        self.canApply = canApply
        self.onApply = onApply
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            texts
                .frame(maxWidth: .infinity, alignment: .leading)
            if canApply {
                applyButton
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            PulseTheme.coachTipFill,
            in: RoundedRectangle(cornerRadius: PulseTheme.rowRadius, style: .continuous)
        )
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            let title: Text = Text("Next time · ").fontWeight(.semibold) + Text(verbatim: line.headline).fontWeight(.semibold)
            title
                .font(.system(size: textSize))
                .foregroundStyle(PulseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = line.detail {
                Text(verbatim: detail)
                    .font(.system(size: textSize - 1))
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var applyButton: some View {
        Button(action: onApply) {
            Text("Apply")
                .font(.system(size: textSize, weight: .semibold))
                .foregroundStyle(PulseTheme.onGreen)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(PulseTheme.green, in: Capsule())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel("Apply suggested weight and reps")
        .accessibilityIdentifier("coach-apply")
    }
}
#endif
