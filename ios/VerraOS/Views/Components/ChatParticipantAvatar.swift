import SwiftUI

struct ChatParticipantAvatar: View {
    let initials: String
    let avatarURL: String?
    var size: CGFloat = 40

    @State private var imageData: Data?

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Theme.Color.ink)
                    .overlay(
                        Text(initials)
                            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.accent)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: avatarURL) {
            imageData = await ProfileLoader.downloadAvatar(path: avatarURL)
        }
    }
}

struct ClientAvatarView: View {
    let client: Client
    var size: CGFloat = 92

    var body: some View {
        ChatParticipantAvatar(
            initials: client.initials,
            avatarURL: client.avatarURL,
            size: size
        )
        .cardShadow(0.8)
    }
}
