#if os(watchOS)
import SwiftUI
import PulseStrengthCore

// MARK: - Beating heart

/// The red heart next to the heart rate. It pulses once per second like the design (scale 1 -> 1.25 -> 1 in the first
/// 0.3 s of every second); it stands still for Reduce Motion and in the Always-On state.
private struct BeatingHeart: View {
    let tint: Color
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { context in
            Image(systemName: "heart.fill")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(tint)
                .scaleEffect(animated ? BeatingHeart.scale(at: context.date) : 1)
        }
        .accessibilityHidden(true)
    }

    /// The pulse curve: ease up to 1.25 during the first 0.15 s, ease back down during the next 0.15 s, then rest.
    static func scale(at date: Date) -> CGFloat {
        let time = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.0)
        if time < 0.15 {
            return 1 + 0.25 * ease(time / 0.15)
        }
        if time < 0.30 {
            return 1.25 - 0.25 * ease((time - 0.15) / 0.15)
        }
        return 1
    }

    private static func ease(_ progress: Double) -> CGFloat {
        let p = min(1, max(0, progress))
        return CGFloat(p * p * (3 - 2 * p))
    }
}

// MARK: - Page

/// "Metrics": elapsed time in yellow, heart rate with a beating heart, volume and sets.
@MainActor
struct MetricsPage: View {
    @ObservedObject var session: WatchWorkoutSession
    let snapshot: WorkoutSnapshot
    let date: Date

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: WatchPalette { WatchPalette(reduced: isLuminanceReduced) }

    private var elapsedSeconds: Int {
        WatchFormat.elapsedSeconds(snapshot, at: date)
    }

    /// The Watch's own sensor first, then the value the phone knows.
    private var heartRate: Int? {
        session.latestHeartRate ?? snapshot.heartRate
    }

    private var heartRateText: String {
        guard let heartRate else { return "–" }
        return String(heartRate)
    }

    private var heartRateSpoken: String {
        guard let heartRate else { return "Not available" }
        return "\(heartRate) beats per minute"
    }

    private var heartAnimated: Bool {
        !reduceMotion && !isLuminanceReduced && heartRate != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            elapsedView
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 2) {
                heartRateRow
                volumeRow
                setsRow
                healthNote
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Rows

    private var elapsedView: some View {
        Text(WatchFormat.clockText(elapsedSeconds, coarse: isLuminanceReduced))
            .font(WatchFont.number(40, .bold))
            .tracking(-0.8)
            .foregroundStyle(palette.time)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(snapshot.isPaused ? "Elapsed time, paused" : "Elapsed time")
            .accessibilityValue(WatchFormat.spoken(seconds: elapsedSeconds))
    }

    /// Number, heart and "bpm" share one vertical centre, as in the design (`align-items: center`). Baseline alignment would hang
    /// the heart and the small "bpm" label below the middle of the digits. The volume and sets rows below stay on a baseline: in
    /// the design their unit is inline text.
    private var heartRateRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(heartRateText)
                .font(WatchFont.number(31, .bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            BeatingHeart(tint: palette.heart, animated: heartAnimated)
            Text("bpm")
                .font(WatchFont.text(12.5, .regular))
                .foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(heartRateSpoken)
    }

    private var volumeRow: some View {
        valueRow(value: snapshot.volumeText, unit: "kg")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(snapshot.volumeText) kilograms")
    }

    private var setsRow: some View {
        valueRow(value: "\(snapshot.loggedSets)/\(snapshot.totalSets)", unit: "sets")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sets")
            .accessibilityValue("\(snapshot.loggedSets) of \(snapshot.totalSets) logged")
    }

    private func valueRow(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(WatchFont.number(20, .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(WatchFont.text(12.5, .regular))
                .foregroundStyle(palette.secondary)
        }
    }

    /// Without Health access there is no heart rate from this Watch: say so instead of showing a bare dash.
    @ViewBuilder
    private var healthNote: some View {
        if session.authorizationDenied {
            Text("Health access is off")
                .font(WatchFont.text(11, .regular))
                .foregroundStyle(palette.heart)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
#endif
