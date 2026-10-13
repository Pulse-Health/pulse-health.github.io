#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Sheets

/// Everything the active-workout screen presents in a sheet. One sheet at a time.
public enum ActiveSheet: Identifiable {
    /// Edit exercises: reorder, options, "Add Exercise".
    case list
    /// Add exercises, or replace one exercise.
    case picker(PickerMode)
    /// Weight / reps keypad for one set.
    case keypad(SetRef, KeypadField)
    /// Set type, reps in reserve, delete.
    case setDetail(SetRef)
    /// Rest timer presets for one workout exercise (plus the two workout-wide toggles).
    case restSettings(UUID)
    /// Form demo and cues.
    case info(Exercise)

    public var id: String {
        switch self {
        case .list:
            return "list"
        case .picker(let mode):
            switch mode {
            case .add:
                return "picker-add"
            case .replace(let exerciseID):
                return "picker-replace-" + exerciseID.uuidString
            }
        case .keypad(let ref, _):
            return "keypad-" + ref.exerciseID.uuidString + "-" + ref.setID.uuidString
        case .setDetail(let ref):
            return "set-" + ref.exerciseID.uuidString + "-" + ref.setID.uuidString
        case .restSettings(let exerciseID):
            return "rest-" + exerciseID.uuidString
        case .info(let exercise):
            return "info-" + exercise.id
        }
    }
}

// MARK: - Screen

/// The active-workout screen: header, optional Watch banner, exercise navigator, the exercise card,
/// the rest dock and the undo toast, plus every sheet, dialog and alert of the feature.
/// It only renders `ActiveWorkoutPresentation` and dispatches `WorkoutAction`s.
@MainActor
public struct ActiveWorkoutView: View {
    @ObservedObject private var controller: WorkoutController
    private let store: StrengthStore
    private let onMinimise: () -> Void
    private let onFinished: (CompletedWorkout?) -> Void

    @Environment(\.watchStatus) private var watchStatus
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeSheet: ActiveSheet?
    @State private var optionsExerciseID: UUID?
    @State private var showMoreMenu = false
    @State private var showFinishDialog = false
    @State private var showDiscardAlert = false
    @State private var showTemplateAlert = false
    @State private var dismissedWatchStatus: WatchStatus?
    /// Set once the workout is finished or discarded here, so the empty state that follows does not minimise as well.
    @State private var didEnd = false

    public init(
        controller: WorkoutController,
        store: StrengthStore,
        onMinimise: @escaping () -> Void,
        onFinished: @escaping (CompletedWorkout?) -> Void
    ) {
        self._controller = ObservedObject(wrappedValue: controller)
        self.store = store
        self.onMinimise = onMinimise
        self.onFinished = onFinished
    }

    // MARK: Body

    public var body: some View {
        let snapshot = controller.presentation(now: Date())
        return ZStack {
            groundLayer
            clockedScreen(snapshot: snapshot)
        }
        // The dock and the lists sit at fixed distances from the physical bottom edge (as in the design);
        // the keyboard still pushes the content up.
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .confirmationDialog(moreMenuTitle, isPresented: $showMoreMenu, titleVisibility: .visible) {
            moreMenuActions
        }
        .alert("Discard workout?", isPresented: $showDiscardAlert) {
            discardAlertActions
        } message: {
            Text(discardMessage(snapshot))
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Background colour, and the host of the exercise options dialog.
    private var groundLayer: some View {
        PulseTheme.ground
            .ignoresSafeArea()
            .exerciseOptionsDialog(
                controller: controller,
                exerciseID: $optionsExerciseID,
                onShowInfo: { (exercise: Exercise) in
                    presentAfterDismissal { activeSheet = .info(exercise) }
                },
                onShowRestSettings: { (exerciseID: UUID) in
                    presentAfterDismissal { activeSheet = .restSettings(exerciseID) }
                },
                onReplace: { (exerciseID: UUID) in
                    presentAfterDismissal { activeSheet = .picker(.replace(exerciseID: exerciseID)) }
                }
            )
    }

    /// The screen proper, redrawn every second (workout clock, rest countdown, undo expiry),
    /// and the host of the finish dialog and the "Update template?" alert.
    private func clockedScreen(snapshot: ActiveWorkoutPresentation?) -> some View {
        let check = snapshot?.finishCheck
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            screen(now: context.date)
        }
        .confirmationDialog(check?.title ?? "Finish workout?", isPresented: $showFinishDialog, titleVisibility: .visible) {
            finishDialogActions(check)
        } message: {
            Text(check?.message ?? "")
        }
        .alert(templateAlertTitle(snapshot), isPresented: $showTemplateAlert) {
            templateAlertActions
        } message: {
            Text(templateAlertMessage(check))
        }
    }

    @ViewBuilder
    private func screen(now: Date) -> some View {
        if let presentation = controller.presentation(now: now) {
            content(presentation)
        } else {
            // No active workout (finished or discarded elsewhere): leave the screen.
            Color.clear
                .onAppear {
                    if !didEnd {
                        onMinimise()
                    }
                }
        }
    }

    private func content(_ presentation: ActiveWorkoutPresentation) -> some View {
        VStack(spacing: 0) {
            ActiveHeaderView(
                header: presentation.header,
                onMinimise: onMinimise,
                onMore: { showMoreMenu = true },
                onFinish: { showFinishDialog = true }
            )
            watchBanner
            mainArea(presentation)
            dockArea(presentation.dock)
        }
        .overlay(alignment: .bottom) {
            toastLayer(presentation)
        }
        .onChange(of: presentation.dock?.phase) { oldPhase, newPhase in
            restPhaseChanged(from: oldPhase, to: newPhase)
        }
        .animation(layoutAnimation, value: presentation.dock != nil)
    }

    // MARK: Watch banner

    @ViewBuilder
    private var watchBanner: some View {
        if watchStatus != .connected && dismissedWatchStatus != watchStatus {
            WatchBannerView(
                status: watchStatus,
                onAction: { openWatchBannerTarget() },
                onDismiss: { dismissedWatchStatus = watchStatus }
            )
            .padding(.horizontal, PulseTheme.screenInset)
            .padding(.top, 8)
        }
    }

    private func openWatchBannerTarget() {
        let target: String
        switch watchStatus {
        case .healthDenied:
            target = UIApplication.openSettingsURLString
        case .notConnected:
            target = "itms-watch://"
        case .connected:
            return
        }
        if let url = URL(string: target) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Main area (navigator, card, empty state)

    @ViewBuilder
    private func mainArea(_ presentation: ActiveWorkoutPresentation) -> some View {
        VStack(spacing: 10) {
            if let navigator = presentation.navigator {
                NavigatorBar(
                    navigator: navigator,
                    onPrevious: { send(.previousExercise) },
                    onNext: { send(.nextExercise) },
                    onEdit: { activeSheet = .list }
                )
            }
            if let card = presentation.card {
                ExerciseCardView(card: card, controller: controller, actions: cardActions)
                    .id(card.exerciseID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if presentation.isEmpty {
                ActiveEmptyStateCard(onAdd: { activeSheet = .picker(.add) })
                    .padding(.top, 40)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, PulseTheme.screenInset)
        .padding(.top, 10)
        .padding(.bottom, presentation.dock == nil ? 30 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cardActions: ExerciseCardActions {
        ExerciseCardActions(
            openKeypad: { (ref: SetRef, field: KeypadField) in
                activeSheet = .keypad(ref, field)
            },
            openSetDetail: { (ref: SetRef) in
                activeSheet = .setDetail(ref)
            },
            showInfo: { (exercise: Exercise) in
                activeSheet = .info(exercise)
            },
            showOptions: { (exerciseID: UUID) in
                optionsExerciseID = exerciseID
            },
            showRestSettings: { (exerciseID: UUID) in
                activeSheet = .restSettings(exerciseID)
            }
        )
    }

    // MARK: Dock and toast

    @ViewBuilder
    private func dockArea(_ dock: ActiveWorkoutPresentation.Dock?) -> some View {
        if let dock = dock {
            RestDockView(
                dock: dock,
                onAdjust: { (seconds: Int) in send(.adjustRest(seconds: seconds)) },
                onSkip: { send(.skipRest) },
                onSelectRIR: { (value: Int) in send(.toggleLastSetRIR(value)) }
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 22)
            .transition(dockTransition)
        }
    }

    private var dockTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .bottom).combined(with: .opacity)
    }

    private var layoutAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.25)
    }

    private var toastTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .move(edge: .bottom).combined(with: .opacity)
    }

    /// Distance of the toast from the bottom edge of the screen: above the dock (and its
    /// "Reps left" row when that is showing), or near the bottom without a dock.
    private func toastBottomInset(_ dock: ActiveWorkoutPresentation.Dock?) -> CGFloat {
        guard let dock = dock else { return 34 }
        return dock.showsRIR ? 158 : 108
    }

    private func toastLayer(_ presentation: ActiveWorkoutPresentation) -> some View {
        ZStack {
            if let text = presentation.undoText {
                UndoToastView(text: text, onUndo: { send(.undo) })
                    .padding(.horizontal, PulseTheme.screenInset)
                    .transition(toastTransition)
            }
        }
        .padding(.bottom, toastBottomInset(presentation.dock))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: presentation.undoText)
    }

    /// Haptic when the rest countdown reaches zero while the app is in the foreground.
    private func restPhaseChanged(
        from oldPhase: ActiveWorkoutPresentation.DockPhase?,
        to newPhase: ActiveWorkoutPresentation.DockPhase?
    ) {
        guard oldPhase == .running, newPhase == .finished else { return }
        guard scenePhase == .active else { return }
        let alertsEnabled = controller.state?.settings.alertWhenRestEnds ?? true
        guard alertsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Rest over")
    }

    // MARK: More menu

    private var currentWorkoutName: String {
        controller.state?.name ?? ""
    }

    private var moreMenuTitle: String {
        currentWorkoutName
    }

    private var isPausedNow: Bool {
        controller.state?.isPaused ?? false
    }

    private var currentExerciseID: UUID? {
        controller.state?.currentExercise?.id
    }

    private var pauseMenuTitle: String {
        isPausedNow ? "Resume workout" : "Pause workout"
    }

    @ViewBuilder
    private var moreMenuActions: some View {
        Button(pauseMenuTitle) {
            togglePause()
        }
        Button("Edit exercises") {
            presentAfterDismissal { activeSheet = .list }
        }
        Button("Add exercise") {
            presentAfterDismissal { activeSheet = .picker(.add) }
        }
        if let exerciseID = currentExerciseID {
            Button("Rest timer settings") {
                presentAfterDismissal { activeSheet = .restSettings(exerciseID) }
            }
        }
        Button("Discard workout", role: .destructive) {
            presentAfterDismissal { showDiscardAlert = true }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func togglePause() {
        if isPausedNow {
            send(.resume)
        } else {
            send(.pause)
        }
    }

    // MARK: Finish and discard

    @ViewBuilder
    private func finishDialogActions(_ check: ActiveWorkoutPresentation.FinishCheck?) -> some View {
        if let check = check, check.canFinish {
            Button("Finish Workout") {
                confirmFinish()
            }
        }
        Button("Keep Training", role: .cancel) {}
        Button("Discard Workout", role: .destructive) {
            presentAfterDismissal { showDiscardAlert = true }
        }
    }

    private func confirmFinish() {
        guard let check = controller.presentation(now: Date())?.finishCheck, check.canFinish else { return }
        if check.asksToUpdateTemplate {
            presentAfterDismissal { showTemplateAlert = true }
        } else {
            completeFinish(updateTemplate: false)
        }
    }

    private func completeFinish(updateTemplate: Bool) {
        didEnd = true
        let completed = controller.finish(updateTemplate: updateTemplate)
        onFinished(completed)
    }

    private func templateAlertTitle(_ snapshot: ActiveWorkoutPresentation?) -> String {
        let name = snapshot?.header.title ?? currentWorkoutName
        return "Update \u{201C}\(name)\u{201D}?"
    }

    private func templateAlertMessage(_ check: ActiveWorkoutPresentation.FinishCheck?) -> String {
        guard let check = check else { return "" }
        return check.diffMessage + " Save this exercise list for your next workouts?"
    }

    @ViewBuilder
    private var templateAlertActions: some View {
        Button("Update Template") {
            completeFinish(updateTemplate: true)
        }
        Button("Only This Workout") {
            completeFinish(updateTemplate: false)
        }
        Button("Back to Workout", role: .cancel) {}
    }

    @ViewBuilder
    private var discardAlertActions: some View {
        Button("Cancel", role: .cancel) {}
        Button("Discard", role: .destructive) {
            performDiscard()
        }
    }

    private func discardMessage(_ snapshot: ActiveWorkoutPresentation?) -> String {
        let logged = snapshot?.totals.loggedSets ?? 0
        if logged == 0 {
            return "Nothing has been logged yet."
        }
        return "You will lose \(logged) logged " + (logged == 1 ? "set." : "sets.")
    }

    private func performDiscard() {
        didEnd = true
        controller.discard()
        onFinished(nil)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .list:
            sheetStyled(ExerciseListSheet(controller: controller, store: store), detents: [.large])
        case .picker(let mode):
            sheetStyled(ExercisePickerSheet(store: store, controller: controller, mode: mode), detents: [.large])
        case .keypad(let ref, let field):
            sheetStyled(
                KeypadSheet(controller: controller, ref: ref, initialField: field),
                detents: [.height(ActiveSheetHeight.keypad), .large]
            )
        case .setDetail(let ref):
            sheetStyled(
                SetDetailSheet(controller: controller, ref: ref),
                detents: [.height(ActiveSheetHeight.setDetail), .large]
            )
        case .restSettings(let exerciseID):
            sheetStyled(
                RestSettingsSheet(controller: controller, exerciseID: exerciseID),
                detents: [.height(ActiveSheetHeight.restSettings), .large]
            )
        case .info(let exercise):
            sheetStyled(FormInfoSheet(exercise: exercise), detents: [.large])
        }
    }

    /// The shared look of the sheets: 26 pt top corners, grouped-grey background, no grabber
    /// (each sheet has its own Done / Cancel button).
    private func sheetStyled<Content: View>(_ content: Content, detents: Set<PresentationDetent>) -> some View {
        content
            .presentationDetents(detents)
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(PulseTheme.sheetRadius)
            .presentationBackground(PulseTheme.ground)
    }

    // MARK: Helpers

    private func send(_ action: WorkoutAction) {
        controller.send(action)
    }

    /// Runs `work` once a dialog that is being dismissed has gone, so a sheet or alert opened from
    /// a dialog button is not dropped by SwiftUI's presentation machinery.
    private func presentAfterDismissal(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            work()
        }
    }
}

/// Heights of the bottom sheets (the sheet can still be dragged up to the full height).
private enum ActiveSheetHeight {
    static let keypad: CGFloat = 650
    static let setDetail: CGFloat = 560
    static let restSettings: CGFloat = 420
}

// MARK: - Empty state

/// "No exercises yet" card with the Add Exercise button, shown when the workout has no exercises.
private struct ActiveEmptyStateCard: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(PulseTheme.greenTint)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(PulseTheme.green)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            Text("No exercises yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PulseTheme.ink)
                .accessibilityAddTraits(.isHeader)

            Text("Add an exercise from the library, or create your own, to start logging sets.")
                .font(PulseFont.subhead)
                .foregroundStyle(PulseTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAdd) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                    Text("Add Exercise")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(PulseTheme.onGreen)
                .padding(.horizontal, 24)
                .frame(height: 48)
                .background(PulseTheme.green, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(PulsePlainButtonStyle())
            .padding(.top, 6)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .pulseCard()
    }
}
#endif
