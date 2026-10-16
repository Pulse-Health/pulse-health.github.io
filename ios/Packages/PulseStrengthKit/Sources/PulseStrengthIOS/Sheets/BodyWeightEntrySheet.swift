#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Sheet

/// Enter a body weight: the weight in kg (the decimal keypad, "82.5" or "82,5"), the date (today by default, never in the future)
/// and Save. The field starts with the latest weight, selected for typing, so an update is a few taps.
///
/// Saving stores the weight with `StrengthStore.recordBodyWeight`, which also moves the next weigh-in reminder out.
@MainActor
struct BodyWeightEntrySheet: View {
    @ObservedObject private var store: StrengthStore

    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var date = Date()
    @FocusState private var isFocused: Bool

    init(store: StrengthStore) {
        self._store = ObservedObject(wrappedValue: store)
        let latest = store.latestBodyWeight
        self._text = State(initialValue: latest.map { NumberText.kg($0.kg) } ?? "")
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    weightCard
                    dateCard
                    hint
                }
                .padding(.horizontal, PulseTheme.screenInset)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(PulseTheme.ground.ignoresSafeArea())
            .navigationTitle("Body Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("weight-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(parsed == nil)
                    .accessibilityIdentifier("weight-save")
                }
            }
        }
        .tint(PulseTheme.green)
        .dynamicTypeSize(PulseDynamicType.screenRange)
        .presentationDetents([.medium, .large])
        .onAppear {
            isFocused = true
        }
    }

    // MARK: Cards

    private var weightCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField("0.0", text: $text)
                .keyboardType(.decimalPad)
                .focused($isFocused)
                .multilineTextAlignment(.trailing)
                .pulseNumber(44, .bold, relativeTo: .largeTitle)
                .foregroundStyle(PulseTheme.ink)
                .accessibilityLabel("Weight in kilograms")
                .accessibilityIdentifier("weight-field")
            Text("kg")
                .pulseFont(20, .semibold, relativeTo: .title3)
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: PulseTheme.cardRadius, style: .continuous))
    }

    private var dateCard: some View {
        DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            .pulseFont(17, relativeTo: .body)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: PulseTheme.listRadius, style: .continuous))
    }

    @ViewBuilder
    private var hint: some View {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty, parsed == nil {
            Text("Enter a weight between \(Int(BodyWeightRules.minimumKg)) and \(Int(BodyWeightRules.maximumKg)) kg.")
                .pulseFont(13, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.destructive)
        } else if let latest = store.latestBodyWeight {
            Text("Last: " + NumberText.kg(latest.kg) + " kg · " + StrengthResultText.monthDay(latest.date, now: Date()))
                .pulseFont(13, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
        }
    }

    // MARK: Actions

    private var parsed: Double? {
        BodyWeightRules.parse(text)
    }

    private func save() {
        guard let kg = parsed else { return }
        store.recordBodyWeight(kg: kg, date: date)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
#endif
