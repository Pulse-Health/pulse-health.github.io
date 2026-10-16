import Foundation

/// Which template to train next: the one after the most recently performed template in the list, wrapping around
/// (Upper A, Lower A, Upper B, then Upper A again). The Strength hub's recommendation, the "next up" widgets and the Start controls all use it.
public enum TemplateRotation {
    /// The template to do next: nil without templates, the first one while none has been performed, and a single template recommends
    /// itself. When two templates share the latest date the one earlier in the list counts as the latest.
    public static func next(in templates: [WorkoutTemplate]) -> WorkoutTemplate? {
        guard !templates.isEmpty else { return nil }
        var latestIndex: Int?
        var latestDate = Date.distantPast
        for (index, template) in templates.enumerated() {
            if let date = template.lastPerformed, date > latestDate {
                latestDate = date
                latestIndex = index
            }
        }
        guard let last = latestIndex else { return templates[0] }
        return templates[(last + 1) % templates.count]
    }
}
