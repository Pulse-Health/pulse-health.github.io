#if os(iOS)
import SwiftUI
import PulseBillingCore

/// The subscription screen: plans, the legal text, the withdrawal consent and the buy button.
///
/// Put it in a sheet or a navigation destination and give it a view model made by `PulseBilling.makeViewModel`. When purchases
/// cannot be started in this storefront it shows a neutral line and no link or hint to buy elsewhere.
public struct PaywallView: View {
    @ObservedObject private var viewModel: BillingViewModel
    private let onFinished: () -> Void

    public init(viewModel: BillingViewModel, onFinished: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onFinished = onFinished
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding()
        }
        .onAppear { viewModel.start() }
    }

    private var strings: BillingStrings { viewModel.strings }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strings.paywallTitle)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(strings.paywallSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        case .purchasable(let offers):
            purchasable(offers)
        case .unavailable:
            unavailable
        case .working(let text):
            VStack(spacing: 12) {
                ProgressView()
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        case .activated:
            message(title: strings.activatedTitle, body: strings.activatedBody, symbol: "checkmark.seal.fill") {
                Button(strings.done) { onFinished() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .pending:
            message(title: strings.pendingTitle, body: strings.pendingBody, symbol: "clock.fill") {
                Button(strings.refresh) { Task { await viewModel.refresh() } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        case .failed(let text):
            message(title: strings.errorGeneric, body: text, symbol: "exclamationmark.triangle.fill") {
                Button(strings.tryAgain) { Task { await viewModel.refresh() } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }

    // MARK: Purchasable

    private func purchasable(_ offers: Offers) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(offers.plans) { plan in
                PlanRow(plan: plan, isSelected: plan.id == viewModel.selectedPlan?.id, strings: strings)
                    .onTapGesture { viewModel.selectedPlanID = plan.id }
            }

            if let plan = viewModel.selectedPlan {
                if plan.trialDays > 0 {
                    Text(strings.trialLine(plan.trialDays, BillingFormat.price(of: plan), strings.period(of: plan)))
                        .font(.callout.weight(.semibold))
                }
                if plan.taxBehavior == .inclusive {
                    Text(strings.taxIncludedNote).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Text(strings.renewalNote).font(.footnote).foregroundStyle(.secondary)

            if offers.requiresWithdrawalConsent {
                Toggle(isOn: $viewModel.consentTicked) {
                    Text(strings.consentText).font(.footnote)
                }
            }

            if let notice = viewModel.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel(notice)
            }

            Button(buyLabel) { viewModel.buy() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.canBuy)

            legalLinks
        }
    }

    private var buyLabel: String {
        (viewModel.selectedPlan?.trialDays ?? 0) > 0 ? strings.buyButtonWithTrial : strings.buyButton
    }

    @ViewBuilder
    private var legalLinks: some View {
        HStack(spacing: 16) {
            if let terms = viewModel.links.termsURL { Link(strings.termsLink, destination: terms) }
            if let privacy = viewModel.links.privacyURL { Link(strings.privacyLink, destination: privacy) }
        }
        .font(.footnote)
    }

    // MARK: Unavailable

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.unavailable)
                .font(.body)
                .foregroundStyle(.secondary)
            legalLinks
        }
    }

    // MARK: Messages

    private func message<Actions: View>(title: String, body: String, symbol: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(body).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

private struct PlanRow: View {
    let plan: Plan
    let isSelected: Bool
    let strings: BillingStrings

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(strings.title(of: plan)).font(.headline)
                Text("\(BillingFormat.price(of: plan)) \(strings.period(of: plan))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
#endif
