import Foundation

public extension TemplateDiff {
    /// What changed in `state` relative to the template it was started from (added, removed and reordered exercises).
    ///
    /// An exercise counts as added when it has no template entry, its entry is not in the baseline, or another exercise
    /// already claims that entry; a baseline entry counts as removed when no exercise refers to it; the exercises that
    /// remain are reordered when their relative order differs from the baseline.
    static func compute(for state: WorkoutState) -> TemplateDiff {
        let baseline = state.templateBaseline
        let baselineSet = Set(baseline)

        var claimed = Set<UUID>()
        var added = 0
        var common: [UUID] = []
        for entry in state.exercises {
            if let entryID = entry.templateEntryID, baselineSet.contains(entryID), !claimed.contains(entryID) {
                claimed.insert(entryID)
                common.append(entryID)
            } else {
                added += 1
            }
        }

        let removed = baseline.filter { !claimed.contains($0) }.count
        let baselineCommon = baseline.filter { claimed.contains($0) }
        return TemplateDiff(added: added, removed: removed, reordered: common != baselineCommon)
    }
}
