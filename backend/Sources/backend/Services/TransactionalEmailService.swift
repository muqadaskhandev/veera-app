import Vapor

/// Queues transactional emails with branded templates and dev fallback logging.
enum TransactionalEmailService {
    static func queueVerification(to email: String, code: String, on app: Application) {
        let template = EmailTemplateService.verificationEmail(code: code)
        queue(to: email, subject: template.subject, text: template.text, html: template.html, on: app)
    }

    static func queuePasswordReset(to email: String, code: String, on app: Application) {
        let template = EmailTemplateService.passwordResetEmail(code: code)
        queue(to: email, subject: template.subject, text: template.text, html: template.html, on: app)
    }

    static func queueClientInvite(
        to email: String,
        trainerName: String,
        clientName: String?,
        code: String,
        expiresAt: Date?,
        on app: Application
    ) {
        let template = EmailTemplateService.clientInviteEmail(
            trainerName: trainerName,
            clientName: clientName,
            code: code,
            expiresAt: expiresAt
        )
        queue(to: email, subject: template.subject, text: template.text, html: template.html, on: app)
    }

    static func queueWelcome(to email: String, displayName: String, role: UserRole, on app: Application) {
        let template = EmailTemplateService.welcomeEmail(displayName: displayName, role: role)
        queue(to: email, subject: template.subject, text: template.text, html: template.html, on: app)
    }

    static func sendSubscriptionExpired(
        to email: String,
        displayName: String,
        planName: String,
        expiredAt: Date?,
        on app: Application
    ) async {
        let template = EmailTemplateService.subscriptionExpiredEmail(
            displayName: displayName,
            planName: planName,
            expiredAt: expiredAt
        )

        do {
            if SESEmailService.isConfigured() {
                try await SESEmailService.send(
                    to: email,
                    subject: template.subject,
                    textBody: template.text,
                    htmlBody: template.html,
                    on: app
                )
            } else if app.environment == .development {
                app.logger.warning("SES not configured — logging subscription expiry email locally")
                app.logger.info("""
                ----- DEV EMAIL -----
                To: \(email)
                Subject: \(template.subject)

                \(template.text)
                ---------------------
                """)
            } else {
                app.logger.error("Subscription expiry email skipped — SES is not configured")
            }
        } catch {
            app.logger.error("Subscription expiry email failed: \(error)")
        }
    }

    static func sendSubscriptionActivated(
        to email: String,
        displayName: String,
        planName: String,
        expiresAt: Date?,
        on app: Application
    ) async {
        let template = EmailTemplateService.subscriptionActivatedEmail(
            displayName: displayName,
            planName: planName,
            expiresAt: expiresAt
        )

        do {
            if SESEmailService.isConfigured() {
                try await SESEmailService.send(
                    to: email,
                    subject: template.subject,
                    textBody: template.text,
                    htmlBody: template.html,
                    on: app
                )
            } else if app.environment == .development {
                app.logger.warning("SES not configured — logging subscription email locally")
                app.logger.info("""
                ----- DEV EMAIL -----
                To: \(email)
                Subject: \(template.subject)

                \(template.text)
                ---------------------
                """)
            } else {
                app.logger.error("Subscription activation email skipped — SES is not configured")
            }
        } catch {
            app.logger.error("Subscription activation email failed: \(error)")
        }
    }

    static func queueSubscriptionActivated(
        to email: String,
        displayName: String,
        planName: String,
        expiresAt: Date?,
        on app: Application
    ) {
        Task {
            await sendSubscriptionActivated(
                to: email,
                displayName: displayName,
                planName: planName,
                expiresAt: expiresAt,
                on: app
            )
        }
    }

    private static func queue(
        to email: String,
        subject: String,
        text: String,
        html: String,
        on app: Application
    ) {
        Task {
            do {
                if SESEmailService.isConfigured() {
                    try await SESEmailService.send(
                        to: email,
                        subject: subject,
                        textBody: text,
                        htmlBody: html,
                        on: app
                    )
                } else if app.environment == .development {
                    app.logger.warning("SES not configured — logging email locally")
                    app.logger.info("""
                    ----- DEV EMAIL -----
                    To: \(email)
                    Subject: \(subject)

                    \(text)
                    ---------------------
                    """)
                } else {
                    app.logger.error("Email delivery skipped — SES is not configured")
                }
            } catch {
                app.logger.error("Email delivery failed: \(error)")
            }
        }
    }
}
