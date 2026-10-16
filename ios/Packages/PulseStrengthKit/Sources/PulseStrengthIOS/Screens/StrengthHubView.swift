#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import PulseStrengthCore

// MARK: - Navigation targets

private enum HubRoute: Hashable {
    case library
    case templates
    case template(UUID)
    case plans
    case history
    case workout(UUID)
    case recovery
    case settings
}

private enum HubEditorTarget: Identifiable {
    case new
    case template(UUID)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .template(let templateID):
            return "template-" + templateID.uuidString
        }
    }
}

// MARK: - Hub

/// The Strength hub (design: Main.dc.html, and TrainLive.dc.html while a workout runs): today's recommended
/// template with readiness, muscle chips, coach note and the Start / Resume button, "Start Empty Workout",
/// templates, muscle recovery, recent workouts, this week and the exercise library. With an active plan (imported from a
/// plan file) a "Plan" section lists the plan's workouts in rotation order and the card recommends the plan's next workout.
///
/// It lives inside the navigation stack of `PulseStrengthRootView`. Starting a workout is delegated to
/// `onStart` (nil = empty workout). The recommended template is the next workout of the active plan, or without a plan the
/// next one in the rotation of the templates (the one after the most recently performed). While a workout runs, the card and the template screen of THAT
/// workout's template read "Resume Workout" and call `onResume`; starting any other workout is refused with an
/// alert (the running one would be lost) that offers to resume.
@MainActor
public struct StrengthHubView: View {
    @ObservedObject private var store: StrengthStore
    @ObservedObject private var controller: WorkoutController
    @ObservedObject private var environment: StrengthAppEnvironment
    private let onStart: (WorkoutTemplate?) -> Void
    private let onResume: () -> Void

    @State private var route: HubRoute?
    @State private var editor: HubEditorTarget?
    @State private var showsBusyAlert = false
    @State private var showsImporter = false
    @State private var showsImportResult = false
    @State private var importMessage = ""
    @State private var showsWeightEntry = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        environment: StrengthAppEnvironment,
        onStart: @escaping (WorkoutTemplate?) -> Void,
        onResume: @escaping () -> Void
    ) {
        self._store = ObservedObject(wrappedValue: environment.store)
        self._controller = ObservedObject(wrappedValue: environment.controller)
        self._environment = ObservedObject(wrappedValue: environment)
        self.onStart = onStart
        self.onResume = onResume
    }

    // MARK: Body

    public var body: some View {
        let now = Date()
        return ScrollView {
            VStack(spacing: 20) {
                weighInCard(now: now)
                recommendedCard(now: now)
                startEmptyRow
                planSection
                templatesSection
                recoverySection
                recentSection
                weekSection(now: now)
                libraryRow
            }
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { (result: Result<URL, Error>) in
                importPlan(from: result)
            }
            .alert("Import Plan", isPresented: $showsImportResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importMessage)
            }
        }
        .background(PulseTheme.ground.ignoresSafeArea())
        .navigationTitle("Strength")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                moreMenu
            }
        }
        .navigationDestination(item: $route) { (target: HubRoute) in
            destination(for: target)
        }
        .sheet(item: $editor) { (target: HubEditorTarget) in
            HubTemplateEditorSheet(store: store, template: template(for: target))
        }
        .sheet(isPresented: $showsWeightEntry) {
            BodyWeightEntrySheet(store: store)
        }
        .alert("Workout in progress", isPresented: $showsBusyAlert) {
            Button("Resume") {
                onResume()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(busyMessage)
        }
    }

    // MARK: Toolbar

    private var moreMenu: some View {
        Menu {
            Button {
                requestStart(nil)
            } label: {
                Label("Start Empty Workout", systemImage: "plus.circle")
            }
            Button {
                editor = .new
            } label: {
                Label("New Template", systemImage: "plus")
            }
            Button {
                showsImporter = true
            } label: {
                Label("Import Plan\u{2026}", systemImage: "square.and.arrow.down")
            }
            if !store.plans.isEmpty {
                Button {
                    route = .plans
                } label: {
                    Label("Plans", systemImage: "list.bullet.rectangle")
                }
            }
            Button {
                route = .library
            } label: {
                Label("Exercise Library", systemImage: "magnifyingglass")
            }
            Button {
                route = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20, weight: .regular))
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("hub-more")
    }

    // MARK: Recommended card

    /// The template of today's card and of the "next up" tag: the next workout of the active plan or, without a plan,
    /// the one after the most recently performed template in the list (a rotation), the first one while none has been
    /// performed yet.
    private var recommendedTemplate: WorkoutTemplate? {
        store.nextTemplate
    }

    /// True while the running workout was started from `template` (an empty workout or another template: false).
    private func isRunning(_ template: WorkoutTemplate) -> Bool {
        controller.state?.templateID == template.id
    }

    @ViewBuilder
    private func recommendedCard(now: Date) -> some View {
        if let template = recommendedTemplate {
            let runsThis = isRunning(template)
            let lines = nextTimeItems(for: template, now: now)
            HubRecommendedCard(
                template: template,
                subtitle: recommendedSubtitle(template, now: now),
                readiness: HubMuscles.readiness(controller.recovery),
                chips: HubMuscles.chips(for: template, recovery: controller.recovery),
                coach: hubNote(for: template, nextTime: lines),
                nextTime: lines,
                primaryTitle: runsThis ? "Resume Workout" : "Start Workout",
                onPrimary: {
                    primaryAction(template, runsThis: runsThis)
                },
                onEdit: {
                    editor = .template(template.id)
                }
            )
        }
    }

    /// The coach note of the card. The readiness sentence is left out while the recovery numbers are the demo constants, and the
    /// "Aim for" sentence while the "Next time" lines already name a weight (the two would disagree).
    private func hubNote(for template: WorkoutTemplate, nextTime lines: [NextTimeItem]) -> String? {
        HubNoteBuilder.message(
            template: template,
            exercise: { store.exercise(id: $0) },
            recovery: controller.isUsingDemoRecovery ? nil : controller.recovery,
            audience: environment.audience,
            includeTarget: !lines.contains { $0.recommendation.verdict.hasTarget }
        )
    }

    /// "Next time" lines from the progression engine for the first exercises of the template that have something to aim for.
    private func nextTimeItems(for template: WorkoutTemplate, now: Date) -> [NextTimeItem] {
        CoachPlanner.nextTime(
            for: template,
            exercise: { store.exercise(id: $0) },
            history: { store.history(for: $0, now: now) },
            audience: environment.audience,
            now: now
        )
    }

    private func recommendedSubtitle(_ template: WorkoutTemplate, now: Date) -> String {
        var suffix: String?
        if let last = template.lastPerformed {
            suffix = "last done " + HubFormat.daysAgo(last, now: now)
        }
        return HubFormat.templateSubtitle(template, suffix: suffix)
    }

    /// Resumes the running workout when it is this template's; otherwise starts it, which only warns while another
    /// workout runs (see `requestStart`).
    private func primaryAction(_ template: WorkoutTemplate, runsThis: Bool) {
        if runsThis {
            onResume()
        } else {
            requestStart(template)
        }
    }

    // MARK: Weigh-in

    /// "Time to update your weight": shown while the weigh-in reminder is on and a weigh-in is due. The in-app half of the reminder
    /// (the notification may be refused or missed); it goes away as soon as the user has logged a weight.
    @ViewBuilder
    private func weighInCard(now: Date) -> some View {
        if store.weighIn.isEnabled, store.isWeighInDue(now: now) {
            Button {
                showsWeightEntry = true
            } label: {
                weighInLabel(now: now)
            }
            .buttonStyle(PulsePlainButtonStyle())
            .accessibilityIdentifier("hub-weigh-in")
        }
    }

    private func weighInLabel(now: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "scalemass.fill")
                .font(.system(size: 26))
                .foregroundStyle(PulseTheme.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Time to update your weight")
                    .pulseFont(17, .semibold, relativeTo: .headline)
                    .foregroundStyle(PulseTheme.ink)
                Text(weighInSubtitle(now: now))
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
            }
            Spacer(minLength: 8)
            HubChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubRowBackground()
        .contentShape(Rectangle())
    }

    private func weighInSubtitle(now: Date) -> String {
        guard let latest = store.latestBodyWeight else { return "Log your first weigh-in" }
        return "Last " + NumberText.kg(latest.kg) + " kg · " + HubFormat.daysAgo(latest.date, now: now)
    }

    // MARK: Start empty workout

    private var startEmptyRow: some View {
        Button {
            requestStart(nil)
        } label: {
            startEmptyLabel
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    private var startEmptyLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(PulseTheme.green)
            VStack(alignment: .leading, spacing: 0) {
                Text("Start Empty Workout")
                    .pulseFont(17, .semibold, relativeTo: .headline)
                    .foregroundStyle(PulseTheme.ink)
                Text("Add exercises as you go")
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
            }
            Spacer(minLength: 8)
            HubChevron()
        }
        .padding(.horizontal, 16)
        // Only matters with larger text: at the default size the 56 pt minimum below is the taller of the two.
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubRowBackground()
        .contentShape(Rectangle())
    }

    // MARK: Plan

    /// The active plan: its workouts in rotation order (the next one is tagged "next up"), how many were done in the last
    /// seven days and a button that passes over the next workout. Not tied to weekdays: the rotation just moves on.
    @ViewBuilder
    private var planSection: some View {
        if let plan = store.activePlan {
            let workouts = plan.workouts(in: store.templates)
            if !workouts.isEmpty {
                VStack(spacing: 12) {
                    HubSectionHeader(title: plan.name, actionTitle: "All Plans") {
                        route = .plans
                    }
                    Text(planProgressText(plan))
                        .pulseFont(12, relativeTo: .footnote)
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) {
                        ForEach(workouts) { template in
                            templateButton(template)
                        }
                        Button {
                            store.skipNextWorkout(planID: plan.id)
                        } label: {
                            HubPlanActionRow(title: skipTitle, systemImage: "forward.end")
                        }
                        .buttonStyle(PulsePlainButtonStyle())
                        .accessibilityIdentifier("hub-plan-skip")
                    }
                }
            }
        }
    }

    /// "Next: workout 2 of 5 \u{00B7} 2 of 4 in the last 7 days" (no target: "2 done in the last 7 days").
    private func planProgressText(_ plan: WorkoutPlan) -> String {
        var parts: [String] = []
        if let position = plan.nextPosition(in: store.templates) {
            parts.append("Next: workout \(position) of \(plan.templateIDs.count)")
        }
        let done = plan.completedCount(in: store.history, now: Date())
        if let target = plan.daysPerWeek {
            parts.append("\(done) of \(target) in the last 7 days")
        } else {
            parts.append("\(done) done in the last 7 days")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var skipTitle: String {
        if let name = recommendedTemplate?.name {
            return "Skip " + name
        }
        return "Skip next workout"
    }

    // MARK: Plan import

    /// Reads the chosen plan file and tells the user what was imported (or why not). Cancelling the picker says nothing.
    private func importPlan(from result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            importMessage = "The file could not be opened."
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if let data = try? Data(contentsOf: url) {
                switch store.importPlan(from: data) {
                case .success(let summary):
                    importMessage = summary.message
                case .failure(let error):
                    importMessage = error.message
                }
            } else {
                importMessage = "The file could not be read."
            }
        }
        showsImportResult = true
    }

    // MARK: Templates

    private var templatesSection: some View {
        VStack(spacing: 12) {
            HubSectionHeader(title: "Templates", actionTitle: "See All") {
                route = .templates
            }
            VStack(spacing: 8) {
                ForEach(store.templates.prefix(3)) { template in
                    templateButton(template)
                }
                newTemplateButton
            }
        }
    }

    private func templateButton(_ template: WorkoutTemplate) -> some View {
        let isNext = template.id == recommendedTemplate?.id
        let subtitle = HubFormat.templateSubtitle(template, suffix: isNext ? "next up" : nil)
        return Button {
            route = .template(template.id)
        } label: {
            HubTemplateRow(template: template, subtitle: subtitle)
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    private var newTemplateButton: some View {
        Button {
            editor = .new
        } label: {
            HubNewTemplateRow()
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    // MARK: Muscle recovery

    private var recoverySection: some View {
        VStack(spacing: 12) {
            HubSectionHeader(title: "Muscle Recovery", actionTitle: "View All") {
                route = .recovery
            }
            LazyVGrid(columns: recoveryColumns, spacing: 12) {
                ForEach(HubMuscles.displayOrder) { muscle in
                    HubRecoveryCard(
                        title: muscle.title,
                        percent: HubMuscles.percent(muscle, controller.recovery)
                    )
                }
            }
        }
    }

    /// Two columns as designed; a single column at the accessibility text sizes, where a card no longer fits half the width.
    private var recoveryColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    // MARK: Recent workouts

    @ViewBuilder
    private var recentSection: some View {
        if !store.history.isEmpty {
            VStack(spacing: 12) {
                HubSectionHeader(title: "Recent Workouts", actionTitle: "See All") {
                    route = .history
                }
                VStack(spacing: 8) {
                    ForEach(store.history.prefix(3)) { workout in
                        workoutButton(workout)
                    }
                }
            }
        }
    }

    private func workoutButton(_ workout: CompletedWorkout) -> some View {
        Button {
            route = .workout(workout.id)
        } label: {
            HubWorkoutRow(workout: workout)
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    // MARK: This week

    private func weekSection(now: Date) -> some View {
        let week = HubFormat.weekStats(history: store.history, now: now)
        return VStack(spacing: 12) {
            HubSectionHeader(title: "This Week")
            HubWeekCard(sessions: week.sessions, sets: week.sets, volumeKg: week.volume)
        }
    }

    // MARK: Library

    private var libraryRow: some View {
        Button {
            route = .library
        } label: {
            libraryLabel
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    private var libraryLabel: some View {
        HStack(spacing: 12) {
            HubIconBox(fill: PulseTheme.greenTint) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PulseTheme.green)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Exercise Library")
                    .pulseFont(17, relativeTo: .body)
                    .foregroundStyle(PulseTheme.ink)
                Text(libraryCaption)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .hubLineLimit(1, whenLarger: nil)
            }
            Spacer(minLength: 8)
            HubChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubRowBackground()
        .contentShape(Rectangle())
    }

    private var libraryCaption: String {
        let count = ExerciseLibrary.builtIn.count + store.customExercises.count
        return "\(count) exercises with form demos · create your own"
    }

    // MARK: Navigation

    @ViewBuilder
    private func destination(for target: HubRoute) -> some View {
        switch target {
        case .library:
            HubExerciseLibraryView(store: store)
        case .templates:
            HubTemplateListView(
                store: store,
                controller: controller,
                onStart: { (template: WorkoutTemplate) in
                    requestStart(template)
                },
                onResume: onResume
            )
        case .template(let templateID):
            HubTemplateDetailView(
                store: store,
                controller: controller,
                templateID: templateID,
                onStart: { (template: WorkoutTemplate) in
                    requestStart(template)
                },
                onResume: onResume
            )
        case .plans:
            HubPlanListView(store: store)
        case .history:
            HubHistoryListView(store: store)
        case .workout(let workoutID):
            HubWorkoutDetailView(store: store, workoutID: workoutID)
        case .recovery:
            HubRecoveryView(recovery: controller.recovery)
        case .settings:
            StrengthSettingsView(environment: environment)
        }
    }

    private func template(for target: HubEditorTarget) -> WorkoutTemplate? {
        switch target {
        case .new:
            return nil
        case .template(let templateID):
            return store.templates.first { $0.id == templateID }
        }
    }

    // MARK: Starting

    /// Starts a workout from `template` (nil = empty) unless one is already running; then it only warns. This alert
    /// belongs to the hub itself: the pushed template screens host their own alert, because a presentation of a view
    /// that a pushed screen covers does not show.
    private func requestStart(_ template: WorkoutTemplate?) {
        if controller.state != nil {
            showsBusyAlert = true
            return
        }
        route = nil
        onStart(template)
    }

    private var busyMessage: String {
        HubFormat.busyMessage(controller.state?.name)
    }
}

// MARK: - Recommended card

private struct HubMuscleChip: Identifiable {
    let id: String
    let title: String
    let color: Color
}

private struct HubRecommendedCard: View {
    let template: WorkoutTemplate
    let subtitle: String
    let readiness: Int
    let chips: [HubMuscleChip]
    let coach: String?
    let nextTime: [NextTimeItem]
    let primaryTitle: String
    let onPrimary: () -> Void
    let onEdit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @PulseScaled(7, relativeTo: .footnote) private var dotSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !chips.isEmpty {
                chipRow
            }
            if !template.entries.isEmpty {
                thumbnails
            }
            if !nextTime.isEmpty {
                nextTimeBlock
            }
            if let coach = coach {
                coachNote(coach)
            }
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard()
    }

    private var header: some View {
        HubAdaptiveStack(alignment: .center, spacing: 12, stackedSpacing: 10) {
            headerTexts
                .frame(maxWidth: .infinity, alignment: .leading)
            HubReadinessRing(percent: readiness)
        }
    }

    private var headerTexts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today · Recommended")
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
            Text(template.name)
                .pulseNumber(28, relativeTo: .largeTitle)
                .foregroundStyle(PulseTheme.ink)
                .hubLineLimit(1, whenLarger: 3)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .hubLineLimit(2, whenLarger: nil)
        }
    }

    /// One row of chips as designed; at larger text sizes the chips wrap onto further lines instead of being cut off.
    @ViewBuilder
    private var chipRow: some View {
        if dynamicTypeSize > .large {
            HubChipFlowLayout(spacing: 6, lineSpacing: 6) {
                chipViews
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                chipViews
            }
        }
    }

    private var chipViews: some View {
        ForEach(chips) { chip in
            chipView(chip)
        }
    }

    private func chipView(_ chip: HubMuscleChip) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(chip.color)
                .frame(width: dotSize, height: dotSize)
            Text(chip.title)
                .pulseFont(12, .semibold, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.ink)
                .hubLineLimit(1, whenLarger: nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PulseTheme.cellFill, in: Capsule())
    }

    private var thumbnails: some View {
        HStack(spacing: 6) {
            ForEach(template.entries.prefix(6)) { entry in
                ExerciseMediaView(mediaKey: entry.exercise.mediaKey, cornerRadius: 10)
                    .frame(width: 46, height: 46)
            }
        }
    }

    /// "Next time" under the thumbnails: one row per exercise, the exercise and what to aim for, with the reason underneath.
    private var nextTimeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next time")
                .pulseFont(12, .semibold, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(nextTime) { item in
                nextTimeRow(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nextTimeRow(_ item: NextTimeItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HubAdaptiveStack(alignment: .firstTextBaseline, spacing: 8, stackedSpacing: 2) {
                Text(verbatim: item.exerciseName)
                    .pulseFont(14, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: item.line.headline)
                    .pulseFont(14, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.greenText)
            }
            if let detail = item.line.detail {
                Text(verbatim: detail)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func coachNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "brain.head.profile")
                .pulseFont(16, .semibold, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.green)
                .padding(.top, 1)
                .accessibilityHidden(true)
            coachText(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HubColor.greenWash, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func coachText(_ text: String) -> some View {
        HubCoachText(text: text)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onPrimary) {
                HStack(spacing: 8) {
                    StrengthDumbbellGlyph(size: 18, color: PulseTheme.onGreen, strokeWidth: 2.2)
                    Text(primaryTitle)
                        .pulseFont(17, .semibold, relativeTo: .headline)
                        .foregroundStyle(PulseTheme.onGreen)
                        .multilineTextAlignment(.center)
                }
                // Padding that only shows once larger text makes the label taller than the 50 pt minimum below.
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(PulseTheme.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PulsePlainButtonStyle())
            Button(action: onEdit) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PulseTheme.greenText)
                    .frame(width: 50, height: 50)
                    .background(PulseTheme.cellFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PulsePlainButtonStyle())
            .accessibilityLabel("Edit plan")
        }
    }
}

/// "Coach · message" as one run of text (the label semibold, the message regular); both grow with Dynamic Type.
/// A `Text` concatenation needs real `Font` values, hence the scaled size here instead of `pulseFont`.
private struct HubCoachText: View {
    let text: String

    @PulseScaled(13, relativeTo: .footnote) private var size: CGFloat

    var body: some View {
        let label = Text("Coach · ")
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(PulseTheme.ink)
        let message = Text(text)
            .font(.system(size: size))
            .foregroundColor(PulseTheme.ink)
        return label + message
    }
}

/// The 56 pt readiness ring: the mean recovery of all muscle groups, coloured by level. The ring, its stroke and the
/// figure inside grow together (the same text style), so the figure always fits.
private struct HubReadinessRing: View {
    let percent: Int

    @PulseScaled(48, relativeTo: .title3) private var ringSize: CGFloat
    @PulseScaled(6, relativeTo: .title3) private var lineWidth: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(PulseTheme.progressTrack, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(percent) / 100)
                    .stroke(HubMuscles.color(percent), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)")
                    .pulseNumber(18, relativeTo: .title3)
                    .foregroundStyle(PulseTheme.ink)
            }
            .frame(width: ringSize, height: ringSize)
            .padding(4)
            Text(HubMuscles.readinessTitle(percent))
                .pulseFont(11, relativeTo: .caption2)
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness")
        .accessibilityValue("\(percent) percent, " + HubMuscles.readinessTitle(percent))
    }
}

// MARK: - Rows and cards

private struct HubTemplateRow: View {
    let template: WorkoutTemplate
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            HubIconBox(fill: HubColor.blueFill) {
                StrengthDumbbellGlyph(size: 18, color: HubColor.blue, strokeWidth: 2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.ink)
                    .hubLineLimit(1, whenLarger: nil)
                Text(subtitle)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .hubLineLimit(1, whenLarger: nil)
            }
            Spacer(minLength: 8)
            HubChevron()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubRowBackground()
        .contentShape(Rectangle())
    }
}

private struct HubNewTemplateRow: View {
    var body: some View {
        HStack(spacing: 12) {
            HubIconBox(fill: PulseTheme.greenTint) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PulseTheme.green)
            }
            Text("New Template")
                .pulseFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.greenText)
            Spacer(minLength: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubRowBackground()
        .contentShape(Rectangle())
    }
}

/// A row like "New Template" with its own title and symbol (the plan's "Skip" button).
private struct HubPlanActionRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            HubIconBox(fill: PulseTheme.greenTint) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PulseTheme.green)
            }
            Text(title)
                .pulseFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.greenText)
                .hubLineLimit(1, whenLarger: nil)
            Spacer(minLength: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubRowBackground()
        .contentShape(Rectangle())
    }
}

private struct HubWorkoutRow: View {
    let workout: CompletedWorkout

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            HubIconBox(fill: HubColor.blueFill) {
                StrengthDumbbellGlyph(size: 18, color: HubColor.blue, strokeWidth: 2)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(workout.name)
                        .pulseFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(PulseTheme.ink)
                        .hubLineLimit(1, whenLarger: nil)
                    if !workout.personalRecords.isEmpty {
                        Text("\(workout.personalRecords.count) PR")
                            .pulseFont(11, .bold, relativeTo: .caption2)
                            .foregroundStyle(PulseTheme.prText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PulseTheme.prFill, in: Capsule())
                            .fixedSize()
                    }
                }
                Text(HubFormat.dateTime(workout.startedAt))
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                if dynamicTypeSize.isAccessibilitySize {
                    // No room for a column of figures on the right: they follow the date, under the name.
                    volumeText
                    durationText
                }
            }
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 2) {
                    volumeText
                    durationText
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubRowBackground()
        .contentShape(Rectangle())
    }

    private var volumeText: some View {
        Text(HubFormat.volume(workout.volumeKg))
            .pulseNumber(12, .semibold, relativeTo: .footnote)
            .foregroundStyle(PulseTheme.ink)
    }

    private var durationText: some View {
        Text(HubFormat.duration(seconds: workout.durationSeconds))
            .pulseFont(12, relativeTo: .footnote)
            .foregroundStyle(PulseTheme.inkSecondary)
    }
}

private struct HubRecoveryCard: View {
    let title: String
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .pulseFont(12, .semibold, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.ink)
            HubBar(fraction: Double(percent) / 100, color: HubMuscles.color(percent))
            Text("\(percent)%")
                .pulseNumber(11, .regular, relativeTo: .caption2)
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubRowBackground()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + " recovery")
        .accessibilityValue("\(percent) percent")
    }
}

private struct HubStat: Identifiable {
    let title: String
    let value: String

    var id: String { title }
}

/// One row of figures: small caption over a 20 pt rounded value, thin dividers between the columns.
/// At the accessibility text sizes the columns no longer fit side by side and are stacked, one figure per line.
private struct HubStatRow: View {
    let stats: [HubStat]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(stats) { stat in
                    column(stat, showsDivider: false)
                }
            }
        } else {
            HStack(spacing: 16) {
                ForEach(Array(stats.enumerated()), id: \.element.id) { pair in
                    column(pair.element, showsDivider: pair.offset > 0)
                }
            }
        }
    }

    private func column(_ stat: HubStat, showsDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stat.title)
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .hubLineLimit(1, whenLarger: 2)
            Text(stat.value)
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
                    .offset(x: -8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HubWeekCard: View {
    let sessions: Int
    let sets: Int
    let volumeKg: Double

    /// The design's weekly target ("2 of 4").
    static let sessionGoal = 4

    var body: some View {
        HubStatRow(stats: [
            HubStat(title: "Sessions", value: "\(sessions) of \(max(HubWeekCard.sessionGoal, sessions))"),
            HubStat(title: "Sets", value: "\(sets)"),
            HubStat(title: "Volume", value: HubFormat.volume(volumeKg))
        ])
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubRowBackground()
    }
}

// MARK: - Small building blocks

/// A section title with an optional action ("See All") at the trailing edge. At the accessibility text sizes the
/// action moves under the title (two long texts do not fit one line).
private struct HubSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                titleText
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let actionTitle = actionTitle {
                    actionButton(actionTitle)
                }
            }
        } else {
            HStack {
                titleText
                Spacer(minLength: 8)
                if let actionTitle = actionTitle {
                    actionButton(actionTitle)
                }
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .pulseFont(17, .semibold, relativeTo: .headline)
            .foregroundStyle(PulseTheme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private func actionButton(_ actionTitle: String) -> some View {
        Button(action: action) {
            Text(actionTitle)
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.blue)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .padding(.vertical, -11)
    }
}

private struct HubIconBox<Content: View>: View {
    private let fill: Color
    private let content: Content

    init(fill: Color, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: 32, height: 32)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HubChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(PulseTheme.inkTertiary)
            .accessibilityHidden(true)
    }
}

/// A 6 pt progress bar on the grey track.
private struct HubBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PulseTheme.progressTrack)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

/// An `HStack` that becomes a `VStack` at the accessibility text sizes, where side-by-side columns no longer fit.
/// At every other size it is exactly `HStack(alignment:spacing:)`.
private struct HubAdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let alignment: VerticalAlignment
    private let spacing: CGFloat
    private let stackedAlignment: HorizontalAlignment
    private let stackedSpacing: CGFloat
    private let content: Content

    init(
        alignment: VerticalAlignment = .center,
        spacing: CGFloat,
        stackedAlignment: HorizontalAlignment = .leading,
        stackedSpacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.stackedAlignment = stackedAlignment
        self.stackedSpacing = stackedSpacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: stackedAlignment, spacing: stackedSpacing) {
                content
            }
        } else {
            HStack(alignment: alignment, spacing: spacing) {
                content
            }
        }
    }
}

/// `lineLimit(normal)` at the default text size and below, `lineLimit(larger)` above it: a title stays on one line
/// as designed but wraps instead of being truncated once the user chose bigger text (nil = no limit).
private struct HubLineLimitModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let normal: Int?
    let larger: Int?

    func body(content: Content) -> some View {
        content.lineLimit(dynamicTypeSize > .large ? larger : normal)
    }
}

/// Chips that wrap onto further lines (the muscle chips of the recommended card at larger text sizes).
private struct HubChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? CGFloat.infinity
        return arrange(subviews: subviews, maxWidth: maxWidth).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews: subviews, maxWidth: bounds.width)
        for index in subviews.indices {
            let origin = result.origins[index]
            let size = result.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
        }
    }

    private func arrange(
        subviews: Subviews,
        maxWidth: CGFloat
    ) -> (origins: [CGPoint], sizes: [CGSize], size: CGSize) {
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(ProposedViewSize.unspecified)
            if size.width > maxWidth {
                // A chip wider than the line wraps its own text instead of running out of the card.
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, sizes, CGSize(width: widest, height: y + rowHeight))
    }
}

private enum HubColor {
    static let blue = Color(light: 0x007AFF, dark: 0x0A84FF)
    static let blueFill = Color(light: 0x007AFF, dark: 0x0A84FF, lightAlpha: 0.10, darkAlpha: 0.20)
    static let greenWash = Color(light: 0x1B8448, dark: 0x30D158, lightAlpha: 0.08, darkAlpha: 0.14)
}

private extension View {
    /// White 12 pt row / card background of the hub lists.
    func hubRowBackground() -> some View {
        self.background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// `lineLimit(normal)` at the default text size and below, `lineLimit(larger)` above it (nil = no limit).
    func hubLineLimit(_ normal: Int?, whenLarger larger: Int?) -> some View {
        self.modifier(HubLineLimitModifier(normal: normal, larger: larger))
    }

    /// A hairline above the view (not drawn for the first row of a list).
    func hubSeparator(visible: Bool, inset: CGFloat) -> some View {
        self.overlay(alignment: .top) {
            if visible {
                Rectangle()
                    .fill(PulseTheme.separator)
                    .frame(height: 0.5)
                    .padding(.leading, inset)
            }
        }
    }
}

// MARK: - Text and number helpers

private enum HubFormat {
    static func exercises(_ count: Int) -> String {
        count == 1 ? "1 exercise" : "\(count) exercises"
    }

    /// "6 exercises · about 55 min", plus an optional suffix ("next up", "last done 5 days ago").
    static func templateSubtitle(_ template: WorkoutTemplate, suffix: String?) -> String {
        var text = exercises(template.entries.count) + " · about \(template.estimatedMinutes) min"
        if let suffix = suffix {
            text += " · " + suffix
        }
        return text
    }

    /// "Oct 8, 18:10" (24-hour clock, English month names, no locale dependence). Month and day come from the
    /// Gregorian calendar the month names belong to, like every other date of the exercise and summary screens,
    /// not from the user's calendar (a Persian or Islamic month number would index the wrong name).
    static func dateTime(_ date: Date) -> String {
        let parts = StrengthResultText.calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let monthIndex = min(max((parts.month ?? 1) - 1, 0), 11)
        let day = parts.day ?? 1
        let time = twoDigits(parts.hour ?? 0) + ":" + twoDigits(parts.minute ?? 0)
        return StrengthResultText.monthNames[monthIndex] + " " + String(day) + ", " + time
    }

    /// The alert text while another workout runs.
    static func busyMessage(_ workoutName: String?) -> String {
        let name = workoutName ?? "your current workout"
        return "Finish or discard \(name) before starting another workout."
    }

    /// "52m" (the design shows minutes only, "61m" for 1 h 1 min).
    static func duration(seconds: Int) -> String {
        let minutes = Int((Double(max(0, seconds)) / 60).rounded())
        return "\(minutes)m"
    }

    /// "8,420 kg"
    static func volume(_ kg: Double) -> String {
        NumberText.thousands(kg) + " kg"
    }

    /// "today", "yesterday", "5 days ago", "3 weeks ago", "2 months ago" (calendar days, computed by hand).
    static func daysAgo(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 14 { return "\(days) days ago" }
        if days < 60 { return "\(days / 7) weeks ago" }
        return "\(days / 30) months ago"
    }

    /// Sessions, logged sets and volume of the calendar week that contains `now`.
    static func weekStats(history: [CompletedWorkout], now: Date) -> (sessions: Int, sets: Int, volume: Double) {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else {
            return (sessions: 0, sets: 0, volume: 0)
        }
        var sessions = 0
        var sets = 0
        var volume = 0.0
        for workout in history where interval.contains(workout.finishedAt) {
            sessions += 1
            sets += workout.loggedSets
            volume += workout.volumeKg
        }
        return (sessions: sessions, sets: sets, volume: volume)
    }

    /// "5 sets · 85 kg × 6 · Rest 2:30" (last working set of the plan).
    static func planSummary(_ entry: TemplateEntry) -> String {
        let count = entry.plannedSets.count
        var parts: [String] = [count == 1 ? "1 set" : "\(count) sets"]
        let working = entry.plannedSets.last(where: { $0.type != .warmup }) ?? entry.plannedSets.last
        if let planned = working {
            switch entry.exercise.tracking {
            case .weightReps:
                parts.append(NumberText.kg(planned.weightKg) + " kg × " + planned.repsText)
            case .repsOnly:
                parts.append(planned.repsText + " reps")
            case .duration:
                parts.append(planned.repsText + " s")
            }
        }
        if entry.restSeconds > 0 {
            parts.append("Rest " + NumberText.rest(seconds: entry.restSeconds))
        }
        if let group = entry.supersetGroup {
            parts.append("Superset " + group)
        }
        return parts.joined(separator: " · ")
    }

    /// "W 50×8 · 82.5×6" for weight exercises, "12 reps" / "45 s" otherwise.
    static func setsText(_ sets: [CompletedSet], tracking: TrackingKind) -> String {
        var texts: [String] = []
        for item in sets {
            let prefix = item.type == .normal ? "" : item.type.badge + " "
            switch tracking {
            case .weightReps:
                texts.append(prefix + NumberText.kg(item.weightKg) + "×" + String(item.reps))
            case .repsOnly:
                texts.append(prefix + String(item.reps) + " reps")
            case .duration:
                texts.append(prefix + String(item.reps) + " s")
            }
        }
        return texts.joined(separator: " · ")
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

// MARK: - Muscle helpers

private enum HubMuscles {
    /// Order of the recovery grid in the design.
    static let displayOrder: [MuscleGroup] = [.chest, .shoulders, .arms, .back, .legs, .core]

    static func percent(_ muscle: MuscleGroup, _ recovery: RecoveryProvider) -> Int {
        max(0, min(100, recovery(muscle)))
    }

    static func level(_ percent: Int) -> ActiveWorkoutPresentation.RecoveryLevel {
        if percent >= 80 { return .good }
        if percent >= 60 { return .fair }
        return .low
    }

    static func color(_ percent: Int) -> Color {
        PulseTheme.recoveryColor(level(percent))
    }

    static func levelTitle(_ percent: Int) -> String {
        switch level(percent) {
        case .good:
            return "Good"
        case .fair:
            return "Fair"
        case .low:
            return "Low"
        }
    }

    static func readinessTitle(_ percent: Int) -> String {
        switch level(percent) {
        case .good:
            return "Ready"
        case .fair:
            return "Fair"
        case .low:
            return "Low"
        }
    }

    /// Mean recovery of all muscle groups, rounded (88, 100, 82, 79, 64, 100 -> 86).
    static func readiness(_ recovery: RecoveryProvider) -> Int {
        var total = 0
        var count = 0
        for muscle in MuscleGroup.allCases {
            total += percent(muscle, recovery)
            count += 1
        }
        if count == 0 { return 0 }
        return Int((Double(total) / Double(count)).rounded())
    }

    /// The template's muscle groups, most exercises first (ties keep the order of first use).
    static func musclesUsed(by template: WorkoutTemplate) -> [MuscleGroup] {
        HubNoteBuilder.musclesUsed(by: template)
    }

    /// Up to three chips "Chest 88%" with a recovery dot.
    static func chips(for template: WorkoutTemplate, recovery: RecoveryProvider) -> [HubMuscleChip] {
        var chips: [HubMuscleChip] = []
        for muscle in musclesUsed(by: template).prefix(3) {
            let value = percent(muscle, recovery)
            chips.append(HubMuscleChip(id: muscle.rawValue, title: muscle.title + " \(value)%", color: color(value)))
        }
        return chips
    }
}

// MARK: - Exercise library

private struct HubExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            ExerciseMediaView(mediaKey: exercise.mediaKey, cornerRadius: 10)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.ink)
                    .hubLineLimit(1, whenLarger: nil)
                Text(exercise.muscle.title + " · " + exercise.equipment.title)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .hubLineLimit(1, whenLarger: nil)
            }
            Spacer(minLength: 8)
            HubChevron()
        }
        .padding(.horizontal, 12)
        // Only matters with larger text: at the default size the 64 pt minimum below is the taller of the two.
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// "Exercise Library": search, muscle filter, create your own; each row opens the exercise detail.
@MainActor
private struct HubExerciseLibraryView: View {
    @ObservedObject var store: StrengthStore
    @State var query = ""
    @State var muscle: MuscleGroup? = nil
    @State var showsCreate = false

    init(store: StrengthStore) {
        self._store = ObservedObject(wrappedValue: store)
    }

    private var results: [Exercise] {
        ExerciseLibrary.filter(store.exercises, query: query, muscle: muscle, equipment: nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                muscleChips
                resultsCard
            }
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(PulseTheme.ground.ignoresSafeArea())
        .navigationTitle("Exercise Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search exercises")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showsCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create exercise")
            }
        }
        .sheet(isPresented: $showsCreate) {
            CreateExerciseSheet(
                initialName: query,
                onCreate: { (exercise: Exercise) in
                    store.addCustomExercise(exercise)
                }
            )
        }
    }

    private var muscleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PulseChip("All", isSelected: muscle == nil) {
                    muscle = nil
                }
                ForEach(MuscleGroup.allCases) { group in
                    PulseChip(group.title, isSelected: muscle == group) {
                        muscle = (muscle == group) ? nil : group
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultsCard: some View {
        let items = results
        if items.isEmpty {
            Text("No exercises found")
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
                .padding(.top, 24)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { pair in
                    exerciseLink(pair.element)
                        .hubSeparator(visible: pair.offset > 0, inset: 68)
                }
            }
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func exerciseLink(_ exercise: Exercise) -> some View {
        NavigationLink {
            ExerciseDetailView(exercise: exercise, store: store)
        } label: {
            HubExerciseRow(exercise: exercise)
        }
        .buttonStyle(PulsePlainButtonStyle())
    }
}

// MARK: - Templates

private struct HubTemplateListRow: View {
    let template: WorkoutTemplate
    let now: Date
    /// True for the template the hub recommends: it gets a "Next up" pill after its name.
    let isNext: Bool

    var body: some View {
        HStack(spacing: 12) {
            HubIconBox(fill: HubColor.blueFill) {
                StrengthDumbbellGlyph(size: 18, color: HubColor.blue, strokeWidth: 2)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(template.name)
                        .pulseFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(PulseTheme.ink)
                        .hubLineLimit(1, whenLarger: nil)
                    if isNext {
                        // A pill of its own (like the "PR" pill of a recent workout) so the tag is never cut off
                        // at the end of the subtitle; the name gives way first.
                        Text("Next up")
                            .pulseFont(11, .bold, relativeTo: .caption2)
                            .foregroundStyle(PulseTheme.greenText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PulseTheme.greenTint, in: Capsule())
                            .fixedSize()
                            .layoutPriority(1)
                    }
                }
                // "6 exercises · about 55 min · last done 5 days ago" wraps to a second line when it does not fit
                // (a narrow phone, a larger text size) instead of losing its end.
                Text(subtitle)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(exerciseNames)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkTertiary)
                    .hubLineLimit(2, whenLarger: 4)
            }
            Spacer(minLength: 8)
            HubChevron()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubRowBackground()
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var suffix: String?
        if let last = template.lastPerformed {
            suffix = "last done " + HubFormat.daysAgo(last, now: now)
        }
        return HubFormat.templateSubtitle(template, suffix: suffix)
    }

    private var exerciseNames: String {
        template.entries.map { $0.exercise.name }.joined(separator: ", ")
    }
}

/// "Templates" > "See All": every template, with the exercises it contains.
@MainActor
private struct HubTemplateListView: View {
    @ObservedObject var store: StrengthStore
    let controller: WorkoutController
    let onStart: (WorkoutTemplate) -> Void
    let onResume: () -> Void
    @State var showsNewTemplate = false

    init(
        store: StrengthStore,
        controller: WorkoutController,
        onStart: @escaping (WorkoutTemplate) -> Void,
        onResume: @escaping () -> Void
    ) {
        self._store = ObservedObject(wrappedValue: store)
        self.controller = controller
        self.onStart = onStart
        self.onResume = onResume
    }

    var body: some View {
        let now = Date()
        let nextID = store.nextTemplate?.id
        return ScrollView {
            VStack(spacing: 8) {
                ForEach(store.templates) { template in
                    NavigationLink {
                        HubTemplateDetailView(
                            store: store,
                            controller: controller,
                            templateID: template.id,
                            onStart: onStart,
                            onResume: onResume
                        )
                    } label: {
                        HubTemplateListRow(template: template, now: now, isNext: template.id == nextID)
                    }
                    .buttonStyle(PulsePlainButtonStyle())
                }
                Button {
                    showsNewTemplate = true
                } label: {
                    HubNewTemplateRow()
                }
                .buttonStyle(PulsePlainButtonStyle())
            }
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(PulseTheme.ground.ignoresSafeArea())
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsNewTemplate) {
            HubTemplateEditorSheet(store: store, template: nil)
        }
    }
}

/// A template at a glance: its exercises (each opens the exercise detail) and the Start button. While a workout
/// runs the button reads "Resume Workout" for that workout's own template; for any other template it explains with
/// an alert of this screen (the hub's alert sits under this pushed screen and would not show).
@MainActor
private struct HubTemplateDetailView: View {
    @ObservedObject var store: StrengthStore
    @ObservedObject var controller: WorkoutController
    let templateID: UUID
    let onStart: (WorkoutTemplate) -> Void
    let onResume: () -> Void
    @State var showsEditor = false
    @State var showsBusyAlert = false

    init(
        store: StrengthStore,
        controller: WorkoutController,
        templateID: UUID,
        onStart: @escaping (WorkoutTemplate) -> Void,
        onResume: @escaping () -> Void
    ) {
        self._store = ObservedObject(wrappedValue: store)
        self._controller = ObservedObject(wrappedValue: controller)
        self.templateID = templateID
        self.onStart = onStart
        self.onResume = onResume
    }

    private var template: WorkoutTemplate? {
        store.templates.first { $0.id == templateID }
    }

    var body: some View {
        detail
            .background(PulseTheme.ground.ignoresSafeArea())
            .navigationTitle(template?.name ?? "Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        showsEditor = true
                    }
                    .disabled(template == nil)
                }
            }
            .sheet(isPresented: $showsEditor) {
                HubTemplateEditorSheet(store: store, template: template)
            }
            .alert("Workout in progress", isPresented: $showsBusyAlert) {
                Button("Resume") {
                    onResume()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(HubFormat.busyMessage(controller.state?.name))
            }
    }

    @ViewBuilder
    private var detail: some View {
        if let template = template {
            content(template)
        } else {
            Text("This template is no longer available.")
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ template: WorkoutTemplate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(template)
                entriesCard(template)
            }
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            startBar(template)
        }
    }

    private func header(_ template: WorkoutTemplate) -> some View {
        var suffix: String?
        if let last = template.lastPerformed {
            suffix = "last done " + HubFormat.daysAgo(last, now: Date())
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .pulseNumber(28, relativeTo: .largeTitle)
                .foregroundStyle(PulseTheme.ink)
            Text(HubFormat.templateSubtitle(template, suffix: suffix))
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func entriesCard(_ template: WorkoutTemplate) -> some View {
        if template.entries.isEmpty {
            Text("This template has no exercises yet. Tap Edit to add some.")
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(template.entries.enumerated()), id: \.element.id) { pair in
                    entryLink(pair.element)
                        .hubSeparator(visible: pair.offset > 0, inset: 68)
                }
            }
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func entryLink(_ entry: TemplateEntry) -> some View {
        let exercise = store.exercise(id: entry.exercise.id) ?? entry.exercise
        return NavigationLink {
            ExerciseDetailView(exercise: exercise, store: store)
        } label: {
            entryRow(entry)
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    private func entryRow(_ entry: TemplateEntry) -> some View {
        HStack(spacing: 12) {
            ExerciseMediaView(mediaKey: entry.exercise.mediaKey, cornerRadius: 10)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise.name)
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.ink)
                    .hubLineLimit(1, whenLarger: nil)
                Text(HubFormat.planSummary(entry))
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .hubLineLimit(1, whenLarger: nil)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .pulseFont(12, relativeTo: .footnote)
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .hubLineLimit(2, whenLarger: nil)
                }
            }
            Spacer(minLength: 8)
            HubChevron()
        }
        .padding(.horizontal, 12)
        // Only matters with larger text: at the default size the 64 pt minimum below is the taller of the two.
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func startBar(_ template: WorkoutTemplate) -> some View {
        let isBusy = controller.state != nil
        let runsThis = controller.state?.templateID == template.id
        return Button {
            if runsThis {
                onResume()
            } else if isBusy {
                showsBusyAlert = true
            } else {
                onStart(template)
            }
        } label: {
            Text(runsThis ? "Resume Workout" : "Start Workout")
        }
        .buttonStyle(PulsePrimaryButtonStyle())
        .padding(.horizontal, PulseTheme.screenInset)
        .padding(.vertical, 8)
        .background(PulseTheme.ground)
    }
}

// MARK: - Plans

/// One plan of the plan list: its name, how many workouts it has and a check mark while it is the plan being followed.
private struct HubPlanListRow: View {
    let plan: WorkoutPlan
    let workoutCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.ink)
                    .hubLineLimit(1, whenLarger: nil)
                Text(subtitle)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .hubLineLimit(1, whenLarger: nil)
            }
            Spacer(minLength: 8)
            if plan.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(PulseTheme.green)
                    .accessibilityLabel("Active plan")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .hubRowBackground()
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var text = workoutCount == 1 ? "1 workout" : "\(workoutCount) workouts"
        if let days = plan.daysPerWeek {
            text += " \u{00B7} \(days) a week"
        }
        return text
    }
}

/// The saved plans. Tapping a plan makes it the one the hub follows; touch and hold deletes it (its workouts stay in Templates).
@MainActor
private struct HubPlanListView: View {
    @ObservedObject var store: StrengthStore

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if store.plans.isEmpty {
                    Text("No plans yet. Choose Import Plan in the menu to add one.")
                        .pulseFont(15, relativeTo: .subheadline)
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(store.plans) { plan in
                        Button {
                            store.activatePlan(id: plan.id)
                        } label: {
                            HubPlanListRow(plan: plan, workoutCount: plan.workouts(in: store.templates).count)
                        }
                        .buttonStyle(PulsePlainButtonStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                store.deletePlan(id: plan.id)
                            } label: {
                                Label("Delete Plan", systemImage: "trash")
                            }
                        }
                    }
                    Text("Tap a plan to follow it. Touch and hold to delete it; its workouts stay in Templates.")
                        .pulseFont(12, relativeTo: .footnote)
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(PulseTheme.ground.ignoresSafeArea())
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Template editor

private struct HubEditorEntryRow: View {
    let entry: TemplateEntry

    var body: some View {
        HStack(spacing: 12) {
            ExerciseMediaView(mediaKey: entry.exercise.mediaKey, cornerRadius: 8)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise.name)
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.ink)
                    .hubLineLimit(1, whenLarger: nil)
                Text(HubFormat.planSummary(entry))
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .hubLineLimit(1, whenLarger: nil)
            }
        }
    }
}

/// "New Template" / "Edit plan": name, exercises (drag to reorder, delete) and "Add Exercises".
/// Nothing is saved until Save.
@MainActor
private struct HubTemplateEditorSheet: View {
    let store: StrengthStore
    let template: WorkoutTemplate?
    @Environment(\.dismiss) var dismiss
    @State var name: String
    @State var entries: [TemplateEntry]
    @State var showsChooser = false

    init(store: StrengthStore, template: WorkoutTemplate?) {
        self.store = store
        self.template = template
        self._name = State(initialValue: template?.name ?? "")
        self._entries = State(initialValue: template?.entries ?? [])
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !entries.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Template name", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name")
                }
                Section {
                    ForEach(entries) { entry in
                        HubEditorEntryRow(entry: entry)
                    }
                    .onMove { (source: IndexSet, destination: Int) in
                        entries.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { (offsets: IndexSet) in
                        entries.remove(atOffsets: offsets)
                    }
                    Button {
                        showsChooser = true
                    } label: {
                        Label("Add Exercises", systemImage: "plus")
                    }
                } header: {
                    Text("Exercises")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(PulseTheme.ground.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle(template == nil ? "New Template" : "Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showsChooser) {
                HubExerciseChooserSheet(
                    store: store,
                    onAdd: { (exercises: [Exercise]) in
                        addExercises(exercises)
                    }
                )
            }
        }
    }

    private func addExercises(_ exercises: [Exercise]) {
        for exercise in exercises {
            entries.append(makeEntry(exercise))
        }
    }

    private func makeEntry(_ exercise: Exercise) -> TemplateEntry {
        let defaults = exercise.defaults
        let count = max(1, defaults.sets)
        var planned: [PlannedSet] = []
        for _ in 0..<count {
            planned.append(PlannedSet(type: .normal, weightKg: defaults.weightKg, reps: defaults.reps))
        }
        return TemplateEntry(exercise: exercise, plannedSets: planned, restSeconds: defaults.restSeconds)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !entries.isEmpty else { return }
        let saved = WorkoutTemplate(
            id: template?.id ?? UUID(),
            name: trimmed,
            entries: entries,
            lastPerformed: template?.lastPerformed
        )
        store.saveTemplate(saved)
        dismiss()
    }
}

/// Multi-select exercise list used by the template editor.
@MainActor
private struct HubExerciseChooserSheet: View {
    @ObservedObject var store: StrengthStore
    let onAdd: ([Exercise]) -> Void
    @Environment(\.dismiss) var dismiss
    @State var query = ""
    @State var selected: [String] = []

    init(store: StrengthStore, onAdd: @escaping ([Exercise]) -> Void) {
        self._store = ObservedObject(wrappedValue: store)
        self.onAdd = onAdd
    }

    private var results: [Exercise] {
        ExerciseLibrary.filter(store.exercises, query: query, muscle: nil, equipment: nil)
    }

    var body: some View {
        NavigationStack {
            List(results) { exercise in
                Button {
                    toggle(exercise)
                } label: {
                    chooserRow(exercise)
                }
                .buttonStyle(PulsePlainButtonStyle())
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add (\(selected.count))") {
                        confirm()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func chooserRow(_ exercise: Exercise) -> some View {
        let isSelected = selected.contains(exercise.id)
        return HStack(spacing: 12) {
            ExerciseMediaView(mediaKey: exercise.mediaKey, cornerRadius: 8)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.ink)
                    .hubLineLimit(1, whenLarger: nil)
                Text(exercise.muscle.title + " · " + exercise.equipment.title)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .hubLineLimit(1, whenLarger: nil)
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .pulseFont(22, relativeTo: .title2)
                .foregroundStyle(isSelected ? PulseTheme.green : PulseTheme.inkTertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ exercise: Exercise) {
        if let index = selected.firstIndex(of: exercise.id) {
            selected.remove(at: index)
        } else {
            selected.append(exercise.id)
        }
    }

    private func confirm() {
        let all = store.exercises
        var chosen: [Exercise] = []
        for exerciseID in selected {
            if let exercise = all.first(where: { $0.id == exerciseID }) {
                chosen.append(exercise)
            }
        }
        onAdd(chosen)
        dismiss()
    }
}

// MARK: - History

/// "Recent Workouts" > "See All": every finished workout, newest first.
@MainActor
private struct HubHistoryListView: View {
    @ObservedObject var store: StrengthStore

    init(store: StrengthStore) {
        self._store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(store.history) { workout in
                    NavigationLink {
                        HubWorkoutDetailView(store: store, workoutID: workout.id)
                    } label: {
                        HubWorkoutRow(workout: workout)
                    }
                    .buttonStyle(PulsePlainButtonStyle())
                }
                if store.history.isEmpty {
                    Text("Finished workouts appear here.")
                        .pulseFont(15, relativeTo: .subheadline)
                        .foregroundStyle(PulseTheme.inkSecondary)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(PulseTheme.ground.ignoresSafeArea())
        .navigationTitle("Recent Workouts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A finished workout: figures, personal records, the sets of each exercise and the muscles worked.
@MainActor
private struct HubWorkoutDetailView: View {
    @ObservedObject var store: StrengthStore
    let workoutID: UUID

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(store: StrengthStore, workoutID: UUID) {
        self._store = ObservedObject(wrappedValue: store)
        self.workoutID = workoutID
    }

    private var workout: CompletedWorkout? {
        store.history.first { $0.id == workoutID }
    }

    var body: some View {
        detail
            .background(PulseTheme.ground.ignoresSafeArea())
            .navigationTitle(workout?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var detail: some View {
        if let workout = workout {
            content(workout)
        } else {
            Text("This workout is no longer available.")
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ workout: CompletedWorkout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(workout)
                statsCard(workout)
                ForEach(workout.personalRecords) { record in
                    recordCard(record)
                }
                exercisesSection(workout)
                musclesSection(workout)
            }
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func header(_ workout: CompletedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.name)
                .pulseNumber(28, relativeTo: .largeTitle)
                .foregroundStyle(PulseTheme.ink)
            Text(HubFormat.dateTime(workout.startedAt) + " · " + HubFormat.duration(seconds: workout.durationSeconds))
                .pulseFont(15, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsCard(_ workout: CompletedWorkout) -> some View {
        var stats: [HubStat] = [
            HubStat(title: "Duration", value: HubFormat.duration(seconds: workout.durationSeconds)),
            HubStat(title: "Volume", value: HubFormat.volume(workout.volumeKg)),
            HubStat(title: "Sets", value: "\(workout.loggedSets)")
        ]
        if let heartRate = workout.averageHeartRate {
            stats.append(HubStat(title: "Avg Heart Rate", value: "\(heartRate) bpm"))
        }
        if let rir = workout.averageRIR {
            stats.append(HubStat(title: "Avg RIR", value: NumberText.kg(((rir * 10).rounded()) / 10)))
        }
        let firstRow = Array(stats.prefix(3))
        let secondRow = Array(stats.dropFirst(3))
        return VStack(spacing: 10) {
            HubStatRow(stats: firstRow)
            if !secondRow.isEmpty {
                Rectangle()
                    .fill(PulseTheme.separator)
                    .frame(height: 0.5)
                HubStatRow(stats: secondRow)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubRowBackground()
    }

    private func recordCard(_ record: PersonalRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(PulseTheme.prText)
                .frame(width: 52, height: 52)
                .background(PulseTheme.prFill, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("New personal record")
                    .pulseFont(12, .semibold, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.prText)
                Text(record.exerciseName)
                    .pulseFont(17, .semibold, relativeTo: .headline)
                    .foregroundStyle(PulseTheme.ink)
                    .hubLineLimit(2, whenLarger: nil)
                Text(recordText(record))
                    .pulseNumber(15, .regular, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulseCard()
        .accessibilityElement(children: .combine)
    }

    private func recordText(_ record: PersonalRecord) -> String {
        let load = NumberText.kg(record.weightKg) + " kg × " + String(record.reps)
        return load + " · est. 1RM " + NumberText.kg(record.estimated1RM.rounded()) + " kg"
    }

    private func exercisesSection(_ workout: CompletedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HubSectionHeader(title: "Exercises")
            VStack(spacing: 0) {
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { pair in
                    exerciseLink(pair.element)
                        .hubSeparator(visible: pair.offset > 0, inset: 68)
                }
            }
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func exerciseLink(_ item: CompletedExercise) -> some View {
        if let exercise = store.exercise(id: item.exerciseID) {
            NavigationLink {
                ExerciseDetailView(exercise: exercise, store: store)
            } label: {
                exerciseRow(item, showsChevron: true)
            }
            .buttonStyle(PulsePlainButtonStyle())
        } else {
            exerciseRow(item, showsChevron: false)
        }
    }

    private func exerciseRow(_ item: CompletedExercise, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            ExerciseMediaView(mediaKey: item.mediaKey, cornerRadius: 10)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.ink)
                    .hubLineLimit(1, whenLarger: nil)
                if item.isPersonalRecord && dynamicTypeSize.isAccessibilitySize {
                    // The trailing edge is too narrow for the pill at these sizes: it sits under the name.
                    personalRecordPill
                }
                Text(HubFormat.setsText(item.sets, tracking: item.tracking))
                    .pulseNumber(12, .regular, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .hubLineLimit(2, whenLarger: nil)
            }
            Spacer(minLength: 8)
            if item.isPersonalRecord && !dynamicTypeSize.isAccessibilitySize {
                personalRecordPill
            }
            if showsChevron {
                HubChevron()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var personalRecordPill: some View {
        Text("PR")
            .pulseFont(11, .bold, relativeTo: .caption2)
            .foregroundStyle(PulseTheme.prText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PulseTheme.prFill, in: Capsule())
            .fixedSize()
    }

    @ViewBuilder
    private func musclesSection(_ workout: CompletedWorkout) -> some View {
        if !workout.muscleSets.isEmpty {
            let most = max(1, workout.muscleSets.map { $0.sets }.max() ?? 1)
            VStack(alignment: .leading, spacing: 12) {
                HubSectionHeader(title: "Muscles Worked")
                VStack(spacing: 14) {
                    ForEach(workout.muscleSets) { item in
                        VStack(spacing: 6) {
                            HStack {
                                Text(item.muscle.title)
                                    .pulseFont(12, .semibold, relativeTo: .footnote)
                                    .foregroundStyle(PulseTheme.ink)
                                Spacer(minLength: 8)
                                Text(item.sets == 1 ? "1 set" : "\(item.sets) sets")
                                    .pulseFont(12, relativeTo: .footnote)
                                    .foregroundStyle(PulseTheme.inkSecondary)
                            }
                            HubBar(fraction: Double(item.sets) / Double(most), color: PulseTheme.progress)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hubRowBackground()
            }
        }
    }
}

// MARK: - Recovery

/// "Muscle Recovery" > "View All": every muscle group with its recovery level.
@MainActor
private struct HubRecoveryView: View {
    let recovery: RecoveryProvider

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(HubMuscles.displayOrder.enumerated()), id: \.element.id) { pair in
                    row(pair.element)
                        .hubSeparator(visible: pair.offset > 0, inset: 16)
                }
            }
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(PulseTheme.ground.ignoresSafeArea())
        .navigationTitle("Muscle Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ muscle: MuscleGroup) -> some View {
        let percent = HubMuscles.percent(muscle, recovery)
        return VStack(alignment: .leading, spacing: 8) {
            rowTitle(muscle, percent: percent)
            HubBar(fraction: Double(percent) / 100, color: HubMuscles.color(percent))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(muscle.title + " recovery")
        .accessibilityValue("\(percent) percent, " + HubMuscles.levelTitle(percent))
    }

    /// Name, level and percentage on one line; at the accessibility text sizes the level and the percentage
    /// move to a second line under the name.
    @ViewBuilder
    private func rowTitle(_ muscle: MuscleGroup, percent: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                muscleName(muscle)
                HStack(spacing: 8) {
                    levelText(percent)
                    Spacer(minLength: 8)
                    percentText(percent)
                }
            }
        } else {
            HStack(spacing: 8) {
                muscleName(muscle)
                Spacer(minLength: 8)
                levelText(percent)
                percentText(percent)
            }
        }
    }

    private func muscleName(_ muscle: MuscleGroup) -> some View {
        Text(muscle.title)
            .pulseFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(PulseTheme.ink)
    }

    private func levelText(_ percent: Int) -> some View {
        Text(HubMuscles.levelTitle(percent))
            .pulseFont(12, relativeTo: .footnote)
            .foregroundStyle(PulseTheme.inkSecondary)
    }

    private func percentText(_ percent: Int) -> some View {
        Text("\(percent)%")
            .pulseNumber(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(PulseTheme.ink)
    }
}
#endif
