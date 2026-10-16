// NextUpAccessoryWidget.swift
//
// One widget, three families, all from `snapshot.nextUp`:
//   LS-04 Quick start (accessoryCircular): the play glyph; the whole widget starts the suggested workout (`StrengthDeepLink.startNext`).
//         While a workout runs it opens that workout instead, so a second start can never be triggered from the Lock Screen; with no
//         workout to start it opens the hub, where one is created.
//   LS-05 Next workout (accessoryRectangular): "NEXT UP", the name and "6 exercises · ~55 min". A tap opens the hub, because this card is
//         for reading; the circle is the button.
//   LS-10 Inline split (accessoryInline): "Push day · last 5 days ago".
//   LS-11 Inline rest day (accessoryInline): "Rest day · back on Sun", shown instead of LS-10 whenever `snapshot.restDay` is set.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct NextUpAccessoryWidget: Widget {
    static let kind = "health.pulse.strength.widget.nextUpAccessory"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            NextUpAccessoryView(entry: entry)
        }
        .configurationDisplayName("Next workout")
        .description("Start your next workout, or see what is up next as a card or a line above the clock.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextUpAccessoryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var environmentFamily
    /// Set by the snapshot tests: `widgetFamily` is read-only in the environment, so a renderer cannot choose the layout through it.
    var familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        content
            .lockContainerBackground()
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            inline
                .widgetURL(StrengthDeepLink.hub.url)
        case .accessoryRectangular:
            rectangular
                .widgetURL(StrengthDeepLink.hub.url)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rectangularSentence)
        default:
            quickStart
                .widgetURL(quickStartLink.url)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(LockAccessoryText.quickStartSentence(snapshot))
                .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Circular: quick start

    private var quickStartLink: StrengthDeepLink {
        if snapshot.active != nil { return .workout }
        return snapshot.nextUp == nil ? .hub : .startNext
    }

    /// With nothing to start the glyph is a plus, because the tap then opens the hub instead of starting anything.
    private var quickStart: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: snapshot.active == nil && snapshot.nextUp == nil ? "plus.circle" : "play.circle")
                .font(.system(size: 36, weight: .medium))
                .widgetAccentable()
        }
    }

    // MARK: Rectangular: next workout

    private var rectangularSentence: String {
        guard let next = snapshot.nextUp else { return "No workouts yet. Add one in the app." }
        return LockAccessoryText.nextUpSentence(next)
    }

    private var rectangular: some View {
        LockAccessoryCard {
            if let next = snapshot.nextUp {
                LockAccessoryLines(eyebrow: "NEXT UP", detail: LockAccessoryText.nextUpDetail(next)) {
                    LockAccessoryTitle(text: next.name)
                        .widgetAccentable()
                }
            } else {
                LockAccessoryLines(eyebrow: "NEXT UP", detail: "Add one in the app") {
                    LockAccessoryTitle(text: "No workouts yet")
                }
            }
        }
    }

    // MARK: Inline: split or rest day

    @ViewBuilder
    private var inline: some View {
        if let rest = snapshot.restDay {
            Text(LockAccessoryText.restLine(rest, tomorrow: snapshot.tomorrow))
                .accessibilityLabel(LockAccessoryText.restSentence(rest, tomorrow: snapshot.tomorrow))
        } else if let next = snapshot.nextUp {
            Text(LockAccessoryText.splitLine(next))
                .accessibilityLabel(LockAccessoryText.splitSentence(next))
        } else {
            Text("No workouts yet")
        }
    }
}
#endif
