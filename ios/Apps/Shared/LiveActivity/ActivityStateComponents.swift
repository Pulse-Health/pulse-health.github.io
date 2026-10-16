// ActivityStateComponents.swift
//
// Building blocks of the live moments of the Live Activity (widgets/SPEC.md LA-01...LA-05, LA-08), shared by the Lock Screen card and
// the Dynamic Island: the gold record banner, the superset rows, the plate strip, the compact set dots and the coach tip choices.
// Compiled into the widget extension next to ActivityComponents.swift. The same rules apply: no live timers here, colours are explicit
// (the surfaces are always dark), every element that carries meaning has a spoken label, and nothing is told by colour alone (the
// record has its words, the current member its tag and ring, the plates their sum).

#if os(iOS)
import AppIntents
import SwiftUI
import PulseStrengthActivity
import PulseStrengthCore

// MARK: - Record banner

/// The gold trophy disc of the record banner and the expanded island.
struct ActivityTrophyDisc: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(ActivityTheme.gold)
            Image(systemName: "trophy.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(ActivityTheme.goldInk)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// LA-01: the gold "NEW RECORD" banner with the lift, `weight × reps` and the new estimated 1RM with its change. 56 pt tall on the
/// Lock Screen, 44 pt in the expanded island.
struct ActivityMomentBanner: View {
    let moment: PRMoment
    var surface: ActivitySurface = .lockScreen

    private var isCompact: Bool {
        surface == .island
    }

    var body: some View {
        HStack(spacing: isCompact ? 10 : 12) {
            ActivityTrophyDisc(size: isCompact ? 28 : ActivityTheme.Metrics.lockBannerDisc)
            VStack(alignment: .leading, spacing: 0) {
                Text("NEW RECORD")
                    .font(ActivityTheme.text(isCompact ? 11 : 13, .bold))
                    .foregroundStyle(ActivityTheme.gold)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(moment.exerciseName)
                        .lineLimit(1)
                    Text(moment.workText)
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(ActivityTheme.text(isCompact ? 15 : 17, .bold))
                .foregroundStyle(ActivityTheme.textPrimary)
            }
            Spacer(minLength: 8)
            if moment.estimated1RM > 0 {
                estimate
            }
        }
        .padding(.horizontal, 12)
        .frame(height: isCompact ? ActivityTheme.Metrics.islandBannerHeight : ActivityTheme.Metrics.lockBannerHeight)
        .background(ActivityTheme.goldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(moment.spokenText)
    }

    /// The new estimated 1RM and, under it, how much it rose.
    private var estimate: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(String(moment.estimated1RM))
                .font(ActivityTheme.number(isCompact ? 17 : 20, .bold))
                .foregroundStyle(ActivityTheme.textPrimary)
            Text(moment.deltaText)
                .font(ActivityTheme.text(11))
                .foregroundStyle(surface.secondaryText)
        }
        .lineLimit(1)
    }
}

// MARK: - Set dots

/// LA-08: one dot per set of the shown exercise in the compact island: filled green when logged, ringed for the set that is next,
/// dim for the ones still to do. More sets than fit the slot shrink the dots, and beyond that the dots give way to "3/9".
struct ActivitySetDots: View {
    let done: Int
    let total: Int

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Set " + String(position) + " of " + String(total))
    }

    /// The set that is next (1-based); the last one when every set is logged.
    private var position: Int {
        min(done + 1, max(total, 1))
    }

    @ViewBuilder
    private var content: some View {
        if let metrics = ActivitySetDots.metrics(count: total) {
            HStack(spacing: metrics.gap) {
                ForEach(0..<total, id: \.self) { index in
                    dot(at: index, size: metrics.size)
                }
            }
        } else {
            Text(String(min(done, total)) + "/" + String(total))
                .font(ActivityTheme.number(13, .semibold))
                .foregroundStyle(ActivityTheme.done)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private func dot(at index: Int, size: CGFloat) -> some View {
        if index < done {
            Circle()
                .fill(ActivityTheme.done)
                .frame(width: size, height: size)
        } else if index == done {
            Circle()
                .strokeBorder(ActivityTheme.done, lineWidth: size >= 6 ? 1.5 : 1)
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(ActivityTheme.dotDim)
                .frame(width: size, height: size)
        }
    }

    /// Dot size and gap that fit `count` dots into `Metrics.compactDotsWidth`; nil when even the smallest do not fit.
    static func metrics(count: Int) -> (size: CGFloat, gap: CGFloat)? {
        guard count > 0 else { return nil }
        let candidates: [(size: CGFloat, gap: CGFloat)] = [(7, 4), (6, 3), (5, 3), (4, 2)]
        for candidate in candidates {
            let width = CGFloat(count) * candidate.size + CGFloat(count - 1) * candidate.gap
            if width <= ActivityTheme.Metrics.compactDotsWidth {
                return candidate
            }
        }
        return nil
    }
}

// MARK: - Plates

/// The end of a barbell as the design draws it: the sleeve, the collar, the plates from the heaviest outwards (at most four are
/// drawn; the summary names all of them) and the end of the bar. Plate height and thickness follow the weight, and the colour
/// follows the usual plate colours, but the sum beside it is what carries the information.
struct ActivityPlateStrip: View {
    let perSide: [Double]
    var height: CGFloat

    private static let drawnLimit = 4
    private static let sleeve = ActivityTheme.hex(0x8E8E93)
    private static let collar = ActivityTheme.hex(0xAEAEB2)

    private var shown: [Double] {
        Array(perSide.prefix(ActivityPlateStrip.drawnLimit))
    }

    /// The thicknesses below are for a 40 pt strip; a smaller one scales them down but keeps every plate at least 3 pt thick.
    private var scale: CGFloat {
        height / 40
    }

    var body: some View {
        HStack(spacing: max(1, 2 * scale)) {
            bar(width: height * 0.55)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(ActivityPlateStrip.collar)
                .frame(width: max(3, 4 * scale), height: height * 0.36)
            ForEach(0..<shown.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ActivityPlateStrip.color(of: shown[index]))
                    .frame(
                        width: max(3, ActivityPlateStrip.thickness(of: shown[index]) * scale),
                        height: height * ActivityPlateStrip.fraction(of: shown[index])
                    )
            }
            bar(width: height * 0.3)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(ActivityPlateStrip.sleeve)
            .frame(width: width, height: max(3, height * 0.12))
    }

    /// Share of the strip's height a plate fills: 25 kg all of it, 1.25 kg about a third.
    private static func fraction(of plate: Double) -> CGFloat {
        if plate >= 25 { return 1 }
        if plate >= 20 { return 0.9 }
        if plate >= 15 { return 0.8 }
        if plate >= 10 { return 0.7 }
        if plate >= 5 { return 0.55 }
        if plate >= 2.5 { return 0.45 }
        return 0.35
    }

    private static func thickness(of plate: Double) -> CGFloat {
        if plate >= 10 { return 8 }
        if plate >= 5 { return 6 }
        return 5
    }

    private static func color(of plate: Double) -> Color {
        if plate >= 25 { return ActivityTheme.hex(0xFF453A) }
        if plate >= 20 { return ActivityTheme.blue }
        if plate >= 15 { return ActivityTheme.gold }
        if plate >= 10 { return ActivityTheme.done }
        if plate >= 5 { return ActivityTheme.hex(0xE5E5EA) }
        if plate >= 2.5 { return ActivityTheme.hex(0xFF9F0A) }
        return ActivityTheme.hex(0xAEAEB2)
    }
}

/// LA-03: the plate row of the logging card, beside the Log set button: the strip, the sum ("20 + 10 + 2.5") and "per side".
struct ActivityPlateRow: View {
    let plates: PlateBrief
    var height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            ActivityPlateStrip(perSide: plates.perSide, height: height - 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(plates.displaySummary)
                    .font(ActivityTheme.number(14, .bold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(plates.caption)
                    .font(ActivityTheme.number(12, .regular))
                    .foregroundStyle(ActivityTheme.lockTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(ActivityTheme.lockTileFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plates.spokenText)
    }
}

// MARK: - Superset

/// LA-02: the members of the running superset, one row each. A logged member has a green check and its tag in the text, the current
/// one is ringed in blue and carries its tag on a blue disc, the others wait on a grey disc. On the Lock Screen the rows are the
/// design's (disc, name, `weight × reps`); the island uses a quieter row (status glyph, "A2 name", detail).
struct ActivitySupersetRows: View {
    let members: [SupersetMember]
    let surface: ActivitySurface

    /// The members that are drawn: at most `Metrics.supersetRowLimit`, the current one always among them.
    private var shown: [SupersetMember] {
        ActivityContentFitting.window(of: members, size: ActivityTheme.Metrics.supersetRowLimit)
    }

    private var isIsland: Bool {
        surface == .island
    }

    private var rowHeight: CGFloat {
        isIsland
            ? ActivityTheme.Metrics.islandSupersetRowHeight(members: shown.count)
            : ActivityTheme.Metrics.lockSupersetRowHeight(members: shown.count)
    }

    private var rowSpacing: CGFloat {
        isIsland ? ActivityTheme.Metrics.islandSupersetRowSpacing : ActivityTheme.Metrics.lockSupersetRowSpacing
    }

    /// Height of all rows together; the Log button next to them is as tall.
    var totalHeight: CGFloat {
        let count = CGFloat(shown.count)
        return count * rowHeight + max(0, count - 1) * rowSpacing
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(0..<shown.count, id: \.self) { index in
                row(shown[index])
            }
        }
    }

    private func row(_ member: SupersetMember) -> some View {
        HStack(spacing: 8) {
            marker(for: member)
            Text(isIsland || member.isDone ? member.tag + " " + member.name : member.name)
                .font(ActivityTheme.text(isIsland ? 14 : 15, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(member.detail)
                .font(ActivityTheme.number(isIsland ? 13 : 14, .regular))
                .foregroundStyle(surface.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(member.isCurrent ? ActivityTheme.blueRowFill : surface.rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if member.isCurrent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ActivityTheme.blue, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(member.spokenRow)
    }

    /// Lock Screen: a disc with the check (logged) or the tag. Island: a small check, ring or dot.
    @ViewBuilder
    private func marker(for member: SupersetMember) -> some View {
        if isIsland {
            islandMarker(for: member)
        } else {
            let size = min(26, rowHeight - 6)
            ZStack {
                Circle()
                    .fill(discFill(for: member))
                if member.isDone {
                    ActivityGlyph(kind: .check, size: size * 0.5, lineWidth: 3, color: Color.black)
                } else {
                    Text(member.tag)
                        .font(ActivityTheme.number(size * 0.46, .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private func islandMarker(for member: SupersetMember) -> some View {
        if member.isDone {
            ActivityGlyph(kind: .check, size: 12, lineWidth: 3, color: ActivityTheme.done)
                .frame(width: 12, height: 12)
        } else if member.isCurrent {
            Circle()
                .strokeBorder(ActivityTheme.blue, lineWidth: 2)
                .frame(width: 12, height: 12)
        } else {
            Circle()
                .fill(ActivityTheme.dotDim)
                .frame(width: 12, height: 12)
        }
    }

    private func discFill(for member: SupersetMember) -> Color {
        if member.isDone { return ActivityTheme.done }
        return member.isCurrent ? ActivityTheme.blue : ActivityTheme.lockControlFill
    }
}

/// The green Log button next to the member rows: a check over "Log A2", as tall as the rows.
struct ActivityTallLogButton: View {
    let intent: LogSetIntent
    let title: String
    let spokenTitle: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 4) {
                ActivityGlyph(kind: .check, size: 20, lineWidth: 3.2, color: Color.white)
                Text(title)
                    .font(ActivityTheme.text(16, .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: width, height: height)
            .background(ActivityTheme.buttonGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenTitle)
    }
}

// MARK: - Coach tip

/// LA-04: the answer to the coach tip. The suggested weight is a real button (`ApplyCoachTipIntent` sets the weight of the set the
/// tip names); "Keep 80" is plain text and not a button on purpose: the tip is not stored in the workout, so nothing could dismiss
/// it, and a button that does nothing would only pretend. Ignoring the tip keeps the weight. "Skip" stays within reach because the
/// tip card has no -15 s / +15 s / Skip row.
struct ActivityTipChoices: View {
    let tip: CoachTipBrief
    let surface: ActivitySurface
    let height: CGFloat

    var body: some View {
        ActivityWeightedRow(weights: [1.5, 1, 0.7], spacing: 8) {
            applyButton
            keepLabel
            skipButton
        }
        .frame(height: height)
    }

    private var radius: CGFloat {
        surface.buttonRadius(height: height)
    }

    private var applyButton: some View {
        Button(intent: ApplyCoachTipIntent(
            setID: tip.targetSetID.uuidString,
            exerciseID: tip.targetExerciseID.uuidString,
            weightKg: tip.suggestedWeightKg
        )) {
            Text(tip.suggestedWeightText)
                .font(ActivityTheme.number(15, .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(ActivityTheme.buttonGreen, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tip.applySpokenTitle)
    }

    private var keepLabel: some View {
        Text(tip.keepWeightText)
            .font(ActivityTheme.number(15, .semibold))
            .foregroundStyle(surface.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityLabel(tip.keepWeightText + " by ignoring the tip")
    }

    private var skipButton: some View {
        Button(intent: SkipRestIntent()) {
            Text("Skip")
                .font(ActivityTheme.text(15, .semibold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(surface.controlFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip rest")
    }
}
#endif
