#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Screen

/// "Workout Complete" (Summary.dc.html): shown full screen over the app after a workout is finished and saved.
///
/// It opens with a celebration (`WorkoutSummaryHero`: a medal whose ring and check draw themselves, confetti, the title and the
/// three big figures counting up) and a cue, "All Stats", that scrolls down when tapped. The stats come up over the celebration
/// as a sheet; from top to bottom it holds the workout name with the date and duration, the personal-record card (only with
/// PRs), the figure tiles (duration, volume, sets, and average heart rate / average RIR when they were recorded), the
/// per-exercise results and the sets per muscle group. A "Done" button stays at the bottom throughout: see-through over the
/// celebration, the solid green button over the stats.
///
/// The motion is a pure function of time (`SummaryCelebration` in the core holds the curves and the confetti paths and is unit
/// tested); with Reduce Motion the celebration is its finished picture and the success haptic fires at once.
///
/// The design's heart-rate zones, calories, coach text, "Save to Health" switch and template row need data or
/// settings that a `CompletedWorkout` does not carry (the workout is already saved when this screen appears), so
/// they are not shown. The muscle bars show sets, because the saved workout has no recovery figures.
@MainActor
public struct WorkoutSummaryView: View {
    private let workout: CompletedWorkout
    private let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didAnnounce = false
    /// Where the top of the scrolled content was before any scrolling: the baseline of `sheetProgress`.
    @State private var restTop: CGFloat?
    /// The height of the area the celebration fills; the stats sheet is at least that tall.
    @State private var viewportHeight: CGFloat = 0
    /// How far the stats sheet has come up over the celebration (0 to 1), in steps of 1/60 so the screen is not redrawn
    /// for every point of scrolling.
    @State private var sheetProgress: Double = 0

    private static let scrollSpace = "workoutSummaryScroll"

    public init(workout: CompletedWorkout, onDone: @escaping () -> Void) {
        self.workout = workout
        self.onDone = onDone
    }

    // MARK: Body

    public var body: some View {
        ScrollViewReader { reader in
            ZStack {
                WorkoutSummaryBackdrop(scrollProgress: sheetProgress)
                heroLayer
                ScrollView {
                    VStack(spacing: 0) {
                        heroSpacer
                        statsSheet
                    }
                }
                .coordinateSpace(name: WorkoutSummaryView.scrollSpace)
                .scrollIndicators(.hidden)
                .accessibilitySortPriority(1)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    WorkoutSummaryScrollCue(
                        visibility: SummaryCelebration.heroVisibility(scrollProgress: sheetProgress),
                        action: {
                            showStats(reader)
                        }
                    )
                }
                .accessibilitySortPriority(2)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            doneBar
        }
        .onPreferenceChange(WorkoutSummaryHeroFrameKey.self) { (frame: WorkoutSummaryHeroFrameKey.Frame) in
            track(frame)
        }
        .task {
            await announce()
        }
    }

    // MARK: Celebration

    /// The celebration sits still behind the scroll view while the stats sheet comes up over it: it shrinks and fades a little
    /// as the sheet covers it.
    private var heroLayer: some View {
        WorkoutSummaryHero(
            subtitle: heroSubtitle,
            figures: SummaryFigures(
                durationSeconds: workout.durationSeconds,
                volumeKg: workout.volumeKg,
                sets: workout.loggedSets
            ),
            spokenDuration: StrengthResultText.durationSpoken(seconds: workout.durationSeconds),
            spokenVolume: NumberText.thousands(workout.volumeKg) + " kilograms"
        )
        .scaleEffect(1 - 0.07 * sheetProgress)
        .offset(y: CGFloat(-24 * sheetProgress))
        .opacity(SummaryCelebration.heroVisibility(scrollProgress: sheetProgress))
        .allowsHitTesting(false)
        .accessibilityHidden(sheetProgress > 0.9)
        .accessibilitySortPriority(3)
    }

    /// The empty first page of the scroll view: as tall as the area the celebration fills, so the stats sheet starts just below it.
    /// Its position tells how far the user has scrolled.
    private var heroSpacer: some View {
        Color.clear
            .containerRelativeFrame(.vertical)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WorkoutSummaryHeroFrameKey.self,
                        value: WorkoutSummaryHeroFrameKey.Frame(
                            minY: proxy.frame(in: .named(WorkoutSummaryView.scrollSpace)).minY,
                            height: proxy.size.height
                        )
                    )
                }
            )
            .accessibilityHidden(true)
    }

    private func track(_ frame: WorkoutSummaryHeroFrameKey.Frame) {
        if abs(viewportHeight - frame.height) > 0.5 {
            viewportHeight = frame.height
        }
        guard frame.height > 0 else { return }
        if restTop == nil {
            restTop = frame.minY
        }
        let scrolled = (restTop ?? frame.minY) - frame.minY
        let progress = SummaryCelebration.scrollProgress(
            sheetTop: Double(frame.height - scrolled),
            heroHeight: Double(frame.height)
        )
        let stepped = (progress * 60).rounded() / 60
        if stepped != sheetProgress {
            sheetProgress = stepped
        }
    }

    private func showStats(_ reader: ScrollViewProxy) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if reduceMotion {
            reader.scrollTo(WorkoutSummaryAnchor.sheet, anchor: .top)
        } else {
            withAnimation(Animation.easeInOut(duration: 0.6)) {
                reader.scrollTo(WorkoutSummaryAnchor.sheet, anchor: .top)
            }
        }
    }

    // MARK: Stats sheet

    private var statsSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerBlock
            if !workout.personalRecords.isEmpty {
                WorkoutSummaryRecordsCard(records: workout.personalRecords)
            }
            WorkoutSummaryStatsCard(tiles: statTiles)
            if !workout.exercises.isEmpty {
                exercisesSection
            }
            if !workout.muscleSets.isEmpty {
                musclesSection
            }
        }
        .padding(.horizontal, PulseTheme.screenInset)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: PulseTheme.sheetRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: PulseTheme.sheetRadius,
                style: .continuous
            )
            .fill(PulseTheme.ground)
            .shadow(color: Color.black.opacity(0.18), radius: 15, x: 0, y: -5)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(PulseTheme.separator)
                .frame(width: 40, height: 5)
                .padding(.top, 9)
                .accessibilityHidden(true)
        }
        .id(WorkoutSummaryAnchor.sheet)
    }

    // MARK: Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: workout.name)
                .tracking(0.37)
                .pulseFont(34, .bold, relativeTo: .largeTitle)
                .foregroundStyle(PulseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: sheetSubtitle)
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dayText: String {
        StrengthResultText.weekdayMonthDay(workout.finishedAt, now: Date())
    }

    /// "Upper A · Fri, Oct 13": under the title of the celebration.
    private var heroSubtitle: String {
        workout.name + " · " + dayText
    }

    /// "Fri, Oct 13 · 52 min": under the workout name at the top of the stats.
    private var sheetSubtitle: String {
        dayText + " · " + StrengthResultText.durationSubtitle(seconds: workout.durationSeconds)
    }

    // MARK: Figures

    private var statTiles: [WorkoutSummaryTile] {
        var tiles: [WorkoutSummaryTile] = []
        tiles.append(
            WorkoutSummaryTile(
                id: "duration",
                title: "Duration",
                value: StrengthResultText.durationTile(seconds: workout.durationSeconds),
                spoken: StrengthResultText.durationSpoken(seconds: workout.durationSeconds)
            )
        )
        let volume = NumberText.thousands(workout.volumeKg)
        tiles.append(
            WorkoutSummaryTile(id: "volume", title: "Volume", value: volume + " kg", spoken: volume + " kilograms")
        )
        let sets = String(workout.loggedSets)
        tiles.append(
            WorkoutSummaryTile(id: "sets", title: "Sets", value: sets, spoken: sets)
        )
        if let bpm = workout.averageHeartRate, bpm > 0 {
            tiles.append(
                WorkoutSummaryTile(
                    id: "heartRate",
                    title: "Avg Heart Rate",
                    value: String(bpm) + " bpm",
                    spoken: String(bpm) + " beats per minute"
                )
            )
        }
        if let rir = workout.averageRIR {
            let text = StrengthResultText.oneDecimal(rir)
            tiles.append(
                WorkoutSummaryTile(id: "rir", title: "Avg RIR", value: text, spoken: text + " reps in reserve")
            )
        }
        return tiles
    }

    // MARK: Exercises

    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkoutSummarySectionTitle(text: "Exercises")
            VStack(spacing: 0) {
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { pair in
                    WorkoutSummaryExerciseRow(exercise: pair.element)
                        .overlay(alignment: .top) {
                            if pair.offset > 0 {
                                StrengthHairline()
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
        }
    }

    // MARK: Muscles

    private var musclesSection: some View {
        let mostSets = max(1, workout.muscleSets.map { $0.sets }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            WorkoutSummarySectionTitle(text: "Muscles Worked")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(workout.muscleSets) { item in
                    WorkoutSummaryMuscleRow(
                        muscle: item.muscle,
                        sets: item.sets,
                        fraction: Double(item.sets) / Double(mostSets)
                    )
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
        }
    }

    // MARK: Done

    /// See-through over the celebration, the solid bar of the stats page once the sheet is up.
    private var doneBar: some View {
        let solid = SummaryCelebration.barProgress(scrollProgress: sheetProgress)
        return Button {
            finish()
        } label: {
            Text("Done")
        }
        .buttonStyle(WorkoutSummaryDoneButtonStyle(progress: solid))
        .accessibilityIdentifier("summary.done")
        .padding(.horizontal, PulseTheme.screenInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(PulseTheme.ground.opacity(solid).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            StrengthHairline()
                .opacity(solid)
        }
    }

    // MARK: Feedback

    /// The success haptic lands with the impact of the celebration (the check landing), not when the screen opens.
    private func announce() async {
        guard !didAnnounce else { return }
        didAnnounce = true
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        if !reduceMotion {
            let wait = SummaryCelebration.appearDelay + SummaryCelebration.impact
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
        }
        generator.notificationOccurred(.success)
    }

    private func finish() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onDone()
    }
}

// MARK: - Scroll tracking

private enum WorkoutSummaryAnchor: Hashable {
    case sheet
}

/// Where the empty first page of the scroll view is (its top in the scroll view's space) and how tall it is.
private struct WorkoutSummaryHeroFrameKey: PreferenceKey {
    struct Frame: Equatable {
        var minY: CGFloat
        var height: CGFloat
    }

    static let defaultValue: Frame = Frame(minY: 0, height: 0)

    static func reduce(value: inout Frame, nextValue: () -> Frame) {
        value = nextValue()
    }
}

// MARK: - Section title

private struct WorkoutSummarySectionTitle: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .pulseFont(17, .semibold, relativeTo: .headline)
            .foregroundStyle(PulseTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Personal records

/// The yellow "New personal record" card: one row per record, separated by a hairline.
private struct WorkoutSummaryRecordsCard: View {
    let records: [PersonalRecord]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(records.enumerated()), id: \.element.id) { pair in
                VStack(spacing: 12) {
                    if pair.offset > 0 {
                        StrengthHairline()
                    }
                    WorkoutSummaryRecordRow(record: pair.element)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard()
    }
}

private struct WorkoutSummaryRecordRow: View {
    let record: PersonalRecord

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        rowContent
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    /// Trophy, text and gain in one row; with the accessibility sizes the text gets the full width and the gain
    /// moves beside the trophy.
    @ViewBuilder
    private var rowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    trophy
                    gain
                }
                textColumn
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 14) {
                trophy
                textColumn
                gain
            }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("New personal record")
                .pulseFont(12, .semibold, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.prText)
            Text(verbatim: record.exerciseName)
                .pulseFont(17, .semibold, relativeTo: .headline)
                .foregroundStyle(PulseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: detailText)
                .pulseNumber(15, .regular, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.ink.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trophy: some View {
        WorkoutSummaryTrophyShape()
            .stroke(PulseTheme.prText, style: StrokeStyle(lineWidth: 2.06, lineCap: .round, lineJoin: .round))
            .frame(width: 26, height: 26)
            .frame(width: 52, height: 52)
            .background(PulseTheme.prFill, in: Circle())
    }

    /// Whole-kilogram improvement over the previous best, as printed ("3 kg"); nil when it rounds to nothing.
    private var gainKg: Double? {
        guard record.previousBest > 0 else { return nil }
        let gain = record.estimated1RM.rounded() - record.previousBest.rounded()
        return gain >= 1 ? gain : nil
    }

    @ViewBuilder
    private var gain: some View {
        if let gainKg {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .pulseFont(12, .heavy, relativeTo: .footnote)
                Text(verbatim: NumberText.kg(gainKg) + " kg")
                    .pulseNumber(13, .semibold, relativeTo: .footnote)
            }
            .foregroundStyle(PulseTheme.green)
        }
    }

    /// "85 kg × 6 · est. 1RM 102 kg"
    private var detailText: String {
        let weight = NumberText.kg(record.weightKg)
        let estimate = NumberText.kg(record.estimated1RM.rounded())
        return "\(weight) kg × \(record.reps) · est. 1RM \(estimate) kg"
    }

    private var accessibilityText: String {
        let weight = NumberText.kg(record.weightKg)
        let estimate = NumberText.kg(record.estimated1RM.rounded())
        var text = "New personal record, \(record.exerciseName), \(weight) kilograms for \(record.reps) reps, estimated one-rep max \(estimate) kilograms"
        if let gainKg {
            text += ", up \(NumberText.kg(gainKg)) kilograms"
        }
        return text
    }
}

/// The trophy of the design (24 x 24 viewBox: cup, two handles, stem, base), drawn as strokes.
private struct WorkoutSummaryTrophyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.minX + (rect.width - 24 * scale) / 2
        let originY = rect.minY + (rect.height - 24 * scale) / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var path = Path()
        // Cup: M8 4 h8 v5 a4 4 0 0 1 -8 0 V4 z
        path.move(to: point(8, 4))
        path.addLine(to: point(16, 4))
        path.addLine(to: point(16, 9))
        path.addCurve(to: point(12, 13), control1: point(16, 11.209), control2: point(14.209, 13))
        path.addCurve(to: point(8, 9), control1: point(9.791, 13), control2: point(8, 11.209))
        path.closeSubpath()
        // Left handle: M8 6 H4 v1 a3 3 0 0 0 3 3
        path.move(to: point(8, 6))
        path.addLine(to: point(4, 6))
        path.addLine(to: point(4, 7))
        path.addCurve(to: point(7, 10), control1: point(4, 8.657), control2: point(5.343, 10))
        // Right handle: M16 6 h4 v1 a3 3 0 0 1 -3 3
        path.move(to: point(16, 6))
        path.addLine(to: point(20, 6))
        path.addLine(to: point(20, 7))
        path.addCurve(to: point(17, 10), control1: point(20, 8.657), control2: point(18.657, 10))
        // Stem: M12 13 v4
        path.move(to: point(12, 13))
        path.addLine(to: point(12, 17))
        // Base: M8 20 h8
        path.move(to: point(8, 20))
        path.addLine(to: point(16, 20))
        return path
    }
}

// MARK: - Figures

private struct WorkoutSummaryTile: Identifiable {
    let id: String
    let title: String
    let value: String
    /// What VoiceOver reads as the value.
    let spoken: String
}

/// White card with the figure tiles, three per row; a short last row keeps its columns.
private struct WorkoutSummaryStatsCard: View {
    let tiles: [WorkoutSummaryTile]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Three figures per row at the default text size (and below), as designed. Bigger text gives each figure more room:
    /// two per row, and one per row with the accessibility sizes.
    private var columns: Int {
        if dynamicTypeSize <= .large {
            return 3
        }
        return dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    private var rows: [[WorkoutSummaryTile]] {
        let columns = self.columns
        var result: [[WorkoutSummaryTile]] = []
        var index = 0
        while index < tiles.count {
            let end = min(index + columns, tiles.count)
            result.append(Array(tiles[index..<end]))
            index = end
        }
        return result
    }

    var body: some View {
        let rows = self.rows
        let columns = self.columns
        return VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                VStack(spacing: 10) {
                    if rowIndex > 0 {
                        StrengthHairline()
                    }
                    WorkoutSummaryTileRow(tiles: rows[rowIndex], columns: columns)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
    }
}

private struct WorkoutSummaryTileRow: View {
    let tiles: [WorkoutSummaryTile]
    let columns: Int

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            ForEach(0..<columns, id: \.self) { slot in
                if slot < tiles.count {
                    WorkoutSummaryTileView(tile: tiles[slot], showsDivider: slot > 0)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 1)
                }
            }
        }
    }
}

private struct WorkoutSummaryTileView: View {
    let tile: WorkoutSummaryTile
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: tile.title)
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: tile.value)
                .pulseNumber(20, .semibold, relativeTo: .title3)
                .foregroundStyle(PulseTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if showsDivider {
                Rectangle()
                    .fill(PulseTheme.separator)
                    .frame(width: 0.5)
                    .offset(x: -16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.title)
        .accessibilityValue(tile.spoken)
    }
}

// MARK: - Exercises

private struct WorkoutSummaryExerciseRow: View {
    let exercise: CompletedExercise

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One line for the name as designed; it wraps instead of truncating when the user chose bigger text.
    private var nameLineLimit: Int? {
        dynamicTypeSize > .large ? nil : 1
    }

    var body: some View {
        rowContent
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 64)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    /// Picture, text and PR tag in one row; with the accessibility sizes the tag moves into the text column.
    @ViewBuilder
    private var rowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: 12) {
                mediaTile
                VStack(alignment: .leading, spacing: 4) {
                    nameText
                    if exercise.isPersonalRecord {
                        StrengthPRChip(horizontal: 8, vertical: 3)
                    }
                    setsText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 12) {
                mediaTile
                VStack(alignment: .leading, spacing: 2) {
                    nameText
                    setsText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if exercise.isPersonalRecord {
                    StrengthPRChip(horizontal: 8, vertical: 3)
                }
            }
        }
    }

    private var mediaTile: some View {
        ExerciseMediaView(mediaKey: exercise.mediaKey, cornerRadius: 10)
            .frame(width: 44, height: 44)
    }

    private var nameText: some View {
        Text(verbatim: exercise.name)
            .pulseFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(PulseTheme.ink)
            .lineLimit(nameLineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var setsText: some View {
        Text(verbatim: setsLine)
            .pulseNumber(12, .regular, relativeTo: .footnote)
            .foregroundStyle(PulseTheme.inkSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var setsLine: String {
        StrengthResultText.setsLine(exercise.sets, tracking: exercise.tracking)
    }

    private var accessibilityText: String {
        let count = exercise.sets.count
        var text = exercise.name + ", " + String(count) + (count == 1 ? " set" : " sets")
        if exercise.isPersonalRecord {
            text += ", personal record"
        }
        text += ". " + setsLine.replacingOccurrences(of: " · ", with: ", ")
        return text
    }
}

// MARK: - Muscles

/// "Chest" and "8 sets" above a 6 pt bar whose length is the share of the most-worked muscle.
private struct WorkoutSummaryMuscleRow: View {
    let muscle: MuscleGroup
    let sets: Int
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: muscle.title)
                    .pulseFont(12, .semibold, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.ink)
                Spacer(minLength: 8)
                Text(verbatim: setsText)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
            }
            bar
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(muscle.title + ", " + setsText)
    }

    private var setsText: String {
        String(sets) + (sets == 1 ? " set" : " sets")
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PulseTheme.progressTrack)
                Capsule()
                    .fill(PulseTheme.progress)
                    .frame(width: fillWidth(in: proxy.size.width))
            }
        }
        .frame(height: 6)
    }

    private func fillWidth(in total: CGFloat) -> CGFloat {
        let share = CGFloat(min(1, max(0, fraction)))
        return max(6, total * share)
    }
}
#endif
