// HomeWidgetBundle.swift
//
// The Home Screen widgets (systemSmall / systemMedium / systemLarge / systemExtraLarge, HS-01...HS-12 and SB-01, SB-03, SB-04).
// PulseStrengthWidgetsBundle composes this bundle with the others.
//
// A widget builder holds a limited number of widgets in the older SDKs (five at first), so the widgets are grouped by size into three small
// bundles and `HomeWidgetBundle`, the one entry of this area, lists the groups through their `body`.

#if os(iOS)
import SwiftUI
import WidgetKit

struct HomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeSmallWidgets().body
        HomeMediumWidgets().body
        HomeLargeWidgets().body
    }
}

/// HS-01 ... HS-06 (systemSmall; Next up also has a medium layout) and the StandBy pair.
private struct HomeSmallWidgets: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        WeeklyGoalWidget()
        PRSpotlightWidget()
        MuscleFreshnessWidget()
        OverloadWidget()
    }
}

/// HS-08 and HS-09 (systemMedium).
private struct HomeMediumWidgets: WidgetBundle {
    var body: some Widget {
        WeeklySetsWidget()
        LiftTrendWidget()
    }
}

/// HS-10 ... HS-12 (systemLarge) and the iPad training block (systemExtraLarge).
private struct HomeLargeWidgets: WidgetBundle {
    var body: some Widget {
        TrainingWeekWidget()
        TemplateLauncherWidget()
        MonthHeatmapWidget()
        TrainingBlockWidget()
    }
}
#endif
