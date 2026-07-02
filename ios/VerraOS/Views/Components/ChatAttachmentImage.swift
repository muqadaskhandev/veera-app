import SwiftUI
import UIKit

struct ChatAttachmentImage: View {
    let path: String
    var cornerRadius: CGFloat = 20

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Theme.Color.surfaceMuted)
                    ProgressView()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: path) {
            image = await ChatAttachmentLoader.image(for: path)
        }
    }
}

enum ChatAttachmentLoader {
    static func image(for path: String) async -> UIImage? {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL),
              let token = AuthStore.accessToken else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    static func localVideoURL(for path: String) async -> URL? {
        await localFileURL(for: path, fallbackExtension: "mp4")
    }

    static func localAudioURL(for path: String) async -> URL? {
        await localFileURL(for: path, fallbackExtension: "m4a")
    }

    private static func localFileURL(for path: String, fallbackExtension: String) async -> URL? {
        guard let url = URL(string: path, relativeTo: APIConfig.baseURL),
              let token = AuthStore.accessToken else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let ext = url.pathExtension.isEmpty ? fallbackExtension : url.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("chat-playback-\(UUID().uuidString).\(ext)")
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }
}
