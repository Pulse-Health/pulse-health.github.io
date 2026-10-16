// RestWatchWidgets.swift
//
// WA-02 the live rest complication (`RestWidget`: rectangular, circular and inline) and WA-05 the Smart Stack rest card (`RestWatchWidget`,
// with +15 and Skip). Both read `WidgetSnapshot.active`, the running workout the iPhone published.
//
// The countdown is drawn by the system: `Text(timerInterval:countsDown:)` and `ProgressView(timerInterval:countsDown:)` keep counting without
// the extension running. The timeline has an entry at the end of the rest, which switches the card to "Go". While the workout is paused
// nothing may run: the frozen value from the snapshot is drawn instead.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

// MARK: - Shared state

/// What the rest widgets draw for the running workout at an entry's date.
struct WatchRestFace {
    let live: WatchLive
    let date: Date

    init(_ entry: WatchEntry) {
        live = WatchLive(entry.snapshot.active, at: entry.date)
        date = entry.date
    }

    var active: WorkoutSnapshot? { live.active }
    var stage: WatchLive.Stage { live.stage }

    /// The interval of a running (not paused) rest, for the system timer views.
    var runningInterval: ClosedRange<Date>? {
        guard stage == .resting, !live.isPaused else { return nil }
        return active?.watchRestInterval
    }

    /// Whole seconds left when no timer runs (a paused rest).
    var frozenSeconds: Int { Int(live.restRemaining(at: date).rounded(.up)) }

    /// The share of the rest that is left, for a ring that does not run: full once the rest is over.
    var fraction: Double {
        switch stage {
        case .restOver:
            return 1
        case .resting:
            let total = Double(active?.restTotalSeconds ?? 0)
            return total > 0 ? min(1, max(0, live.restRemaining(at: date) / total)) : 0
        case .idle, .logging, .complete:
            return 0
        }
    }

    /// "Next 80 × 6": the set that follows the rest.
    var nextLine: String {
        guard let active else { return "" }
        return "Next " + WatchText.work(active)
    }
}

/// The countdown of a rest: live while it runs, the frozen value (yellow) while the workout is paused, "Go" once it is over.
struct WatchRestCountdown: View {
    let face: WatchRestFace
    var size: CGFloat
    var width: CGFloat?
    var alignment: TextAlignment = .leading

    var body: some View {
        if let interval = face.runningInterval {
            WatchCountdownText(interval: interval, size: size, color: WidgetTheme.progress, width: width, alignment: alignment)
        } else {
            let over = face.stage == .restOver
            Text(over ? "Go" : NumberText.clock(seconds: face.frozenSeconds))
                .font(WidgetTheme.number(size, .bold))
                .foregroundStyle(over ? WidgetTheme.progress : WidgetTheme.recovering)
                .multilineTextAlignment(alignment)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: width ?? CGFloat.infinity, alignment: frameAlignment)
        }
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// The heart-rate figure next to a countdown: a heart and the bpm.
struct WatchHeartLabel: View {
    let bpm: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .font(.system(size: 9))
                .foregroundStyle(WidgetTheme.heart)
            Text("\(bpm)")
                .font(WidgetTheme.number(12, .semibold))
                .foregroundStyle(WidgetTheme.ink)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate \(bpm) beats per minute")
    }
}

// MARK: - Live rest complication (WA-02)

struct RestWidget: Widget {
    static let kind = WatchWidgetTopic.rest.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .rest)) { entry in
            RestWidgetView(entry: entry)
        }
        .configurationDisplayName("Rest timer")
        .description("The rest countdown between sets, on any watch face.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct RestWidgetView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.watchWidgetStaticNow) private var staticNow

    private var face: WatchRestFace { WatchRestFace(entry) }

    var body: some View {
        content
            .widgetURL(StrengthDeepLink.workout.url)
            .widgetBackground(family == .accessoryRectangular ? WatchStyle.greenCard : Color.clear)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default: rectangular
        }
    }

    // MARK: Rectangular

    @ViewBuilder
    private var rectangular: some View {
        let face = self.face
        switch face.stage {
        case .resting, .restOver:
            HStack(spacing: 8) {
                WatchRestRing(interval: face.runningInterval, fixedFraction: face.fraction)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        WatchRestCountdown(face: face, size: 22, width: 52)
                        Spacer(minLength: 0)
                        if let bpm = face.active?.heartRate {
                            WatchHeartLabel(bpm: bpm)
                        }
                    }
                    Text(face.live.isPaused ? "Paused · " + face.nextLine : face.nextLine)
                        .font(WidgetTheme.text(11))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        case .logging:
            if let active = face.active {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(WidgetTheme.track, lineWidth: 4.5)
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WidgetTheme.green)
                            .widgetAccentable()
                    }
                    .frame(width: WatchStyle.touchTarget, height: WatchStyle.touchTarget)
                    .accessibilityHidden(true)
                    WatchRectMessage(
                        eyebrow: "LOG SET",
                        title: WatchText.work(active),
                        detail: active.exerciseName + " · " + WatchText.setTag(active.setLabel)
                    )
                }
            }
        case .complete:
            WatchRectMessage(eyebrow: "WORKOUT", title: "All sets logged", detail: "Finish on your iPhone")
        case .idle:
            WatchRectMessage(eyebrow: "REST TIMER", title: "No workout running", detail: "Starts when you log a set")
        }
    }

    // MARK: Circular

    @ViewBuilder
    private var circular: some View {
        let face = self.face
        ZStack {
            AccessoryWidgetBackground()
            switch face.stage {
            case .resting, .restOver:
                WatchRestRing(interval: face.runningInterval, fixedFraction: face.fraction, diameter: 44, lineWidth: 4)
                    .widgetAccentable()
                WatchRestCountdown(face: face, size: 13, width: 32, alignment: .center)
            case .logging:
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WidgetTheme.green)
                    .widgetAccentable()
            case .complete:
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WidgetTheme.green)
                    .widgetAccentable()
            case .idle:
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WidgetTheme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Inline

    @ViewBuilder
    private var inline: some View {
        let face = self.face
        switch face.stage {
        case .resting:
            if let interval = face.runningInterval {
                let timer = WatchCountdownText.text(interval, staticNow: staticNow)
                WatchInlineText(
                    long: Text(verbatim: "Rest ") + timer + Text(verbatim: " · " + face.nextLine),
                    medium: Text(verbatim: "Rest ") + timer,
                    short: timer,
                    spoken: "Rest timer",
                    systemImage: "timer"
                )
            } else {
                let frozen = NumberText.clock(seconds: face.frozenSeconds)
                WatchInlineText(long: "Rest \(frozen) paused", medium: "Rest \(frozen)", short: frozen, systemImage: "timer")
            }
        case .restOver:
            WatchInlineText(long: "Go · " + face.nextLine, medium: "Rest over", short: "Go", systemImage: "timer")
        case .logging:
            if let active = face.active {
                WatchInlineText(
                    long: "Log set · " + WatchText.work(active),
                    medium: "Log " + WatchText.work(active),
                    short: "Log set",
                    systemImage: "dumbbell.fill"
                )
            }
        case .complete:
            WatchInlineText(long: "All sets logged", medium: "Sets done", short: "Done", systemImage: "checkmark")
        case .idle:
            WatchInlineText(long: "No workout running", medium: "No workout", short: "Rest", systemImage: "timer")
        }
    }
}

// MARK: - Smart Stack rest card (WA-05)

struct RestWatchWidget: Widget {
    static let kind = WatchWidgetTopic.restControls.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .restControls)) { entry in
            RestWatchView(entry: entry)
        }
        .configurationDisplayName("Rest controls")
        .description("Add 15 seconds or skip the rest without opening the app.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct RestWatchView: View {
    let entry: WatchEntry

    private var face: WatchRestFace { WatchRestFace(entry) }

    var body: some View {
        content
            .widgetURL(StrengthDeepLink.workout.url)
            .widgetBackground(WidgetTheme.card)
    }

    @ViewBuilder
    private var content: some View {
        let face = self.face
        switch face.stage {
        case .resting:
            controls(face)
        case .restOver:
            WatchRectMessage(eyebrow: "REST", title: "Rest over", detail: face.nextLine, tint: WidgetTheme.progress)
        case .logging:
            WatchRectMessage(eyebrow: "REST", title: "No rest running", detail: "Starts when you log a set", tint: WidgetTheme.progress)
        case .complete:
            WatchRectMessage(eyebrow: "REST", title: "All sets logged", detail: "Finish on your iPhone", tint: WidgetTheme.progress)
        case .idle:
            WatchRectMessage(eyebrow: "REST", title: "No workout running", detail: "Start one on your iPhone", tint: WidgetTheme.progress)
        }
    }

    /// The countdown with its bar on the left, "+15" and "Skip" on the right (44 pt each). The first button is the double-tap target.
    private func controls(_ face: WatchRestFace) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(face.live.isPaused ? "PAUSED" : "REST")
                    .font(WidgetTheme.eyebrow(11))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
                WatchRestCountdown(face: face, size: 22, width: 52)
                bar(face)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            WatchIntentButton(intent: WatchAdjustRestIntent(seconds: 15)) {
                WatchRoundButtonLabel(systemImage: nil, title: "+15", fill: WidgetTheme.track, foreground: WidgetTheme.ink)
            }
            .accessibilityLabel("Add 15 seconds")
            WatchIntentButton(intent: WatchSkipRestIntent()) {
                WatchRoundButtonLabel(systemImage: "forward.end.fill", title: nil, fill: WidgetTheme.green, foreground: WidgetTheme.onGreen)
            }
            .widgetAccentable()
            .accessibilityLabel("Skip rest")
        }
    }

    @ViewBuilder
    private func bar(_ face: WatchRestFace) -> some View {
        if let interval = face.runningInterval {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(WidgetTheme.progress)
            .accessibilityHidden(true)
        } else {
            BarMeter(fraction: face.fraction, color: WidgetTheme.progress, track: WidgetTheme.track, height: 4)
                .accessibilityHidden(true)
        }
    }
}
#endif
