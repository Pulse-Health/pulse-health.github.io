#if os(iOS)
import Foundation
import PulseStrengthCore

/// Keeps the content of the workout Live Activity inside ActivityKit's size limit.
///
/// ActivityKit accepts at most 4 KB for the attributes and the content state together. Everything in a `WorkoutSnapshot` is short
/// except the names that come from text fields without a limit (workout, exercise) and the lists a long superset or a very heavy bar
/// can produce, so the app bounds them before every start, update and end:
///
/// * `clamped` cuts a name to `maximumNameScalars` Unicode scalars plus "…" (60 scalars are at most 240 bytes of UTF-8; the workout name
///   is in the attributes as well, so four names in all);
/// * `fitting` also bounds the texts and lists of the live moments (record banner, superset, plates, coach tip, finish card) and then
///   checks the encoded size: if a state with long multi-byte names still does not fit, the optional pieces are dropped, least valuable
///   first, until it does.
///
/// Pure functions of the snapshot, so the visual tests can assert the limit without the app.
public enum ActivityContentFitting {
    /// Most Unicode scalars of a workout or exercise name.
    public static let maximumNameScalars = 60
    /// Most bytes the encoded `WorkoutSnapshot` may take: 4096 less the attributes (a UUID and a name, about 330 bytes) and a margin for
    /// the difference between this encoder and ActivityKit's.
    public static let maximumStateBytes = 3_400

    /// Most members of a superset the content carries (the Lock Screen has room for three rows).
    public static let maximumSupersetMembers = 3
    /// Most plates per side the content carries (the Lock Screen draws four of them, the summary text names all of them).
    static let maximumPlates = 8

    /// `text` itself when it has at most `limit` Unicode scalars, else its start (whole characters, so no emoji or accent is cut in
    /// half; a single character of more scalars than the limit is cut) followed by "…".
    public static func clamped(_ text: String, limit: Int = ActivityContentFitting.maximumNameScalars) -> String {
        if text.unicodeScalars.dropFirst(limit).isEmpty {
            return text
        }
        var result = ""
        var used = 0
        for character in text {
            let size = character.unicodeScalars.count
            if used + size > limit {
                break
            }
            result.append(character)
            used += size
        }
        if result.isEmpty {
            result = String(text.unicodeScalars.prefix(limit))
        }
        return result + "…"
    }

    /// The snapshot as it goes to ActivityKit: names and moment texts bounded, and, when the encoded state is still too large, the
    /// optional pieces dropped (plates, coach tip, superset rows beyond two, the superset, the record banner, the finish card).
    /// A superset of more than `maximumSupersetMembers` keeps the current member and its neighbours.
    public static func fitting(_ snapshot: WorkoutSnapshot) -> WorkoutSnapshot {
        var fitted = boundedTexts(snapshot)
        let steps: [(inout WorkoutSnapshot) -> Void] = [
            { $0.plates = nil },
            { $0.coachTip = nil },
            { snapshot in
                if var superset = snapshot.superset {
                    superset.members = window(of: superset.members, size: 2)
                    snapshot.superset = superset
                }
            },
            { $0.superset = nil },
            { $0.moment = nil },
            { $0.finish = nil },
        ]
        for step in steps {
            if encodedSize(of: fitted) <= maximumStateBytes {
                break
            }
            step(&fitted)
        }
        return fitted
    }

    /// Bytes of the JSON the snapshot encodes to; `Int.max` when it cannot be encoded (everything optional is then dropped).
    static func encodedSize(of snapshot: WorkoutSnapshot) -> Int {
        guard let data = try? JSONEncoder().encode(snapshot) else { return Int.max }
        return data.count
    }

    // MARK: Bounding the texts

    private static func boundedTexts(_ snapshot: WorkoutSnapshot) -> WorkoutSnapshot {
        var bounded = snapshot
        bounded.workoutName = clamped(snapshot.workoutName)
        bounded.exerciseName = clamped(snapshot.exerciseName)
        bounded.nextExerciseName = snapshot.nextExerciseName.map { clamped($0) }
        bounded.moment = snapshot.moment.map { boundedMoment($0) }
        bounded.superset = snapshot.superset.map { boundedSuperset($0) }
        bounded.plates = snapshot.plates.map { boundedPlates($0) }
        bounded.coachTip = snapshot.coachTip.map { boundedTip($0) }
        bounded.finish = snapshot.finish.map { boundedFinish($0) }
        return bounded
    }

    private static func boundedMoment(_ moment: PRMoment) -> PRMoment {
        var bounded = moment
        bounded.exerciseName = clamped(moment.exerciseName, limit: 40)
        bounded.weightText = clamped(moment.weightText, limit: 12)
        bounded.repsText = clamped(moment.repsText, limit: 6)
        return bounded
    }

    /// At most `maximumSupersetMembers` members, each with short texts.
    private static func boundedSuperset(_ superset: SupersetBrief) -> SupersetBrief {
        var bounded = superset
        bounded.label = clamped(superset.label, limit: 4)
        bounded.members = window(of: superset.members, size: maximumSupersetMembers).map { member in
            var shortened = member
            shortened.tag = clamped(member.tag, limit: 4)
            shortened.name = clamped(member.name, limit: 28)
            shortened.detail = clamped(member.detail, limit: 20)
            return shortened
        }
        return bounded
    }

    /// `size` consecutive members that include the current one and, when there is room, the one before it; all of them when the group
    /// is not longer than `size`. The views use it too, for a snapshot that did not pass through `fitting`.
    public static func window(of members: [SupersetMember], size: Int) -> [SupersetMember] {
        guard members.count > size else { return members }
        let current = members.firstIndex(where: { $0.isCurrent }) ?? 0
        let start = min(max(0, current - 1), members.count - size)
        return Array(members[start..<(start + size)])
    }

    /// A bar of 100,000 kg would need thousands of plates per side, so the list is cut; the summary text says the rest.
    private static func boundedPlates(_ plates: PlateBrief) -> PlateBrief {
        var bounded = plates
        bounded.perSide = Array(plates.perSide.prefix(maximumPlates))
        bounded.summary = clamped(plates.summary, limit: 40)
        return bounded
    }

    private static func boundedTip(_ tip: CoachTipBrief) -> CoachTipBrief {
        var bounded = tip
        bounded.title = clamped(tip.title, limit: 24)
        bounded.subtitle = clamped(tip.subtitle, limit: 40)
        bounded.text = clamped(tip.text, limit: 100)
        bounded.suggestedWeightText = clamped(tip.suggestedWeightText, limit: 12)
        bounded.keepWeightText = clamped(tip.keepWeightText, limit: 16)
        return bounded
    }

    private static func boundedFinish(_ finish: FinishBrief) -> FinishBrief {
        var bounded = finish
        bounded.workoutName = clamped(finish.workoutName, limit: 40)
        bounded.volumeText = clamped(finish.volumeText, limit: 8)
        return bounded
    }
}
#endif
