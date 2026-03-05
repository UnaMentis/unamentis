// UnaMentis - Reading Inline Image View
// Displays images extracted from PDFs during reading playback
//
// Follows the curriculum InlineVisualAssetView pattern with simplified
// 2-tier loading: cachedData -> localPath
//
// Part of UI/ReadingList

import SwiftUI

// MARK: - Reading Inline Image View

/// Displays an inline image extracted from a PDF during reading playback
struct ReadingInlineImageView: View {
    let asset: ReadingVisualAssetData
    @State private var isFullscreen = false
    @State private var imageData: Data?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            if isLoading {
                ProgressView()
                    .frame(height: 120)
            } else if let data = imageData, let image = UIImage(data: data) {
                Button {
                    isFullscreen = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                placeholderView
            }

            if let altText = asset.altText, !altText.isEmpty {
                Text(altText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
        .frame(maxWidth: 300)
        .task {
            await loadImageData()
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            fullscreenView
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(asset.altText ?? "Image from page \(asset.chunkIndex + 1)")
        .accessibilityHint("Double-tap to view fullscreen")
    }

    // MARK: - Subviews

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.2))
            .frame(height: 120)
            .overlay {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }

    private var fullscreenView: some View {
        NavigationStack {
            Group {
                if let data = imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                } else {
                    placeholderView
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isFullscreen = false
                    }
                }
            }
        }
    }

    // MARK: - Image Loading

    private func loadImageData() async {
        // 1. Try Core Data cached data
        if let cached = asset.cachedData {
            imageData = cached
            isLoading = false
            return
        }

        // 2. Try VisualAssetCache (shared memory/disk cache)
        let assetId = asset.id.uuidString
        if let cached = await VisualAssetCache.shared.retrieve(assetId: assetId) {
            imageData = cached
            isLoading = false
            return
        }

        // 3. Try local file path
        if let localPath = asset.localPath {
            let url = URL(fileURLWithPath: localPath)
            if let data = try? Data(contentsOf: url) {
                imageData = data
                isLoading = false
                try? await VisualAssetCache.shared.cache(assetId: assetId, data: data)
                return
            }
        }

        isLoading = false
    }
}

// MARK: - Preview

#Preview {
    ReadingInlineImageView(
        asset: ReadingVisualAssetData(
            id: UUID(),
            chunkIndex: 0,
            localPath: nil,
            cachedData: nil,
            width: 200,
            height: 150,
            altText: "Sample diagram"
        )
    )
}
