import Foundation
import Vapor

/// Branded HTML + plain-text email templates matching VerraOS design tokens.
enum EmailTemplateService {
    enum Brand {
        static let background = "#F4F1EA"
        static let surface = "#FFFFFF"
        static let surfaceMuted = "#EDE9E0"
        static let ink = "#1A1A17"
        static let inkMuted = "#8C887E"
        static let inkFaint = "#B6B2A8"
        static let accent = "#C2F23C"
        static let accentInk = "#222417"
        static let danger = "#E8483D"
    }

    static var appURL: String {
        Environment.get("APP_URL") ?? "https://verraos.app"
    }

    // MARK: - Public templates

    static func verificationEmail(code: String) -> (subject: String, text: String, html: String) {
        let subject = "Verify your Verra account"
        let text = """
        Welcome to Verra.

        Your verification code is: \(code)

        Enter this code in the app to finish setting up your account. It expires in 10 minutes.

        If you didn't create a Verra account, you can ignore this email.
        """
        let html = layout(
            preview: "Your verification code is \(code)",
            eyebrow: "Account verification",
            title: "Confirm your email",
            body: """
            \(paragraph("Enter this code in Verra to finish setting up your account."))
            \(codeBlock(code, caption: "Expires in 10 minutes"))
            \(muted("If you didn't create a Verra account, you can safely ignore this email."))
            """
        )
        return (subject, text, html)
    }

    static func passwordResetEmail(code: String) -> (subject: String, text: String, html: String) {
        let subject = "Reset your Verra password"
        let text = """
        We received a request to reset your Verra password.

        Your reset code is: \(code)

        Enter this code in the app to choose a new password. It expires in 10 minutes.

        If you didn't request this, you can ignore this email.
        """
        let html = layout(
            preview: "Your password reset code is \(code)",
            eyebrow: "Password reset",
            title: "Reset your password",
            body: """
            \(paragraph("Use the code below to reset your password in the Verra app."))
            \(codeBlock(code, caption: "Expires in 10 minutes"))
            \(muted("If you didn't request a password reset, you can safely ignore this email."))
            """
        )
        return (subject, text, html)
    }

    static func clientInviteEmail(
        trainerName: String,
        clientName: String?,
        code: String,
        expiresAt: Date?
    ) -> (subject: String, text: String, html: String) {
        let greeting = clientName.map { "Hi \($0)," } ?? "Hi there,"
        let expiryLine = expiresAt.map { "This invite expires on \(formatDate($0))." } ?? "This invite does not expire."
        let joinURL = "\(appURL)/join?code=\(code)"

        let subject = "\(trainerName) invited you to Verra"
        let text = """
        \(greeting)

        \(trainerName) invited you to join them on Verra — your coach's operating system for training, progress, and accountability.

        Your invite code: \(code)

        Download Verra, choose Client, and enter this code during signup.
        \(expiryLine)

        \(joinURL)
        """
        let html = layout(
            preview: "\(trainerName) invited you to Verra",
            eyebrow: "Client invitation",
            title: "You're invited to Verra",
            body: """
            \(paragraph("\(greeting) <strong>\(escape(trainerName))</strong> invited you to join them on Verra — your coach's operating system for training, progress, and accountability."))
            \(infoCard(label: "Your invite code", value: code, highlight: true))
            \(paragraph("Download Verra, tap <strong>Client</strong>, and enter your invite code during signup."))
            \(button("Open Verra", url: joinURL))
            \(muted(expiryLine))
            """
        )
        return (subject, text, html)
    }

    static func welcomeEmail(displayName: String, role: UserRole) -> (subject: String, text: String, html: String) {
        let firstName = displayName.split(separator: " ").first.map(String.init) ?? displayName
        let (headline, detail) = welcomeCopy(for: role)

        let subject = "Welcome to Verra, \(firstName)"
        let text = """
        Hi \(firstName),

        \(detail)

        Open Verra to get started.
        \(appURL)
        """
        let html = layout(
            preview: headline,
            eyebrow: "Welcome",
            title: headline,
            body: """
            \(paragraph("Hi \(escape(firstName)),")) 
            \(paragraph(detail))
            \(accentCard("""
            <p style="margin:0 0 8px;font-size:13px;font-weight:700;color:\(Brand.accentInk);text-transform:uppercase;letter-spacing:0.08em;">You're all set</p>
            <p style="margin:0;font-size:15px;line-height:1.6;color:\(Brand.accentInk);">Open Verra to connect with your coach, track progress, and stay on plan.</p>
            """))
            \(button("Open Verra", url: appURL))
            """
        )
        return (subject, text, html)
    }

    // MARK: - Layout primitives

    private static func layout(preview: String, eyebrow: String, title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="color-scheme" content="light">
          <meta name="supported-color-schemes" content="light">
          <title>\(escape(title))</title>
          <!--[if mso]><style>body,table,td{font-family:Arial,sans-serif!important;}</style><![endif]-->
        </head>
        <body style="margin:0;padding:0;background-color:\(Brand.background);">
          <div style="display:none;max-height:0;overflow:hidden;opacity:0;">\(escape(preview))</div>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color:\(Brand.background);padding:32px 16px;">
            <tr>
              <td align="center">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;">
                  \(headerRow)
                  <tr>
                    <td style="background:\(Brand.surface);border:1px solid rgba(26,26,23,0.08);border-top:none;border-radius:0 0 20px 20px;padding:32px 28px 28px;">
                      <p style="margin:0 0 10px;font-size:11px;font-weight:700;letter-spacing:0.12em;text-transform:uppercase;color:\(Brand.inkMuted);">\(escape(eyebrow))</p>
                      <h1 style="margin:0 0 20px;font-size:28px;line-height:1.15;font-weight:800;color:\(Brand.ink);">\(escape(title))</h1>
                      \(body)
                    </td>
                  </tr>
                  \(footerRow)
                </table>
              </td>
            </tr>
          </table>
        </body>
        </html>
        """
    }

    private static var headerRow: String {
        """
        <tr>
          <td style="background:\(Brand.ink);border-radius:20px 20px 0 0;padding:22px 28px;">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
              <tr>
                <td>
                  <span style="display:inline-block;width:10px;height:10px;border-radius:999px;background:\(Brand.accent);margin-right:8px;vertical-align:middle;"></span>
                  <span style="font-size:22px;font-weight:900;letter-spacing:-0.04em;color:#FFFFFF;vertical-align:middle;">VERRA</span>
                  <span style="font-size:22px;font-weight:300;letter-spacing:-0.04em;color:rgba(255,255,255,0.72);vertical-align:middle;">OS</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        """
    }

    private static var footerRow: String {
        """
        <tr>
          <td style="padding:20px 8px 0;text-align:center;">
            <p style="margin:0 0 6px;font-size:12px;line-height:1.5;color:\(Brand.inkMuted);">Verra — your coach's operating system</p>
            <p style="margin:0;font-size:11px;line-height:1.5;color:\(Brand.inkFaint);">© \(Calendar.current.component(.year, from: Date())) VerraOS</p>
          </td>
        </tr>
        """
    }

    private static func paragraph(_ html: String) -> String {
        """
        <p style="margin:0 0 18px;font-size:15px;line-height:1.65;color:\(Brand.ink);">\(html)</p>
        """
    }

    private static func muted(_ text: String) -> String {
        """
        <p style="margin:18px 0 0;font-size:13px;line-height:1.6;color:\(Brand.inkMuted);">\(escape(text))</p>
        """
    }

    private static func codeBlock(_ code: String, caption: String) -> String {
        """
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 18px;">
          <tr>
            <td align="center" style="background:\(Brand.surfaceMuted);border:1px solid rgba(26,26,23,0.08);border-radius:16px;padding:22px 18px;">
              <p style="margin:0;font-size:34px;line-height:1;font-weight:800;letter-spacing:0.24em;color:\(Brand.ink);font-family:ui-monospace,SFMono-Regular,Menlo,monospace;">\(escape(code))</p>
              <p style="margin:10px 0 0;font-size:12px;font-weight:600;color:\(Brand.inkMuted);">\(escape(caption))</p>
            </td>
          </tr>
        </table>
        """
    }

    private static func infoCard(label: String, value: String, highlight: Bool = false) -> String {
        let valueColor = highlight ? Brand.accentInk : Brand.ink
        let bg = highlight ? Brand.accent : Brand.surfaceMuted
        return """
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 18px;">
          <tr>
            <td style="background:\(bg);border:1px solid rgba(26,26,23,0.08);border-radius:16px;padding:18px 20px;">
              <p style="margin:0 0 6px;font-size:11px;font-weight:700;letter-spacing:0.1em;text-transform:uppercase;color:\(highlight ? Brand.accentInk : Brand.inkMuted);">\(escape(label))</p>
              <p style="margin:0;font-size:28px;line-height:1.1;font-weight:800;letter-spacing:0.18em;color:\(valueColor);font-family:ui-monospace,SFMono-Regular,Menlo,monospace;">\(escape(value))</p>
            </td>
          </tr>
        </table>
        """
    }

    private static func accentCard(_ innerHTML: String) -> String {
        """
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:0 0 18px;">
          <tr>
            <td style="background:\(Brand.accent);border-radius:16px;padding:18px 20px;">\(innerHTML)</td>
          </tr>
        </table>
        """
    }

    private static func button(_ title: String, url: String) -> String {
        """
        <table role="presentation" cellspacing="0" cellpadding="0" style="margin:4px 0 0;">
          <tr>
            <td style="border-radius:999px;background:\(Brand.accent);">
              <a href="\(escape(url))" style="display:inline-block;padding:14px 24px;font-size:14px;font-weight:800;color:\(Brand.accentInk);text-decoration:none;">\(escape(title))</a>
            </td>
          </tr>
        </table>
        """
    }

    private static func welcomeCopy(for role: UserRole) -> (String, String) {
        switch role {
        case .trainer:
            return (
                "Welcome to Verra",
                "Your account is verified. You can now manage clients, plans, and progress from one place."
            )
        case .client:
            return (
                "Welcome to Verra",
                "Your account is verified. You're ready to connect with your coach, sync wearables, and track your training."
            )
        case .admin:
            return (
                "Welcome to Verra",
                "Your admin account is verified and ready to use."
            )
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
