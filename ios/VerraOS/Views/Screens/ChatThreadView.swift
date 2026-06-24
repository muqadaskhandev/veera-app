//
//  ChatThreadView.swift
//  VerraOS
//
//  Level 2 + 3 — the active chat thread. Context header with a profile shortcut,
//  a message stream with tap-back reactions and media bubbles, and a rich input
//  bar with text, camera (tap photo / hold video), gallery, and voice tools.
//

import SwiftUI

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
    @State private var isRecordingVoice = false
    @State private var voiceSeconds = 0
    @State private var isRecordingVideo = false
    @State private var voiceTimer: Timer?

    private var conversation: Conversation? { store.conversation(id: conversationID) }
    private var client: Client? {
        guard let cid = conversation?.clientID else { return nil }
        return clientStore.clients.first { $0.id == cid }
    }

    private var orderedMessages: [Message] {
        (conversation?.messages ?? []).sorted { $0.minutesAgo > $1.minutesAgo }
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
        .onAppear { if !coachMode { app.isChatThreadOpen = true } }
        .onDisappear { if !coachMode { app.isChatThreadOpen = false } }
    }

    private func content(_ conversation: Conversation) -> some View {
        VStack(spacing: 0) {
            header(conversation)
            messageStream
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
                if coachMode {
                    Text(coachSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.Color.inkMuted)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(conversation.lastActiveMinutes < 15 ? Color(hex: 0x57C77B) : Theme.Color.inkFaint)
                            .frame(width: 6, height: 6)
                        Text(conversation.lastActiveMinutes < 1 ? "Active now" : "Active \(relativeTime(minutes: conversation.lastActiveMinutes)) ago")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Color.inkMuted)
                    }
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

    // MARK: Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if isRecordingVoice {
                recordingStrip(label: "Recording voice note", color: Theme.Color.danger)
            } else if isRecordingVideo {
                recordingStrip(label: "Recording video message", color: Theme.Color.accentInk)
            }

            HStack(alignment: .bottom, spacing: 8) {
                mediaButton(icon: "photo.on.rectangle") {
                    store.send(.photo, to: conversationID)
                    toast = ToastData(message: "Photo sent · use on device for live capture", icon: "photo.fill")
                    triggerReply()
                }

                cameraButton

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .font(.system(size: 15.5, weight: .medium))
                        .lineLimit(1...5)
                        .padding(.leading, 4)

                    if draft.trimmingCharacters(in: .whitespaces).isEmpty {
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
    }

    private func recordingStrip(label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.Color.danger).frame(width: 9, height: 9)
                .opacity(0.9)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.ink)
            Spacer()
            if isRecordingVoice {
                Text(String(format: "0:%02d", voiceSeconds))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 10)
        .background(Theme.Color.surfaceMuted)
    }

    private func mediaButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.Color.inkMuted)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    /// Tap = photo, long-press (hold) = record a video message, release sends.
    private var cameraButton: some View {
        Image(systemName: isRecordingVideo ? "video.fill" : "camera")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isRecordingVideo ? Theme.Color.accentInk : Theme.Color.inkMuted)
            .frame(width: 40, height: 40)
            .background(isRecordingVideo ? Theme.Color.accent : Color.clear, in: Circle())
            .scaleEffect(isRecordingVideo ? 1.12 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecordingVideo)
            .gesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        withAnimation { isRecordingVideo = true }
                    }
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { _ in
                        if isRecordingVideo {
                            withAnimation { isRecordingVideo = false }
                            store.send(.video, to: conversationID)
                            toast = ToastData(message: "Video message sent · use on device for live capture", icon: "video.fill")
                            triggerReply()
                        }
                    }
            )
            .highPriorityGesture(
                TapGesture().onEnded {
                    store.send(.photo, to: conversationID)
                    toast = ToastData(message: "Photo sent · use on device for live capture", icon: "camera.fill")
                    triggerReply()
                }
            )
    }

    private var micButton: some View {
        Button {
            if isRecordingVoice {
                stopVoiceRecording(send: true)
            } else {
                startVoiceRecording()
            }
        } label: {
            Image(systemName: isRecordingVoice ? "stop.circle.fill" : "mic")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isRecordingVoice ? Theme.Color.danger : Theme.Color.inkMuted)
        }
        .buttonStyle(.plain)
    }

    private var sendButton: some View {
        Button {
            let text = draft.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            store.send(.text(text), to: conversationID)
            draft = ""
            triggerReply()
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

    // MARK: Voice recording (simulated)

    private func startVoiceRecording() {
        isRecordingVoice = true
        voiceSeconds = 0
        voiceTimer?.invalidate()
        voiceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            voiceSeconds += 1
        }
    }

    private func stopVoiceRecording(send: Bool) {
        voiceTimer?.invalidate()
        voiceTimer = nil
        let seconds = max(1, voiceSeconds)
        withAnimation { isRecordingVoice = false }
        if send {
            store.send(.voice(seconds: seconds), to: conversationID)
            toast = ToastData(message: "Voice note sent · use on device for live capture", icon: "mic.fill")
            triggerReply()
        }
        voiceSeconds = 0
    }

    private func triggerReply() {
        Task { await store.simulateReply(to: conversationID) }
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: Message
    var onLongPress: () -> Void

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
            mediaTile(icon: "photo.fill", label: "Photo", aspect: 1.1)
        case .video:
            mediaTile(icon: "play.fill", label: "Video message", aspect: 1.0)
        case .voice(let seconds):
            voiceBubble(seconds: seconds)
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

    private func voiceBubble(seconds: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(message.isOutgoing ? Theme.Color.accentInk : Theme.Color.ink)
            HStack(spacing: 2.5) {
                ForEach(0..<18, id: \.self) { i in
                    Capsule()
                        .fill((message.isOutgoing ? Theme.Color.accentInk : Theme.Color.inkMuted).opacity(0.7))
                        .frame(width: 2.5, height: waveformHeight(i))
                }
            }
            Text(String(format: "0:%02d", seconds))
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundStyle(message.isOutgoing ? Theme.Color.accentInk.opacity(0.8) : Theme.Color.inkMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(outgoingStroke)
    }

    private func waveformHeight(_ index: Int) -> CGFloat {
        let pattern: [CGFloat] = [8, 14, 20, 11, 24, 16, 9, 18, 26, 13, 7, 19, 22, 10, 15, 23, 12, 8]
        return pattern[index % pattern.count]
    }
}
