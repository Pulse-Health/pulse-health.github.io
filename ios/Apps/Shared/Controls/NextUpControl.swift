// NextUpControl.swift
//
// CT-08 Next up, the large control of the board: where Start workout names the action ("Start Push day"), this one names the workout itself,
// kicker and template ("Next up: Upper A · Push"), which is what the 2x2 size has room for. It starts the same workout through the same intent,
// and it names the running workout ("Open Upper A · Push") while one runs. Control Center decides the size; the label does not change with it.

#if os(iOS)
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct NextUpControl: ControlWidget {
    static let kind = "health.pulse.strength.control.nextUp"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: WorkoutControlProvider()) { state in
            ControlWidgetButton(action: StartNextIntent()) {
                Label(state.nextUpTitle, systemImage: "dumbbell.fill")
            }
        }
        .displayName("Next up")
        .description("Shows the workout that is next in your split and starts it with one press.")
    }
}
#endif
