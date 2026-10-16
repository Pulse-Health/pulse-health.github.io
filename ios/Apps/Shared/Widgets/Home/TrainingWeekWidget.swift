// TrainingWeekWidget.swift
//
// HS-10 Training week (systemLarge): the week strip with the initials of each day's workout, the last session (duration, sets, volume),
// the latest personal record and a Start button for the next workout. The Start button is a `Link`; the rest of the widget opens the hub.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct TrainingWeekWidget: Widget {
    static let kind = "health.pulse.strength.widget.trainingWeek"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            TrainingWeekView(entry: entry)
        }
        .configurationDisplayName("Training week")
        .description("Your week at a glance: the days you trained, the last session, your latest record and a Start button.")
        .supportedFamilies([.systemLarge])
    }
}

struct TrainingWeekView: View {
    let entry: SnapshotEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var week: WeekSummary { snapshot.week }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)
            HomeWeekStrip(days: HomeDates.weekDays(of: week), circleSize: 34)
            Spacer(minLength: 4)
            TrainingWeekSessionCard(session: snapshot.lastSession, now: entry.date, timeZoneID: snapshot.timeZoneID)
            Spacer(minLength: 4)
            if let record = snapshot.latestPR {
                TrainingWeekRecordRow(record: record)
                Spacer(minLength: 4)
            }
            startRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetCardBackground()
        .widgetURL(StrengthDeepLink.hub.url)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("This week")
                .font(WidgetTheme.text(17, .bold))
                .foregroundStyle(WidgetTheme.ink)
            Spacer(minLength: 8)
            Text(verbatim: "\(week.completed) of \(week.goal)")
                .font(WidgetTheme.number(15, .semibold))
                .foregroundStyle(WidgetTheme.greenText)
                .widgetAccentable()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(week.completed) of \(week.goal) workouts")
    }

    @ViewBuilder
    private var startRow: some View {
        if let nextUp = snapshot.nextUp {
            HomeStartLink(
                destination: StrengthDeepLink.startNext.url,
                title: "Start " + nextUp.name,
                spokenTitle: "Start " + nextUp.name,
                height: 44
            )
            .widgetAccentable()
        } else {
            Text("Create a workout in Pulse Strength")
                .font(WidgetTheme.text(14, .semibold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(WidgetTheme.rowFill))
        }
    }
}

/// "Last session": its name and when, then duration, sets and volume.
private struct TrainingWeekSessionCard: View {
    let session: SessionSummary?
    let now: Date
    let timeZoneID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeEyebrow(title: "Last session", color: WidgetTheme.inkSecondary)
            if let session {
                details(of: session)
            } else {
                emptyDetails
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeInsetCard()
    }

    /// "Today", "Yesterday", the weekday for the rest of the week, then "12 days ago".
    private func when(_ session: SessionSummary) -> String {
        let days = HomeDates.daysBetween(session.finishedAt, and: now, timeZoneID: timeZoneID)
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return HomeDates.weekday(of: session.finishedAt, timeZoneID: timeZoneID)
        default: return WidgetText.daysAgo(days)
        }
    }

    private func details(of session: SessionSummary) -> some View {
        let volume = HomeText.volume(kg: session.volumeKg)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.name)
                    .font(WidgetTheme.text(15, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(when(session))
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                HomeStatTile(value: "\(session.durationMinutes)", unit: "min", spokenUnit: "minutes", caption: "Duration")
                HomeStatTile(value: "\(session.loggedSets)", caption: "Sets")
                HomeStatTile(
                    value: volume.value,
                    unit: volume.unit,
                    spokenUnit: HomeText.spokenVolumeUnit(volume.unit),
                    caption: "Volume"
                )
            }
        }
    }

    private var emptyDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No sessions yet")
                .font(WidgetTheme.text(15, .semibold))
                .foregroundStyle(WidgetTheme.ink)
            Text("Finish a workout and it shows up here.")
                .font(WidgetTheme.text(13))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Bench Press PR ........ 85 × 5"
private struct TrainingWeekRecordRow: View {
    let record: PRSummary

    var body: some View {
        HStack(spacing: 10) {
            HomeTrophyTile()
            Text(record.exerciseName + " PR")
                .font(WidgetTheme.text(14))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(WidgetText.weightReps(record.weightKg, record.reps))
                .font(WidgetTheme.number(14))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Latest personal record: " + record.exerciseName + ", " + WidgetText.kg(record.weightKg) + " for " + HomeText.reps(record.reps)
        )
    }
}
#endif
