import Fluent
import Foundation
import Vapor

enum TwilioService {
    static func isConfigured() -> Bool {
        guard let sid = Environment.get("TWILIO_ACCOUNT_SID"), !sid.isEmpty,
              let token = Environment.get("TWILIO_AUTH_TOKEN"), !token.isEmpty,
              let from = Environment.get("TWILIO_FROM_NUMBER"), !from.isEmpty else {
            return false
        }
        return true
    }

    static func sendSMS(to phone: String, body: String, on app: Application) async -> Bool {
        let result = await sendSMSWithResult(to: phone, body: body, statusCallbackURL: nil, on: app)
        return result.success
    }

    static func sendSMSWithResult(
        to phone: String,
        body: String,
        statusCallbackURL: String?,
        on app: Application
    ) async -> TwilioSendResult {
        guard isConfigured(),
              let accountSID = Environment.get("TWILIO_ACCOUNT_SID"),
              let authToken = Environment.get("TWILIO_AUTH_TOKEN"),
              let fromNumber = Environment.get("TWILIO_FROM_NUMBER") else {
            if app.environment == .development {
                app.logger.info("Twilio SMS (dev): to=\(phone) body=\(body)")
            }
            return TwilioSendResult(success: false, messageSID: nil, statusCode: 0, error: "Twilio not configured")
        }

        let normalized = normalizePhone(phone)
        guard !normalized.isEmpty else {
            return TwilioSendResult(success: false, messageSID: nil, statusCode: 0, error: "Invalid phone number")
        }

        let url = URI(string: "https://api.twilio.com/2010-04-01/Accounts/\(accountSID)/Messages.json")
        let credentials = "\(accountSID):\(authToken)"
        let authHeader = "Basic \(Data(credentials.utf8).base64EncodedString())"

        do {
            let response = try await app.client.post(url) { request in
                request.headers.add(name: .authorization, value: authHeader)
                request.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")
                let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
                var form = "To=\(normalized)&From=\(fromNumber.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fromNumber)&Body=\(encodedBody)"
                if let statusCallbackURL,
                   let encoded = statusCallbackURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    form += "&StatusCallback=\(encoded)&StatusCallbackMethod=POST"
                }
                request.body = .init(string: form)
            }

            let responseBody = response.body.map { String(buffer: $0) } ?? ""
            if (200..<300).contains(response.status.code) {
                let sid = parseMessageSID(from: responseBody)
                app.logger.info("Twilio SMS sent to \(normalized.prefix(6))… sid=\(sid ?? "unknown")")
                return TwilioSendResult(
                    success: true,
                    messageSID: sid,
                    statusCode: Int(response.status.code),
                    error: nil
                )
            }

            app.logger.warning("Twilio SMS failed (\(response.status.code)): \(responseBody)")
            return TwilioSendResult(
                success: false,
                messageSID: nil,
                statusCode: Int(response.status.code),
                error: responseBody
            )
        } catch {
            app.logger.warning("Twilio SMS error: \(error.localizedDescription)")
            return TwilioSendResult(success: false, messageSID: nil, statusCode: 0, error: error.localizedDescription)
        }
    }

    static func inviteMessage(trainerName: String, clientName: String?, code: String) -> String {
        let greeting = clientName.map { "Hi \($0), " } ?? "Hi, "
        return "\(greeting)\(trainerName) invited you to Verra. Your invite code is \(code). Download the app and sign up as a client."
    }

    static func sessionReminderMessage(clientName: String, focus: String, timeLabel: String, location: String) -> String {
        let place = location.isEmpty ? "" : " · \(location)"
        return "Verra reminder: \(focus) with \(clientName) at \(timeLabel)\(place)."
    }

    private static func parseMessageSID(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sid = json["sid"] as? String else {
            return nil
        }
        return sid
    }

    private static func normalizePhone(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("+") { return digits }
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        return trimmed.hasPrefix("+") ? trimmed : "+\(digits)"
    }
}

enum ClientInviteSMSService {
    static func queueInvite(
        to phone: String,
        trainerName: String,
        clientName: String?,
        code: String,
        userID: UUID?,
        on app: Application
    ) {
        let body = TwilioService.inviteMessage(trainerName: trainerName, clientName: clientName, code: code)
        Task {
            _ = try? await NotificationDeliveryService.sendSMS(
                userID: userID,
                phone: phone,
                title: "Client invite",
                body: body,
                kind: .clientInvite,
                on: app.db,
                app: app
            )
        }
    }
}
