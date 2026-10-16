// PlatesControl.swift
//
// CT-05 Plate calculator: a button that opens the app on the plate calculator of the running workout (the hub when none runs). The glyph is a plate
// seen from the side: a ring around a hub, like the one on the design board.

#if os(iOS)
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct PlatesControl: ControlWidget {
    static let kind = "health.pulse.strength.control.plates"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenPlateCalculatorControlIntent()) {
                Label("Open plate calculator", systemImage: "circle.circle")
            }
        }
        .displayName("Plate calculator")
        .description("Opens the plate calculator for the bar you are loading in your running workout.")
    }
}
#endif
