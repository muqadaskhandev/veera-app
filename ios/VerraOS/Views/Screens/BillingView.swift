//
//  BillingView.swift
//  VerraOS
//

import SwiftUI

struct BillingView: View {
    let isPaywall: Bool
    /// Called when the paywall's X is tapped. Dismisses the paywall for the
    /// current session only — it never logs the trainer out.
    var onDismiss: (() -> Void)? = nil

    @Environment(SubscriptionStore.self) private var subscription
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: SubscriptionPlan = .annual
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.lg) {
                    header
                    if isPaywall && !subscription.hasActiveSubscription {
                        urgencyBanner
                    }
                    if subscription.hasActiveSubscription && !isPaywall {
                        activeCard
                    } else {
                        features
                        planPicker
                        payButton
                    }
                    if subscription.hasActiveSubscription && !isPaywall {
                        features
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Color.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, isPaywall ? 12 : Theme.Spacing.lg)
                .padding(.bottom, 40)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if isPaywall {
                dismissBar
            }
        }
        .task {
            await subscription.loadPaymentConfig()
            await subscription.refreshFromServer()
        }
    }

    private var dismissBar: some View {
        HStack {
            Spacer()
            Button {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    .frame(width: 34, height: 34)
                    .background(Theme.Color.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .background(Theme.Color.background.opacity(0.96))
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(isPaywall ? "Your Clients Are Waiting" : "Verra Pro")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.Color.ink)
                .multilineTextAlignment(.center)
            Text(
                isPaywall
                    ? "Subscribe to Verra Pro to invite clients and keep scheduling, messaging, and billing without interruption."
                    : "Run your coaching business with scheduling, clients, messaging, and financials."
            )
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// Urgency framing for the paywall — a bold banner making the cost of
    /// inaction concrete, plus a limited-time discount callout.
    private var urgencyBanner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.Color.danger)
                Text("Access paused — clients can't book or message you")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.Color.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.danger.opacity(0.25), lineWidth: 1))

            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("LIMITED OFFER · SAVE 20% ON ANNUAL")
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundStyle(Theme.Color.accentInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.Color.accent, in: Capsule())
        }
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Choose billing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
                .textCase(.uppercase)
                .tracking(0.4)
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
                    HStack(spacing: 6) {
                        Text(plan.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.Color.ink)
                        if plan == .annual {
                            Text("BEST VALUE")
                                .font(.system(size: 9.5, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.Color.accentInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.Color.accent, in: Capsule())
                        }
                    }
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
                    .stroke(isSelected ? Theme.Color.accentInk.opacity(0.6) : Theme.Color.hairline, lineWidth: isSelected ? 1.6 : 1)
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
                    Text(isPurchasing ? "Processing…" : ctaTitle)
                        .font(.system(size: 16.5, weight: .bold))
                }
                .foregroundStyle(Theme.Color.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Theme.Color.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .shadow(color: Theme.Color.accent.opacity(0.55), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || !subscription.stripeConfigured)

            if isPaywall {
                Label("Cancel anytime — no long-term commitment", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.Color.inkMuted)
            }

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

    private var ctaTitle: String {
        isPaywall ? "Unlock Verra Pro Now" : "Pay with Apple Pay"
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Included with monthly & annual")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
                .textCase(.uppercase)
                .tracking(0.4)
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

