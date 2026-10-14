#if os(watchOS)
import Foundation
import Combine
import HealthKit
import PulseStrengthCore

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

/// Stops the data collection and saves the workout to Health. The builder stays alive until saving finishes. When HealthKit
/// refuses `endDate` and a `fallbackEndDate` is given (`endDate` is an earlier time than the moment of ending, taken from the
/// phone), the collection ends at the fallback instead: the workout is saved either way.
private func endCollectionAndSave(_ builder: HKLiveWorkoutBuilder, endDate: Date, fallbackEndDate: Date? = nil) {
    builder.endCollection(withEnd: endDate) { (succeeded: Bool, _: Error?) in
        if !succeeded, let fallbackEndDate {
            builder.endCollection(withEnd: fallbackEndDate) { (_: Bool, _: Error?) in
                builder.finishWorkout { (_: HKWorkout?, _: Error?) in
                }
            }
            return
        }
        builder.finishWorkout { (_: HKWorkout?, _: Error?) in
        }
    }
}

/// Stops the data collection and throws the workout away: nothing is written to Health.
private func discardCollection(of builder: HKLiveWorkoutBuilder) {
    builder.discardWorkout()
}

/// The answer of `recoverActiveWorkoutSession`, wrapped so that it can cross from HealthKit's queue to the main actor. The session
/// is only handed on, never used from two threads at once.
private final class RecoveredSession: @unchecked Sendable {
    let session: HKWorkoutSession?

    init(_ session: HKWorkoutSession?) {
        self.session = session
    }
}

/// Asks HealthKit for the workout session that was running when the app crashed or was terminated (nil when there is none).
private func recoverActiveSession(store: HKHealthStore, completion: @escaping @Sendable (RecoveredSession) -> Void) {
    store.recoverActiveWorkoutSession { (session: HKWorkoutSession?, _: Error?) in
        completion(RecoveredSession(session))
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
/// `start(workoutStartDate:)` and `end(save:endDate:)` are idempotent. `end(save: false)` throws the workout away instead of
/// saving it (the phone discarded it); `endDate` is when the phone ended the workout if the Watch learned of it later.
/// `setPaused(_:)` follows the phone's pause, and `recover()` takes over the session the system kept alive after a crash.
/// `onEndedByItself` reports a session that ended without `end` having been called. HealthKit delegate callbacks arrive on
/// background queues and are moved to the main actor with Sendable values only.
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

    /// Called after a session that was recording ended although `end(save:endDate:)` was never called (another app took the
    /// workout session, or HealthKit failed it). What it recorded has been saved by then, so a session started again for the same
    /// workout must not begin at the workout's start: the two Health workouts would overlap.
    public var onEndedByItself: (@MainActor () -> Void)?

    /// When the Health workout of the session in hand began (the start it was given, or the one HealthKit reports for a recovered
    /// session); nil without a session, or while one is still being set up or recovered.
    public private(set) var recordingStartDate: Date?

    private enum Phase {
        case idle
        case authorizing
        /// Waiting for HealthKit to hand over the session that survived a crash.
        case recovering
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
    /// A start requested while the previous session was still ending (or a crashed one was being recovered); run as soon as that
    /// one is finished.
    private var restartDate: Date?
    private var endFallback: Task<Void, Never>?
    /// Set by `end(save: false)` (and by a builder that could not start): the session being ended is finalized without saving.
    private var discardOnEnd = false
    /// When the phone ended the workout, if the Watch learned of it later (`end(save:endDate:)`): the Health workout ends then.
    private var requestedEndDate: Date?
    /// An `end` that arrived while the crashed session was being recovered: it ends as soon as it is in hand.
    private var endAfterRecovery = false
    /// Whether the phone's workout is paused, and so whether the Health session should be (see `setPaused(_:)`).
    private var wantsPaused = false
    /// The last pause state the phone reported, even when it equalled `wantsPaused` at the time; nil before the first report. A
    /// recovered session takes it over instead of the state the session had when the app crashed.
    private var phonePaused: Bool?

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
        case .ending, .recovering:
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
        recordingStartDate = startDate
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
        // The builder could not start collecting: give this session up so that the next workout can try again. Nothing was
        // recorded, so there is nothing worth saving.
        discardOnEnd = true
        finalize(endDate: Date(), endSessionFirst: true)
    }

    // MARK: End

    /// Ends the session. With `save` (the default) the workout is saved to Health (end of collection, then finish); with
    /// `save: false` it is thrown away (`HKWorkoutBuilder.discardWorkout()`: nothing reaches Health), which is what a workout the
    /// phone discarded, or a session that never got a workout, needs. A discard wins over a save when the session is already
    /// ending, unless a start is queued behind it: then the call is about that queued session and only cancels the start.
    /// `isRecording` becomes false immediately. Does nothing without a session.
    ///
    /// `endDate` is when the phone ended the workout, for a Watch that learned of it later (the phone finished while the link was
    /// down): the saved Health workout ends then (`SyncReconciler.healthWorkoutEnd` decides whether the time is usable) instead
    /// of when the Watch got round to it. nil: the Watch's own moment.
    public func end(save: Bool = true, endDate: Date? = nil) {
        switch phase {
        case .idle:
            restartDate = nil
        case .authorizing:
            authorizationTicket += 1
            phase = .idle
            restartDate = nil
        case .recovering:
            // The crashed session is not in hand yet: it ends as soon as it is.
            endAfterRecovery = true
            if !save { discardOnEnd = true }
            if let endDate { requestedEndDate = endDate }
            restartDate = nil
        case .starting, .running:
            if !save { discardOnEnd = true }
            if let endDate { requestedEndDate = endDate }
            phase = .ending
            setRecording(false)
            liveSession?.end()
            armEndFallback()
        case .ending:
            // A queued start means this call is about the queued session, not about the one that is still ending: it must not
            // decide how the ending one is finalized (the workout that just finished would be thrown away with it).
            if restartDate == nil, !save { discardOnEnd = true }
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

    /// Releases the session and the builder, saves (or discards) the workout and starts a queued restart.
    private func finalize(endDate: Date, endSessionFirst: Bool) {
        endFallback?.cancel()
        endFallback = nil

        let discard = discardOnEnd
        discardOnEnd = false
        let requestedEnd = requestedEndDate
        requestedEndDate = nil
        let startedAt = recordingStartDate
        recordingStartDate = nil
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
            if discard {
                discardCollection(of: builder)
            } else {
                let healthEnd = SyncReconciler.healthWorkoutEnd(requested: requestedEnd, processedAt: endDate, start: startedAt)
                endCollectionAndSave(builder, endDate: healthEnd, fallbackEndDate: healthEnd == endDate ? nil : endDate)
            }
        }

        if let date = restartDate {
            restartDate = nil
            start(workoutStartDate: date)
        }
    }

    // MARK: Pause

    /// Mirrors the phone's pause: while the workout is paused the Health session is paused too, so Health's duration, heart rate
    /// and active energy leave the pauses out, as the app's own duration does. Call it with the phone's state whenever it
    /// changes; a pause that arrives before the session is running is applied as soon as it runs. Does nothing for a repeated
    /// value.
    public func setPaused(_ paused: Bool) {
        phonePaused = paused
        guard paused != wantsPaused else { return }
        wantsPaused = paused
        applyPause()
    }

    /// Brings the running Health session in line with `wantsPaused`. HealthKit reports the new state to the delegate afterwards,
    /// and `sessionStateChanged` calls this again for every `running` and `paused` report, so a pause or a resume that was
    /// skipped because the session had not changed state yet is applied as soon as it has (a resume to `running` is not a start).
    private func applyPause() {
        guard phase == .running, let session = liveSession else { return }
        if wantsPaused {
            if session.state == .running { session.pause() }
        } else if session.state == .paused {
            session.resume()
        }
    }

    // MARK: Recovery

    /// After the app crashed or was terminated during a workout the system keeps the Health session alive and relaunches the app
    /// (`WKApplicationDelegate.handleActiveWorkoutRecovery()`): takes that session over, so heart rate flows again and the workout
    /// is saved when it ends, instead of a second session being started next to the orphan. Returns false (and does nothing) while
    /// a session already exists or is starting. The session is released like any other when `end(save:)` is called, so the caller
    /// must end it when no workout shows up.
    @discardableResult
    public func recover() -> Bool {
        guard phase == .idle else { return false }
        phase = .recovering
        endAfterRecovery = false
        recoverActiveSession(store: healthStore) { [weak self] (recovered: RecoveredSession) in
            Task { @MainActor [weak self] in
                self?.recoveryFinished(recovered.session)
            }
        }
        return true
    }

    private func recoveryFinished(_ recovered: HKWorkoutSession?) {
        guard phase == .recovering else { return }
        let endRequested = endAfterRecovery
        endAfterRecovery = false
        guard let recovered else {
            // The system has no session to give back (the workout already ended): carry on with a start that waited.
            phase = .idle
            discardOnEnd = false
            requestedEndDate = nil
            if let date = restartDate {
                restartDate = nil
                start(workoutStartDate: date)
            }
            return
        }

        let builder = recovered.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: recovered.workoutConfiguration)
        recovered.delegate = self
        builder.delegate = self

        liveSession = recovered
        liveBuilder = builder
        recordingStartDate = recovered.startDate
        restartDate = nil
        latestHeartRate = nil
        // A recovered session keeps the state it had, unless the phone already reported its pause state while the session was
        // being recovered (the report is newer than the crash); the phone's next state decides from then on.
        wantsPaused = phonePaused ?? (recovered.state == .paused)
        phase = .running
        setRecording(true)
        if endRequested {
            end()
        } else {
            applyPause()
        }
    }

    private func setRecording(_ value: Bool) {
        guard isRecording != value else { return }
        isRecording = value
        onRecordingChanged?(value)
    }

    // MARK: Events on the main actor

    private func sessionStateChanged(sessionID: ObjectIdentifier, isRunning: Bool, isPaused: Bool, isEnded: Bool, date: Date) {
        guard let current = liveSession, ObjectIdentifier(current) == sessionID else { return }
        if isRunning {
            if phase == .starting {
                phase = .running
                setRecording(true)
            }
            // The phone may have been paused before the session got going, or paused again while it resumed.
            if phase == .running { applyPause() }
        } else if isPaused {
            // A resume that arrived before the session had paused found it running and did nothing: do it now.
            if phase == .running { applyPause() }
        } else if isEnded {
            let wasRecording = phase == .running
            finalize(endDate: date, endSessionFirst: false)
            if wasRecording { onEndedByItself?() }
        }
    }

    private func sessionFailed(sessionID: ObjectIdentifier) {
        guard let current = liveSession, ObjectIdentifier(current) == sessionID else { return }
        let wasRecording = phase == .running
        finalize(endDate: Date(), endSessionFirst: true)
        if wasRecording { onEndedByItself?() }
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
        let isPaused = toState == .paused
        let isEnded = toState == .ended
        Task { @MainActor [weak self] in
            self?.sessionStateChanged(sessionID: sessionID, isRunning: isRunning, isPaused: isPaused, isEnded: isEnded, date: date)
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
