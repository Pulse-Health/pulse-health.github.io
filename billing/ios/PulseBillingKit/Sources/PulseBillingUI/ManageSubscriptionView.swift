#if os(iOS)
import SwiftUI
import PulseBillingCore

/// Shows the subscription (status, renewal or end date) and lets the user cancel at the end of the period, undo that, or open the
/// Stripe customer portal for payment methods and invoices.
public struct ManageSubscriptionView: View {
    @ObservedObject private var viewModel: BillingViewModel
    @Environment(\.openURL) private var openURL
    @State private var confirmingCancel = false

    public init(viewModel: BillingViewModel) {
        self.viewModel = viewModel
    }

    private var strings: BillingStrings { viewModel.strings }

    public var body: some View {
        List {
            if let entitlement = viewModel.entitlement {
                details(entitlement)
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            if let notice = viewModel.notice {
                Text(notice).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle(strings.manageTitle)
        .task { await viewModel.refreshEntitlement() }
        .disabled(viewModel.isBusy)
        .confirmationDialog(strings.manageCancelConfirm, isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button(strings.manageCancel, role: .destructive) { viewModel.cancelSubscription() }
        } message: {
            Text(strings.manageCancelNote)
        }
    }

    @ViewBuilder
    private func details(_ entitlement: Entitlement) -> some View {
        switch entitlement.source {
        case .stripe where entitlement.status != .none && entitlement.status != .canceled:
            Section {
                row(strings.manageStatusLabel, strings.statusText(entitlement.status))
                if let date = dateRow(entitlement) {
                    row(date.label, date.value)
                }
            }
            Section {
                if entitlement.cancelAtPeriodEnd {
                    Text(strings.manageCancelNote).font(.footnote).foregroundStyle(.secondary)
                    Button(strings.manageResume) { viewModel.resumeSubscription() }
                } else {
                    Button(strings.manageCancel, role: .destructive) { confirmingCancel = true }
                }
                Button(strings.managePortal) {
                    Task {
                        if let url = await viewModel.portalURL() { openURL(url) }
                    }
                }
            }
        case .code where entitlement.premium:
            Section {
                Text(strings.manageViaCode)
                if let until = entitlement.premiumUntil {
                    row(strings.manageEnds, until.formatted(date: .long, time: .omitted))
                }
            }
        default:
            Section { Text(strings.manageNone).foregroundStyle(.secondary) }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func dateRow(_ entitlement: Entitlement) -> (label: String, value: String)? {
        if entitlement.status == .trialing, let end = entitlement.trialEnd {
            return (strings.manageTrialEnds, end.formatted(date: .long, time: .omitted))
        }
        guard let end = entitlement.currentPeriodEnd else { return nil }
        let label = entitlement.cancelAtPeriodEnd ? strings.manageEnds : strings.manageRenews
        return (label, end.formatted(date: .long, time: .omitted))
    }
}
#endif
