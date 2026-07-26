import Vapor

struct GifController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let gifs = routes.grouped("api", "gifs")
            .grouped(JWTAuthMiddleware())
        gifs.get("trending", use: trending)
        gifs.get("search", use: search)
    }

    @Sendable
    func trending(req: Request) async throws -> GifListResponse {
        _ = try req.auth.require(User.self)
        let limit = req.query[Int.self, at: "limit"] ?? 24
        let gifs = try await GifService.trending(limit: limit, on: req.application)
        return GifListResponse(gifs: gifs)
    }

    @Sendable
    func search(req: Request) async throws -> GifListResponse {
        _ = try req.auth.require(User.self)
        let query = req.query[String.self, at: "q"] ?? ""
        let limit = req.query[Int.self, at: "limit"] ?? 24
        let gifs = try await GifService.search(query: query, limit: limit, on: req.application)
        return GifListResponse(gifs: gifs)
    }
}
