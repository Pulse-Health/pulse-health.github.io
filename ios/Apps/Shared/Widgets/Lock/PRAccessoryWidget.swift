// PRAccessoryWidget.swift
//
// LS-07 Latest record (accessoryRectangular): the trophy, "LATEST PR", "Bench Press 85 × 5" and "e1RM 99 kg", from `snapshot.latestPR`.
// The exercise name is the part that gives way in a narrow card; the weight and reps never do. A tap opens that exercise's detail; before
// the first record it opens the Strength hub.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct PRAccessoryWidget: Widget {
    static let kind = "health.pulse.strength.widget.prAccessory"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            PRAccessoryView(entry: entry)
        }
        .configurationDisplayName("Latest record")
        .description("Your newest personal record with its estimated one-rep max.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct PRAccessoryView: View {
    let entry: SnapshotEntry

    private var pr: PRSummary? { entry.snapshot.latestPR }

    private var link: StrengthDeepLink {
        guard let pr else { return .hub }
        return .exercise(id: pr.exerciseID)
    }

    private var sentence: String {
        guard let pr else { return "No personal records yet. Beat a best to set one." }
        return LockAccessoryText.prSentence(pr)
    }

    var body: some View {
        LockAccessoryCard {
            HStack(spacing: 10) {
                Image(systemName: pr == nil ? "trophy" : "trophy.fill")
                    .font(.system(size: 24))
                    .widgetAccentable()
                lines
            }
        }
        .lockContainerBackground()
        .widgetURL(link.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence)
    }

    @ViewBuilder
    private var lines: some View {
        if let pr {
            LockAccessoryLines(eyebrow: "LATEST PR", detail: LockAccessoryText.prDetail(pr), detailFont: WidgetTheme.number(12, .regular)) {
                LockAccessoryHeadline(name: pr.exerciseName, figure: WidgetText.weightReps(pr.weightKg, pr.reps))
                    .widgetAccentable()
            }
        } else {
            LockAccessoryLines(eyebrow: "LATEST PR", detail: "Beat a best to set one", detailFont: WidgetTheme.text(12)) {
                LockAccessoryTitle(text: "No records yet")
            }
        }
    }
}
#endif
