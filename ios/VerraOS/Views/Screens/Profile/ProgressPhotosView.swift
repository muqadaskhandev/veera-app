//
//  ProgressPhotosView.swift
//  VerraOS
//

import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProgressPhotosView: View {
    let client: Client
    var onBack: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(\.openURL) private var openURL

    @State private var sliderPosition: CGFloat = 0.5
    @State private var toast: ToastData?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var showLibraryPicker = false
    @State private var showCamera = false
    @State private var showPermissionAlert = false
    @State private var permissionAlertMessage = ""

    /// Logged photos, newest first.
    private var photos: [ProgressPhoto] { profile.photos(for: client.id) }
    private var latest: ProgressPhoto? { photos.first }
    private var earliest: ProgressPhoto? { photos.last }

    var body: some View {
        VStack(spacing: 0) {
            ProfileTopBar(
                title: "Progress Photos",
                subtitle: client.name.firstWord,
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
        .photosPicker(isPresented: $showLibraryPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await uploadFromLibrary(item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(mode: .photo) { capture in
                showCamera = false
                guard case .photo(let data)? = capture else { return }
                Task { await uploadImageData(data, source: "camera") }
            }
            .ignoresSafeArea()
        }
        .alert("Photo Access Needed", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(permissionAlertMessage)
        }
    }

    private var addButton: some View {
        Menu {
            Button {
                Task { await requestLibraryAndPick() }
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    Task { await requestCameraAndCapture() }
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
        } label: {
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
        .disabled(isUploading)
    }

    @MainActor
    private func requestLibraryAndPick() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized, .limited:
            showLibraryPicker = true
        case .denied, .restricted:
            permissionAlertMessage = "Allow photo library access in Settings so you can upload progress photos."
            showPermissionAlert = true
        case .notDetermined:
            break
        @unknown default:
            permissionAlertMessage = "Allow photo library access in Settings so you can upload progress photos."
            showPermissionAlert = true
        }
    }

    @MainActor
    private func requestCameraAndCapture() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                showCamera = true
            } else {
                permissionAlertMessage = "Allow camera access in Settings so you can take progress photos."
                showPermissionAlert = true
            }
        case .denied, .restricted:
            permissionAlertMessage = "Allow camera access in Settings so you can take progress photos."
            showPermissionAlert = true
        @unknown default:
            permissionAlertMessage = "Allow camera access in Settings so you can take progress photos."
            showPermissionAlert = true
        }
    }

    @MainActor
    private func uploadFromLibrary(_ item: PhotosPickerItem) async {
        isUploading = true
        defer {
            isUploading = false
            pickerItem = nil
        }

        guard let data = await ProgressPhotoDataLoader.data(from: item) else {
            toast = ToastData(message: "Could not load photo", icon: "exclamationmark.triangle.fill")
            return
        }
        await uploadImageData(data, source: "library", alreadyUploading: true)
    }

    @MainActor
    private func uploadImageData(_ data: Data, source: String, alreadyUploading: Bool = false) async {
        if !alreadyUploading { isUploading = true }
        defer { if !alreadyUploading { isUploading = false } }

        guard let prepared = ChatMediaService.preparePhoto(from: data, maxDimension: 2000) else {
            toast = ToastData(message: "Could not process photo", icon: "exclamationmark.triangle.fill")
            return
        }

        do {
            try await profile.uploadPhoto(
                data: prepared.data,
                filename: prepared.filename,
                mimeType: prepared.mimeType,
                for: client.id
            )
            toast = ToastData(message: "Photo uploaded", icon: "photo.badge.plus")
        } catch {
            toast = ToastData(
                message: error.localizedDescription.isEmpty ? "Upload failed" : error.localizedDescription,
                icon: "exclamationmark.triangle.fill"
            )
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
                Text("No photos yet — tap + to upload from your library or camera.")
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
            // Fixed-aspect cell: the image fills it via overlay and gets
            // clipped, so scaledToFill can never push the grid around.
            Color.clear
                .aspectRatio(0.78, contentMode: .fit)
                .overlay {
                    if photo.hasRemoteImage, let url = photo.imageURL {
                        ProgressPhotoImage(url: url)
                    } else {
                        LinearGradient(colors: [Color(hex: photo.tintHex).opacity(0.9), Color(hex: photo.tintHex).opacity(0.5)], startPoint: .top, endPoint: .bottom)
                            .overlay(
                                Image(systemName: "figure.stand")
                                    .font(.system(size: 30, weight: .ultraLight))
                                    .foregroundStyle(.white.opacity(0.55))
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if photo.hasRemoteImage {
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

// MARK: - Robust PhotosPicker loading

/// `PhotosPickerItem.loadTransferable(Data.self)` often returns nil for HEIC /
/// limited-library assets. This loader tries several representations.
enum ProgressPhotoDataLoader {
    static func data(from item: PhotosPickerItem) async -> Data? {
        if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
            return data
        }
        if let photo = try? await item.loadTransferable(type: ProgressPhotoTransfer.self) {
            return photo.data
        }
        return nil
    }
}

private struct ProgressPhotoTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ProgressPhotoTransfer(data: data)
        }
        DataRepresentation(importedContentType: .jpeg) { data in
            ProgressPhotoTransfer(data: data)
        }
        DataRepresentation(importedContentType: .heic) { data in
            ProgressPhotoTransfer(data: data)
        }
        DataRepresentation(importedContentType: .png) { data in
            ProgressPhotoTransfer(data: data)
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
                // GeometryReader pins the image to the container's exact size
                // so scaledToFill overflow is clipped instead of stretching
                // the surrounding layout (grid cells stay aligned).
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
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
