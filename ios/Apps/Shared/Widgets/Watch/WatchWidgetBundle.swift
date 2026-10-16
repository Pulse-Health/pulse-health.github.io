// WatchWidgetBundle.swift
//
// The Apple Watch widgets (WA-01 ... WA-10). `PulseStrengthWatchWidgetsBundle` (Apps/PulseStrengthWatchWidgets, the `@main` of the watchOS
// widget extension) composes this bundle. The twelve widgets sit in three nested bundles of four because a bundle builder only takes a handful
// of children (five in the oldest SDKs).
//
//   Face set        Next up (rectangular, inline, corner), Weekly goal, Days since training, Start
//   Statistics      Week streak, Weekly sets, Lift trend, Heart rate by set
//   Workout cards   Rest timer, Rest controls, Log set, Record
//
// Every widget reads only the WidgetSnapshot the Watch app saved (WatchWidgetSnapshotReceiver); the buttons hand their action to the Watch app
// through WatchIntents.swift. Kinds are `health.pulse.strength.watch.<name>` (WatchWidgetTopic.kind).

#if os(watchOS)
import SwiftUI
import WidgetKit

struct WatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchFaceWidgetBundle()
        WatchStatisticsWidgetBundle()
        WatchWorkoutWidgetBundle()
    }
}

/// The face set of WA-01 and WA-07: the next workout, the goal, the days since training and Start.
struct WatchFaceWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWatchWidget()
        WeeklyGoalWatchWidget()
        DaysSinceWatchWidget()
        StartWatchWidget()
    }
}

/// The numbers and charts of WA-08, WA-09 and WA-10.
struct WatchStatisticsWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakWatchWidget()
        WeeklySetsWatchWidget()
        LiftTrendWatchWidget()
        HeartRateWatchWidget()
    }
}

/// The cards that follow the running workout (WA-02, WA-04, WA-05) and the record card (WA-06).
struct WatchWorkoutWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestWidget()
        RestWatchWidget()
        LogSetWatchWidget()
        RecordWatchWidget()
    }
}
#endif
