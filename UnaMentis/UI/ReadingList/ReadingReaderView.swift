// UnaMentis - Reading Reader View
// Full-text visual reading with bookmark navigation and audio start-from-here
//
// This view allows users to read the full text of a reading list item,
// navigate via bookmarks, scroll freely, and switch to audio playback
// from any position in the document.
//
// Part of UI/ReadingList

import SwiftUI

// MARK: - Reading Reader View

/// Full-text reader for reading list items with audio integration
public struct ReadingReaderView: View {
    let item: ReadingListItem
    @StateObject private var viewModel: ReadingPlaybackViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scrolledChunkIndex: Int32 = 0
    @State private var showBookmarkSheet = false
    @State private var bookmarkNote = ""
    @State private var isAudioMode = false

    public init(item: ReadingListItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: ReadingPlaybackViewModel(item: item))
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Main text content
                readerContent

                // Bottom control bar
                bottomBar
            }
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
                    bookmarkMenu
                }
            }
            .task {
                await viewModel.loadAndPrepare()
                scrolledChunkIndex = item.currentChunkIndex
            }
            .sheet(isPresented: $showBookmarkSheet) {
                bookmarkSheet
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { viewModel.showError = false }
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .onDisappear {
                Task { await viewModel.suspendPlayback() }
            }
        }
    }

    // MARK: - Reader Content

    private var readerContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Document header
                    documentHeader

                    // All chunks as continuous text
                    ForEach(Array(item.chunksArray.enumerated()), id: \.element.id) { index, chunk in
                        chunkView(chunk: chunk, index: Int32(index))
                            .id(chunk.index)
                    }

                    // Bottom padding for the floating bar
                    Spacer()
                        .frame(height: 120)
                }
                .padding(.horizontal)
            }
            .onChange(of: scrolledChunkIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .top)
                }
            }
            .onChange(of: viewModel.currentChunkIndex) { _, newIndex in
                if viewModel.hasActivePlayback {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Document Header

    private var documentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let author = item.author, !author.isEmpty {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(item.totalChunks) sections", systemImage: "text.justify.left")
                Label(item.sourceType.displayName, systemImage: item.sourceType.iconName)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Divider()
                .padding(.top, 4)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Chunk View

    private func chunkView(chunk: ReadingChunk, index: Int32) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Chunk text with tap to set scroll position
            Text(chunk.text ?? "")
                .font(.body)
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .background(chunkBackground(for: index))
                .contentShape(Rectangle())
                .onTapGesture {
                    scrolledChunkIndex = index
                }

            // Inline images for this chunk
            let images = item.visualAssets(forChunkIndex: index)
                .map { asset in
                    ReadingVisualAssetData(
                        id: asset.id ?? UUID(),
                        chunkIndex: asset.chunkIndex,
                        localPath: asset.localPath,
                        cachedData: asset.cachedData,
                        width: asset.width,
                        height: asset.height,
                        altText: asset.altText
                    )
                }

            if !images.isEmpty {
                ForEach(images) { imageAsset in
                    ReadingInlineImageView(asset: imageAsset)
                        .frame(maxWidth: .infinity)
                }
            }

            // Bookmark indicator
            if let bookmark = viewModel.bookmarks.first(where: { $0.chunkIndex == index }) {
                bookmarkIndicator(bookmark)
            }
        }
    }

    /// Background highlight for the currently active chunk
    private func chunkBackground(for index: Int32) -> some ShapeStyle {
        if viewModel.hasActivePlayback && viewModel.currentChunkIndex == index {
            return AnyShapeStyle(Color.blue.opacity(0.08))
        }
        if scrolledChunkIndex == index && !viewModel.hasActivePlayback {
            return AnyShapeStyle(Color.blue.opacity(0.04))
        }
        return AnyShapeStyle(Color.clear)
    }

    /// Small bookmark indicator between chunks
    private func bookmarkIndicator(_ bookmark: ReadingBookmarkData) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(.orange)

            Text(bookmark.note ?? "Bookmarked")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            scrolledChunkIndex = bookmark.chunkIndex
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 12) {
                // Progress indicator
                if viewModel.totalChunks > 0 {
                    ProgressView(value: viewModel.hasActivePlayback
                                 ? viewModel.progress
                                 : Double(scrolledChunkIndex) / Double(max(viewModel.totalChunks - 1, 1)))
                        .tint(viewModel.hasActivePlayback ? .blue : .gray)
                }

                // Controls
                HStack(spacing: 24) {
                    // Section info
                    Text("Section \(viewModel.hasActivePlayback ? viewModel.currentChunkIndex + 1 : scrolledChunkIndex + 1) of \(viewModel.totalChunks)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 80, alignment: .leading)

                    Spacer()

                    if viewModel.hasActivePlayback {
                        // Audio playback controls (visible during play, pause, and buffering)
                        playbackControls
                    } else {
                        // Listen from here button
                        Button {
                            Task {
                                await startAudioFromPosition(scrolledChunkIndex)
                            }
                        } label: {
                            Label("Listen", systemImage: "headphones")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.state == .loading)
                    }

                    // Bookmark button
                    Button {
                        showBookmarkSheet = true
                    } label: {
                        Image(systemName: hasBookmarkAtPosition ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(hasBookmarkAtPosition ? .orange : .primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Playback Controls (inline in bottom bar)

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button {
                Task { await viewModel.skipBackward() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.body)
            }
            .disabled(!viewModel.canSkipBackward)

            Button {
                Task { await viewModel.togglePlayPause() }
            } label: {
                if viewModel.state == .buffering {
                    ProgressView()
                        .frame(width: 32)
                        .accessibilityLabel("Buffering audio")
                } else {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 32)
                        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
                }
            }
            .disabled(viewModel.state == .buffering)

            Button {
                Task { await viewModel.skipForward() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body)
            }
            .disabled(!viewModel.canSkipForward)

            // Stop button
            Button {
                Task { await viewModel.stopPlayback() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bookmark Menu

    private var bookmarkMenu: some View {
        Menu {
            Button {
                showBookmarkSheet = true
            } label: {
                Label("Add Bookmark Here", systemImage: "bookmark")
            }

            if !viewModel.bookmarks.isEmpty {
                Divider()
                ForEach(viewModel.bookmarks, id: \.id) { bookmark in
                    Button {
                        scrolledChunkIndex = bookmark.chunkIndex
                    } label: {
                        Label(
                            bookmark.note ?? "Section \(bookmark.chunkIndex + 1)",
                            systemImage: "bookmark.fill"
                        )
                    }
                }
            }
        } label: {
            Image(systemName: "bookmark.circle")
        }
    }

    // MARK: - Bookmark Sheet

    private var bookmarkSheet: some View {
        NavigationStack {
            Form {
                Section("Add Bookmark") {
                    Text("Section \(scrolledChunkIndex + 1) of \(viewModel.totalChunks)")
                        .foregroundStyle(.secondary)

                    TextField("Note (optional)", text: $bookmarkNote)
                }
            }
            .navigationTitle("Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        bookmarkNote = ""
                        showBookmarkSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.addBookmark(
                                note: bookmarkNote.isEmpty ? nil : bookmarkNote,
                                atChunk: scrolledChunkIndex
                            )
                            bookmarkNote = ""
                            showBookmarkSheet = false
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var hasBookmarkAtPosition: Bool {
        viewModel.bookmarks.contains { $0.chunkIndex == scrolledChunkIndex }
    }

    /// Start audio playback from a specific section
    private func startAudioFromPosition(_ chunkIndex: Int32) async {
        await viewModel.startPlaybackFromChunk(chunkIndex)
    }
}

// MARK: - Preview

#Preview {
    Text("ReadingReaderView requires a ReadingListItem")
}
