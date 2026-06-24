//
//  OnboardingView.swift
//  VerraOS
//
//  A guided, multi-step onboarding flow shown the first time a role is chosen.
//  Trainer flow: invite code -> three styled app previews -> a friendly HELLO
//  intro -> a numbered questionnaire -> a notifications primer -> a placeholder
//  account registration screen. Visual style matches WelcomeView (dark, video-
//  backed, electric-lime accent, bold rounded type).
//

import SwiftUI
import UserNotifications

/// Which experience the onboarding flow is tailoring itself to.
enum OnboardingRole {
    case trainer
    case client
}

/// A run of headline text that may be drawn in the accent color.
private struct Seg {
    let text: String
    let accent: Bool
    init(_ text: String, accent: Bool = false) {
        self.text = text
        self.accent = accent
    }
}

/// A single tappable option in a questionnaire step.
private struct OBOption: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    init(_ title: String, _ subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
}

/// A numbered questionnaire step.
private struct OBQuestion {
    let key: String
    let number: Int
    let headline: [Seg]
    let options: [OBOption]
}

/// The distinct screens that can appear in the flow.
private enum OBScreen {
    case invite
    case preview(mock: PreviewMock, page: Int, headline: [Seg])
    case hello
    case question(OBQuestion)
    case notifications(number: Int)
    case register
}

/// Which lightweight in-app mockup a preview screen renders.
private enum PreviewMock {
    case clientProfile
    case financials
    case messages
}

struct OnboardingView: View {
    let role: OnboardingRole
    /// Called when the flow finishes (or is skipped). Carries the collected
    /// profile name and, for clients, their primary goal. The redesigned flow
    /// no longer collects these, so both are passed empty.
    var onFinish: (_ name: String, _ goal: String) -> Void

    @State private var index = 0
    @State private var appeared = false
    @State private var answers: [String: UUID] = [:]
    @State private var notificationsResolved = false
    @State private var notificationsDenied = false
    @State private var agreedToComms = true

    private let questionTotal = 7

    // MARK: Screen list

    private var screens: [OBScreen] {
        // Clients only confirm an invite code, then drop straight into the app.
        if role == .client {
            return [.invite]
        }
        return [
            .invite,
            .preview(
                mock: .clientProfile,
                page: 0,
                headline: [
                    Seg("Access "),
                    Seg("complete client profiles", accent: true),
                    Seg(", progress notes, and histories instantly from your "),
                    Seg("central trainer hub", accent: true),
                    Seg("."),
                ]
            ),
            .preview(
                mock: .financials,
                page: 1,
                headline: [
                    Seg("Track your "),
                    Seg("training packages and balances", accent: true),
                    Seg(" effortlessly. View "),
                    Seg("clear financial histories", accent: true),
                    Seg(" without long, cluttered screens."),
                ]
            ),
            .preview(
                mock: .messages,
                page: 2,
                headline: [
                    Seg("Eliminate "),
                    Seg("messy text threads", accent: true),
                    Seg(" and spreadsheets. See your schedule, notes, and metrics in "),
                    Seg("one clean app", accent: true),
                    Seg("."),
                ]
            ),
            .hello,
            .question(OBQuestion(
                key: "gender", number: 1,
                headline: [Seg("Help us "), Seg("tailor the experience", accent: true), Seg(" for you")],
                options: [OBOption("Male"), OBOption("Female")]
            )),
            .question(OBQuestion(
                key: "tenure", number: 2,
                headline: [Seg("How long have you been a "), Seg("personal trainer", accent: true), Seg("?")],
                options: [
                    OBOption("Less than 1 year"),
                    OBOption("1–3 years"),
                    OBOption("3–5 years"),
                    OBOption("5+ years"),
                ]
            )),
            .question(OBQuestion(
                key: "location", number: 3,
                headline: [Seg("Where do you primarily "), Seg("train your clients", accent: true), Seg("?")],
                options: [
                    OBOption("Commercial Gym", "Big-box or chain facilities"),
                    OBOption("Private / Boutique Studio", "Smaller, dedicated training spaces"),
                    OBOption("Home Gym / Client Homes", "In-person at your or their place"),
                    OBOption("Online / Remote Only", "Coaching delivered fully remotely"),
                ]
            )),
            .question(OBQuestion(
                key: "clients", number: 4,
                headline: [Seg("How many "), Seg("active clients", accent: true), Seg(" do you currently manage?")],
                options: [
                    OBOption("1–5 clients"),
                    OBOption("6–15 clients"),
                    OBOption("16–30 clients"),
                    OBOption("31+ clients"),
                ]
            )),
            .question(OBQuestion(
                key: "focus", number: 5,
                headline: [Seg("What is your primary "), Seg("coaching focus", accent: true), Seg("?")],
                options: [
                    OBOption("Strength & Muscle Building", "Hypertrophy and getting stronger"),
                    OBOption("Weight Loss & Toning", "Fat loss and body composition"),
                    OBOption("Athletic Performance", "Speed, power, and sport-specific"),
                    OBOption("General Health & Longevity", "Wellness, mobility, and healthy aging"),
                ]
            )),
            .question(OBQuestion(
                key: "referral", number: 6,
                headline: [Seg("How did you "), Seg("hear about us", accent: true), Seg("?")],
                options: [
                    OBOption("Word of mouth / Another trainer"),
                    OBOption("Instagram / Social media"),
                    OBOption("Online search"),
                    OBOption("Other"),
                ]
            )),
            .notifications(number: 7),
            .register,
        ]
    }

    private var current: OBScreen { screens[index] }
    private var isFirst: Bool { index == 0 }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 28)
                    .padding(.top, 4)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomBar
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.05)) { appeared = true }
        }
    }

    // MARK: Top bar

    @ViewBuilder
    private var topBar: some View {
        switch current {
        case .preview(_, let page, _):
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Theme.Color.accent : .white.opacity(0.25))
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
                }
                Spacer()
            }
            .frame(height: 28)
            .padding(.top, 8)
        default:
            Color.clear.frame(height: 8)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch current {
        case .invite:
            inviteBody
        case .preview(let mock, _, let headline):
            previewBody(mock: mock, headline: headline)
        case .hello:
            helloBody
        case .question(let q):
            questionBody(q)
        case .notifications(let number):
            notificationsBody(number: number)
        case .register:
            registerBody
        }
    }

    // MARK: Invite

    private var inviteBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            headlineText([
                Seg("Have an "),
                Seg("invite code", accent: true),
                Seg("?"),
            ])
            Text("Enter the code from your trainer or studio. No code? You can skip this for now.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 14)

            InviteCodeField()
                .padding(.top, 28)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Preview

    private func previewBody(mock: PreviewMock, headline: [Seg]) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            PhoneFrame { mockContent(mock) }
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)
            Spacer(minLength: 16)
            headlineText(headline, size: 27)
                .padding(.horizontal, 28)
            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private func mockContent(_ mock: PreviewMock) -> some View {
        switch mock {
        case .clientProfile: ClientProfileMock()
        case .financials: FinancialsMock()
        case .messages: MessagesMock()
        }
    }

    // MARK: Hello

    private var helloBody: some View {
        ZStack {
            Image(systemName: "gearshape")
                .font(.system(size: 320, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.04))
                .offset(y: 120)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                HStack(spacing: 10) {
                    Text("HELLO!")
                        .font(.system(size: 68, weight: .black))
                        .fontWidth(.condensed)
                        .foregroundStyle(Theme.Color.accent)
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(appeared ? 0 : -18))
                        .animation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.2), value: appeared)
                }

                (
                    Text("To get started, ").foregroundStyle(.white).fontWeight(.heavy)
                    + Text("we'd like to ask you a couple questions.").foregroundStyle(.white.opacity(0.85))
                )
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .padding(.top, 26)

                Text("Your answers will help our system craft the ultimate training experience for you.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 18)

                Spacer()
                Spacer()
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Question

    private func questionBody(_ q: OBQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressRing(number: q.number, total: questionTotal)
                .padding(.top, 8)

            headlineText(q.headline, size: 30)
                .padding(.top, 22)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    ForEach(q.options) { option in
                        OptionCard(
                            option: option,
                            isSelected: answers[q.key] == option.id
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                answers[q.key] = option.id
                            }
                        }
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 28)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Notifications primer

    private func notificationsBody(number: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressRing(number: number, total: questionTotal)
                .padding(.top, 8)

            headlineText([
                Seg("For the "),
                Seg("best coaching experience", accent: true),
                Seg(", enable push notifications"),
            ], size: 30)
            .padding(.top, 22)

            Text("Get instant updates when clients message you, book sessions, or request schedule changes.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 16)

            if notificationsDenied {
                Text("You declined push notifications. To change it, go to your system Settings.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                    .padding(.top, 22)
            } else {
                Button(action: requestNotifications) {
                    HStack(spacing: 10) {
                        Image(systemName: notificationsResolved ? "checkmark.circle.fill" : "bell.badge.fill")
                        Text(notificationsResolved ? "Notifications Enabled" : "Enable Notifications")
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(notificationsResolved ? Theme.Color.accent : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .overlay(Capsule().stroke(notificationsResolved ? Theme.Color.accent.opacity(0.6) : .white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(notificationsResolved)
                .padding(.top, 28)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Register

    private var registerBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            (
                Text("Register your account\n").foregroundStyle(.white)
                + Text("to save these settings").foregroundStyle(.white.opacity(0.45))
            )
            .font(.system(size: 36, weight: .black))
            .fontWidth(.condensed)
            .textCase(.uppercase)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 14) {
                Button(action: finish) {
                    HStack(spacing: 12) {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.Color.accentInk)
                        Text("Continue with Google")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: finish) {
                    Text("Continue with Email")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 36)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { agreedToComms.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: agreedToComms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(agreedToComms ? Theme.Color.accent : .white.opacity(0.5))
                        .scaleEffect(agreedToComms ? 1.05 : 1)
                    Text("By continuing, you agree to receive communications from Verra.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(agreedToComms ? .white : .white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(agreedToComms ? Theme.Color.accent.opacity(0.12) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(agreedToComms ? Theme.Color.accent.opacity(0.5) : .white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 26)

            Spacer()

            Text("By continuing, you agree to our **Terms of Use and Privacy Policy**")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        switch current {
        case .register:
            // Register has its own buttons; only a small back control here.
            HStack {
                if !isFirst { backButton }
                Spacer()
            }
        case .hello:
            controlRow(label: "I'M READY")
        case .invite:
            controlRow(label: "Continue")
        case .preview:
            controlRow(label: "Next")
        case .question:
            controlRow(label: "Next")
        case .notifications:
            controlRow(label: "Next")
        }
    }

    private func controlRow(label: String) -> some View {
        HStack(spacing: 14) {
            if !isFirst { backButton }
            Button(action: advance) {
                Text(label)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var backButton: some View {
        Button(action: goBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func advance() {
        if index >= screens.count - 1 {
            finish()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                index += 1
                appeared = false
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.05)) { appeared = true }
        }
    }

    private func goBack() {
        guard index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            index -= 1
            appeared = false
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.05)) { appeared = true }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            Task { @MainActor in
                notificationsResolved = granted
                notificationsDenied = !granted
            }
        }
    }

    private func finish() {
        onFinish("", "")
    }

    // MARK: Headline helper

    private func headlineText(_ segs: [Seg], size: CGFloat = 34) -> some View {
        segs.reduce(Text("")) { partial, seg in
            partial + Text(seg.text).foregroundColor(seg.accent ? Theme.Color.accent : .white)
        }
        .font(.system(size: size, weight: .black))
        .fontWidth(.condensed)
        .textCase(.uppercase)
        .lineSpacing(1)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Progress ring

private struct ProgressRing: View {
    let number: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(number) / CGFloat(total))
                .stroke(Theme.Color.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: number)
            Text("\(number)")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 66, height: 66)
    }
}

// MARK: - Option card

private struct OptionCard: View {
    let option: OBOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(option.title)
                        .font(.system(size: 20, weight: .black))
                        .fontWidth(.condensed)
                        .textCase(.uppercase)
                        .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.accent)
                    if let subtitle = option.subtitle {
                        Text(subtitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(isSelected ? Theme.Color.accentInk.opacity(0.8) : .white.opacity(0.8))
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.Color.accentInk)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, option.subtitle == nil ? 22 : 20)
            .background(
                (isSelected ? Theme.Color.accent : Color.white.opacity(0.06)),
                in: RoundedRectangle(cornerRadius: Theme.Radius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? Theme.Color.accent : .white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Invite code field

private struct InviteCodeField: View {
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.Color.accent)
            TextField("", text: $code, prompt: Text("INVITE CODE").foregroundColor(.white.opacity(0.4)))
                .focused($focused)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .tracking(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(focused ? Theme.Color.accent : .white.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Phone frame

private struct PhoneFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: 232, height: 372)
            .background(Theme.Color.background)
            .clipShape(.rect(cornerRadius: 34))
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(.black, lineWidth: 10))
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 28, x: 0, y: 18)
    }
}

// MARK: - Mockups

private struct ClientProfileMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.Color.accent.opacity(0.25))
                    .frame(width: 44, height: 44)
                    .overlay(Text("JM").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.Color.ink))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jordan Miles")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text("Fat Loss · Member since 2024")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
                Spacer()
            }
            .padding(14)

            HStack(spacing: 8) {
                statTile("24", "Sessions")
                statTile("12", "Week streak")
                statTile("82%", "Adherence")
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("PROGRESS NOTES")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.Color.inkMuted)
                ForEach(["Improved squat depth", "Bumped protein to 160g", "Sleep trending up"], id: \.self) { line in
                    HStack(spacing: 8) {
                        Circle().fill(Theme.Color.accent).frame(width: 6, height: 6)
                        Text(line)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Color.ink)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.surface)
            .clipShape(.rect(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()
        }
        .padding(.top, 14)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Color.ink)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.Color.surface)
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct FinancialsMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OUTSTANDING BALANCE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.Color.accentInk.opacity(0.7))
                Text("$480.00")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.Color.accentInk)
                Text("Next payment due Jun 30")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentInk.opacity(0.8))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.accent)
            .clipShape(.rect(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 10) {
                Text("HISTORY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.Color.inkMuted)
                historyRow("12-Session Pack", "+$960", paid: true)
                historyRow("Single Session", "+$80", paid: true)
                historyRow("Monthly Coaching", "$480", paid: false)
                historyRow("8-Session Pack", "+$640", paid: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.surface)
            .clipShape(.rect(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()
        }
    }

    private func historyRow(_ title: String, _ amount: String, paid: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text(paid ? "Paid" : "Pending")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(paid ? Theme.Color.inkMuted : Theme.Color.danger)
            }
            Spacer()
            Text(amount)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(paid ? Theme.Color.ink : Theme.Color.danger)
        }
    }
}

private struct MessagesMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.Color.accent.opacity(0.25))
                    .frame(width: 36, height: 36)
                    .overlay(Text("JM").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Color.ink))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Jordan Miles")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.Color.ink)
                    Text("Active now")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.Color.accent)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.Color.surface)

            VStack(spacing: 10) {
                bubble("Hey coach! Hit all my reps today 💪", mine: false)
                bubble("Let's go! Proud of you. Bump squats to 5×5 next week.", mine: true)
                bubble("On it. Same time Thursday?", mine: false)
                bubble("Yep — locked in your slot.", mine: true)
            }
            .padding(14)

            Spacer()

            HStack(spacing: 8) {
                Text("Message…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                Spacer()
                Circle().fill(Theme.Color.accent).frame(width: 28, height: 28)
                    .overlay(Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Color.accentInk))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.Color.surfaceMuted)
            .clipShape(Capsule())
            .padding(12)
        }
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer(minLength: 30) }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(mine ? Theme.Color.accentInk : Theme.Color.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(mine ? Theme.Color.accent : Theme.Color.surface)
                .clipShape(.rect(cornerRadius: 14))
            if !mine { Spacer(minLength: 30) }
        }
    }
}
