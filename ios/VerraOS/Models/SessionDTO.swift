import Foundation

struct SessionDTO: Codable {
    let id: UUID
    let trainerID: UUID
    let clientID: UUID?
    let clientName: String
    let focus: String
    let location: String
    let accent: String
    let initials: String
    let scheduledAt: Date
    let timeZoneIdentifier: String?
    let durationMinutes: Int
    let notes: String
    let isCompleted: Bool
    let isSkipped: Bool
}
