#if os(iOS)
import SwiftUI
import PulseStrengthCore

// MARK: - Sheet

/// Form demo and cues of one exercise (Active.dc.html, `sh.info`).
///
/// Title bar ("Form" + Done), then a scrolling page: the large looping demo (3 : 2, 16 pt radius, "Start · End"
/// badge), the exercise name with chips for the primary muscle, the equipment and the secondary muscles, the
/// numbered "How to" cues and the photo attribution. The demo is `ExerciseMediaView`, which pauses on the first
/// frame when Reduce Motion is on.
@MainActor
public struct FormInfoSheet: View {
    private let exercise: Exercise

    @Environment(\.dismiss) private var dismiss

    public init(exercise: Exercise) {
        self.exercise = exercise
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            FormInfoHeader(onDone: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    demoTile
                    titleBlock
                    if !exercise.cues.isEmpty {
                        cuesCard
                    }
                    attribution
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PulseTheme.ground.ignoresSafeArea())
    }

    // MARK: Demo

    private var hasMedia: Bool {
        guard let key = exercise.mediaKey else { return false }
        return !key.isEmpty
    }

    /// 358 x 239 in the design: full width, 3 : 2.
    private var demoTile: some View {
        Color.clear
            .aspectRatio(358.0 / 239.0, contentMode: .fit)
            .overlay { demoContent }
            .overlay(alignment: .bottomLeading) { startEndBadge }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(demoAccessibilityLabel)
    }

    @ViewBuilder
    private var demoContent: some View {
        if hasMedia {
            ExerciseMediaView(mediaKey: exercise.mediaKey, cornerRadius: 16)
        } else {
            noDemoPlaceholder
        }
    }

    private var noDemoPlaceholder: some View {
        ZStack {
            PulseTheme.progressTrack
            VStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(PulseTheme.inkTertiary)
                Text("No form demo for this exercise yet")
                    .font(PulseFont.subhead)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var startEndBadge: some View {
        if hasMedia {
            Text("Start · End")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(10)
        }
    }

    private var demoAccessibilityLabel: String {
        if hasMedia {
            return "Form demo for " + exercise.name + ", alternating between the start and the end position"
        }
        return "No form demo for this exercise yet"
    }

    // MARK: Name and chips

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: exercise.name)
                .font(PulseFont.title)
                .foregroundStyle(PulseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            FormInfoChipFlowLayout(spacing: 6, lineSpacing: 6) {
                FormInfoChip(text: exercise.muscle.title, isPrimary: true)
                FormInfoChip(text: exercise.equipment.title, isPrimary: false)
                if showsSecondary {
                    FormInfoChip(text: exercise.secondary, isPrimary: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Custom exercises carry the placeholder "Custom" instead of secondary muscles; nothing to show then.
    private var showsSecondary: Bool {
        !exercise.secondary.isEmpty && exercise.secondary != "Custom"
    }

    // MARK: Cues

    private var cuesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to")
                .font(PulseFont.headline)
                .foregroundStyle(PulseTheme.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(exercise.cues.enumerated()), id: \.offset) { pair in
                FormInfoCueRow(number: pair.offset + 1, text: pair.element)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Attribution

    private var attribution: some View {
        Text("Demo photos: Free Exercise DB (public domain).")
            .font(PulseFont.caption2)
            .foregroundStyle(PulseTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Colours

private enum FormInfoColors {
    /// The 12 % green wash behind the primary-muscle chip and the cue numbers.
    static let greenWash = Color(light: 0x1B8448, dark: 0x30D158, lightAlpha: 0.12, darkAlpha: 0.18)
}

// MARK: - Title bar

private struct FormInfoHeader: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Text("Form")
                .font(PulseFont.headline)
                .foregroundStyle(PulseTheme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer(minLength: 0)
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PulseTheme.green)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PulsePlainButtonStyle())
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
    }
}

// MARK: - Chip

/// Pill with the primary muscle (green) or the equipment / secondary muscles (grey).
private struct FormInfoChip: View {
    let text: String
    let isPrimary: Bool

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: isPrimary ? .semibold : .regular))
            .foregroundStyle(isPrimary ? PulseTheme.greenText : PulseTheme.ink.opacity(0.8))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(fill, in: Capsule())
    }

    private var fill: Color {
        isPrimary ? FormInfoColors.greenWash : PulseTheme.chipFill
    }
}

// MARK: - Cue row

/// "1  Lie back with your eyes under the bar." A 24 pt green number badge and the cue text.
private struct FormInfoCueRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(number))
                .pulseNumber(13, .bold)
                .foregroundStyle(PulseTheme.greenText)
                .frame(width: 24, height: 24)
                .background(FormInfoColors.greenWash, in: Circle())
            Text(verbatim: text)
                .font(PulseFont.subhead)
                .foregroundStyle(PulseTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step " + String(number) + ". " + text)
    }
}

// MARK: - Flow layout

/// Wraps its children onto several lines (a CSS flex-wrap row).
private struct FormInfoChipFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    struct Arrangement {
        var origins: [CGPoint]
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            let origin = arrangement.origins[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
        let limit: CGFloat = width ?? CGFloat.infinity
        var sizes: [CGSize] = []
        for subview in subviews {
            sizes.append(subview.sizeThatFits(.unspecified))
        }

        var origins = [CGPoint](repeating: .zero, count: sizes.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for index in sizes.indices {
            let itemSize = sizes[index]
            if x > 0 && x + itemSize.width > limit {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins[index] = CGPoint(x: x, y: y)
            x += itemSize.width
            usedWidth = max(usedWidth, x)
            x += spacing
            rowHeight = max(rowHeight, itemSize.height)
        }
        return Arrangement(origins: origins, size: CGSize(width: usedWidth, height: y + rowHeight))
    }
}
#endif
