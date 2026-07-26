//
//  ChatGIFPickerView.swift
//  VerraOS
//
//  Dedicated GIF browser backed by the Verra `/api/gifs` proxy (Giphy).
//

import SwiftUI

struct ChatGIFPickerView: View {
    var onSelect: (VerraAPI.GifDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var gifs: [VerraAPI.GifDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                content
            }
            .background(Theme.Color.background)
            .navigationTitle("GIFs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadTrending() }
        }
        .preferredColorScheme(.light)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Color.inkMuted)
            TextField("Search GIFs", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: query) { _, value in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        await search(value)
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    Task { await loadTrending() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Color.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Color.hairline, lineWidth: 1))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && gifs.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if let errorMessage, gifs.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Color.inkMuted)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await query.isEmpty ? loadTrending() : search(query) }
                }
                .font(.system(size: 14, weight: .semibold))
            }
            .padding()
            Spacer()
        } else if gifs.isEmpty {
            Spacer()
            Text("No GIFs found")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Color.inkMuted)
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(gifs) { gif in
                        Button {
                            onSelect(gif)
                            dismiss()
                        } label: {
                            AsyncImage(url: URL(string: gif.previewURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    Theme.Color.surfaceMuted
                                default:
                                    Theme.Color.surfaceMuted
                                        .overlay(ProgressView().scaleEffect(0.7))
                                }
                            }
                            .frame(minHeight: 110, maxHeight: 160)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .background(Theme.Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
    }

    private func loadTrending() async {
        guard let token = AuthStore.accessToken else {
            errorMessage = "Sign in to browse GIFs"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            gifs = try await VerraAPI.fetchTrendingGifs(accessToken: token)
        } catch {
            errorMessage = "Couldn't load GIFs"
        }
    }

    private func search(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            await loadTrending()
            return
        }
        guard let token = AuthStore.accessToken else {
            errorMessage = "Sign in to browse GIFs"
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            gifs = try await VerraAPI.searchGifs(query: trimmed, accessToken: token)
        } catch {
            errorMessage = "Couldn't search GIFs"
        }
    }
}
