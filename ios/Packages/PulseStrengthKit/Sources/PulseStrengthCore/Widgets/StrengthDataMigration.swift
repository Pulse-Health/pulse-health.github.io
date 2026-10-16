import Foundation

/// Moves the strength data into the App Group container when the app gains the App Group capability.
///
/// Before widgets existed the app kept its files in `Application Support/PulseStrength`; the widget extension, the controls and the Watch
/// widgets can only read the group container, so the app now keeps everything there. The first launch copies what the old folder holds.
public enum StrengthDataMigration {
    /// The files `FileStrengthPersistence` writes.
    public static let fileNames = [
        "active-workout.json", "templates.json", "history.json", "custom-exercises.json",
        "personal-bests.json", "acknowledged-commands.json", "settings.json",
    ]

    /// Copies every data file that exists in `legacy` but not yet in `target`; an existing file in `target` is never replaced and
    /// nothing is deleted from `legacy` (a failed or partial migration can run again). Returns the number of files copied.
    @discardableResult
    public static func copyMissingFiles(from legacy: URL, to target: URL) -> Int {
        guard legacy.standardizedFileURL != target.standardizedFileURL else { return 0 }
        let manager = FileManager.default
        var copied = 0
        for name in fileNames {
            let source = legacy.appendingPathComponent(name)
            let destination = target.appendingPathComponent(name)
            guard manager.fileExists(atPath: source.path), !manager.fileExists(atPath: destination.path) else { continue }
            do {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
                try manager.copyItem(at: source, to: destination)
                copied += 1
            } catch {
                continue
            }
        }
        return copied
    }
}
