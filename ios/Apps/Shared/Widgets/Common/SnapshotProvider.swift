// SnapshotProvider.swift
//
// The timeline entry and provider of every widget that only needs the WidgetSnapshot (no user configuration). The app writes the snapshot
// (WidgetPublisher) and reloads the timelines when something changes; the provider also asks for a reload at the next midnight and, while
// a rest timer runs, adds an entry at its end so the view can switch to "Go".

#if os(iOS) || os(watchOS)
import WidgetKit
import PulseStrengthCore

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// True for the gallery / redacted placeholder (the preview snapshot, never live data).
    let isPlaceholder: Bool

    init(date: Date, snapshot: WidgetSnapshot, isPlaceholder: Bool = false) {
        self.date = date
        self.snapshot = snapshot
        self.isPlaceholder = isPlaceholder
    }
}

enum SnapshotLoading {
    /// The snapshot a widget shows now: the stored one (rebuilt after midnight), or the empty week when the app has not run yet.
    static func current(now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshotStore.loadForDisplay(now: now) ?? WidgetSnapshot.empty(now: now)
    }

    /// The entries and reload date for `snapshot`: now, the end of a running rest, and a reload at the next midnight.
    static func timeline(for snapshot: WidgetSnapshot, now: Date = Date()) -> Timeline<SnapshotEntry> {
        var entries = [SnapshotEntry(date: now, snapshot: snapshot)]
        if let end = snapshot.active?.restEndsAt, end > now {
            entries.append(SnapshotEntry(date: end, snapshot: snapshot))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: snapshot.timeZoneID) ?? .current
        let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(6 * 3600)
        let soon = now.addingTimeInterval(30 * 60)
        return Timeline(entries: entries, policy: .after(min(midnight, soon)))
    }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(SnapshotEntry(date: Date(), snapshot: .preview, isPlaceholder: true))
        } else {
            completion(SnapshotEntry(date: Date(), snapshot: SnapshotLoading.current()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(SnapshotLoading.timeline(for: SnapshotLoading.current()))
    }
}
#endif
