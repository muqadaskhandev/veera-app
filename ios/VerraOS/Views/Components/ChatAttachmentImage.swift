import ImageIO
import SwiftUI
import UIKit

struct ChatAttachmentImage: View {
    let path: String
    var cornerRadius: CGFloat = 20

    @State private var image: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let image {
                if image.images != nil {
                    // SwiftUI `Image` only shows the first GIF frame — use UIKit to animate.
                    AnimatedUIImageView(image: image)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else if loadFailed {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Theme.Color.surfaceMuted)
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Theme.Color.inkFaint)
                        Text("Couldn't load image")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
                }
            } else {
                SkeletonBone(height: 180, cornerRadius: cornerRadius)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: path) {
            loadFailed = false
            image = await ChatAttachmentLoader.image(for: path)
            if image == nil { loadFailed = true }
        }
    }
}

/// Hosts an animated `UIImage` in a full-bounds container so SwiftUI layout
/// doesn't collapse the UIImageView to zero size on device.
private struct AnimatedUIImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tag = 100
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        if image.images != nil {
            imageView.startAnimating()
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let imageView = uiView.viewWithTag(100) as? UIImageView else { return }
        if imageView.image !== image {
            imageView.image = image
        }
        if image.images != nil {
            imageView.startAnimating()
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        (uiView.viewWithTag(100) as? UIImageView)?.stopAnimating()
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
        guard isGIFData(data) || looksLikeAnimatedImage(data) else {
            // Still try ImageIO for multi-frame sources that aren't tagged GIF.
            return decodeAnimated(from: data)
        }
        return decodeAnimated(from: data)
    }

    private static func decodeAnimated(from data: Data) -> UIImage? {
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

    static func isGIFData(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let header = String(data: data.prefix(6), encoding: .ascii) ?? ""
        return header == "GIF87a" || header == "GIF89a"
    }

    private static func looksLikeAnimatedImage(_ data: Data) -> Bool {
        // WebP RIFF header — Giphy sometimes serves webp; ImageIO can still animate.
        guard data.count >= 12 else { return false }
        let riff = data.prefix(4)
        let webp = data.subdata(in: 8..<12)
        return riff == Data("RIFF".utf8) && webp == Data("WEBP".utf8)
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
                return unclamped
            }
            if let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
                return delay
            }
        }
        if let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
            if let unclamped = webp[kCGImagePropertyWebPUnclampedDelayTime] as? Double, unclamped > 0 {
                return unclamped
            }
            if let delay = webp[kCGImagePropertyWebPDelayTime] as? Double, delay > 0 {
                return delay
            }
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
        // Absolute remote URLs (e.g. public S3) fetch directly; API-relative
        // paths resolve against the configured backend and send the auth token.
        let url: URL?
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            url = URL(string: path)
        } else {
            url = URL(string: path, relativeTo: APIConfig.baseURL)
        }
        guard let url else { return nil }

        var request = URLRequest(url: url)
        if !(path.hasPrefix("http://") || path.hasPrefix("https://")),
           let token = AuthStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData

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
