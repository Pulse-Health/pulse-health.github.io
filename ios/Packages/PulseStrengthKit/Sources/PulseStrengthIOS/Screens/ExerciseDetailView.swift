#if os(iOS)
import SwiftUI
import Charts
import PulseStrengthCore

// MARK: - Screen

/// "History & records" of one exercise (Exercise.dc.html).
///
/// Scrolling page: title with the muscles and equipment, the looping form demo, three figure tiles (estimated 1RM
/// with its trend, best set, 30 day volume), the estimated-1RM chart with a range menu, the records table, the recent
/// sessions, the "How To" cues and the photo attribution. Everything numeric comes from
/// `StrengthStore.history(for:now:)`; the view only renders it.
///
/// The design's "Ask AI" pill and "More" menu have no behaviour in this package. The pill is therefore an integration
/// seam: it appears in the navigation bar only when the host app installs a handler with `onAskAI(_:)`.
@MainActor
public struct ExerciseDetailView: View {
    private let exercise: Exercise
    @ObservedObject private var store: StrengthStore
    private var askAIAction: ((Exercise) -> Void)?

    @State private var range: ExerciseDetailRange = .twelveWeeks
    @State private var showsAllSessions = false
    @State private var expandedSessions: Set<UUID> = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(exercise: Exercise, store: StrengthStore) {
        self.exercise = exercise
        self._store = ObservedObject(wrappedValue: store)
        self.askAIAction = nil
    }

    /// Shows the "Ask AI" pill in the navigation bar and calls `action` with this exercise when it is tapped.
    public func onAskAI(_ action: @escaping (Exercise) -> Void) -> ExerciseDetailView {
        var copy = self
        copy.askAIAction = action
        return copy
    }

    // MARK: Body

    public var body: some View {
        let now = Date()
        let history = store.history(for: exercise.id, now: now)
        let progress = ExerciseDetailProgress(series: history.e1RMSeries, range: range, now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleBlock
                mediaTile
                statTiles(history: history, progress: progress, now: now)
                if exercise.tracksWeight {
                    ExerciseDetailChartCard(
                        progress: progress,
                        hasSeries: !history.e1RMSeries.isEmpty,
                        range: $range
                    )
                }
                if !history.records.isEmpty {
                    recordsSection(history.records, now: now)
                }
                if !history.sessions.isEmpty {
                    sessionsSection(history.sessions, now: now)
                }
                if !exercise.cues.isEmpty {
                    cuesSection
                }
                if hasMedia {
                    attribution
                }
            }
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 2)
            .padding(.bottom, 40)
            .pulseReadableColumn()
        }
        .scrollIndicators(.hidden)
        .background(PulseTheme.ground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if askAIAction != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    askAIButton
                }
            }
        }
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: exercise.name)
                .tracking(0.3)
                .pulseFont(30, .bold, relativeTo: .largeTitle)
                .foregroundStyle(PulseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: subtitle)
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Chest · Shoulders · Triceps · Barbell"
    private var subtitle: String {
        var parts: [String] = [exercise.muscle.title]
        if !exercise.secondary.isEmpty && exercise.secondary != "Custom" {
            parts.append(exercise.secondary)
        }
        parts.append(exercise.equipment.title)
        return parts.joined(separator: " · ")
    }

    // MARK: Ask AI

    private var askAIButton: some View {
        Button {
            askAIAction?(exercise)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                Text("Ask AI")
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
            }
            .foregroundStyle(PulseTheme.greenText)
            .padding(.leading, 10)
            .padding(.trailing, 13)
            .pulseScaledFrame(minHeight: 34, relativeTo: .subheadline)
            .background(ExerciseDetailColors.greenWash, in: Capsule())
            // A navigation bar item cannot grow without limit: the pill follows the text size up to xxxLarge.
            .dynamicTypeSize(PulseDynamicType.activeWorkoutRange)
        }
        .accessibilityLabel("Ask AI about this exercise")
    }

    // MARK: Media

    private var hasMedia: Bool {
        guard let key = exercise.mediaKey else { return false }
        return !key.isEmpty
    }

    /// 358 x 239 in the design: full width, 3 : 2, radius 20.
    private var mediaTile: some View {
        Color.clear
            .aspectRatio(358.0 / 239.0, contentMode: .fit)
            .overlay { ExerciseMediaView(mediaKey: exercise.mediaKey, cornerRadius: 20) }
            .overlay(alignment: .bottomLeading) { formDemoBadge }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.07), radius: 5, x: 0, y: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mediaAccessibilityLabel)
    }

    @ViewBuilder
    private var formDemoBadge: some View {
        if hasMedia {
            Text("Form demo")
                .pulseFont(12, .semibold, relativeTo: .footnote)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(12)
        }
    }

    private var mediaAccessibilityLabel: String {
        if hasMedia {
            return "Form demo for " + exercise.name + ", alternating between the start and the end position"
        }
        return "No form demo for this exercise yet"
    }

    // MARK: Figure tiles

    /// Side by side at the default text size (and below), as designed. With bigger text they stay in one row only while
    /// they fit, otherwise they stack.
    @ViewBuilder
    private func statTiles(history: ExerciseHistory, progress: ExerciseDetailProgress, now: Date) -> some View {
        if dynamicTypeSize <= .large {
            HStack(spacing: 10) {
                statTileViews(history: history, progress: progress, now: now)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    statTileViews(history: history, progress: progress, now: now)
                }
                VStack(spacing: 10) {
                    statTileViews(history: history, progress: progress, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private func statTileViews(history: ExerciseHistory, progress: ExerciseDetailProgress, now: Date) -> some View {
        if exercise.tracksWeight {
            e1RMTile(history: history, progress: progress)
            bestSetTile(history: history, now: now)
            volumeTile(history: history)
        } else {
            bestSetTile(history: history, now: now)
            sessionsTile(history: history)
        }
    }

    /// Value and trend come from the same window as the chart: the best estimate of the visible sessions and its gain
    /// over the first one. Without a session in the window the all-time best is shown, without a trend.
    private func e1RMTile(history: ExerciseHistory, progress: ExerciseDetailProgress) -> some View {
        ExerciseDetailStatTile(
            title: "Est. 1RM",
            value: ExerciseDetailFormat.e1RM(progress.best ?? history.bestE1RM),
            detail: progress.trendText,
            detailColor: progress.direction == .up ? PulseTheme.green : PulseTheme.inkSecondary,
            detailWeight: .semibold,
            arrow: ExerciseDetailStatTile.Arrow(progress.direction)
        )
    }

    private func bestSetTile(history: ExerciseHistory, now: Date) -> some View {
        var detail = "–"
        if history.bestSetText != nil, let date = history.bestSetDate {
            detail = "PR · " + StrengthResultText.monthDay(date, now: now)
        }
        return ExerciseDetailStatTile(
            title: "Best set",
            value: ExerciseDetailFormat.bestSet(history.bestSetText),
            detail: detail,
            detailColor: PulseTheme.prText,
            detailWeight: .semibold,
            arrow: .none
        )
    }

    private func volumeTile(history: ExerciseHistory) -> some View {
        ExerciseDetailStatTile(
            title: "Volume · 30d",
            value: ExerciseDetailFormat.volume(history.volumeLast30Days),
            detail: ExerciseDetailFormat.sessionCount(history.sessionsLast30Days),
            detailColor: PulseTheme.inkSecondary,
            detailWeight: .regular,
            arrow: .none
        )
    }

    private func sessionsTile(history: ExerciseHistory) -> some View {
        ExerciseDetailStatTile(
            title: "Sessions · 30d",
            value: String(history.sessionsLast30Days),
            detail: "Last 30 days",
            detailColor: PulseTheme.inkSecondary,
            detailWeight: .regular,
            arrow: .none
        )
    }

    // MARK: Records

    private func recordsSection(_ rows: [ExerciseRecordRow], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ExerciseDetailSectionTitle(text: "Personal Records")
            ExerciseDetailRecordsCard(rows: rows, now: now)
        }
    }

    // MARK: Sessions

    private func sessionsSection(_ sessions: [ExerciseSession], now: Date) -> some View {
        let visible: [ExerciseSession] = showsAllSessions ? sessions : Array(sessions.prefix(3))
        return VStack(alignment: .leading, spacing: 12) {
            sessionsHeading(hasSeeAll: sessions.count > 3)
            VStack(spacing: 8) {
                ForEach(visible) { session in
                    ExerciseDetailSessionRow(
                        session: session,
                        tracking: exercise.tracking,
                        now: now,
                        isExpanded: expandedSessions.contains(session.id),
                        onToggle: { toggleSession(session.id) }
                    )
                }
            }
        }
    }

    /// "Recent Sessions" with "See All" on the right; with the accessibility sizes the button moves under the title.
    @ViewBuilder
    private func sessionsHeading(hasSeeAll: Bool) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                ExerciseDetailSectionTitle(text: "Recent Sessions")
                if hasSeeAll {
                    seeAllButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 8) {
                ExerciseDetailSectionTitle(text: "Recent Sessions")
                Spacer(minLength: 0)
                if hasSeeAll {
                    seeAllButton
                }
            }
        }
    }

    /// "See All" in the design: 12 pt blue text with a 44 pt touch target that does not add height to the heading row.
    private var seeAllButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : Animation.easeInOut(duration: 0.2)) {
                showsAllSessions.toggle()
            }
        } label: {
            Text(showsAllSessions ? "Show Less" : "See All")
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.blue)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .padding(.vertical, -11)
    }

    private func toggleSession(_ id: UUID) {
        withAnimation(reduceMotion ? nil : Animation.easeInOut(duration: 0.2)) {
            if expandedSessions.contains(id) {
                expandedSessions.remove(id)
            } else {
                expandedSessions.insert(id)
            }
        }
    }

    // MARK: How to

    private var cuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExerciseDetailSectionTitle(text: "How To")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(exercise.cues.enumerated()), id: \.offset) { pair in
                    ExerciseDetailCueRow(number: pair.offset + 1, text: pair.element)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
        }
    }

    // MARK: Attribution

    private var attribution: some View {
        Text("Demo photos from the Free Exercise DB.")
            .pulseFont(11, relativeTo: .caption2)
            .foregroundStyle(PulseTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Colours

private enum ExerciseDetailColors {
    /// The 12 % green wash behind the Ask AI pill and the cue numbers.
    static let greenWash = Color(light: 0x1B8448, dark: 0x30D158, lightAlpha: 0.12, darkAlpha: 0.18)
    /// Horizontal grid lines of the chart (rgba(142,142,147,0.25) in the design).
    static let gridLine = Color(light: 0x8E8E93, dark: 0x8E8E93, lightAlpha: 0.25, darkAlpha: 0.25)
    /// Line, dots and fill of the chart: the system green #34C759 of the design (not the darker brand green).
    static let chartGreen = PulseTheme.recoveryGood
}

// MARK: - Text formats

private enum ExerciseDetailFormat {
    /// "99 kg", or an en dash without a value.
    static func e1RM(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "–" }
        return NumberText.kg(value.rounded()) + " kg"
    }

    /// The store's "85 kg × 5" shows as "85 × 5" in the tile; "12 reps" and "45 s" stay as they are.
    static func bestSet(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "–" }
        return text.replacingOccurrences(of: " kg", with: "")
    }

    /// "12.5 t" from one tonne on, "840 kg" below.
    static func volume(_ kg: Double) -> String {
        guard kg.isFinite, kg > 0 else { return "0 kg" }
        if kg < 1000 {
            return NumberText.thousands(kg) + " kg"
        }
        let tonnes = (kg / 100).rounded() / 10
        return NumberText.kg(tonnes) + " t"
    }

    static func sessionCount(_ count: Int) -> String {
        count == 1 ? "1 session" : String(count) + " sessions"
    }
}

// MARK: - Range

/// The time windows of the estimated-1RM chart (the "12w" menu of the design).
private enum ExerciseDetailRange: String, CaseIterable, Identifiable {
    case fourWeeks
    case twelveWeeks
    case sixMonths
    case oneYear
    case all

    var id: String { rawValue }

    /// The label on the small menu button.
    var chipTitle: String {
        switch self {
        case .fourWeeks: return "4w"
        case .twelveWeeks: return "12w"
        case .sixMonths: return "6m"
        case .oneYear: return "1y"
        case .all: return "All"
        }
    }

    var menuTitle: String {
        switch self {
        case .fourWeeks: return "4 weeks"
        case .twelveWeeks: return "12 weeks"
        case .sixMonths: return "6 months"
        case .oneYear: return "1 year"
        case .all: return "All time"
        }
    }

    /// Length of the window in days; nil = the whole history.
    var days: Int? {
        switch self {
        case .fourWeeks: return 28
        case .twelveWeeks: return 84
        case .sixMonths: return 182
        case .oneYear: return 365
        case .all: return nil
        }
    }
}

// MARK: - Chart data

private struct ExerciseDetailChartPoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
    let isLast: Bool
}

/// The vertical scale: rounded bounds with two grid intervals at most (93...99 kg gives 90, 95, 100).
private struct ExerciseDetailAxis {
    let lower: Double
    let upper: Double
    let ticks: [Double]

    static func make(values: [Double]) -> ExerciseDetailAxis {
        guard let minimum = values.min(), let maximum = values.max() else {
            return ExerciseDetailAxis(lower: 0, upper: 100, ticks: [0, 50, 100])
        }
        var low = minimum
        var high = maximum
        if high - low < 1 {
            low -= 2.5
            high += 2.5
        }
        let steps: [Double] = [1, 2, 2.5, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]
        var chosen: Double = steps[steps.count - 1]
        for step in steps {
            let lowerTick = (low / step).rounded(.down) * step
            let upperTick = (high / step).rounded(.up) * step
            if (upperTick - lowerTick) / step <= 2.0001 {
                chosen = step
                break
            }
        }
        let lower = (low / chosen).rounded(.down) * chosen
        var upper = (high / chosen).rounded(.up) * chosen
        if upper - lower < chosen {
            upper = lower + chosen
        }
        var ticks: [Double] = [lower]
        if (upper - lower) / chosen > 1.5 {
            ticks.append((lower + upper) / 2)
        }
        ticks.append(upper)
        return ExerciseDetailAxis(lower: lower, upper: upper, ticks: ticks)
    }
}

/// The time between two sessions: "5 d" / "3 wk" for the trend text, "5 days" / "3 weeks" for VoiceOver. Whole days
/// below a week, rounded weeks from then on, never less than one.
private struct ExerciseDetailSpan {
    let short: String
    let spoken: String

    init(from start: Date, to end: Date) {
        let days = max(1, Int((end.timeIntervalSince(start) / 86_400).rounded()))
        if days < 7 {
            self.short = String(days) + " d"
            self.spoken = days == 1 ? "1 day" : String(days) + " days"
        } else {
            let weeks = max(1, Int((Double(days) / 7).rounded()))
            self.short = String(weeks) + " wk"
            self.spoken = weeks == 1 ? "1 week" : String(weeks) + " weeks"
        }
    }
}

/// Everything the chart card shows for one window: the points, the dates, the scale, the best value and the trend.
///
/// One figure runs through the tile, the chart heading and the VoiceOver text: `best`, the highest estimate of the
/// sessions in the window, and its gain over the first session in whole kilograms (the design: "99 kg", "6 kg · 12 wk",
/// "rising from 93 to 99 kilograms"). The span named in the texts is the time between the two sessions compared, not the
/// length of the selected window.
private struct ExerciseDetailProgress {
    enum Direction {
        case up
        case down
        case flat
        case unknown
    }

    let points: [ExerciseDetailChartPoint]
    /// Horizontal domain of the chart.
    let start: Date
    let end: Date
    /// Dates printed under the chart and in the heading ("Jul 21 – Oct 13").
    let startLabel: String
    let middleLabel: String
    let endLabel: String
    let axis: ExerciseDetailAxis
    /// The highest estimate of the sessions in the window; nil without a session.
    let best: Double?
    let direction: Direction
    /// "6 kg · 12 wk", "No change" or an en dash.
    let trendText: String
    /// VoiceOver text of the chart.
    let summary: String

    init(series: [E1RMPoint], range: ExerciseDetailRange, now: Date) {
        let calendar = StrengthResultText.calendar
        let ordered = series.filter { $0.value.isFinite }.sorted { $0.date < $1.date }

        var windowStart: Date = ordered.first?.date ?? now
        if let days = range.days {
            windowStart = calendar.date(byAdding: .day, value: -days, to: now) ?? now.addingTimeInterval(-Double(days) * 86_400)
        }
        let visible = ordered.filter { $0.date >= windowStart }

        var displayEnd = now
        if let lastDate = visible.last?.date, lastDate > displayEnd {
            displayEnd = lastDate
        }
        var domainEnd = displayEnd
        if domainEnd.timeIntervalSince(windowStart) < 86_400 {
            domainEnd = windowStart.addingTimeInterval(86_400)
        }
        let middle = Date(timeInterval: displayEnd.timeIntervalSince(windowStart) / 2, since: windowStart)

        var chartPoints: [ExerciseDetailChartPoint] = []
        for (index, point) in visible.enumerated() {
            chartPoints.append(
                ExerciseDetailChartPoint(id: index, date: point.date, value: point.value, isLast: index == visible.count - 1)
            )
        }

        // The best session of the window (the earliest one on a tie) against the first one.
        var bestPoint: E1RMPoint?
        for point in visible {
            if let current = bestPoint, point.value <= current.value { continue }
            bestPoint = point
        }

        var direction: Direction = .unknown
        var trendText = "–"
        var summary = "No estimated one-rep max in this range"
        if let first = visible.first, let peak = bestPoint {
            let fromKg = first.value.rounded()
            let toKg = peak.value.rounded()
            let fromText = NumberText.kg(fromKg)
            let toText = NumberText.kg(toKg)
            // The line ends below the best when the latest session was weaker: VoiceOver is told, the heading is not.
            var latestNote = ""
            if let last = visible.last, last.value.rounded() < toKg {
                latestNote = ", latest " + NumberText.kg(last.value.rounded()) + " kilograms"
            }
            if visible.count < 2 {
                summary = "Estimated one-rep max \(toText) kilograms"
            } else if toKg > fromKg {
                let span = ExerciseDetailSpan(from: first.date, to: peak.date)
                direction = .up
                trendText = NumberText.kg(toKg - fromKg) + " kg · " + span.short
                summary = "Estimated one-rep max rising from \(fromText) to \(toText) kilograms over \(span.spoken)" + latestNote
            } else {
                let span = ExerciseDetailSpan(from: first.date, to: visible.last?.date ?? first.date)
                direction = .flat
                trendText = "No change"
                summary = "Estimated one-rep max steady at \(toText) kilograms over \(span.spoken)" + latestNote
            }
        }

        self.points = chartPoints
        self.start = windowStart
        self.end = domainEnd
        self.startLabel = StrengthResultText.monthDay(windowStart, now: now)
        self.middleLabel = StrengthResultText.monthDay(middle, now: now)
        self.endLabel = StrengthResultText.monthDay(displayEnd, now: now)
        self.axis = ExerciseDetailAxis.make(values: visible.map { $0.value })
        self.best = bestPoint?.value
        self.direction = direction
        self.trendText = trendText
        self.summary = summary
    }

    /// "Jul 21 – Oct 13"
    var rangeLabel: String {
        startLabel + " – " + endLabel
    }
}

// MARK: - Figure tile

private struct ExerciseDetailStatTile: View {
    enum Arrow {
        case none
        case up
        case down

        init(_ direction: ExerciseDetailProgress.Direction) {
            switch direction {
            case .up: self = .up
            case .down: self = .down
            case .flat, .unknown: self = .none
            }
        }

        var symbolName: String? {
            switch self {
            case .none: return nil
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            }
        }
    }

    let title: String
    let value: String
    let detail: String
    let detailColor: Color
    let detailWeight: Font.Weight
    let arrow: Arrow

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Title and detail stay on one line as designed; with the accessibility sizes they wrap instead of shrinking.
    private var textLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? nil : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title)
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .lineLimit(textLineLimit)
            Text(verbatim: value)
                .pulseNumber(22, relativeTo: .title2)
                .foregroundStyle(PulseTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            detailLine
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var detailLine: some View {
        HStack(spacing: 3) {
            if let name = arrow.symbolName {
                Image(systemName: name)
                    .pulseFont(11, .heavy, relativeTo: .caption2)
            }
            Text(verbatim: detail)
                .pulseFont(12, detailWeight, relativeTo: .footnote)
                .lineLimit(textLineLimit)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(detailColor)
    }
}

// MARK: - Section title

private struct ExerciseDetailSectionTitle: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .pulseFont(17, .semibold, relativeTo: .headline)
            .foregroundStyle(PulseTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Chart card

private struct ExerciseDetailChartCard: View {
    let progress: ExerciseDetailProgress
    let hasSeries: Bool
    @Binding var range: ExerciseDetailRange

    /// The plot height (112 pt by default) grows slowly with the text, which makes room for bigger axis labels.
    @PulseScaled(112, relativeTo: .largeTitle) private var chartHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chartArea
            Text("Estimated with weight × (1 + reps ÷ 30). Warm-up sets are left out.")
                .pulseFont(11, relativeTo: .caption2)
                .foregroundStyle(PulseTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard()
    }

    // MARK: Heading

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated 1RM")
                    .pulseFont(15, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.inkSecondary)
                Text(verbatim: bestText)
                    .pulseNumber(28, relativeTo: .largeTitle)
                    .foregroundStyle(PulseTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !progress.points.isEmpty {
                    Text(verbatim: progress.rangeLabel)
                        .pulseFont(12, relativeTo: .footnote)
                        .foregroundStyle(PulseTheme.inkSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            ExerciseDetailRangeMenu(selection: $range)
        }
    }

    /// The same figure as the "Est. 1RM" tile.
    private var bestText: String {
        guard let best = progress.best else { return "–" }
        return NumberText.kg(best.rounded()) + " kg"
    }

    // MARK: Chart

    @ViewBuilder
    private var chartArea: some View {
        if progress.points.isEmpty {
            Text(emptyMessage)
                .pulseFont(13, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: chartHeight)
        } else {
            VStack(spacing: 4) {
                ExerciseDetailChart(points: progress.points, axis: progress.axis, start: progress.start, end: progress.end)
                    .frame(height: chartHeight)
                    .accessibilityLabel(progress.summary)
                ExerciseDetailDateRow(
                    start: progress.startLabel,
                    middle: progress.middleLabel,
                    end: progress.endLabel
                )
            }
        }
    }

    private var emptyMessage: String {
        hasSeries ? "No sessions in this range" : "No sessions logged yet"
    }
}

/// The "12w" button with its range menu.
private struct ExerciseDetailRangeMenu: View {
    @Binding var selection: ExerciseDetailRange

    var body: some View {
        Menu {
            Picker("Chart range", selection: $selection) {
                ForEach(ExerciseDetailRange.allCases) { option in
                    Text(option.menuTitle).tag(option)
                }
            }
        } label: {
            chip
        }
        .accessibilityLabel("Chart range")
        .accessibilityValue(selection.menuTitle)
    }

    private var chip: some View {
        HStack(spacing: 4) {
            Text(selection.chipTitle)
                .pulseFont(12, .semibold, relativeTo: .footnote)
            Image(systemName: "chevron.down")
                .pulseFont(9, .heavy, relativeTo: .caption2)
        }
        .foregroundStyle(PulseTheme.inkSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PulseTheme.progressTrack, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
        .contentShape(Rectangle())
    }
}

/// Estimated 1RM per session: a green line with round caps and joins, a point per session (the latest one larger)
/// and a soft fill under the line; grid lines and labels sit on the trailing side like in the design.
private struct ExerciseDetailChart: View {
    let points: [ExerciseDetailChartPoint]
    let axis: ExerciseDetailAxis
    let start: Date
    let end: Date

    /// Size of the axis labels (a `Font` value is needed inside the chart's axis content).
    @PulseScaled(9, relativeTo: .caption2) private var axisLabelSize: CGFloat

    var body: some View {
        let labelSize = axisLabelSize
        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Baseline", axis.lower),
                    yEnd: .value("Estimated 1RM", point.value)
                )
                .foregroundStyle(fillGradient)
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Estimated 1RM", point.value)
                )
                .foregroundStyle(ExerciseDetailColors.chartGreen)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Estimated 1RM", point.value)
                )
                .foregroundStyle(ExerciseDetailColors.chartGreen)
                .symbolSize(symbolSize(for: point))
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: axis.lower...axis.upper)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: axis.ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(ExerciseDetailColors.gridLine)
                AxisValueLabel {
                    Text(verbatim: NumberText.kg(value.as(Double.self) ?? 0))
                        .font(.system(size: labelSize))
                        .foregroundStyle(PulseTheme.inkSecondary)
                }
            }
        }
    }

    private var fillGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                Gradient.Stop(color: ExerciseDetailColors.chartGreen.opacity(0.30), location: 0),
                Gradient.Stop(color: ExerciseDetailColors.chartGreen.opacity(0.08), location: 0.6),
                Gradient.Stop(color: ExerciseDetailColors.chartGreen.opacity(0), location: 1)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 6.4 pt dots, 9.4 pt for the latest session (r 3.2 and 4.7 in the design).
    private func symbolSize(for point: ExerciseDetailChartPoint) -> CGSize {
        let side: CGFloat = point.isLast ? 9.4 : 6.4
        return CGSize(width: side, height: side)
    }
}

/// The three dates under the chart: start, middle, end.
private struct ExerciseDetailDateRow: View {
    let start: String
    let middle: String
    let end: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The width the chart's value labels take on the trailing side; they grow with the text like the dates below.
    @PulseScaled(20, relativeTo: .caption2) private var valueLabelInset: CGFloat

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Text(verbatim: start)
                Spacer(minLength: 0)
            }
            if middle != start && middle != end && !dynamicTypeSize.isAccessibilitySize {
                Text(verbatim: middle)
            }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(verbatim: end)
            }
        }
        .pulseFont(11, relativeTo: .caption2)
        .foregroundStyle(PulseTheme.inkSecondary)
        // The value labels of the chart take the trailing edge.
        .padding(.trailing, valueLabelInset)
        .accessibilityHidden(true)
    }
}

// MARK: - Records

private struct ExerciseDetailRecordsCard: View {
    let rows: [ExerciseRecordRow]
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { pair in
                ExerciseDetailRecordRow(row: pair.element, now: now)
                    .overlay(alignment: .top) {
                        if pair.offset > 0 {
                            StrengthHairline()
                        }
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
    }
}

private struct ExerciseDetailRecordRow: View {
    let row: ExerciseRecordRow
    let now: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @PulseScaled(54, relativeTo: .footnote) private var dateColumnWidth: CGFloat

    var body: some View {
        rowContent
            .padding(.vertical, 6)
            .frame(minHeight: 48)
            .accessibilityElement(children: .combine)
    }

    /// Label, value and date in one row; with the accessibility sizes the label gets its own line.
    @ViewBuilder
    private var rowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                labelText
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    valueText
                    Spacer(minLength: 0)
                    dateLabel
                }
            }
        } else {
            HStack(spacing: 10) {
                labelText
                    .frame(maxWidth: .infinity, alignment: .leading)
                valueText
                dateLabel
            }
        }
    }

    private var labelText: some View {
        Text(verbatim: row.label)
            .pulseFont(15, relativeTo: .subheadline)
            .foregroundStyle(PulseTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(verbatim: row.value)
            .pulseNumber(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(PulseTheme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var dateLabel: some View {
        Text(verbatim: dateText)
            .pulseFont(12, relativeTo: .footnote)
            .foregroundStyle(PulseTheme.inkSecondary)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: dateColumnWidth, alignment: .trailing)
    }

    private var dateText: String {
        guard let date = row.date else { return "" }
        return StrengthResultText.monthDay(date, now: now)
    }
}

// MARK: - Sessions

/// One session: "Oct 8 · Upper A · Push", an optional PR tag and the sets on one line.
/// The row opens in place to list every set with its type and reps in reserve.
private struct ExerciseDetailSessionRow: View {
    let session: ExerciseSession
    let tracking: TrackingKind
    let now: Date
    let isExpanded: Bool
    let onToggle: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                header
            }
            .buttonStyle(PulsePlainButtonStyle())
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows every set of this session")
            if isExpanded {
                ExerciseDetailSetLines(lines: StrengthResultText.setLines(session.sets, tracking: tracking))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
    }

    private var title: String {
        StrengthResultText.monthDay(session.date, now: now) + " · " + session.workoutName
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                titleLine
                Text(verbatim: StrengthResultText.setsLine(session.sets, tracking: tracking))
                    .pulseNumber(13, .regular, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .pulseFont(14, .bold, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkTertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(12)
        .contentShape(Rectangle())
    }

    /// The title with the PR tag beside it; with the accessibility sizes the tag moves under the title.
    @ViewBuilder
    private var titleLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                titleText
                if session.isPersonalRecord {
                    StrengthPRChip(horizontal: 7, vertical: 2)
                }
            }
        } else {
            HStack(spacing: 8) {
                titleText
                if session.isPersonalRecord {
                    StrengthPRChip(horizontal: 7, vertical: 2)
                }
            }
        }
    }

    private var titleText: some View {
        Text(verbatim: title)
            .pulseFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(PulseTheme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ExerciseDetailSetLines: View {
    let lines: [StrengthSetLine]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(lines) { line in
                ExerciseDetailSetLineRow(line: line)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

private struct ExerciseDetailSetLineRow: View {
    let line: StrengthSetLine

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The type badge (24 pt) grows with the number inside it.
    @PulseScaled(24, relativeTo: .footnote) private var badgeSide: CGFloat

    var body: some View {
        rowContent
            .accessibilityElement(children: .combine)
    }

    /// Badge, set and reps in reserve in one row; with the accessibility sizes the reps in reserve move to their own line.
    @ViewBuilder
    private var rowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    badgeView
                    detailView
                }
                rirLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                badgeView
                detailView
                Spacer(minLength: 8)
                rirLabel
            }
        }
    }

    private var badgeView: some View {
        Text(verbatim: line.badge)
            .pulseNumber(12, .bold, relativeTo: .footnote)
            .foregroundStyle(line.type.badgeForeground)
            .frame(width: badgeSide, height: badgeSide)
            .background(line.type.badgeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var detailView: some View {
        Text(verbatim: line.detailText)
            .pulseNumber(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(PulseTheme.ink)
    }

    @ViewBuilder
    private var rirLabel: some View {
        if let rir = line.rirText {
            Text(verbatim: rir)
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
        }
    }
}

// MARK: - How to

private struct ExerciseDetailCueRow: View {
    let number: Int
    let text: String

    /// The number badge (24 pt) grows with the number inside it.
    @PulseScaled(24, relativeTo: .footnote) private var badgeSide: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(number))
                .pulseNumber(13, .bold, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.greenText)
                .frame(width: badgeSide, height: badgeSide)
                .background(ExerciseDetailColors.greenWash, in: Circle())
            Text(verbatim: text)
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step " + String(number) + ". " + text)
    }
}

// MARK: - Shared with the workout summary

/// Hand-made date and set text, shared by the exercise detail and the workout summary. No `DateFormatter`, so the text is
/// the same in every locale ("Oct 3", "Fri, Oct 13", "80×6").
enum StrengthResultText {
    static let monthNames: [String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let weekdayNames: [String] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Gregorian calendar in the current time zone (month and weekday names above assume it).
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    /// "Oct 3"; "Oct 3, 2025" when the year differs from the year of `now`.
    static func monthDay(_ date: Date, now: Date) -> String {
        let calendar = StrengthResultText.calendar
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let monthIndex = min(max((parts.month ?? 1) - 1, 0), 11)
        var text = monthNames[monthIndex] + " " + String(parts.day ?? 1)
        if let year = parts.year, year != calendar.component(.year, from: now) {
            text += ", " + String(year)
        }
        return text
    }

    /// "Fri, Oct 13"
    static func weekdayMonthDay(_ date: Date, now: Date) -> String {
        let calendar = StrengthResultText.calendar
        let weekday = min(max(calendar.component(.weekday, from: date) - 1, 0), 6)
        return weekdayNames[weekday] + ", " + monthDay(date, now: now)
    }

    /// "52m", "1h 5m" or "45s".
    static func durationTile(seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 60 {
            return String(total) + "s"
        }
        let minutes = total / 60
        if minutes < 60 {
            return String(minutes) + "m"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 {
            return String(hours) + "h"
        }
        return String(hours) + "h " + String(rest) + "m"
    }

    /// "52 min", "65 min" or "< 1 min".
    static func durationSubtitle(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 1 {
            return "< 1 min"
        }
        return String(minutes) + " min"
    }

    /// "52 minutes", "1 hour 5 minutes" or "45 seconds" for VoiceOver.
    static func durationSpoken(seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 60 {
            return String(total) + (total == 1 ? " second" : " seconds")
        }
        let minutes = total / 60
        let hours = minutes / 60
        let rest = minutes % 60
        var parts: [String] = []
        if hours > 0 {
            parts.append(String(hours) + (hours == 1 ? " hour" : " hours"))
        }
        if rest > 0 || hours == 0 {
            parts.append(String(rest) + (rest == 1 ? " minute" : " minutes"))
        }
        return parts.joined(separator: " ")
    }

    /// One decimal with a "." separator: 2.14 gives "2.1", 2 gives "2.0".
    static func oneDecimal(_ value: Double) -> String {
        guard value.isFinite else { return "0.0" }
        let clamped = max(0, min(value, 1_000_000))
        let tenths = Int((clamped * 10).rounded())
        return String(tenths / 10) + "." + String(tenths % 10)
    }

    // MARK: Sets

    /// "W 50×8", "80×6", "8 reps" or "45 s": one set on the one-line summaries.
    static func compactText(_ set: CompletedSet, tracking: TrackingKind) -> String {
        var text: String
        switch tracking {
        case .weightReps:
            text = NumberText.kg(set.weightKg) + "×" + String(set.reps)
        case .repsOnly:
            if set.weightKg > 0 {
                text = "+" + NumberText.kg(set.weightKg) + "×" + String(set.reps)
            } else {
                text = String(set.reps) + " reps"
            }
        case .duration:
            text = String(set.reps) + " s"
        }
        if set.type != .normal {
            text = set.type.badge + " " + text
        }
        return text
    }

    /// "W 50×8 · W 70×5 · 80×6 · 80×6 · 80×5"
    static func setsLine(_ sets: [CompletedSet], tracking: TrackingKind) -> String {
        sets.map { compactText($0, tracking: tracking) }.joined(separator: " · ")
    }

    /// "RIR 2", "RIR 4+" or nil.
    static func rirText(_ rir: Int?) -> String? {
        guard let rir else { return nil }
        if rir >= 4 {
            return "RIR 4+"
        }
        return "RIR " + String(max(0, rir))
    }

    /// "80 kg × 6", "8 reps", "+10 kg × 8" or "45 s".
    static func detailText(_ set: CompletedSet, tracking: TrackingKind) -> String {
        switch tracking {
        case .weightReps:
            return NumberText.kg(set.weightKg) + " kg × " + String(set.reps)
        case .repsOnly:
            if set.weightKg > 0 {
                return "+" + NumberText.kg(set.weightKg) + " kg × " + String(set.reps)
            }
            return String(set.reps) + (set.reps == 1 ? " rep" : " reps")
        case .duration:
            return String(set.reps) + " s"
        }
    }

    /// One line per set with the badge ("W", "D", "F" or the running number of the normal sets).
    static func setLines(_ sets: [CompletedSet], tracking: TrackingKind) -> [StrengthSetLine] {
        var lines: [StrengthSetLine] = []
        var normalCount = 0
        for (index, set) in sets.enumerated() {
            var badge = set.type.badge
            if set.type == .normal {
                normalCount += 1
                badge = String(normalCount)
            }
            lines.append(
                StrengthSetLine(
                    id: index,
                    type: set.type,
                    badge: badge,
                    detailText: detailText(set, tracking: tracking),
                    rirText: rirText(set.rir)
                )
            )
        }
        return lines
    }
}

/// One expanded set of a session.
struct StrengthSetLine: Identifiable {
    let id: Int
    let type: SetType
    let badge: String
    let detailText: String
    let rirText: String?
}

/// The yellow "PR" tag of the session rows and the exercise results.
struct StrengthPRChip: View {
    var horizontal: CGFloat
    var vertical: CGFloat

    var body: some View {
        Text("PR")
            .pulseFont(11, .bold, relativeTo: .caption2)
            .foregroundStyle(PulseTheme.prText)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(PulseTheme.prFill, in: Capsule())
            .accessibilityLabel("Personal record")
    }
}

/// A 0.5 pt separator line (rgba(60,60,67,0.18) in the design).
struct StrengthHairline: View {
    var body: some View {
        Rectangle()
            .fill(PulseTheme.separator)
            .frame(height: 0.5)
    }
}
#endif
