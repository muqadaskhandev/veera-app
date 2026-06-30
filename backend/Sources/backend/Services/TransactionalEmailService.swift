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
