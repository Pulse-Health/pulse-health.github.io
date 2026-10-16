// WatchWidgetTimeline.swift
//
// The timeline entry and provider of every Watch widget. They differ from the Home Screen's `SnapshotEntry` / `SnapshotProvider` in three ways:
//   * the entry carries a `TimelineEntryRelevance`, which the Smart Stack uses to rank the widget (rest and log cards while a workout runs,
//     Next up around the usual training hour, the record card for 24 hours; see WatchTimelinePlan);
//   * the snapshot is the one the Watch app saved, aged to the entry's date (WatchSnapshotAging), not rebuilt from strength data;
//   * the timeline has an entry wherever the content changes by itself (end of a rest, end of the record's 24 hours, midnight), so nothing
//     depends on the extension being woken up at that moment.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import Foundation
import WidgetKit
import PulseStrengthCore

struct WatchEntry: TimelineEntry {
    let date: Date
    /// The snapshot as it reads at `date`.
    let snapshot: WidgetSnapshot
    /// True for the gallery / redacted placeholder (the preview snapshot, never live data).
    let isPlaceholder: Bool
    let relevance: TimelineEntryRelevance?

    init(date: Date, snapshot: WidgetSnapshot, isPlaceholder: Bool = false, relevance: TimelineEntryRelevance? = nil) {
        self.date = date
        self.snapshot = snapshot
        self.isPlaceholder = isPlaceholder
        self.relevance = relevance
    }

    init(_ planned: WatchPlannedEntry) {
        let relevance = planned.relevance.map { TimelineEntryRelevance(score: $0.score, duration: $0.duration) }
        self.init(date: planned.date, snapshot: planned.snapshot, relevance: relevance)
    }

    /// The entry of the widget gallery and of the placeholder: the preview snapshot, with a running workout for the cards that need one.
    static func sample(for topic: WatchWidgetTopic, now: Date) -> WatchEntry {
        var snapshot = WidgetSnapshot.preview
        switch topic {
        case .rest, .restControls:
            snapshot.active = WorkoutSnapshot.watchSample(resting: true, now: now)
        case .logSet:
            snapshot.active = WorkoutSnapshot.watchSample(resting: false, now: now)
        case .nextUp, .goal, .daysSince, .start, .streak, .weeklySets, .liftTrend, .record, .heartRate:
            break
        }
        return WatchEntry(date: now, snapshot: snapshot, isPlaceholder: true)
    }
}

/// One provider type for every Watch widget; `topic` decides which moments and which relevance the timeline has.
struct WatchProvider: TimelineProvider {
    let topic: WatchWidgetTopic

    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry.sample(for: topic, now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(WatchEntry.sample(for: topic, now: now))
            return
        }
        let raw = WatchSnapshotLoading.stored(now: now)
        let planned = WatchTimelinePlan.entries(for: topic, raw: raw, now: now)
        completion(planned.first.map { WatchEntry($0) } ?? WatchEntry(date: now, snapshot: raw))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let now = Date()
        let raw = WatchSnapshotLoading.stored(now: now)
        let entries = WatchTimelinePlan.entries(for: topic, raw: raw, now: now).map { WatchEntry($0) }
        completion(Timeline(entries: entries, policy: .after(WatchTimelinePlan.reloadDate(raw: raw, now: now))))
    }
}
#endif
