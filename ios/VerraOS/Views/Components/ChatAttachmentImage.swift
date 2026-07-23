import ImageIO
import SwiftUI
import UIKit

struct ChatAttachmentImage: View {
    let path: String
    var cornerRadius: CGFloat = 20

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                if image.images != nil {
                    // SwiftUI `Image` only shows the first GIF frame — use UIKit to animate.
                    AnimatedUIImageView(image: image)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
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

private struct AnimatedUIImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = image
    }
}

enum ChatAttachmentLoader {
    static func image(for path: String) async -> UIImage? {
        guard let data = await downloadData(for: path) else { return nil }
        return animatedImage(from: data) ?? UIImage(data: data)
    }

    /// Builds an animated `UIImage` for multi-frame GIFs; falls back to nil for
    /// still images so callers can use `UIImage(data:)`.
    static func animatedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        var frames: [UIImage] = []
        var duration: Double = 0
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: cgImage))
            duration += frameDuration(source: source, index: index)
        }
        guard !frames.isEmpty else { return nil }
        if duration <= 0 { duration = Double(frames.count) * 0.1 }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            return unclamped
        }
        if let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
            return delay
        }
        return 0.1
    }

    static func localVideoURL(for path: String) async -> URL? {
        await localFileURL(for: path, fallbackExtension: "mp4")
    }

    static func localAudioURL(for path: String) async -> URL? {
        await localFileURL(for: path, fallbackExtension: "m4a")
    }

    static func localDocumentURL(for path: String, fileName: String) async -> URL? {
        let ext = (fileName as NSString).pathExtension
        return await localFileURL(for: path, fallbackExtension: ext.isEmpty ? "bin" : ext, preferredName: fileName)
    }

    private static func downloadData(for path: String) async -> Data? {
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
            return data
        } catch {
            return nil
        }
    }

    private static func localFileURL(
        for path: String,
        fallbackExtension: String,
        preferredName: String? = nil
    ) async -> URL? {
        guard let data = await downloadData(for: path) else { return nil }
        let ext: String
        if let preferredName, !preferredName.isEmpty {
            let preferredExt = (preferredName as NSString).pathExtension
            ext = preferredExt.isEmpty ? fallbackExtension : preferredExt
        } else if let url = URL(string: path, relativeTo: APIConfig.baseURL), !url.pathExtension.isEmpty {
            ext = url.pathExtension
        } else {
            ext = fallbackExtension
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-playback-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }
}
