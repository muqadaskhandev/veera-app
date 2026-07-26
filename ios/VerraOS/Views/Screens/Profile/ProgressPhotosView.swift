//
//  ProgressPhotosView.swift
//  VerraOS
//

import PhotosUI
import SwiftUI

struct ProgressPhotosView: View {
    let client: Client
    var onBack: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(\.isReadOnly) private var isReadOnly

    @State private var sliderPosition: CGFloat = 0.5
    @State private var toast: ToastData?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false

    /// Logged photos, newest first.
    private var photos: [ProgressPhoto] { profile.photos(for: client.id) }
    private var latest: ProgressPhoto? { photos.first }
    private var earliest: ProgressPhoto? { photos.last }

    var body: some View {
        VStack(spacing: 0) {
            ProfileTopBar(
                title: "Progress Photos",
                subtitle: client.name.firstWord,
                // Clients can log their own progress photos too, same as weight —
                // this is not gated behind isReadOnly like trainer-only editing controls.
                trailing: AnyView(addButton),
                onBack: onBack
            )
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    if photos.count >= 2 {
                        SectionCard(title: "Before / After") {
                            VStack(alignment: .leading, spacing: 10) {
                                comparison
                                HStack {
                                    captionTag(label: earliest?.exactLabel ?? "Start", system: "calendar")
                                    Spacer()
                                    captionTag(label: latest?.exactLabel ?? "Now", system: "calendar")
                                }
                            }
                        }
                    }

                    galleryCard
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabScrollContent()
        }
        .background(Theme.Color.background)
        .toast($toast)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(from: item) }
        }
    }

    private var addButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Group {
                if isUploading {
                    ProgressView()
                        .tint(Theme.Color.accentInk)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(Theme.Color.accentInk)
            .frame(width: 42, height: 42)
            .background(Theme.Color.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
    }

    @MainActor
    private func uploadPhoto(from item: PhotosPickerItem) async {
        isUploading = true
        defer {
            isUploading = false
            pickerItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            toast = ToastData(message: "Could not load photo", icon: "exclamationmark.triangle.fill")
            return
        }
        if await profile.uploadPhoto(data: data, for: client.id) {
            toast = ToastData(message: "Photo uploaded", icon: "photo.badge.plus")
        } else {
            toast = ToastData(message: "Upload failed", icon: "exclamationmark.triangle.fill")
        }
    }

    private func captionTag(label: String, system: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: system).font(.system(size: 10, weight: .bold))
            Text(label).font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(Theme.Color.inkMuted)
    }

    private var galleryCard: some View {
        SectionCard(title: "Gallery · \(photos.count) photos") {
            if photos.isEmpty {
                Text("No photos yet — tap + to upload the first one.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(photos) { photo in
                        photoTile(photo)
                    }
                }
            }
        }
    }

    private var comparison: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                comparisonSide(photo: latest, label: "After")
                comparisonSide(photo: earliest, label: "Before")
                    .frame(width: max(0, w * sliderPosition))
                    .clipped()

                Rectangle()
                    .fill(Theme.Color.surface)
                    .frame(width: 3)
                    .overlay(
                        Circle()
                            .fill(Theme.Color.surface)
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Color.ink))
                            .cardShadow()
                    )
                    .position(x: w * sliderPosition, y: geo.size.height / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        sliderPosition = min(1, max(0, value.location.x / w))
                    }
            )
        }
        .frame(height: 260)
    }

    @ViewBuilder
    private func comparisonSide(photo: ProgressPhoto?, label: String) -> some View {
        if let photo, photo.hasRemoteImage, let url = photo.imageURL {
            ProgressPhotoImage(url: url, label: label)
        } else {
            placeholder(label: label, tint: Color(hex: photo?.tintHex ?? 0x8C887E))
        }
    }

    private func placeholder(label: String, tint: Color) -> some View {
        LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.25), in: Capsule())
                    .padding(10)
            }
            .overlay(
                Image(systemName: "figure.stand")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.5))
            )
    }

    private func photoTile(_ photo: ProgressPhoto) -> some View {
        VStack(spacing: 5) {
            Group {
                if photo.hasRemoteImage, let url = photo.imageURL {
                    ProgressPhotoImage(url: url)
                        .aspectRatio(0.78, contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color(hex: photo.tintHex).opacity(0.9), Color(hex: photo.tintHex).opacity(0.5)], startPoint: .top, endPoint: .bottom))
                        .aspectRatio(0.78, contentMode: .fit)
                        .overlay(
                            Image(systemName: "figure.stand")
                                .font(.system(size: 30, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.55))
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if !isReadOnly, photo.hasRemoteImage {
                    Menu {
                        Button(role: .destructive) {
                            Task {
                                if await profile.deletePhoto(photo.id, for: client.id) {
                                    toast = ToastData(message: "Photo deleted", icon: "trash")
                                } else {
                                    toast = ToastData(message: "Delete failed", icon: "exclamationmark.triangle.fill")
                                }
                            }
                        } label: { Label("Delete", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.black.opacity(0.25), in: Circle())
                            .padding(6)
                    }
                }
            }

            Text(photo.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
        }
    }
}

private struct ProgressPhotoImage: View {
    let url: String
    var label: String?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.Color.surfaceMuted
                    ProgressView()
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.25), in: Capsule())
                    .padding(10)
            }
        }
        .task(id: url) {
            image = await ChatAttachmentLoader.image(for: url)
        }
    }
}
