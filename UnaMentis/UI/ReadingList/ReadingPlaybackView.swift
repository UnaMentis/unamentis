// UnaMentis - Reading Playback View
// Full-featured playback interface for reading list items
//
// Part of UI/ReadingList

import SwiftUI

// MARK: - Reading Playback View

/// Full playback interface for reading a document aloud
public struct ReadingPlaybackView: View {
    let item: ReadingListItem
    @StateObject private var viewModel: ReadingPlaybackViewModel
    @Environment(\.dismiss) private var dismiss

    public init(item: ReadingListItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: ReadingPlaybackViewModel(item: item))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Content area
                contentArea

                Spacer()

                // Progress section
                progressSection

                // Playback controls
                controlsSection
            }
            .padding()
            .navigationTitle(item.title ?? "Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        Task {
                            await viewModel.stopPlayback()
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await viewModel.addBookmark() }
                        } label: {
                            Label("Add Bookmark", systemImage: "bookmark")
                        }

                        if !viewModel.bookmarks.isEmpty {
                            Divider()
                            ForEach(viewModel.bookmarks, id: \.id) { bookmark in
                                Button {
                                    Task { await viewModel.jumpToBookmark(bookmark) }
                                } label: {
                                    Label(
                                        bookmark.note ?? "Bookmark at \(bookmark.chunkIndex + 1)",
                                        systemImage: "bookmark.fill"
                                    )
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                await viewModel.loadAndPrepare()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { viewModel.showError = false }
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .onDisappear {
                Task { await viewModel.stopPlayback() }
            }
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 16) {
            // Current chunk text and inline images
            if let currentChunk = viewModel.currentChunkText {
                ScrollView {
                    VStack(spacing: 12) {
                        Text(currentChunk)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Inline images for this chunk
                        ForEach(viewModel.currentChunkImages) { asset in
                            ReadingInlineImageView(asset: asset)
                        }
                    }
                }
                .frame(maxHeight: viewModel.currentChunkImages.isEmpty ? 200 : 320)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                // Loading state
                VStack(spacing: 12) {
                    if viewModel.state == .loading {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Preparing audio...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Ready to play")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 200)
            }

            // Metadata
            HStack {
                if let author = item.author, !author.isEmpty {
                    Label(author, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label("\(item.totalChunks) segments", systemImage: "text.justify.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 8) {
            // Progress bar
            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .tint(.blue)

            // Time/position info
            HStack {
                Text("Segment \(viewModel.currentChunkIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("of \(viewModel.totalChunks)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(spacing: 16) {
            // Main playback controls
            HStack(spacing: 40) {
                // Skip backward
                Button {
                    Task { await viewModel.skipBackward() }
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title)
                        .foregroundStyle(.primary)
                }
                .disabled(!viewModel.canSkipBackward)

                // Play/Pause button
                Button {
                    Task { await viewModel.togglePlayPause() }
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                }
                .disabled(viewModel.state == .loading)

                // Skip forward
                Button {
                    Task { await viewModel.skipForward() }
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title)
                        .foregroundStyle(.primary)
                }
                .disabled(!viewModel.canSkipForward)
            }

            // State indicator
            if viewModel.state == .buffering {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Buffering...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.bottom, 32)
    }
}

// MARK: - Preview

#Preview {
    // Note: Preview requires a valid ReadingListItem from Core Data
    Text("ReadingPlaybackView requires a ReadingListItem")
}
