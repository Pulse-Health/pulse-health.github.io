// LogSetControl.swift
//
// CT-02 Log set: a button that logs the next pending set of the running workout without opening the app. While a workout runs the title names the
// set ("Log set 4 of 5"). The intent is a LiveActivityIntent, so it runs in the app's process even while the app is suspended.

#if os(iOS)
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct LogSetControl: ControlWidget {
    static let kind = "health.pulse.strength.control.logSet"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: WorkoutControlProvider()) { state in
            ControlWidgetButton(action: LogNextSetControlIntent()) {
                Label(state.logTitle, systemImage: "checkmark")
            }
        }
        .displayName("Log set")
        .description("Logs the next set of your running workout with its planned weight and reps, without opening the app.")
    }
}
#endif
