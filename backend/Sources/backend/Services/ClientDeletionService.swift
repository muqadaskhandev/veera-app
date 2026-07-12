import Fluent
import Vapor

enum ClientDeletionService {
    static func delete(_ client: Client, on database: any Database) async throws {
        let clientID = try client.requireID()

        try await WeightLog.query(on: database).filter(\.$client.$id == clientID).delete()
        try await ProgressPhoto.query(on: database).filter(\.$client.$id == clientID).delete()
        try await NutritionNote.query(on: database).filter(\.$client.$id == clientID).delete()
        try await Supplement.query(on: database).filter(\.$client.$id == clientID).delete()
        try await NutritionProfile.query(on: database).filter(\.$client.$id == clientID).delete()
        try await WorkoutWeek.query(on: database).filter(\.$client.$id == clientID).delete()
        try await FinancialEvent.query(on: database).filter(\.$client.$id == clientID).delete()

        let sessions = try await Session.query(on: database).filter(\.$client.$id == clientID).all()
        for session in sessions {
            if let sessionID = session.id {
                try await ScheduledReminder.query(on: database).filter(\.$session.$id == sessionID).delete()
            }
            try await session.delete(on: database)
        }

        let conversations = try await Conversation.query(on: database).filter(\.$client.$id == clientID).all()
        for conversation in conversations {
            if let conversationID = conversation.id {
                try await Message.query(on: database).filter(\.$conversation.$id == conversationID).delete()
            }
            try await conversation.delete(on: database)
        }

        try await client.delete(on: database)
    }
}
