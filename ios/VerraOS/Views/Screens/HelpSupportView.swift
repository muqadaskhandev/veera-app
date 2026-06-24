//
//  HelpSupportView.swift
//  VerraOS
//

import SwiftUI
import PhotosUI

/// Contact Us / Report a Bug form. Pick a topic, write a message, optionally
/// attach a screenshot, and send (simulated with a confirmation toast).
struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var topic: SupportTopic = .bug
    @State private var message = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var attachment: UIImage?
    @State private var toast: ToastData?

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    intro
                    topicSection
                    messageSection
                    attachmentSection
                    sendButton
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, 44)
            }
            .background(Theme.Color.background)
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Color.ink)
                }
            }
            .toast($toast)
            .onChange(of: pickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadImage(newValue) }
            }
        }
    }

    private var intro: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.Color.accent.opacity(0.2)).frame(width: 48, height: 48)
                Image(systemName: "lifepreserver.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Theme.Color.accentInk)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("How can we help?")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Color.ink)
                Text("Pick a topic and tell us what's going on.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Topic")
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(SupportTopic.allCases) { option in
                    let selected = topic == option
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { topic = option }
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: option.icon)
                                .font(.system(size: 18, weight: .semibold))
                            Text(option.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(selected ? Theme.Color.accentInk : Theme.Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selected ? Theme.Color.accent : Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(selected ? Color.clear : Theme.Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Message")
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Theme.Color.inkFaint)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $message)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.Color.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
        }
    }

    private var placeholder: String {
        switch topic {
        case .bug: return "Describe what broke and what you expected to happen…"
        case .question: return "What would you like to know?"
        case .billing: return "Tell us about your billing question…"
        }
    }

    @ViewBuilder
    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(topic == .bug ? "Screenshot" : "Attachment (optional)")
            if let attachment {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: attachment)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Color.hairline, lineWidth: 1))
                    Button {
                        withAnimation { self.attachment = nil; pickerItem = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Color.background)
                            .frame(width: 30, height: 30)
                            .background(Theme.Color.ink.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    HStack(spacing: 10) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Attach a screenshot")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(Theme.Color.ink)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .strokeBorder(Theme.Color.inkFaint.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            Text("Send Message")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(canSend ? Theme.Color.accentInk : Theme.Color.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canSend ? Theme.Color.accent : Theme.Color.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private func send() {
        message = ""
        attachment = nil
        pickerItem = nil
        toast = ToastData(message: "Message sent — we'll be in touch", icon: "paperplane.fill")
    }

    private func loadImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await MainActor.run {
            withAnimation { attachment = image }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.Color.inkFaint)
    }
}
