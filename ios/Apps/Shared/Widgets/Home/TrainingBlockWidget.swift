// TrainingBlockWidget.swift
//
// SB-03 iPad training block (systemExtraLarge, iPad only): the derived four-week block as a grid of templates by week, and three stat tiles
// (sessions done, the change of the most trained lift, missed sessions). A cell is a symbol as well as a fill: a check for done, a dash
// for missed, a dashed outline for the current week's session still to do, empty for a week to come.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct TrainingBlockWidget: Widget {
    static let kind = "health.pulse.strength.widget.trainingBlock"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            TrainingBlockView(entry: entry)
        }
        .configurationDisplayName("Training block")
        .description("Your four-week block at a glance: the sessions done and missed per template, on iPad.")
        .supportedFamilies([.systemExtraLarge])
    }
}

struct TrainingBlockView: View {
    let entry: SnapshotEntry

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(StrengthDeepLink.hub.url)
    }

    @ViewBuilder
    private var content: some View {
        if let block = entry.snapshot.block {
            TrainingBlockContent(block: block)
        } else {
            TrainingBlockEmptyContent()
        }
    }
}

private struct TrainingBlockContent: View {
    let block: TrainingBlock

    private var sessionsValue: String {
        block.sessionsPlanned > 0 ? "\(block.sessionsDone) / \(block.sessionsPlanned)" : "\(block.sessionsDone)"
    }

    private var spokenSessions: String {
        block.sessionsPlanned > 0 ? "\(block.sessionsDone) of \(block.sessionsPlanned)" : "\(block.sessionsDone)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(block.name) · Week \(block.weekIndex) of \(block.weekCount)")
                .font(WidgetTheme.text(17, .bold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TrainingBlockGrid(block: block)
                .frame(maxHeight: .infinity)
            HStack(spacing: 10) {
                HomeStatTile(value: sessionsValue, spokenValue: spokenSessions, caption: "Sessions done")
                    .homeInsetCard(padding: 10, cornerRadius: 12)
                liftTile
                HomeStatTile(value: "\(block.sessionsMissed)", caption: "Missed")
                    .homeInsetCard(padding: 10, cornerRadius: 12)
            }
        }
    }

    /// "+4 kg / Bench Press e1RM"; a dash while the most trained lift has fewer than two sessions.
    @ViewBuilder
    private var liftTile: some View {
        let caption = (block.liftName ?? "Top lift") + " e1RM"
        if let delta = block.liftDeltaKg {
            HomeStatTile(value: WidgetText.signed(delta), unit: "kg", spokenUnit: "kilograms", caption: caption)
                .homeInsetCard(padding: 10, cornerRadius: 12)
        } else {
            HomeStatTile(value: "–", spokenValue: "not enough sessions yet", caption: caption)
                .homeInsetCard(padding: 10, cornerRadius: 12)
        }
    }
}

/// The templates (rows) by the weeks of the block (columns), read out as one sentence per template.
private struct TrainingBlockGrid: View {
    let block: TrainingBlock

    private let labelWidth: CGFloat = 64
    private let gap: CGFloat = 6

    private var weeks: [Int] { Array(1...max(1, block.weekCount)) }

    private func state(row: Int, week: Int) -> BlockCellState {
        let cells = block.rows[row].cells
        return week - 1 < cells.count ? cells[week - 1].state : .upcoming
    }

    private func word(for state: BlockCellState) -> String {
        switch state {
        case .done: return "done"
        case .planned: return "planned"
        case .missed: return "missed"
        case .upcoming: return "upcoming"
        }
    }

    private var spoken: String {
        let rows = block.rows.indices.map { row -> String in
            let cells = weeks.map { week -> String in "week \(week) " + word(for: state(row: row, week: week)) }
            return block.rows[row].label + ": " + cells.joined(separator: ", ")
        }
        return block.name + ", week \(block.weekIndex) of \(block.weekCount). " + rows.joined(separator: ". ") + "."
    }

    var body: some View {
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                Color.clear
                    .frame(width: labelWidth, height: 1)
                ForEach(weeks, id: \.self) { week in
                    Text("Wk \(week)")
                        .font(WidgetTheme.text(12, week == block.weekIndex ? .bold : .regular))
                        .foregroundStyle(week == block.weekIndex ? WidgetTheme.ink : WidgetTheme.inkSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(block.rows.indices, id: \.self) { row in
                HStack(spacing: gap) {
                    Text(block.rows[row].label)
                        .font(WidgetTheme.text(12))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(weeks, id: \.self) { week in
                        TrainingBlockCell(state: state(row: row, week: week))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// One template in one week.
private struct TrainingBlockCell: View {
    let state: BlockCellState

    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 34)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .done:
            shape
                .fill(WidgetTheme.green)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WidgetTheme.onGreen)
                }
                .widgetAccentable()
        case .planned:
            shape
                .strokeBorder(WidgetTheme.green, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        case .missed:
            shape
                .fill(WidgetTheme.trackStrong)
                .overlay {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WidgetTheme.ink)
                }
        case .upcoming:
            shape
                .fill(WidgetTheme.muted)
        }
    }
}

/// No history, so no block yet.
private struct TrainingBlockEmptyContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Training block")
                .font(WidgetTheme.text(17, .bold))
                .foregroundStyle(WidgetTheme.ink)
            Spacer(minLength: 4)
            Text("No block yet")
                .font(WidgetTheme.text(22, .bold))
                .foregroundStyle(WidgetTheme.ink)
            Text("Your four-week block appears after your first workout.")
                .font(WidgetTheme.text(15))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
