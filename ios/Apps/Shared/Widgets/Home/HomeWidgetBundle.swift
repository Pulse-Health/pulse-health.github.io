// HomeWidgetBundle.swift
//
// The Home Screen widgets (systemSmall / systemMedium / systemLarge / systemExtraLarge, HS-01...HS-12 and SB-01, SB-03, SB-04).
// PulseStrengthWidgetsBundle composes this bundle with the others.

#if os(iOS)
import SwiftUI
import WidgetKit

struct HomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeeklyGoalWidget()
    }
}
#endif
