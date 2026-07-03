import Fluent
import Foundation
import Vapor

enum ClientAccessService {
    static func requireClient(_ clientID: UUID, for user: User, on database: any Database) async throws -> Client {
        guard let client = try await Client.find(clientID, on: database) else {
            throw Abort(.notFound, reason: "Client not found")
        }

        switch user.userRole {
        case .admin:
            return client
        case .trainer:
            guard let trainer = try await Trainer.query(on: database).filter(\.$user.$id == user.id!).first(),
                  client.$trainer.id == trainer.id else {
                throw Abort(.forbidden, reason: "Not your client")
            }
            return client
        case .client:
            guard client.$user.id == user.id else {
                throw Abort(.forbidden, reason: "Not your profile")
            }
            return client
        case .none:
            throw Abort(.forbidden)
        }
    }

    static func trainer(for user: User, trainerID: UUID? = nil, on database: any Database) async throws -> Trainer {
        if user.userRole == .admin {
            if let trainerID, let trainer = try await Trainer.find(trainerID, on: database) {
                return trainer
            }
            return try await TrainerService.defaultTrainer(on: database)
        }

        guard let trainer = try await Trainer.query(on: database).filter(\.$user.$id == user.id!).first() else {
            throw Abort(.notFound, reason: "Trainer profile not found")
        }
        return trainer
    }

    static func trainerForClient(_ clientID: UUID, on database: any Database) async throws -> Trainer {
        let client = try await requireClientUnrestricted(clientID, on: database)
        guard let trainer = try await Trainer.find(client.$trainer.id, on: database) else {
            throw Abort(.notFound, reason: "Trainer not found for client")
        }
        return trainer
    }

    private static func requireClientUnrestricted(_ clientID: UUID, on database: any Database) async throws -> Client {
        guard let client = try await Client.find(clientID, on: database) else {
            throw Abort(.notFound, reason: "Client not found")
        }
        return client
    }
}
