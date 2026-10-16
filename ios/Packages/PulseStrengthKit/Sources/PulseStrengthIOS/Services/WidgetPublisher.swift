#if os(iOS)
import Combine
import Foundation
import WidgetKit
import PulseStrengthCore

/// Keeps the `WidgetSnapshot` that the widgets, controls and Watch widgets read in step with the app.
///
/// It rebuilds the snapshot (`WidgetSnapshotBuilder`) when the workout changes, when templates or history change and when the app asks (launch,
/// foreground), writes it atomically into the App Group container and asks WidgetKit to reload every timeline and control. Changes are
/// coalesced (a burst of edits produces one write), and the heart-rate samples that arrive every few seconds are published at most every 10 s.
/// A snapshot that equals the previous one except for its time stamp is not written, so an idle app costs nothing.
@MainActor
final class WidgetPublisher: WorkoutSideEffect {
    /// Data that only the host can supply; the defaults are the standalone build.
    struct Providers {
        var weeklyGoal: @MainActor () -> Int = { WidgetContext.defaultWeeklyGoal }
        var bodyweightKg: @MainActor () -> Double? = { nil }
        var readiness: @MainActor () -> ReadinessSummary? = { nil }
        var partners: @MainActor () -> [PartnerWeek] = { [] }
    }

    /// Called after every write with the snapshot that was written (the Watch sender).
    var onPublish: ((WidgetSnapshot) -> Void)?

    private static let debounce: UInt64 = 300_000_000
    private static let heartRateInterval: TimeInterval = 10

    private let store: StrengthStore
    private let controller: WorkoutController
    private let directory: URL?
    private let providers: Providers
    private let reloadTimelines: Bool
    private var subscription: AnyCancellable?
    private var pendingTask: Task<Void, Never>?
    private var lastSnapshot: WidgetSnapshot?
    private var lastHeartRatePublish: Date?

    /// - Parameters:
    ///   - directory: where the snapshot file goes (the App Group directory); nil makes `publishNow` a no-op.
    ///   - reloadTimelines: false in tests and previews, which must not talk to WidgetKit.
    init(store: StrengthStore, controller: WorkoutController, directory: URL?, providers: Providers = Providers(), reloadTimelines: Bool = true) {
        self.store = store
        self.controller = controller
        self.directory = directory
        self.providers = providers
        self.reloadTimelines = reloadTimelines
    }

    /// Starts observing the store and writes the first snapshot.
    func start() {
        subscription = store.objectWillChange.sink { [weak self] in
            // `objectWillChange` fires before the values change: the debounced task reads them afterwards.
            Task { @MainActor [weak self] in self?.publishSoon() }
        }
        publishNow()
    }

    /// Schedules one write shortly from now; further calls before it runs are absorbed.
    func publishSoon() {
        guard pendingTask == nil else { return }
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounce)
            guard let self else { return }
            self.pendingTask = nil
            self.publishNow()
        }
    }

    /// Builds and writes the snapshot now (unless nothing but its time stamp changed).
    func publishNow() {
        let now = Date()
        let data = StrengthData(
            templates: store.templates,
            history: store.history,
            customExercises: store.customExercises,
            personalBests: store.personalBests
        )
        let context = WidgetContext(
            weeklyGoal: providers.weeklyGoal(),
            bodyweightKg: providers.bodyweightKg(),
            readiness: providers.readiness(),
            partners: providers.partners(),
            active: controller.snapshot(now: now)
        )
        let snapshot = WidgetSnapshotBuilder.build(data: data, context: context, now: now)
        if let previous = lastSnapshot, Self.sameContent(previous, snapshot) { return }
        guard let directory else { return }
        do {
            try WidgetSnapshotStore.save(snapshot, directory: directory)
        } catch {
            ServiceLog.error("The widget snapshot could not be written: \(error.localizedDescription)")
            return
        }
        lastSnapshot = snapshot
        if reloadTimelines {
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 18.0, *) {
                ControlCenter.shared.reloadAllControls()
            }
        }
        onPublish?(snapshot)
    }

    /// True when the two snapshots show the same (everything but the time stamp is equal).
    private static func sameContent(_ lhs: WidgetSnapshot, _ rhs: WidgetSnapshot) -> Bool {
        var comparable = lhs
        comparable.generatedAt = rhs.generatedAt
        // The running workout's revision changes with every edit, even ones that look the same on screen.
        comparable.active?.revision = rhs.active?.revision ?? 0
        return comparable == rhs
    }

    // MARK: WorkoutSideEffect

    func workoutStarted(_ state: WorkoutState) {
        publishSoon()
    }

    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        if case .updateHeartRate = action {
            let now = Date()
            if let last = lastHeartRatePublish, now.timeIntervalSince(last) < Self.heartRateInterval { return }
            lastHeartRatePublish = now
        }
        publishSoon()
    }

    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {
        publishSoon()
    }
}
#endif
