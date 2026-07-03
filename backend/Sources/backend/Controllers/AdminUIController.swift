import Vapor

struct AdminUIController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("admin", use: serveAdmin)
        routes.get("admin", "**", use: serveAdminAsset)
    }

    @Sendable
    func serveAdmin(req: Request) async throws -> Response {
        try await serveFile(named: "index.html", req: req)
    }

    @Sendable
    func serveAdminAsset(req: Request) async throws -> Response {
        guard let path = req.parameters.getCatchall().first else {
            return try await serveFile(named: "index.html", req: req)
        }
        return try await serveFile(named: path, req: req)
    }

    private func serveFile(named name: String, req: Request) async throws -> Response {
        let filePath = req.application.directory.publicDirectory + "admin/" + name

        guard FileManager.default.fileExists(atPath: filePath) else {
            if name != "index.html" {
                return try await serveFile(named: "index.html", req: req)
            }
            throw Abort(.notFound, reason: "Admin UI not found. Ensure Public/admin is deployed.")
        }

        return try await req.fileio.asyncStreamFile(at: filePath)
    }
}
