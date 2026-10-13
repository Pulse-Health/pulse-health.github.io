#if os(watchOS)
import Foundation
import Combine
import HealthKit

// MARK: - Plain helpers
//
// These are file-scope functions (not members of the main-actor class below) on purpose: HealthKit calls their
// completion closures on background queues, so the closures must not be main-actor isolated. Each one reports back
// with Sendable values only.

/// Asks for the Health permissions of a strength workout: share workouts, read heart rate and active energy.
/// Reports false when the request itself failed (whether saving workouts was allowed is checked afterwards).
private func requestHealthAuthorization(
    store: HKHealthStore,
    share: Set<HKSampleType>,
    read: Set<HKObjectType>,
    completion: @escaping @Sendable (Bool) -> Void
) {
    store.requestAuthorization(toShare: share, read: read) { (success: Bool, error: Error?) in
        completion(success && error == nil)
    }
}

/// Starts the live builder's data collection at `startDate`.
private func beginCollection(
    of builder: HKLiveWorkoutBuilder,
    at startDate: Date,
    completion: @escaping @Sendable (Bool) -> Void
) {
    builder.beginCollection(withStart: startDate) { (success: Bool, error: Error?) in
        completion(success && error == nil)
    }
}

/// Stops the data collection and saves the workout to Health. The builder stays alive until saving finishes.
private func endCollectionAndSave(_ builder: HKLiveWorkoutBuilder, endDate: Date) {
    builder.endCollection(withEnd: endDate) { (_: Bool, _: Error?) in
        builder.finishWorkout { (_: HKWorkout?, _: Error?) in
        }
    }
}

/// A workout that started in the future or a very long time ago starts now instead.
private func clampedStartDate(_ requested: Date, now: Date) -> Date {
    let longestWorkout: TimeInterval = 3 * 3600
    if requested > now { return now }
    if now.timeIntervalSince(requested) > longestWorkout { return now }
    return requested
}

// MARK: - Session

/// The Watch's Health workout: an `HKWorkoutSession` (traditional strength training, indoor) with an
/// `HKLiveWorkoutBuilder`. It keeps the Watch running in the background, measures heart rate and saves the workout
/// to Health when it ends.
///
/// The session reports what it observes through two callbacks (wired by `WatchEnvironment`):
/// * `onHeartRate` receives the most recent heart rate in beats per minute for every collected sample;
/// * `onRecordingChanged` receives `true` when the session is running and `false` when it ends.
///
/// `start(workoutStartDate:)` and `end()` are idempotent. HealthKit delegate callbacks arrive on background queues and are
/// moved to the main actor with Sendable values only.
@MainActor
public final class WatchWorkoutSession: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {

    /// True while the Health workout session is running (set when it starts, cleared as soon as `end()` is called).
    @Published public private(set) var isRecording: Bool = false

    /// True when Health access for saving workouts was refused (or Health data is unavailable).
    @Published public private(set) var authorizationDenied: Bool = false

    /// The most recent heart rate in beats per minute; nil without a running session or before the first sample.
    @Published public private(set) var latestHeartRate: Int? = nil

    /// Receives each heart-rate sample (bpm) while the session records.
    public var onHeartRate: (@MainActor (Int) -> Void)?

    /// Receives `true` when recording starts and `false` when it stops.
    public var onRecordingChanged: (@MainActor (Bool) -> Void)?

    private enum Phase {
        case idle
        case authorizing
        case starting
        case running
        case ending
    }

    private let healthStore = HKHealthStore()
    private var liveSession: HKWorkoutSession?
    private var liveBuilder: HKLiveWorkoutBuilder?
    private var phase: Phase = .idle
    /// Incremented when a pending authorisation request is abandoned, so its late answer is ignored.
    private var authorizationTicket = 0
    /// A start requested while the previous session was still ending; run as soon as that one is finished.
    private var restartDate: Date?
    private var endFallback: Task<Void, Never>?

    public override init() {
        super.init()
    }

    // MARK: Start

    /// Requests Health authorisation (share: workouts; read: heart rate, active energy), then starts the session and the
    /// live builder at `workoutStartDate`. Does nothing while a session is already starting or running.
    public func start(workoutStartDate: Date = Date()) {
        switch phase {
        case .idle:
            break
        case .ending:
            restartDate = workoutStartDate
            return
        case .authorizing, .starting, .running:
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationDenied = true
            return
        }

        phase = .authorizing
        authorizationTicket += 1
        let ticket = authorizationTicket

        var share = Set<HKSampleType>()
        share.insert(HKObjectType.workoutType())
        var read = Set<HKObjectType>()
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            read.insert(heartRate)
        }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            read.insert(energy)
        }

        requestHealthAuthorization(store: healthStore, share: share, read: read) { [weak self] (granted: Bool) in
            Task { @MainActor [weak self] in
                self?.authorizationFinished(granted: granted, ticket: ticket, startDate: workoutStartDate)
            }
        }
    }

    private func authorizationFinished(granted: Bool, ticket: Int, startDate: Date) {
        guard ticket == authorizationTicket, phase == .authorizing else { return }
        // Reading is not observable, but a refusal to save workouts is: without it there is no workout session.
        let savingDenied = healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied
        guard granted, !savingDenied else {
            phase = .idle
            authorizationDenied = true
            return
        }
        authorizationDenied = false
        beginSession(startDate: clampedStartDate(startDate, now: Date()))
    }

    private func beginSession(startDate: Date) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        } catch {
            phase = .idle
            if healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied {
                authorizationDenied = true
            }
            return
        }

        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        liveSession = session
        liveBuilder = builder
        phase = .starting
        latestHeartRate = nil

        let sessionID = ObjectIdentifier(session)
        session.startActivity(with: startDate)
        beginCollection(of: builder, at: startDate) { [weak self] (succeeded: Bool) in
            Task { @MainActor [weak self] in
                self?.collectionStarted(succeeded: succeeded, sessionID: sessionID)
            }
        }
    }

    private func collectionStarted(succeeded: Bool, sessionID: ObjectIdentifier) {
        guard !succeeded, let current = liveSession, ObjectIdentifier(current) == sessionID else { return }
        // The builder could not start collecting: give this session up so that the next workout can try again.
        finalize(endDate: Date(), endSessionFirst: true)
    }

    // MARK: End

    /// Ends the session and saves the workout to Health (end of collection, then finish). `isRecording` becomes false
    /// immediately. Does nothing without a session.
    public func end() {
        switch phase {
        case .idle:
            restartDate = nil
        case .authorizing:
            authorizationTicket += 1
            phase = .idle
            restartDate = nil
        case .starting, .running:
            phase = .ending
            setRecording(false)
            liveSession?.end()
            armEndFallback()
        case .ending:
            restartDate = nil
        }
    }

    /// If HealthKit never reports the `ended` state, finish the workout anyway so that the next one can start.
    private func armEndFallback() {
        endFallback?.cancel()
        endFallback = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.phase == .ending {
                self.finalize(endDate: Date(), endSessionFirst: true)
            }
        }
    }

    /// Releases the session and the builder, saves the workout and starts a queued restart.
    private func finalize(endDate: Date, endSessionFirst: Bool) {
        endFallback?.cancel()
        endFallback = nil

        let session = liveSession
        let builder = liveBuilder
        if endSessionFirst, let session, session.state != .ended {
            session.end()
        }
        session?.delegate = nil
        builder?.delegate = nil
        liveSession = nil
        liveBuilder = nil
        phase = .idle
        latestHeartRate = nil
        setRecording(false)

        if let builder {
            endCollectionAndSave(builder, endDate: endDate)
        }

        if let date = restartDate {
            restartDate = nil
            start(workoutStartDate: date)
        }
    }

    private func setRecording(_ value: Bool) {
        guard isRecording != value else { return }
        isRecording = value
        onRecordingChanged?(value)
    }

    // MARK: Events on the main actor

    private func sessionStateChanged(sessionID: ObjectIdentifier, isRunning: Bool, isEnded: Bool, date: Date) {
        guard let current = liveSession, ObjectIdentifier(current) == sessionID else { return }
        if isRunning {
            guard phase == .starting else { return }
            phase = .running
            setRecording(true)
        } else if isEnded {
            finalize(endDate: date, endSessionFirst: false)
        }
    }

    private func sessionFailed(sessionID: ObjectIdentifier) {
        guard let current = liveSession, ObjectIdentifier(current) == sessionID else { return }
        finalize(endDate: Date(), endSessionFirst: true)
    }

    private func heartRateCollected(_ bpm: Int, builderID: ObjectIdentifier) {
        guard let current = liveBuilder, ObjectIdentifier(current) == builderID else { return }
        guard phase == .starting || phase == .running else { return }
        latestHeartRate = bpm
        onHeartRate?(bpm)
    }

    // MARK: HKWorkoutSessionDelegate (called on a background queue)

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let sessionID = ObjectIdentifier(workoutSession)
        let isRunning = toState == .running
        let isEnded = toState == .ended
        Task { @MainActor [weak self] in
            self?.sessionStateChanged(sessionID: sessionID, isRunning: isRunning, isEnded: isEnded, date: date)
        }
    }

    nonisolated public func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let sessionID = ObjectIdentifier(workoutSession)
        Task { @MainActor [weak self] in
            self?.sessionFailed(sessionID: sessionID)
        }
    }

    // MARK: HKLiveWorkoutBuilderDelegate (called on a background queue)

    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
    }

    nonisolated public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let builderID = ObjectIdentifier(workoutBuilder)
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            guard quantityType.identifier == HKQuantityTypeIdentifier.heartRate.rawValue else { continue }
            guard let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            guard let quantity = statistics.mostRecentQuantity() else { continue }
            let value = quantity.doubleValue(for: unit)
            guard value.isFinite, value > 0 else { continue }
            let bpm = Int(value.rounded())
            Task { @MainActor [weak self] in
                self?.heartRateCollected(bpm, builderID: builderID)
            }
        }
    }
}
#endif
