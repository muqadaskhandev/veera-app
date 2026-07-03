import SwiftUI

struct ExerciseThumbnail: View {
    let url: String?
    var cornerRadius: CGFloat = 10
    var placeholderIcon: String = "figure.strengthtraining.traditional"

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
                    Image(systemName: placeholderIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkFaint)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await ChatAttachmentLoader.image(for: url)
        }
    }
}

struct ExerciseCategoryChip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(isSelected ? Theme.Color.accentInk : Theme.Color.inkMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.Color.accent : Theme.Color.surfaceMuted, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
