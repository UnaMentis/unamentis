// UnaMentis - Visual Asset View
// UI components for displaying visual content during curriculum playback
//
// Part of UI/UX (TDD Section 10)

import SwiftUI

// MARK: - Visual Asset View

/// Main view for rendering a single visual asset
struct VisualAssetView: View {
    let asset: VisualAsset
    @State private var isFullscreen = false
    @State private var imageData: Data?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            switch asset.visualType {
            case .image, .diagram, .slideImage:
                ImageAssetView(
                    asset: asset,
                    imageData: imageData,
                    isLoading: isLoading,
                    loadError: loadError,
                    isFullscreen: $isFullscreen
                )
            case .equation:
                EquationAssetView(
                    latex: asset.latex ?? "",
                    title: asset.title,
                    isFullscreen: $isFullscreen
                )
            case .chart:
                ChartAssetView(asset: asset, isFullscreen: $isFullscreen)
            case .slideDeck:
                SlideDeckPreviewView(asset: asset)
            case .generated:
                GeneratedImageView(asset: asset, isFullscreen: $isFullscreen)
            }
        }
        .task {
            await loadImageData()
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            FullscreenVisualView(asset: asset, imageData: imageData)
        }
    }

    private func loadImageData() async {
        // 1. First try Core Data cached data
        if let cached = asset.cachedData {
            imageData = cached
            isLoading = false
            return
        }

        // 2. Then try VisualAssetCache (disk/memory cache)
        if let assetId = asset.assetId {
            if let cached = await VisualAssetCache.shared.retrieve(assetId: assetId) {
                imageData = cached
                isLoading = false
                // Also update Core Data for future quick access
                await MainActor.run {
                    asset.cachedData = cached
                }
                return
            }
        }

        // 3. Then try local file path (bundled or absolute)
        if let localPath = asset.localPath {
            // First try as bundled resource (relative path from app bundle)
            if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent(localPath),
               let data = try? Data(contentsOf: bundleURL) {
                imageData = data
                isLoading = false
                // Cache for future use
                if let assetId = asset.assetId {
                    try? await VisualAssetCache.shared.cache(assetId: assetId, data: data)
                }
                await MainActor.run {
                    asset.cachedData = data
                }
                return
            }

            // Then try as absolute path (for downloaded/cached files)
            let absoluteURL = URL(fileURLWithPath: localPath)
            if let data = try? Data(contentsOf: absoluteURL) {
                imageData = data
                isLoading = false
                // Cache for future use
                if let assetId = asset.assetId {
                    try? await VisualAssetCache.shared.cache(assetId: assetId, data: data)
                }
                await MainActor.run {
                    asset.cachedData = data
                }
                return
            }
        }

        // 4. Finally try remote URL (fallback, also caches result)
        if let remoteURL = asset.remoteURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: remoteURL)
                imageData = data
                isLoading = false

                // Cache in VisualAssetCache and Core Data
                if let assetId = asset.assetId {
                    try? await VisualAssetCache.shared.cache(assetId: assetId, data: data)
                }
                await MainActor.run {
                    asset.cachedData = data
                }
            } catch {
                loadError = "Failed to load image"
                isLoading = false
            }
        } else {
            isLoading = false
        }
    }
}

// MARK: - Image Asset View

struct ImageAssetView: View {
    let asset: VisualAsset
    let imageData: Data?
    let isLoading: Bool
    let loadError: String?
    @Binding var isFullscreen: Bool

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .frame(height: 150)
            } else if let error = loadError {
                VStack {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 150)
            } else if let data = imageData, let uiImage = platformImage(from: data) {
                Button {
                    isFullscreen = true
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                PlaceholderImageView(asset: asset)
            }

            // Caption
            if let caption = asset.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(asset.altText ?? asset.title ?? "Image")
    }

    #if os(iOS)
    private func platformImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }
    #else
    private func platformImage(from data: Data) -> NSImage? {
        NSImage(data: data)
    }
    #endif
}

// MARK: - Placeholder Image View

struct PlaceholderImageView: View {
    let asset: VisualAsset

    var body: some View {
        VStack {
            Image(systemName: asset.visualType.iconName)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            if let title = asset.title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
        }
    }
}

// MARK: - Equation Asset View

struct EquationAssetView: View {
    let latex: String
    let title: String?
    @Binding var isFullscreen: Bool

    var body: some View {
        VStack(spacing: 8) {
            Button {
                isFullscreen = true
            } label: {
                VStack(spacing: 4) {
                    // Simple LaTeX display - in production, use a proper LaTeX renderer
                    Text(formatLatexForDisplay(latex))
                        .font(.system(.body, design: .serif))
                        .italic()
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                        }

                    if let title = title {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }

    /// Basic LaTeX to display string conversion (placeholder for proper renderer)
    private func formatLatexForDisplay(_ latex: String) -> String {
        // This is a simplified version - a real app would use a LaTeX rendering library
        var formatted = latex
        // Remove common LaTeX commands and show plain text
        formatted = formatted.replacingOccurrences(of: "\\frac{", with: "(")
        formatted = formatted.replacingOccurrences(of: "}{", with: ")/(")
        formatted = formatted.replacingOccurrences(of: "}", with: ")")
        formatted = formatted.replacingOccurrences(of: "\\sigma", with: "σ")
        formatted = formatted.replacingOccurrences(of: "\\alpha", with: "α")
        formatted = formatted.replacingOccurrences(of: "\\beta", with: "β")
        formatted = formatted.replacingOccurrences(of: "\\gamma", with: "γ")
        formatted = formatted.replacingOccurrences(of: "\\pi", with: "π")
        formatted = formatted.replacingOccurrences(of: "\\sum", with: "Σ")
        formatted = formatted.replacingOccurrences(of: "\\int", with: "∫")
        formatted = formatted.replacingOccurrences(of: "^{", with: "^")
        formatted = formatted.replacingOccurrences(of: "_{", with: "_")
        formatted = formatted.replacingOccurrences(of: "\\", with: "")
        return formatted
    }
}

// MARK: - Chart Asset View

struct ChartAssetView: View {
    let asset: VisualAsset
    @Binding var isFullscreen: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Placeholder for chart rendering
            // In production, integrate with Swift Charts or a charting library
            VStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                if let title = asset.title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
            }
            .onTapGesture {
                isFullscreen = true
            }

            if let caption = asset.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Slide Deck Preview View

struct SlideDeckPreviewView: View {
    let asset: VisualAsset

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext.fill")
                .font(.title)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.title ?? "Slide Deck")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let description = asset.audioDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Generated Image View

struct GeneratedImageView: View {
    let asset: VisualAsset
    @Binding var isFullscreen: Bool
    @State private var isGenerating = false

    var body: some View {
        VStack(spacing: 8) {
            if isGenerating {
                VStack {
                    ProgressView()
                    Text("Generating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 150)
            } else if let data = asset.cachedData {
                #if os(iOS)
                if let image = UIImage(data: data) {
                    Button {
                        isFullscreen = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                #else
                if let image = NSImage(data: data) {
                    Button {
                        isFullscreen = true
                    } label: {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                #endif
            } else {
                VStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(.purple)
                    Text(asset.title ?? "Generated Image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.1))
                }
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Fullscreen Visual View

struct FullscreenVisualView: View {
    let asset: VisualAsset
    let imageData: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let data = imageData ?? asset.cachedData {
                    #if os(iOS)
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                    #else
                    if let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                    #endif
                } else if asset.visualType == .equation, let latex = asset.latex {
                    VStack {
                        Text(latex)
                            .font(.system(size: 24, design: .serif))
                            .italic()
                            .foregroundStyle(.white)
                            .padding()
                    }
                }
            }
            .navigationTitle(asset.title ?? "Visual")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Visual Asset Overlay

/// Overlay view that displays active visuals for the current segment
struct VisualAssetOverlay: View {
    let currentSegment: Int
    let topic: Topic?
    @Binding var isExpanded: Bool

    private var activeAssets: [VisualAsset] {
        guard let topic = topic else { return [] }
        return topic.visualAssetsForSegment(currentSegment)
    }

    /// Filter assets by display mode
    private var persistentAssets: [VisualAsset] {
        activeAssets.filter { $0.visualDisplayMode == .persistent }
    }

    private var highlightAssets: [VisualAsset] {
        activeAssets.filter { $0.visualDisplayMode == .highlight }
    }

    private var inlineAssets: [VisualAsset] {
        activeAssets.filter { $0.visualDisplayMode == .inline }
    }

    private var popupAssets: [VisualAsset] {
        activeAssets.filter { $0.visualDisplayMode == .popup }
    }

    /// Non-inline assets for the carousel/panel
    private var overlayAssets: [VisualAsset] {
        activeAssets.filter { $0.visualDisplayMode != .inline }
    }

    var body: some View {
        VStack {
            Spacer()

            if !overlayAssets.isEmpty {
                VStack(spacing: 8) {
                    // Collapse/expand button
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            Text("\(overlayAssets.count) visual\(overlayAssets.count == 1 ? "" : "s")")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        VisualAssetCarousel(assets: overlayAssets)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .animation(.spring(response: 0.3), value: activeAssets.count)
    }
}

// MARK: - iPad Split View for Visual Assets

/// Side panel for displaying visual assets on iPad
struct VisualAssetSidePanel: View {
    let currentSegment: Int
    let topic: Topic?

    private var activeAssets: [VisualAsset] {
        guard let topic = topic else { return [] }
        return topic.visualAssetsForSegment(currentSegment)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "photo.stack")
                    .foregroundStyle(.secondary)
                Text("Visual Content")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)

            if activeAssets.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No visuals for this segment")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(activeAssets, id: \.id) { asset in
                            VisualAssetView(asset: asset)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Inline Visual Asset View (for embedding in transcript)

/// Compact visual asset view for inline display within transcript
struct InlineVisualAssetView: View {
    let asset: VisualAsset
    @State private var isFullscreen = false
    @State private var imageData: Data?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            if isLoading {
                ProgressView()
                    .frame(height: 120)
            } else if let data = imageData {
                #if os(iOS)
                if let image = UIImage(data: data) {
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
                }
                #else
                if let image = NSImage(data: data) {
                    Button {
                        isFullscreen = true
                    } label: {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                #endif
            } else {
                // Placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 120)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            }

            // Caption
            if let caption = asset.caption {
                Text(caption)
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
            FullscreenVisualView(asset: asset, imageData: imageData)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(asset.altText ?? asset.title ?? "Image")
    }

    private func loadImageData() async {
        // 1. First try Core Data cached data
        if let cached = asset.cachedData {
            imageData = cached
            isLoading = false
            return
        }

        // 2. Then try VisualAssetCache (disk/memory cache)
        if let assetId = asset.assetId {
            if let cached = await VisualAssetCache.shared.retrieve(assetId: assetId) {
                imageData = cached
                isLoading = false
                await MainActor.run {
                    asset.cachedData = cached
                }
                return
            }
        }

        // 3. Then try local file path (bundled or absolute)
        if let localPath = asset.localPath {
            // First try as bundled resource (relative path from app bundle)
            if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent(localPath),
               let data = try? Data(contentsOf: bundleURL) {
                imageData = data
                isLoading = false
                if let assetId = asset.assetId {
                    try? await VisualAssetCache.shared.cache(assetId: assetId, data: data)
                }
                await MainActor.run {
                    asset.cachedData = data
                }
                return
            }

            // Then try as absolute path (for downloaded/cached files)
            let absoluteURL = URL(fileURLWithPath: localPath)
            if let data = try? Data(contentsOf: absoluteURL) {
                imageData = data
                isLoading = false
                if let assetId = asset.assetId {
                    try? await VisualAssetCache.shared.cache(assetId: assetId, data: data)
                }
                await MainActor.run {
                    asset.cachedData = data
                }
                return
            }
        }

        // 4. Finally try remote URL (fallback)
        if let remoteURL = asset.remoteURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: remoteURL)
                imageData = data
                isLoading = false

                // Cache for future use
                if let assetId = asset.assetId {
                    try? await VisualAssetCache.shared.cache(assetId: assetId, data: data)
                }
                await MainActor.run {
                    asset.cachedData = data
                }
            } catch {
                isLoading = false
            }
        } else {
            isLoading = false
        }
    }
}

// MARK: - Visual Asset Carousel

/// Horizontal scrolling carousel of visual assets
struct VisualAssetCarousel: View {
    let assets: [VisualAsset]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(assets, id: \.id) { asset in
                    VisualAssetView(asset: asset)
                        .frame(width: 280)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 250)
    }
}

// MARK: - Visual Request Detection

/// Utility for detecting visual requests in user speech
struct VisualRequestDetector {
    /// Keywords that indicate a visual request
    private static let visualKeywords = [
        "show", "display", "see", "look", "diagram", "image", "picture",
        "formula", "equation", "chart", "graph", "visual", "illustration"
    ]

    /// Patterns that strongly indicate a visual request
    private static let requestPatterns = [
        "show me", "can i see", "display the", "what does .* look like",
        "let me see", "show the"
    ]

    /// Determines if the transcript contains a visual request
    static func isVisualRequest(_ transcript: String) -> Bool {
        let lowercased = transcript.lowercased()

        // Check for direct patterns
        for pattern in requestPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(lowercased.startIndex..., in: lowercased)
                if regex.firstMatch(in: lowercased, options: [], range: range) != nil {
                    return true
                }
            }
        }

        // Check for keyword combinations
        let words = lowercased.components(separatedBy: .whitespaces)
        let matchingKeywords = words.filter { visualKeywords.contains($0) }
        return matchingKeywords.count >= 1
    }

    /// Extracts the subject of a visual request
    static func extractVisualSubject(_ transcript: String) -> String? {
        let lowercased = transcript.lowercased()

        // Try to extract what comes after "show me" or similar
        let patterns = [
            "show me the (.+)",
            "show me (.+)",
            "display the (.+)",
            "can i see the (.+)",
            "can i see (.+)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(lowercased.startIndex..., in: lowercased)
                if let match = regex.firstMatch(in: lowercased, options: [], range: range) {
                    if let subjectRange = Range(match.range(at: 1), in: lowercased) {
                        return String(lowercased[subjectRange])
                    }
                }
            }
        }

        return nil
    }
}

// MARK: - Preview

#Preview {
    VStack {
        // Placeholder preview since we don't have real Core Data objects
        Text("Visual Asset Views")
    }
}
