//
//  ChatThreadView.swift
//  VerraOS
//
//  Level 2 + 3 — the active chat thread. Context header with a profile shortcut,
//  a message stream with tap-back reactions and media bubbles, and a rich input
//  bar with text, camera (tap photo / hold video), gallery, and voice tools.
//

import SwiftUI
import PhotosUI
import AVKit

struct ChatThreadView: View {
    let conversationID: UUID
    @Binding var path: NavigationPath
    /// When true, the thread is shown to a client talking to their coach: the
    /// header shows the coach instead of the client, the profile shortcut is
    /// hidden, and the bottom tab bar is kept visible.
    var coachMode: Bool = false
    var coachName: String = ""
    var coachSubtitle: String = ""
    var showsBack: Bool = true
    /// Optional override for the back button (used when the thread isn't on a
    /// navigation stack, e.g. the client's full-screen Messages tab).
    var onBack: (() -> Void)? = nil

    @Environment(MessageStore.self) private var store
    @Environment(ClientStore.self) private var clientStore
    @Environment(AppState.self) private var app

    @State private var draft: String = ""
    @State private var reactionTarget: Message?
    @State private var toast: ToastData?
    @State private var voiceRecorder = ChatVoiceRecorder()
    @State private var galleryItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var cameraMode: CameraPicker.Mode = .photo
    @State private var isUploadingMedia = false

    private var conversation: Conversation? { store.conversation(id: conversationID) }
    private var client: Client? {
        guard let cid = conversation?.clientID else { return nil }
        return clientStore.clients.first { $0.id == cid }
    }

    private var orderedMessages: [Message] {
        (conversation?.messages ?? []).sorted { $0.sentAt < $1.sentAt }
    }

    var body: some View {
        Group {
            if let conversation {
                content(conversation)
            } else {
                VStack { Spacer(); Text("Conversation unavailable").foregroundStyle(Theme.Color.inkMuted); Spacer() }
            }
        }
        .background(Theme.Color.background)
        .toast($toast)
        .overlay {
            if let target = reactionTarget {
                reactionOverlay(for: target)
            }
        }
        .onAppear {
            if !coachMode { app.isChatThreadOpen = true }
            Task { await store.loadMessages(for: conversationID) }
        }
        .onDisappear {
            if voiceRecorder.isRecording { voiceRecorder.cancel() }
            ChatVoicePlayer.shared.stop()
            if !coachMode { app.isChatThreadOpen = false }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(mode: cameraMode) { capture in
                showingCamera = false
                guard let capture else { return }
                Task { await handleCameraCapture(capture) }
            }
            .ignoresSafeArea()
        }
    }

    private func content(_ conversation: Conversation) -> some View {
        VStack(spacing: 0) {
            header(conversation)
            messageStream
            if store.typingConversationIDs.contains(conversationID) {
                typingIndicator
            }
            inputBar
        }
    }

    // MARK: Header

    private func header(_ conversation: Conversation) -> some View {
        HStack(spacing: 11) {
            if showsBack {
                Button {
                    if let onBack { onBack() }
                    else if !path.isEmpty { path.removeLast() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Color.ink)
                        .frame(width: 40, height: 40)
                        .background(Theme.Color.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Circle()
                .fill(Theme.Color.ink)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(coachMode ? coachName.initialsValue : conversation.initials)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.accent)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(coachMode ? coachName : conversation.clientName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Color.ink)
                    .lineLimit(1)
                if coachMode, !coachSubtitle.isEmpty {
                    Text(coachSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(conversation.presenceIsLive ? Color(hex: 0x57C77B) : Theme.Color.inkFaint)
                        .frame(width: 6, height: 6)
                    Text(conversation.presenceLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                }
            }
            Spacer(minLength: 6)

            if let client, !coachMode {
                Button { path.append(client) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 13, weight: .bold))
                        Text("Profile")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Theme.Color.accentInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.Color.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Color.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Color.hairline).frame(height: 1) }
    }

    // MARK: Message stream

    private var messageStream: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    ForEach(orderedMessages) { message in
                        MessageBubble(message: message) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                                reactionTarget = message
                            }
                        }
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
            .onChange(of: orderedMessages.count) { _, _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Reaction overlay

    private func reactionOverlay(for message: Message) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { reactionTarget = nil }
                }
            VStack {
                HStack(spacing: 10) {
                    ForEach(Reaction.allCases) { reaction in
                        Button {
                            store.setReaction(reaction, messageID: message.id, in: conversationID)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { reactionTarget = nil }
                            toast = ToastData(message: "Reacted \(reaction.rawValue)", icon: "face.smiling.fill")
                        } label: {
                            Text(reaction.rawValue)
                                .font(.system(size: 30))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.Color.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.Color.hairline, lineWidth: 1))
                .cardShadow()
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    private var typingIndicator: some View {
        HStack {
            Text(coachMode ? "\(coachName) is typing…" : "Typing…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, 4)
    }

    // MARK: Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if voiceRecorder.isRecording {
                recordingStrip(label: "Recording voice note", color: Theme.Color.danger)
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $galleryItem, matching: .any(of: [.images, .videos])) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(isUploadingMedia || voiceRecorder.isRecording)
                .onChange(of: galleryItem) { _, item in
                    guard let item else { return }
                    galleryItem = nil
                    Task { await handleGallerySelection(item) }
                }

                cameraButton

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .font(.system(size: 15.5, weight: .medium))
                        .lineLimit(1...5)
                        .padding(.leading, 4)
                        .onChange(of: draft) { _, value in
                            let isTyping = !value.trimmingCharacters(in: .whitespaces).isEmpty
                            store.sendTyping(conversationID: conversationID, isTyping: isTyping)
                        }

                    if draft.trimmingCharacters(in: .whitespaces).isEmpty, !voiceRecorder.isRecording {
                        micButton
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.Color.hairline, lineWidth: 1))

                if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    sendButton
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(Theme.Color.background)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Color.hairline).frame(height: 1) }
        .overlay {
            if isUploadingMedia {
                ZStack {
                    Color.black.opacity(0.12)
                    ProgressView("Sending…")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Theme.Color.surface, in: Capsule())
                }
            }
        }
    }

    private func recordingStrip(label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.Color.danger).frame(width: 9, height: 9)
                .opacity(0.9)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
            Spacer()
            if voiceRecorder.isRecording {
                Text(String(format: "0:%02d", voiceRecorder.elapsedSeconds))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 10)
        .background(Theme.Color.surfaceMuted)
    }

    /// Tap = photo, long-press = record a video message.
    private var cameraButton: some View {
        Image(systemName: "camera")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(Theme.Color.inkMuted)
            .frame(width: 40, height: 40)
            .opacity(isUploadingMedia || voiceRecorder.isRecording ? 0.4 : 1)
            .disabled(isUploadingMedia || voiceRecorder.isRecording)
            .gesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        cameraMode = .video
                        showingCamera = true
                    }
            )
            .highPriorityGesture(
                TapGesture().onEnded {
                    cameraMode = .photo
                    showingCamera = true
                }
            )
    }

    private var micButton: some View {
        Button {
            if voiceRecorder.isRecording {
                Task { await stopVoiceRecording(send: true) }
            } else {
                Task { await startVoiceRecording() }
            }
        } label: {
            Image(systemName: voiceRecorder.isRecording ? "stop.circle.fill" : "mic")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(voiceRecorder.isRecording ? Theme.Color.danger : Theme.Color.inkMuted)
        }
        .buttonStyle(.plain)
        .disabled(isUploadingMedia)
    }

    private var sendButton: some View {
        Button {
            let text = draft.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            draft = ""
            store.sendTyping(conversationID: conversationID, isTyping: false)
            Task { await store.send(.text(text), to: conversationID) }
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Color.accentInk)
                .frame(width: 40, height: 40)
                .background(Theme.Color.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: Voice recording

    @MainActor
    private func startVoiceRecording() async {
        do {
            try await voiceRecorder.start()
        } catch {
            toast = ToastData(message: error.localizedDescription, icon: "mic.slash.fill")
        }
    }

    @MainActor
    private func stopVoiceRecording(send: Bool) async {
        if !send {
            voiceRecorder.cancel()
            return
        }

        guard let result = voiceRecorder.stop() else { return }

        isUploadingMedia = true
        defer { isUploadingMedia = false }

        guard let upload = ChatMediaService.prepareVoice(from: result.url, duration: result.duration) else {
            try? FileManager.default.removeItem(at: result.url)
            toast = ToastData(message: "Couldn't process voice note", icon: "exclamationmark.triangle.fill")
            return
        }

        await sendPreparedUpload(upload, successMessage: "Voice note sent", icon: "mic.fill")
        try? FileManager.default.removeItem(at: result.url)
    }

    @MainActor
    private func handleGallerySelection(_ item: PhotosPickerItem) async {
        isUploadingMedia = true
        defer { isUploadingMedia = false }

        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try? await item.loadTransferable(type: ChatMovie.self),
                  let upload = ChatMediaService.prepareVideo(from: movie.url) else {
                toast = ToastData(message: "Couldn't load that video", icon: "exclamationmark.triangle.fill")
                return
            }
            await sendPreparedUpload(upload, successMessage: "Video sent", icon: "video.fill")
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let upload = ChatMediaService.preparePhoto(from: data) else {
            toast = ToastData(message: "Couldn't load that photo", icon: "exclamationmark.triangle.fill")
            return
        }
        await sendPreparedUpload(upload, successMessage: "Photo sent", icon: "photo.fill")
    }

    @MainActor
    private func handleCameraCapture(_ capture: CameraPicker.Capture) async {
        isUploadingMedia = true
        defer { isUploadingMedia = false }

        switch capture {
        case .photo(let data):
            guard let upload = ChatMediaService.preparePhoto(from: data) else {
                toast = ToastData(message: "Couldn't process photo", icon: "exclamationmark.triangle.fill")
                return
            }
            await sendPreparedUpload(upload, successMessage: "Photo sent", icon: "camera.fill")
        case .video(let url):
            guard let upload = ChatMediaService.prepareVideo(from: url) else {
                toast = ToastData(message: "Couldn't process video", icon: "exclamationmark.triangle.fill")
                return
            }
            await sendPreparedUpload(upload, successMessage: "Video sent", icon: "video.fill")
        }
    }

    @MainActor
    private func sendPreparedUpload(
        _ upload: ChatMediaService.PreparedUpload,
        successMessage: String,
        icon: String
    ) async {
        let sent = await store.sendAttachment(upload, to: conversationID)
        if sent {
            toast = ToastData(message: successMessage, icon: icon)
        } else {
            toast = ToastData(message: "Couldn't send attachment", icon: "exclamationmark.triangle.fill")
        }
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: Message
    var onLongPress: () -> Void

    @State private var playbackURL: URL?
    @State private var isLoadingVideo = false

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 50) }
            bubble
                .overlay(alignment: message.isOutgoing ? .bottomLeading : .bottomTrailing) {
                    if let reaction = message.reaction {
                        Text(reaction.rawValue)
                            .font(.system(size: 14))
                            .padding(4)
                            .background(Theme.Color.surface, in: Circle())
                            .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                            .offset(x: message.isOutgoing ? -6 : 6, y: 10)
                    }
                }
                .onLongPressGesture(minimumDuration: 0.3) { onLongPress() }
            if !message.isOutgoing { Spacer(minLength: 50) }
        }
        .sheet(isPresented: Binding(
            get: { playbackURL != nil },
            set: { if !$0 { playbackURL = nil } }
        )) {
            if let playbackURL {
                VideoPlayer(player: AVPlayer(url: playbackURL))
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder private var bubble: some View {
        switch message.kind {
        case .text(let body):
            Text(body)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(message.isOutgoing ? Theme.Color.accentInk : Theme.Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 20))
                .overlay(outgoingStroke)
        case .photo:
            if let path = message.attachmentURL {
                ChatAttachmentImage(path: path)
                    .frame(width: 220, height: 220)
            } else {
                mediaTile(icon: "photo.fill", label: "Photo", aspect: 1.1)
            }
        case .video:
            if let path = message.attachmentURL {
                videoAttachment(path: path)
            } else {
                mediaTile(icon: "play.fill", label: "Video message", aspect: 1.0)
            }
        case .voice(let seconds):
            VoiceNoteBubble(
                message: message,
                seconds: seconds,
                bubbleBackground: bubbleBackground,
                isOutgoing: message.isOutgoing
            )
        }
    }

    private var bubbleBackground: Color {
        message.isOutgoing ? Theme.Color.accent : Theme.Color.surface
    }

    @ViewBuilder private var outgoingStroke: some View {
        if !message.isOutgoing {
            RoundedRectangle(cornerRadius: 20).stroke(Theme.Color.hairline, lineWidth: 1)
        }
    }

    private func mediaTile(icon: String, label: String, aspect: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(message.isOutgoing ? Theme.Color.accentInk : Theme.Color.ink)
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.Color.accent)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.background.opacity(0.8))
            }
        }
        .frame(width: 168, height: 168 / aspect)
    }

    private func videoAttachment(path: String) -> some View {
        Button {
            guard !isLoadingVideo else { return }
            isLoadingVideo = true
            Task {
                let url = await ChatAttachmentLoader.localVideoURL(for: path)
                await MainActor.run {
                    isLoadingVideo = false
                    playbackURL = url
                }
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(message.isOutgoing ? Theme.Color.accentInk : Theme.Color.ink)
                    .frame(width: 220, height: 220)
                if isLoadingVideo {
                    ProgressView()
                        .tint(Theme.Color.accent)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 52, weight: .regular))
                        .foregroundStyle(Theme.Color.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func waveformHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [8, 14, 20, 11, 24, 16, 9, 18, 26, 13, 7, 19, 22, 10, 15, 23, 12, 8]
        return pattern[index % pattern.count]
    }
}

private struct VoiceNoteBubble: View {
    let message: Message
    let seconds: Int
    let bubbleBackground: Color
    let isOutgoing: Bool

    @State private var voicePlayer = ChatVoicePlayer.shared
    @State private var isLoading = false

    private var isPlaying: Bool {
        voicePlayer.isPlaying(messageID: message.id)
    }

    var body: some View {
        Button {
            guard let path = message.attachmentURL else { return }
            Task {
                isLoading = true
                _ = await voicePlayer.toggle(messageID: message.id, path: path)
                isLoading = false
            }
        } label: {
            HStack(spacing: 10) {
                Group {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .foregroundStyle(isOutgoing ? Theme.Color.accentInk : Theme.Color.ink)
                .frame(width: 16)

                HStack(spacing: 2.5) {
                    ForEach(0..<18, id: \.self) { i in
                        Capsule()
                            .fill((isOutgoing ? Theme.Color.accentInk : Theme.Color.inkMuted).opacity(isPlaying ? 1 : 0.7))
                            .frame(width: 2.5, height: waveformHeight(i))
                    }
                }

                Text(String(format: "0:%02d", seconds))
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isOutgoing ? Theme.Color.accentInk.opacity(0.8) : Theme.Color.inkMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                if !isOutgoing {
                    RoundedRectangle(cornerRadius: 20).stroke(Theme.Color.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(message.attachmentURL == nil)
    }

    private func waveformHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [8, 14, 20, 11, 24, 16, 9, 18, 26, 13, 7, 19, 22, 10, 15, 23, 12, 8]
        let scale: CGFloat = isPlaying ? 1.15 : 1
        return pattern[index % pattern.count] * scale
    }
}
