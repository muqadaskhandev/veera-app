//
//  BillingView.swift
//  VerraOS
//

import SwiftUI

struct BillingView: View {
    let isPaywall: Bool

    @Environment(SubscriptionStore.self) private var subscription
    @State private var selectedPlan: SubscriptionPlan = .annual
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    if subscription.hasActiveSubscription && !isPaywall {
                        activeCard
                    } else {
                        planPicker
                        payButton
                    }
                    features
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Color.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, isPaywall ? 56 : Theme.Spacing.lg)
                .padding(.bottom, 40)
            }
        }
        .task {
            await subscription.loadPaymentConfig()
            await subscription.refreshFromServer()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(isPaywall ? "Unlock Verra Pro" : "Verra Pro")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
            Text("Run your coaching business with scheduling, clients, messaging, and financials.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Subscription active", systemImage: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk)
            Text(subscription.statusSubtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Color.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private var planPicker: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(SubscriptionPlan.allCases) { plan in
                planCard(plan)
            }
        }
    }

    private func planCard(_ plan: SubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedPlan = plan
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                    Text(plan.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                Spacer()
                Text(subscription.priceLabel(for: plan))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
            }
            .padding(Theme.Spacing.md)
            .background(isSelected ? Theme.Color.accent.opacity(0.35) : Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? Theme.Color.accentInk.opacity(0.35) : Theme.Color.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var payButton: some View {
        VStack(spacing: 10) {
            Button {
                Task { await purchase() }
            } label: {
                HStack(spacing: 10) {
                    if isPurchasing {
                        ProgressView()
                            .tint(Theme.Color.accentInk)
                    } else {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Text(isPurchasing ? "Processing…" : "Pay with Apple Pay")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Theme.Color.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.Color.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || !subscription.stripeConfigured)

            if !subscription.stripeConfigured {
                Text("Add your Stripe keys to the server environment to enable checkout.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .multilineTextAlignment(.center)
            } else {
                Text("You can also pay with a card in the payment sheet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow("calendar", "Schedule & calendar sync")
            featureRow("person.2.fill", "Unlimited clients")
            featureRow("message.fill", "Messaging & notifications")
            featureRow("chart.bar.fill", "Financial tracking")
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.ink)
        }
    }

    @MainActor
    private func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            try await subscription.purchase(plan: selectedPlan)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    BillingView(isPaywall: true)
        .environment(SubscriptionStore())
}
