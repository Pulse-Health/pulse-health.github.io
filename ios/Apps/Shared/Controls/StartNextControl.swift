// StartNextControl.swift
//
// CT-01 Start workout: a button that opens the app on the workout that comes next in the split, or on the one that runs. On the Lock Screen the
// system asks to unlock first, because the intent opens the app. The glyph is a dumbbell; the title says what the press does ("Start Push day").

#if os(iOS)
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct StartNextControl: ControlWidget {
    static let kind = "health.pulse.strength.control.startNext"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: WorkoutControlProvider()) { state in
            ControlWidgetButton(action: StartNextIntent()) {
                Label(state.startTitle, systemImage: "dumbbell.fill")
            }
        }
        .displayName("Start workout")
        .description("Opens Pulse Strength on the next workout of your split. A workout that is already running opens instead.")
    }
}
#endif
