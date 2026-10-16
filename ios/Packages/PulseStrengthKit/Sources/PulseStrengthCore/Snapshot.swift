import Foundation

// MARK: - Snapshot (Live Activity content, Watch screens)

public enum SnapshotPhase: String, Codable, Hashable, Sendable {
    /// A set is waiting to be logged.
    case logging
    /// Rest countdown is running.
    case resting
    /// Rest countdown reached zero and has not been dismissed.
    case restOver
    /// Every set of every exercise is logged.
    case complete
}

/// A small, flat summary of the workout for surfaces that cannot render the full state:
/// the Live Activity / Dynamic Island and the Apple Watch. It is the `ContentState` of the
/// Live Activity, so it must stay small (ActivityKit limit: 4 KB).
/// Built by `SnapshotBuilder.make(from:now:)`.
public struct WorkoutSnapshot: Codable, Hashable, Sendable {
    public var workoutID: UUID
    public var revision: Int
    public var workoutName: String

    /// `startedAt + pausedTotal`: elapsed active time is `now - activeStart` while running.
    public var activeStart: Date
    public var isPaused: Bool
    /// Elapsed seconds, valid while paused (frozen).
    public var elapsedWhenPaused: Int

    public var phase: SnapshotPhase
    public var exerciseName: String
    /// 0-based position of the current exercise.
    public var exerciseIndex: Int
    public var exerciseCount: Int

    /// The set a "Log set" button logs (the next pending set); nil when `phase == .complete`.
    public var targetExerciseID: UUID?
    public var targetSetID: UUID?
    /// "Set 4 of 5" or "Warm-up 1 of 2" style label for the target set.
    public var setLabel: String
    public var tracking: TrackingKind
    public var weightText: String
    public var repsText: String
    /// "reps" or "sec".
    public var repsUnit: String
    /// True when the target exercise logs a weight (weightReps).
    public var showsWeight: Bool

    /// Rest countdown: `restStartedAt ... restEndsAt` for `Text(timerInterval:)` / `ProgressView(timerInterval:)`.
    public var restStartedAt: Date?
    public var restEndsAt: Date?
    public var restTotalSeconds: Int
    /// Seconds left while the workout is paused (frozen rest).
    public var restFrozenRemaining: Int?

    public var heartRate: Int?
    public var volumeText: String
    public var loggedSets: Int
    public var totalSets: Int
    /// "Set 4 · 82.5 kg × 6"
    public var nextSetText: String
    public var nextExerciseName: String?

    // MARK: Live moments and context (all optional: an older payload without them still decodes)

    /// Sets of the shown exercise that are logged / in total (the "set dots" of the compact Dynamic Island).
    public var exerciseDoneSets: Int?
    public var exerciseSetCount: Int?
    /// A personal record that was just logged; cleared by an update at `PRMoment.expiresAt`.
    public var moment: PRMoment?
    /// The running superset, nil when the shown exercise is not in one.
    public var superset: SupersetBrief?
    /// Plates for the target set; nil unless the target is a barbell weight exercise.
    public var plates: PlateBrief?
    /// A one-tap suggestion shown while resting (reps in reserve of the last set were high).
    public var coachTip: CoachTipBrief?
    /// Set on the final content of a finished workout (the Live Activity stays on the Lock Screen for a while).
    public var finish: FinishBrief?

    public init(
        workoutID: UUID,
        revision: Int,
        workoutName: String,
        activeStart: Date,
        isPaused: Bool,
        elapsedWhenPaused: Int,
        phase: SnapshotPhase,
        exerciseName: String,
        exerciseIndex: Int,
        exerciseCount: Int,
        targetExerciseID: UUID? = nil,
        targetSetID: UUID? = nil,
        setLabel: String,
        tracking: TrackingKind,
        weightText: String,
        repsText: String,
        repsUnit: String,
        showsWeight: Bool,
        restStartedAt: Date? = nil,
        restEndsAt: Date? = nil,
        restTotalSeconds: Int,
        restFrozenRemaining: Int? = nil,
        heartRate: Int? = nil,
        volumeText: String,
        loggedSets: Int,
        totalSets: Int,
        nextSetText: String,
        nextExerciseName: String? = nil,
        exerciseDoneSets: Int? = nil,
        exerciseSetCount: Int? = nil,
        moment: PRMoment? = nil,
        superset: SupersetBrief? = nil,
        plates: PlateBrief? = nil,
        coachTip: CoachTipBrief? = nil,
        finish: FinishBrief? = nil
    ) {
        self.workoutID = workoutID
        self.revision = revision
        self.workoutName = workoutName
        self.activeStart = activeStart
        self.isPaused = isPaused
        self.elapsedWhenPaused = elapsedWhenPaused
        self.phase = phase
        self.exerciseName = exerciseName
        self.exerciseIndex = exerciseIndex
        self.exerciseCount = exerciseCount
        self.targetExerciseID = targetExerciseID
        self.targetSetID = targetSetID
        self.setLabel = setLabel
        self.tracking = tracking
        self.weightText = weightText
        self.repsText = repsText
        self.repsUnit = repsUnit
        self.showsWeight = showsWeight
        self.restStartedAt = restStartedAt
        self.restEndsAt = restEndsAt
        self.restTotalSeconds = restTotalSeconds
        self.restFrozenRemaining = restFrozenRemaining
        self.heartRate = heartRate
        self.volumeText = volumeText
        self.loggedSets = loggedSets
        self.totalSets = totalSets
        self.nextSetText = nextSetText
        self.nextExerciseName = nextExerciseName
        self.exerciseDoneSets = exerciseDoneSets
        self.exerciseSetCount = exerciseSetCount
        self.moment = moment
        self.superset = superset
        self.plates = plates
        self.coachTip = coachTip
        self.finish = finish
    }
}

// MARK: - Watch / Live Activity -> phone sync

/// A command issued on another surface (Watch, Live Activity button) and executed by the phone.
public struct RemoteCommand: Codable, Hashable, Sendable, Identifiable {
    /// Unique id so the receiver can drop duplicates (WatchConnectivity may redeliver) and acknowledge the command
    /// (`SyncEnvelope.ackedCommandIDs`).
    public var id: UUID
    public var action: WorkoutAction
    public var origin: ActionOrigin
    public var issuedAt: Date
    /// The workout the sender was showing when it issued the command; nil for a sender that does not say.
    ///
    /// The phone ignores a command whose workout is not the one running, so a late command (queued by
    /// `transferUserInfo` while the Watch was out of reach) cannot act on the next workout. An older payload without this
    /// entry decodes to nil.
    public var workoutID: UUID?
    /// Which launch of the sending mirror made the command (one id per `WorkoutEngine` instance). Together with `sequence` it lets
    /// the phone recognise a command that was overtaken by a newer edit of the same value: the Watch's two channels
    /// (`sendMessage`, `transferUserInfo`) have no common order. nil for a sender that does not number its commands (an older
    /// Watch app, the Live Activity); an older payload without this entry decodes to nil.
    public var senderID: UUID?
    /// The command's position among the commands of `senderID` (1, 2, 3, ...); nil together with `senderID`.
    public var sequence: Int?

    public init(
        id: UUID = UUID(),
        action: WorkoutAction,
        origin: ActionOrigin,
        issuedAt: Date = Date(),
        workoutID: UUID? = nil,
        senderID: UUID? = nil,
        sequence: Int? = nil
    ) {
        self.id = id
        self.action = action
        self.origin = origin
        self.issuedAt = issuedAt
        self.workoutID = workoutID
        self.senderID = senderID
        self.sequence = sequence
    }
}

/// The phone's authoritative state, pushed to the Watch after every change and after every command it received.
///
/// Besides the state it acknowledges the commands the phone dealt with (`ackedCommandIDs`), so the Watch can stop showing its
/// own, optimistic copy of those edits. An envelope can be delivered twice, late, out of order or coalesced with a newer one;
/// the acknowledgements therefore repeat the most recent command ids in every envelope.
public struct SyncEnvelope: Codable, Hashable, Sendable {
    /// nil = the workout ended; see `endedWorkoutID`.
    public var state: WorkoutState?
    public var endedWorkoutID: UUID?
    public var sentAt: Date
    /// Ids of the most recent commands the phone has dealt with (applied, dropped as duplicates or found to be no-ops), oldest
    /// first. The Watch removes these from the edits it still shows on top of `state`. Empty in an older payload.
    public var ackedCommandIDs: [UUID]
    /// True for an envelope that was decoded from a payload without the `ackedCommandIDs` entry: it comes from a phone build that
    /// does not acknowledge commands at all, so the Watch must not wait for acknowledgements that will never come (the mirror
    /// then lets the phone's state win, as it did before acknowledgements existed). Every envelope made by this code, including
    /// one with an empty list, writes the entry and is not legacy. Not part of the payload and not part of equality.
    public private(set) var isFromLegacyPhone: Bool = false
    /// How the workout named by `endedWorkoutID` ended: true when the phone threw it away (Discard Workout, or a finish with no
    /// logged set, which the phone discards), false when it was finished and recorded. nil when the envelope does not say: it
    /// carries a state, no workout ended since the phone app launched, or it comes from a phone build that does not send the
    /// entry (an older payload without it decodes to nil). The Watch uses it to decide whether its Health session saves the
    /// workout to Health or throws it away.
    public var discarded: Bool?

    public init(
        state: WorkoutState?,
        endedWorkoutID: UUID? = nil,
        sentAt: Date = Date(),
        ackedCommandIDs: [UUID] = [],
        discarded: Bool? = nil
    ) {
        self.state = state
        self.endedWorkoutID = endedWorkoutID
        self.sentAt = sentAt
        self.ackedCommandIDs = ackedCommandIDs
        self.discarded = discarded
    }

    private enum CodingKeys: String, CodingKey {
        case state, endedWorkoutID, sentAt, ackedCommandIDs, discarded
    }

    /// Reads an envelope; a payload written before acknowledgements existed has no `ackedCommandIDs`: it decodes to `[]` and
    /// is marked `isFromLegacyPhone`. A payload without `discarded` decodes to nil.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decodeIfPresent(WorkoutState.self, forKey: .state)
        endedWorkoutID = try container.decodeIfPresent(UUID.self, forKey: .endedWorkoutID)
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        let acknowledged = try container.decodeIfPresent([UUID].self, forKey: .ackedCommandIDs)
        ackedCommandIDs = acknowledged ?? []
        isFromLegacyPhone = acknowledged == nil
        discarded = try container.decodeIfPresent(Bool.self, forKey: .discarded)
    }

    public static func == (lhs: SyncEnvelope, rhs: SyncEnvelope) -> Bool {
        lhs.state == rhs.state && lhs.endedWorkoutID == rhs.endedWorkoutID && lhs.sentAt == rhs.sentAt
            && lhs.ackedCommandIDs == rhs.ackedCommandIDs && lhs.discarded == rhs.discarded
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(state)
        hasher.combine(endedWorkoutID)
        hasher.combine(sentAt)
        hasher.combine(ackedCommandIDs)
        hasher.combine(discarded)
    }
}

public struct HeartRateSample: Codable, Hashable, Sendable {
    public var bpm: Int
    public var at: Date

    public init(bpm: Int, at: Date = Date()) {
        self.bpm = bpm
        self.at = at
    }
}

/// Every message that crosses the WatchConnectivity channel.
public enum SyncMessage: Codable, Hashable, Sendable {
    /// Phone -> Watch.
    case state(SyncEnvelope)
    /// Watch -> phone.
    case command(RemoteCommand)
    /// Watch -> phone.
    case heartRate(HeartRateSample)
    /// Watch -> phone: the Watch workout session started / stopped recording.
    case watchSession(isRecording: Bool)
    /// Watch -> phone: send me the current state.
    case requestState
}
