// LockWidgetBundle.swift
//
// The Lock Screen accessory widgets (accessoryCircular / accessoryRectangular / accessoryInline, LS-01...LS-11).
// PulseStrengthWidgetsBundle composes this bundle with the others.

#if os(iOS)
import SwiftUI
import WidgetKit

struct LockWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeeklyGoalAccessoryWidget()
        DaysSinceAccessoryWidget()
        StreakAccessoryWidget()
        NextUpAccessoryWidget()
        WeeklySetsAccessoryWidget()
        PRAccessoryWidget()
        OverloadAccessoryWidget()
    }
}
#endif
