// FinishControl.swift
//
// CT-07 Finish workout: a button that opens the running workout. It does not finish anything by itself: finishing asks for a confirmation (and,
// when the workout changed its template, for the template update), and both belong to the app. The glyph is a chequered flag.

#if os(iOS)
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct FinishControl: ControlWidget {
    static let kind = "health.pulse.strength.control.finish"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: FinishWorkoutControlIntent()) {
                Label("Finish workout", systemImage: "flag.checkered")
            }
        }
        .displayName("Finish workout")
        .description("Opens your running workout so you can finish it. Finishing always needs your confirmation in the app.")
    }
}
#endif
