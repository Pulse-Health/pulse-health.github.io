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
        .description("Start your next workout from the circle, or read it as a card or a line above the clock. On a rest day the line says when you are back.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextUpAccessoryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

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
                .accessibilityLabel(LockText.quickStartSentence(snapshot))
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
                .font(.system(size: 36))
                .widgetAccentable()
        }
    }

    // MARK: Rectangular: next workout

    private var rectangularSentence: String {
        guard let next = snapshot.nextUp else { return "No workouts yet. Add one in the app." }
        return LockText.nextUpSentence(next)
    }

    private var rectangular: some View {
        LockCard {
            if let next = snapshot.nextUp {
                LockLines(eyebrow: "NEXT UP", detail: LockText.nextUpDetail(next)) {
                    LockTitle(text: next.name)
                        .widgetAccentable()
                }
            } else {
                LockLines(eyebrow: "NEXT UP", detail: "Add one in the app") {
                    LockTitle(text: "No workouts yet")
                }
            }
        }
    }

    // MARK: Inline: split or rest day

    @ViewBuilder
    private var inline: some View {
        if let rest = snapshot.restDay {
            Text(LockText.restLine(rest, tomorrow: snapshot.tomorrow))
                .accessibilityLabel(LockText.restSentence(rest, tomorrow: snapshot.tomorrow))
        } else if let next = snapshot.nextUp {
            Text(LockText.splitLine(next))
                .accessibilityLabel(LockText.splitSentence(next))
        } else {
            Text("No workouts yet")
        }
    }
}
#endif
