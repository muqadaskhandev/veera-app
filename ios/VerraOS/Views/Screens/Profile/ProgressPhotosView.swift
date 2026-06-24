//
//  ProgressPhotosView.swift
//  VerraOS
//

import SwiftUI

struct ProgressPhotosView: View {
    let client: Client
    var onBack: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(\.isReadOnly) private var isReadOnly

    @State private var sliderPosition: CGFloat = 0.5
    @State private var toast: ToastData?

    /// Logged photos, newest first.
    private var photos: [ProgressPhoto] { profile.photos(for: client.id) }
    private var latest: ProgressPhoto? { photos.first }
    private var earliest: ProgressPhoto? { photos.last }

    var body: some View {
        VStack(spacing: 0) {
            ProfileTopBar(
                title: "Progress Photos",
                subtitle: client.name.firstWord,
                trailing: isReadOnly ? nil : AnyView(addButton),
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

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Install this app on your device via the Rork App to capture photos.")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.Color.inkFaint)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, 100)
            }
        }
        .background(Theme.Color.background)
        .toast($toast)
    }

    private var addButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                profile.addPhoto(for: client.id)
            }
            toast = ToastData(message: "Photo added to log", icon: "photo.badge.plus")
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 42, height: 42)
                .background(Theme.Color.accent, in: Circle())
        }
        .buttonStyle(.plain)
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
                Text(isReadOnly ? "No photos yet." : "No photos yet — tap + to add the first one.")
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
                placeholder(label: "After", tint: Color(hex: latest?.tintHex ?? 0x8C887E))
                placeholder(label: "Before", tint: Color(hex: earliest?.tintHex ?? 0xB6B2A8))
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
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(hex: photo.tintHex).opacity(0.9), Color(hex: photo.tintHex).opacity(0.5)], startPoint: .top, endPoint: .bottom))
                .aspectRatio(0.78, contentMode: .fit)
                .overlay(
                    Image(systemName: "figure.stand")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.55))
                )
                .overlay(alignment: .topTrailing) {
                    if !isReadOnly {
                        Menu {
                            Button(role: .destructive) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                    profile.deletePhoto(photo.id, for: client.id)
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
