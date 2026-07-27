import Vapor

enum GifService {
    /// Giphy public beta key — fine for local/dev; override with `GIPHY_API_KEY` in production.
    private static let fallbackAPIKey = "dc6zaTOxFJmzC"

    static func apiKey() -> String {
        let configured = Environment.get("GIPHY_API_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? fallbackAPIKey : configured
    }

    static func trending(limit: Int, on app: Application) async throws -> [GifDTO] {
        let capped = min(max(limit, 1), 50)
        let uri = URI(string: "https://api.giphy.com/v1/gifs/trending?api_key=\(apiKey())&limit=\(capped)&rating=pg")
        return try await fetch(uri: uri, on: app)
    }

    static func search(query: String, limit: Int, on app: Application) async throws -> [GifDTO] {
        let capped = min(max(limit, 1), 50)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await trending(limit: capped, on: app)
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let uri = URI(string: "https://api.giphy.com/v1/gifs/search?api_key=\(apiKey())&q=\(encoded)&limit=\(capped)&rating=pg")
        return try await fetch(uri: uri, on: app)
    }

    private static func fetch(uri: URI, on app: Application) async throws -> [GifDTO] {
        let response = try await app.client.get(uri)
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "GIF search unavailable")
        }
        let payload = try response.content.decode(GiphyListResponse.self)
        return payload.data.compactMap { item in
            // Prefer classic GIF URLs — some Giphy variants serve webp/mp4 that
            // break our image/gif upload + ImageIO animation path on device.
            guard let url = item.images.downsized?.url
                ?? item.images.fixedWidth?.url
                ?? item.images.original?.url else {
                return nil
            }
            let preview = item.images.fixedWidthStill?.url
                ?? item.images.downsizedStill?.url
                ?? url
            return GifDTO(
                id: item.id,
                title: item.title ?? "",
                url: url,
                previewURL: preview,
                width: item.images.fixedWidth.flatMap { Int($0.width ?? "") },
                height: item.images.fixedWidth.flatMap { Int($0.height ?? "") }
            )
        }
    }
}

struct GifDTO: Content {
    let id: String
    let title: String
    let url: String
    let previewURL: String
    let width: Int?
    let height: Int?
}

struct GifListResponse: Content {
    let gifs: [GifDTO]
}

private struct GiphyListResponse: Content {
    let data: [GiphyGif]
}

private struct GiphyGif: Content {
    let id: String
    let title: String?
    let images: GiphyImages
}

private struct GiphyImages: Content {
    let original: GiphyImageAsset?
    let fixedWidth: GiphyImageAsset?
    let fixedWidthStill: GiphyImageAsset?
    let downsized: GiphyImageAsset?
    let downsizedStill: GiphyImageAsset?

    enum CodingKeys: String, CodingKey {
        case original
        case fixedWidth = "fixed_width"
        case fixedWidthStill = "fixed_width_still"
        case downsized
        case downsizedStill = "downsized_still"
    }
}

private struct GiphyImageAsset: Content {
    let url: String?
    let width: String?
    let height: String?
}
