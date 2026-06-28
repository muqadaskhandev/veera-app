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
import AuthenticationServices

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
  /// Stable id so selection survives SwiftUI re-renders.
  let id: String
  let title: String
  let subtitle: String?
  init(_ title: String, _ subtitle: String? = nil) {
    self.id = title
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
    @State private var answers: [String: String] = [:]
    @State private var inviteCode = ""
    @State private var notificationsResolved = false
    @State private var notificationsDenied = false
    @State private var agreedToComms = true
    @State private var showingEmailFields = false
    @State private var registerName = ""
    @State private var registerEmail = ""
    @State private var registerPassword = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showingEmailCodeEntry = false
    @State private var verificationEmail = ""
    @State private var verificationCode = ""
    @State private var devCodeHint: String?
    @State private var showingLogin = false
    @State private var showingLoginEmailFields = false
    @State private var loginEmail = ""
    @State private var loginPassword = ""
    @State private var showingForgotPassword = false
    @State private var showingResetPassword = false
    @State private var forgotPasswordEmail = ""
    @State private var forgotPasswordMessage: String?
    @State private var devResetToken: String?
    @State private var resetToken = ""
    @State private var resetPassword = ""
    @State private var resetPasswordConfirm = ""
    @State private var successMessage: String?

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
        .alert("Something went wrong", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .alert("Success", isPresented: .init(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
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
        Group {
            if showingResetPassword {
                resetPasswordBody
            } else if showingForgotPassword {
                forgotPasswordBody
            } else if showingLogin {
                loginBody
            } else {
                inviteEntryBody
            }
        }
        .padding(.horizontal, 28)
        .opacity(appeared ? 1 : 0)
    }

    private var inviteEntryBody: some View {
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

            InviteCodeField(code: $inviteCode)
                .padding(.top, 28)

            Spacer()
            Spacer()
        }
    }

    private var loginBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            (
                Text("Welcome back\n").foregroundStyle(.white)
                + Text("sign in to your account").foregroundStyle(.white.opacity(0.45))
            )
            .font(.system(size: 36, weight: .black))
            .fontWidth(.condensed)
            .textCase(.uppercase)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 14) {
                Button(action: { Task { await signInWithApple(isLogin: true) } }) {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.Color.accentInk)
                        Text(isSaving ? "Signing in…" : "Continue with Apple")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingLoginEmailFields.toggle()
                    }
                }) {
                    Text(showingLoginEmailFields ? "Hide Email Form" : "Continue with Email")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                if showingLoginEmailFields {
                    VStack(spacing: 12) {
                        registerField("Email", text: $loginEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        passwordField("Password", text: $loginPassword)

                        Button(action: { Task { await signInWithEmail() } }) {
                            Text(isSaving ? "Signing in…" : "Sign In")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Color.accentInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.Color.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || !canSubmitLogin)
                        .opacity(canSubmitLogin ? 1 : 0.45)

                        HStack {
                            Button(action: { openForgotPassword() }) {
                                Text("Forgot password?")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(action: { openResetPassword() }) {
                                Text("Have a reset code?")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.Color.accent.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 36)

            Spacer()
        }
    }

    private var forgotPasswordBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            headlineText([
                Seg("Forgot your "),
                Seg("password", accent: true),
                Seg("?"),
            ], size: 30)

            Text("Enter your email and we'll send you a link to reset your password.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 14)

            registerField("Email", text: $forgotPasswordEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .padding(.top, 28)

            if let forgotPasswordMessage {
                Text(forgotPasswordMessage)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Color.accent)
                    .padding(.top, 16)

                #if DEBUG
                if let devResetToken {
                    Text("Dev reset token: \(devResetToken)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 8)
                }
                #endif
            }

            Button(action: { Task { await submitForgotPassword() } }) {
                Text(isSaving ? "Sending…" : (forgotPasswordMessage == nil ? "Send Reset Link" : "Resend Link"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSaving || !forgotPasswordEmail.contains("@"))
            .opacity(forgotPasswordEmail.contains("@") ? 1 : 0.45)
            .padding(.top, 24)

            if forgotPasswordMessage != nil {
                Button(action: { openResetPassword(prefillToken: devResetToken) }) {
                    Text("Enter reset code")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }

            Spacer()
        }
    }

    private var resetPasswordBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            headlineText([
                Seg("Set a new "),
                Seg("password", accent: true),
            ], size: 30)

            Text("Paste the reset code from your email and choose a new password.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 14)

            VStack(spacing: 12) {
                registerField("Reset code", text: $resetToken)
                    .textInputAutocapitalization(.never)
                passwordField(
                    "New password (8+ characters)",
                    text: $resetPassword,
                    hasError: resetPasswordTooShort
                )
                passwordField(
                    "Confirm new password",
                    text: $resetPasswordConfirm,
                    hasError: resetPasswordMismatch
                )

                passwordValidationMessages(
                    password: resetPassword,
                    confirm: resetPasswordConfirm
                )
            }
            .padding(.top, 28)

            Button(action: { Task { await submitResetPassword() } }) {
                Text(isSaving ? "Updating…" : "Update Password")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSaving || !canSubmitResetPassword)
            .opacity(canSubmitResetPassword ? 1 : 0.45)
            .padding(.top, 24)

            Spacer()
        }
    }

    // MARK: Preview (was invite-only body)

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
        Group {
            if showingEmailCodeEntry {
                emailCodeEntryBody
            } else {
                registerOptionsBody
            }
        }
        .padding(.horizontal, 28)
        .opacity(appeared ? 1 : 0)
    }

    private var registerOptionsBody: some View {
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
                Button(action: { Task { await signInWithApple(isLogin: false) } }) {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.Color.accentInk)
                        Text(isSaving ? "Saving…" : "Continue with Apple")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingEmailFields.toggle()
                    }
                }) {
                    Text(showingEmailFields ? "Hide Email Form" : "Continue with Email")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                if showingEmailFields {
                    VStack(spacing: 12) {
                        registerField("Display name", text: $registerName)
                        registerField("Email", text: $registerEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        passwordField(
                            "Password (8+ characters)",
                            text: $registerPassword,
                            hasError: registerPasswordTooShort
                        )

                        passwordValidationMessages(password: registerPassword, confirm: nil)

                        Button(action: { Task { await signUpWithEmail() } }) {
                            Text(isSaving ? "Saving…" : "Save & Continue")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Color.accentInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.Color.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving || !canSubmitEmail)
                        .opacity(canSubmitEmail ? 1 : 0.45)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
    }

    private var emailCodeEntryBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            headlineText([
                Seg("Enter the "),
                Seg("6-digit code", accent: true),
                Seg(" we sent to your email"),
            ], size: 30)

            Text(verificationEmail)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Color.accent)
                .padding(.top, 14)

            #if DEBUG
            if let devCodeHint {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Development mode", systemImage: "hammer.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accent)
                    Text("Real emails are not sent yet. Use this code: \(devCodeHint)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.Color.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Color.accent.opacity(0.35), lineWidth: 1)
                )
                .padding(.top, 16)
            }
            #endif

            TextField("", text: $verificationCode, prompt: Text("000000").foregroundColor(.white.opacity(0.35)))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .tracking(10)
                .padding(.vertical, 20)
                .padding(.horizontal, 18)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Color.accent.opacity(0.45), lineWidth: 1)
                )
                .padding(.top, 28)
                .onChange(of: verificationCode) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    verificationCode = String(digits.prefix(6))
                }

            Button(action: { Task { await verifyEmailCode() } }) {
                Text(isSaving ? "Verifying…" : "Verify & Continue")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.accentInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.Color.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSaving || verificationCode.count != 6)
            .opacity(verificationCode.count == 6 ? 1 : 0.45)
            .padding(.top, 20)

            Text("Check your inbox and spam folder.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 18)

            Button(action: { Task { await resendVerificationCode() } }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                    Text(isSaving ? "Sending…" : "Resend Code")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.top, 12)

            Spacer()
        }
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
            if showingLogin || showingForgotPassword || showingResetPassword {
                HStack {
                    backButton
                    Spacer()
                }
            } else {
                VStack(spacing: 14) {
                    controlRow(label: "Continue")
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingLogin = true
                            appeared = false
                        }
                        withAnimation(.easeOut(duration: 0.5).delay(0.05)) { appeared = true }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Already have an account?")
                                .foregroundStyle(.white.opacity(0.55))
                            Text("Log in")
                                .foregroundStyle(Theme.Color.accent)
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .preview:
            controlRow(label: "Next")
        case .question:
            controlRow(label: "Next")
        case .notifications:
            controlRow(label: "Next")
        }
    }

    private var canAdvance: Bool {
        switch current {
        case .question(let q):
            return answers[q.key] != nil
        default:
            return true
        }
    }

    private func controlRow(label: String) -> some View {
        HStack(spacing: 14) {
            if !isFirst { backButton }
            Button(action: advance) {
                Text(label)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(canAdvance ? Theme.Color.accentInk : Theme.Color.accentInk.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background((canAdvance ? Theme.Color.accent : Theme.Color.accent.opacity(0.35)), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance || isSaving)
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
        guard canAdvance else { return }
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
        if case .invite = current, showingResetPassword {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingResetPassword = false
                clearResetPasswordFields()
                showingLogin = true
                showingLoginEmailFields = true
            }
            return
        }
        if case .invite = current, showingForgotPassword {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingForgotPassword = false
                forgotPasswordMessage = nil
                devResetToken = nil
                showingLogin = true
            }
            return
        }
        if case .invite = current, showingLogin {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingLogin = false
                showingLoginEmailFields = false
                loginEmail = ""
                loginPassword = ""
            }
            return
        }
        if case .register = current, showingEmailCodeEntry {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingEmailCodeEntry = false
                verificationCode = ""
            }
            return
        }
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

    private var canSubmitLogin: Bool {
        loginEmail.contains("@") && loginPassword.count >= 8
    }

    private var canSubmitResetPassword: Bool {
        !resetToken.trimmingCharacters(in: .whitespaces).isEmpty
            && resetPassword.count >= 8
            && resetPassword == resetPasswordConfirm
    }

    private func openForgotPassword() {
        forgotPasswordEmail = loginEmail
        forgotPasswordMessage = nil
        devResetToken = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showingLogin = false
            showingForgotPassword = true
        }
    }

    private func openResetPassword(prefillToken: String? = nil) {
        resetToken = prefillToken ?? devResetToken ?? ""
        resetPassword = ""
        resetPasswordConfirm = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showingLogin = false
            showingForgotPassword = false
            showingResetPassword = true
        }
    }

    private func clearResetPasswordFields() {
        resetToken = ""
        resetPassword = ""
        resetPasswordConfirm = ""
    }

    private var canSubmitEmail: Bool {
        !registerName.trimmingCharacters(in: .whitespaces).isEmpty
            && registerEmail.contains("@")
            && registerPassword.count >= 8
    }

    private var registerPasswordTooShort: Bool {
        !registerPassword.isEmpty && registerPassword.count < 8
    }

    private var resetPasswordTooShort: Bool {
        !resetPassword.isEmpty && resetPassword.count < 8
    }

    private var resetPasswordMismatch: Bool {
        !resetPasswordConfirm.isEmpty && resetPassword != resetPasswordConfirm
    }

    private func passwordField(_ placeholder: String, text: Binding<String>, hasError: Bool = false) -> some View {
        PasswordField(placeholder: placeholder, text: text, hasError: hasError)
    }

    @ViewBuilder
    private func passwordValidationMessages(password: String, confirm: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !password.isEmpty && password.count < 8 {
                passwordValidationLine("Password must be at least 8 characters")
            }
            if let confirm, !confirm.isEmpty, password != confirm {
                passwordValidationLine("Passwords don't match")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func passwordValidationLine(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Theme.Color.danger)
    }

    private func registerField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.4)))
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
    }

    @MainActor
    private func signUpWithEmail() async {
        guard canSubmitEmail, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let name = registerName.trimmingCharacters(in: .whitespaces)
            let email = registerEmail.trimmingCharacters(in: .whitespaces).lowercased()
            let response: RegisterResponse

            switch role {
            case .trainer:
                response = try await VerraAPI.registerTrainer(
                    email: email,
                    password: registerPassword,
                    displayName: name
                )
            case .client:
                response = try await VerraAPI.registerClient(
                    email: email,
                    password: registerPassword,
                    displayName: name,
                    inviteCode: inviteCode.isEmpty ? nil : inviteCode
                )
            }

            if response.requiresEmailVerification {
                verificationEmail = response.email
                devCodeHint = response.devCode
                verificationCode = ""
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingEmailCodeEntry = true
                }
                return
            }

            guard
                let accessToken = response.accessToken,
                let refreshToken = response.refreshToken,
                let expiresIn = response.expiresIn,
                let user = response.user
            else {
                saveError = "Registration did not return account details."
                return
            }

            let auth = AuthTokenResponse(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresIn: expiresIn,
                user: user
            )
            try await OnboardingAuthService.complete(
                role: role,
                auth: auth,
                trainerAnswers: answers,
                onComplete: { name in onFinish(name, "") }
            )
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func verifyEmailCode() async {
        guard verificationCode.count == 6, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let auth = try await VerraAPI.verifyEmail(email: verificationEmail, code: verificationCode)
            try await OnboardingAuthService.complete(
                role: role,
                auth: auth,
                trainerAnswers: answers,
                onComplete: { name in onFinish(name, "") }
            )
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func resendVerificationCode() async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let response = try await VerraAPI.resendVerificationEmail(email: verificationEmail)
            devCodeHint = response.devCode
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func submitForgotPassword() async {
        let email = forgotPasswordEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard email.contains("@"), !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let response = try await VerraAPI.requestPasswordReset(email: email)
            forgotPasswordMessage = response.message
            devResetToken = response.resetToken
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func submitResetPassword() async {
        guard canSubmitResetPassword, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let response = try await VerraAPI.resetPassword(
                token: resetToken.trimmingCharacters(in: .whitespaces),
                newPassword: resetPassword
            )
            loginEmail = forgotPasswordEmail.isEmpty ? loginEmail : forgotPasswordEmail
            loginPassword = ""
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingResetPassword = false
                showingForgotPassword = false
                showingLogin = true
                showingLoginEmailFields = true
                clearResetPasswordFields()
                forgotPasswordMessage = nil
                devResetToken = nil
            }
            successMessage = response.message
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func signInWithEmail() async {
        guard canSubmitLogin, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let email = loginEmail.trimmingCharacters(in: .whitespaces).lowercased()
            let auth = try await VerraAPI.login(email: email, password: loginPassword)
            try finishLogin(auth: auth)
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func signInWithApple(isLogin: Bool) async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            let apple = try await AppleSignInService.signIn()
            let fallbackName = registerName.trimmingCharacters(in: .whitespaces)
            let displayName = apple.displayName ?? (fallbackName.isEmpty ? nil : fallbackName)

            let auth = try await VerraAPI.signInWithApple(
                identityToken: apple.identityToken,
                role: role,
                displayName: isLogin ? nil : displayName,
                inviteCode: inviteCode.isEmpty ? nil : inviteCode
            )

            if isLogin {
                try finishLogin(auth: auth)
            } else {
                try await OnboardingAuthService.complete(
                    role: role,
                    auth: auth,
                    trainerAnswers: answers,
                    onComplete: { name in onFinish(name, "") }
                )
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func finishLogin(auth: AuthTokenResponse) throws {
        let expectedRole = role == .trainer ? "trainer" : "client"
        guard auth.user.role == expectedRole else {
            AuthStore.clear()
            let roleLabel = auth.user.role == "trainer" ? "trainer" : "client"
            throw NSError(
                domain: "VerraAuth",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "This account is registered as a \(roleLabel). Go back and choose \(roleLabel.capitalized) on the welcome screen."]
            )
        }
        AuthStore.save(accessToken: auth.accessToken, refreshToken: auth.refreshToken)
        onFinish(auth.user.displayName, "")
    }

    private func finish() {
        switch role {
        case .trainer:
            break
        case .client:
            if inviteCode.trimmingCharacters(in: .whitespaces).isEmpty {
                onFinish("", "")
            }
        }
    }

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

// MARK: - Password field

private struct PasswordField: View {
    let placeholder: String
    @Binding var text: String
    var hasError: Bool = false

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isRevealed {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.4)))
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.4)))
                }
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(hasError ? Theme.Color.danger.opacity(0.75) : .white.opacity(0.18), lineWidth: 1)
        )
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
    @Binding var code: String
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
