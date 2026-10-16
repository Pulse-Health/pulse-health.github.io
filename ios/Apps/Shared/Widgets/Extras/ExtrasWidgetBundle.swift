// ExtrasWidgetBundle.swift
//
// The "wilder idea" widgets (WI-01...WI-11, widgets/SPEC.md): body map, log from the Home Screen, gym partner, form cue, loaded bar,
// rest-day swap, strength ratio, year in iron, readiness, plateau watch and session timeline. PulseStrengthWidgetsBundle composes this
// bundle with the others through its `body`: a `WidgetBundle` is not itself a `Widget` (its `Body` is one), so a surrounding builder
// block takes `ExtrasWidgetBundle().body`.
//
// The widgets are listed in three groups of at most five, because a widget builder block has a limited number of children.

#if os(iOS)
import SwiftUI
import WidgetKit

struct ExtrasWidgetBundle: WidgetBundle {
    var body: some Widget {
        mediumWidgets
        insightWidgets
        smallWidgets
    }

    /// WI-01, WI-02, WI-03.
    @WidgetBundleBuilder
    private var mediumWidgets: some Widget {
        BodyMapWidget()
        LogSetWidget()
        PartnerWidget()
    }

    /// WI-09, WI-10, WI-11.
    @WidgetBundleBuilder
    private var insightWidgets: some Widget {
        ReadinessWidget()
        PlateauWidget()
        SessionTimelineWidget()
    }

    /// WI-04 ... WI-08.
    @WidgetBundleBuilder
    private var smallWidgets: some Widget {
        FormCueWidget()
        LoadedBarWidget()
        RestDayWidget()
        StrengthRatioWidget()
        YearInIronWidget()
    }
}
#endif
