// HomeWidgetBundle.swift
//
// The Home Screen widgets (systemSmall / systemMedium / systemLarge / systemExtraLarge, HS-01...HS-12 and SB-01, SB-03, SB-04).
// PulseStrengthWidgetsBundle composes this bundle with the others.

#if os(iOS)
import SwiftUI
import WidgetKit

struct HomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        WeeklyGoalWidget()
        PRSpotlightWidget()
        MuscleFreshnessWidget()
        OverloadWidget()
        WeeklySetsWidget()
        LiftTrendWidget()
        HomeLargeWidgetBundle()
    }
}

/// The large and extra large widgets. A widget builder holds a limited number of widgets in the SDKs this project builds with, so the last
/// group is a bundle of its own.
struct HomeLargeWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrainingWeekWidget()
        TemplateLauncherWidget()
        MonthHeatmapWidget()
        TrainingBlockWidget()
    }
}
#endif
