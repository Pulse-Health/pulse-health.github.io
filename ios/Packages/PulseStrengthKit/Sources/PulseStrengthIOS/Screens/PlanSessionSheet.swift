#if os(iOS)
import SwiftUI
import PulseStrengthActivity
import PulseStrengthCore

/// Plans a session for one template (widgets/SPEC.md LA-06): from that moment on a countdown shows on the Lock Screen and in the Dynamic Island,
/// and a notification tells the person when it is time. Planning again replaces the earlier plan; a workout that starts ends it.
struct PlanSessionSheet: View {
    let template: WorkoutTemplate

    @Environment(\.dismiss) private var dismiss
    @State private var startsAt: Date
    @State private var existing: PlannedSessionPlan?

    init(template: WorkoutTemplate) {
        self.template = template
        self._startsAt = State(initialValue: PlanSessionSheet.suggestedStart(after: Date()))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Starts", selection: $startsAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text(template.name)
                } footer: {
                    Text("A countdown appears on your Lock Screen and in the Dynamic Island, and a notification tells you when it is time.")
                }
                if let existing {
                    Section {
                        Button("Cancel the planned session", role: .destructive) {
                            PlannedSessionManager.shared.cancel()
                            dismiss()
                        }
                    } footer: {
                        Text("Planned: \(existing.state.templateName), \(existing.startsAt.formatted(date: .abbreviated, time: .shortened)).")
                    }
                }
            }
            .navigationTitle("Plan a session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Plan") {
                        if PlannedSessionManager.shared.schedule(template: template, startsAt: startsAt) {
                            dismiss()
                        }
                    }
                    .disabled(startsAt <= Date())
                }
            }
            .onAppear {
                existing = PlannedSessionManager.shared.plan
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The next full hour that is at least half an hour away.
    static func suggestedStart(after now: Date) -> Date {
        let earliest = now.addingTimeInterval(30 * 60)
        return Calendar.current.nextDate(after: earliest, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? earliest
    }
}
#endif
