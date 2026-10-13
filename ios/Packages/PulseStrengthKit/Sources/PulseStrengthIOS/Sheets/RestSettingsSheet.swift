#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Sheet

/// Rest timer settings (Active.dc.html, `sh.rest`).
///
/// Title bar ("Rest Timer" + Done), the line "Rest after each set · <exercise>", ten presets in two rows of five
/// (Off, 0:30, 0:45, 1:00, 1:30, 2:00, 2:30, 3:00, 4:00, 5:00; the chosen one is green) that set the exercise's rest,
/// and the two workout-wide switches "Start after logging a set" and "Alert when rest is over".
@MainActor
public struct RestSettingsSheet: View {
    @ObservedObject private var controller: WorkoutController
    private let exerciseID: UUID

    @Environment(\.dismiss) private var dismiss

    /// Local copies of the two switches, kept in step with the workout settings in both directions.
    @State private var autoStart: Bool
    @State private var alertWhenOver: Bool

    public init(controller: WorkoutController, exerciseID: UUID) {
        self._controller = ObservedObject(wrappedValue: controller)
        self.exerciseID = exerciseID
        let settings = controller.state?.settings
        self._autoStart = State(initialValue: settings?.autoStartRest ?? true)
        self._alertWhenOver = State(initialValue: settings?.alertWhenRestEnds ?? true)
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            RestSettingsHeader(onDone: { dismiss() })
            ViewThatFits(in: .vertical) {
                panel
                ScrollView {
                    panel
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PulseTheme.ground.ignoresSafeArea())
        .sheetDetentsHuggingContent(titleBarHeight: 56, estimate: 341)
        .onChange(of: liveAutoStart) { _, newValue in
            if autoStart != newValue {
                autoStart = newValue
            }
        }
        .onChange(of: liveAlertWhenOver) { _, newValue in
            if alertWhenOver != newValue {
                alertWhenOver = newValue
            }
        }
        .onChange(of: autoStart) { _, newValue in
            if newValue != liveAutoStart {
                controller.send(.setAutoStartRest(newValue))
            }
        }
        .onChange(of: alertWhenOver) { _, newValue in
            if newValue != liveAlertWhenOver {
                controller.send(.setAlertWhenRestEnds(newValue))
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let entry = resolved {
                Text(verbatim: "Rest after each set · " + entry.exercise.name)
                    .font(PulseFont.footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .padding(.leading, 4)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                presetGrid(entry)
            }
            toggleCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .reportsSheetPanelHeight()
    }

    // MARK: Live data

    /// The workout exercise being configured; the current exercise when the id is no longer in the workout.
    private var resolved: WorkoutExercise? {
        guard let state = controller.state else { return nil }
        return state.exercises.first(where: { $0.id == exerciseID }) ?? state.currentExercise
    }

    private var liveAutoStart: Bool {
        controller.state?.settings.autoStartRest ?? true
    }

    private var liveAlertWhenOver: Bool {
        controller.state?.settings.alertWhenRestEnds ?? true
    }

    // MARK: Presets

    private static let presetRows: [[Int]] = [
        [0, 30, 45, 60, 90],
        [120, 150, 180, 240, 300]
    ]

    private func presetGrid(_ entry: WorkoutExercise) -> some View {
        VStack(spacing: 8) {
            ForEach(0..<RestSettingsSheet.presetRows.count, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(RestSettingsSheet.presetRows[rowIndex], id: \.self) { (seconds: Int) in
                        RestSettingsPresetButton(
                            seconds: seconds,
                            isSelected: entry.restSeconds == seconds,
                            action: { selectPreset(seconds, for: entry) }
                        )
                    }
                }
            }
        }
    }

    private func selectPreset(_ seconds: Int, for entry: WorkoutExercise) {
        RestSettingsHaptics.select()
        controller.send(.setRest(exerciseID: entry.id, seconds: seconds))
    }

    // MARK: Switches

    private var toggleCard: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 0) {
            RestSettingsToggleRow(
                title: "Start after logging a set",
                subtitle: "Shorter after warm-up sets",
                accessibilityTitle: "Start rest timer automatically",
                isOn: $autoStart
            )
            Rectangle()
                .fill(PulseTheme.separator)
                .frame(height: 0.5)
            RestSettingsToggleRow(
                title: "Alert when rest is over",
                subtitle: "Haptic, sound and Lock Screen update",
                accessibilityTitle: "Alert when rest is over",
                isOn: $alertWhenOver
            )
        }
        .background(PulseTheme.card, in: shape)
        .clipShape(shape)
    }
}

// MARK: - Haptics

@MainActor
private enum RestSettingsHaptics {
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Title bar

private struct RestSettingsHeader: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Text("Rest Timer")
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

// MARK: - Preset button

/// One of the ten presets: 48 pt tall, white, or solid green when it is the exercise's rest.
private struct RestSettingsPresetButton: View {
    let seconds: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: NumberText.rest(seconds: seconds))
                .pulseNumber(17, .semibold)
                .foregroundStyle(isSelected ? PulseTheme.onGreen : PulseTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    isSelected ? PulseTheme.green : PulseTheme.card,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel(spokenText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "Rest timer off", "30 seconds", "1 minute 30 seconds", "5 minutes".
    private var spokenText: String {
        if seconds <= 0 {
            return "Rest timer off"
        }
        let minutes = seconds / 60
        let rest = seconds % 60
        var parts: [String] = []
        if minutes > 0 {
            parts.append(String(minutes) + (minutes == 1 ? " minute" : " minutes"))
        }
        if rest > 0 {
            parts.append(String(rest) + (rest == 1 ? " second" : " seconds"))
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Switch row

/// A 56 pt row: title and explanation on the left, the system switch (green) on the right.
private struct RestSettingsToggleRow: View {
    let title: String
    let subtitle: String
    let accessibilityTitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(PulseFont.body)
                    .foregroundStyle(PulseTheme.ink)
                Text(verbatim: subtitle)
                    .font(PulseFont.caption)
                    .foregroundStyle(PulseTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            Toggle(accessibilityTitle, isOn: $isOn)
                .labelsHidden()
                .tint(PulseTheme.recoveryGood)
                .accessibilityHint(subtitle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }
}
#endif
