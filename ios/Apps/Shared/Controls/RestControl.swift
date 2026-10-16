// RestControl.swift
//
// CT-03 Rest timer: shows how much rest is left and skips it when pressed. The countdown is a system timer text (`Text(timerInterval:)`), the one
// thing in a control that keeps moving without a refresh; everything else comes from the value provider, which the app refreshes when the workout
// changes. A paused workout shows the frozen time, and a rest that ran out says so. With no rest running the label is "Rest timer" and a press
// changes nothing (the engine ignores a skip when no rest runs).

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

@available(iOS 18.0, *)
struct RestControl: ControlWidget {
    static let kind = "health.pulse.strength.control.rest"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: WorkoutControlProvider()) { state in
            ControlWidgetButton(action: SkipRestControlIntent()) {
                Label {
                    state.restLabel
                } icon: {
                    Image(systemName: "timer")
                }
            }
        }
        .displayName("Rest timer")
        .description("Shows how much rest is left in your running workout. Press it to skip the rest.")
    }
}

private extension WorkoutControlState {
    /// "Rest 1:24" (the digits count down by themselves), "Rest paused 1:12", "Rest over", or "Rest timer" when no rest is shown.
    var restLabel: Text {
        switch rest {
        case .inactive:
            return Text("Rest timer")
        case .running(let interval):
            return Text("Rest ") + Text(timerInterval: interval, countsDown: true, showsHours: false)
        case .frozen(let seconds):
            return Text(verbatim: "Rest paused " + NumberText.clock(seconds: seconds))
        case .over:
            return Text("Rest over")
        }
    }
}
#endif
