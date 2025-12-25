// UnaMentis - Topic Selection View
// UI for selecting which topics to download from a curriculum
//
// Part of Curriculum UI (Phase 4 Integration)

import SwiftUI
import Combine
import Logging

// MARK: - Topic Selection View

struct TopicSelectionView: View {
    let curriculum: CurriculumSummary
    let detail: CurriculumDetail?
    let onDownload: (Set<String>) async -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloadManager = CurriculumDownloadManager.shared
    @State private var selectedTopicIds: Set<String> = []
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var showingError = false

    private static let logger = Logger(label: "com.unamentis.curriculum.topicselection")

    var topics: [TopicSummary] {
        detail?.topics.sorted { $0.orderIndex < $1.orderIndex } ?? []
    }

    var selectedCount: Int {
        selectedTopicIds.count
    }

    var totalCount: Int {
        topics.count
    }

    var allSelected: Bool {
        selectedTopicIds.count == topics.count && !topics.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Download/Progress Section
                downloadHeaderSection
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))

                Divider()

                // Topic List
                if let detail = detail {
                    topicListContent(detail: detail)
                } else {
                    ProgressView("Loading topics...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Select Topics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDownloading {
                            Task {
                                await CurriculumDownloadManager.shared.cancelDownload(for: curriculum.id)
                            }
                        }
                        onCancel()
                    }
                }
            }
            .alert("Download Failed", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(downloadError ?? "An unknown error occurred.")
            }
            .onAppear {
                // Select all topics by default
                selectedTopicIds = Set(topics.map { $0.id })
            }
            .onChange(of: currentProgress?.state) { _, newState in
                if let state = newState {
                    switch state {
                    case .completed:
                        isDownloading = false
                    case .failed(let error):
                        isDownloading = false
                        downloadError = error
                        showingError = true
                    case .notStarted:
                        isDownloading = false
                    default:
                        break
                    }
                }
            }
        }
    }

    private var currentProgress: CurriculumDownloadProgress? {
        downloadManager.activeDownloads[curriculum.id]
    }

    // MARK: - Header Section

    @ViewBuilder
    private var downloadHeaderSection: some View {
        VStack(spacing: 12) {
            // Curriculum info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(curriculum.title)
                        .font(.headline)
                    Text("\(totalCount) topics available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if isDownloading, let progress = currentProgress {
                // Progress view
                downloadProgressView(progress: progress)
            } else {
                // Selection controls and download button
                selectionControlsView
            }
        }
    }

    @ViewBuilder
    private var selectionControlsView: some View {
        VStack(spacing: 12) {
            // Select all / deselect all
            HStack {
                Button {
                    if allSelected {
                        selectedTopicIds.removeAll()
                    } else {
                        selectedTopicIds = Set(topics.map { $0.id })
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(allSelected ? .blue : .secondary)
                        Text(allSelected ? "Deselect All" : "Select All")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(selectedCount) of \(totalCount) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Download button
            Button {
                Task {
                    await startDownload()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(selectedCount == totalCount ? "Download All Topics" : "Download \(selectedCount) Topics")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selectedTopicIds.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(selectedTopicIds.isEmpty)
        }
    }

    @ViewBuilder
    private func downloadProgressView(progress: CurriculumDownloadProgress) -> some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * progress.overallProgress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: progress.overallProgress)
                }
            }
            .frame(height: 8)

            // Status text
            HStack {
                if let currentTopic = progress.currentTopicTitle {
                    Text(currentTopic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Int(progress.overallProgress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Cancel button
            Button(role: .cancel) {
                Task {
                    await CurriculumDownloadManager.shared.cancelDownload(for: curriculum.id)
                    isDownloading = false
                }
            } label: {
                Text("Cancel Download")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Topic List

    @ViewBuilder
    private func topicListContent(detail: CurriculumDetail) -> some View {
        List {
            ForEach(topics) { topic in
                TopicSelectionRow(
                    topic: topic,
                    isSelected: selectedTopicIds.contains(topic.id),
                    isDownloading: isDownloading
                ) {
                    toggleTopic(topic.id)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func toggleTopic(_ id: String) {
        guard !isDownloading else { return }

        if selectedTopicIds.contains(id) {
            selectedTopicIds.remove(id)
        } else {
            selectedTopicIds.insert(id)
        }
    }

    @MainActor
    private func startDownload() async {
        guard !selectedTopicIds.isEmpty else { return }

        isDownloading = true
        downloadError = nil

        Self.logger.info("Starting download for \(selectedTopicIds.count) topics")

        await onDownload(selectedTopicIds)
    }

    private func checkDownloadProgress() {
        if let progress = currentProgress {
            switch progress.state {
            case .completed:
                isDownloading = false
            case .failed(let error):
                isDownloading = false
                downloadError = error
                showingError = true
            case .notStarted:
                isDownloading = false
            default:
                break
            }
        }
    }
}

// MARK: - Topic Selection Row

struct TopicSelectionRow: View {
    let topic: TopicSummary
    let isSelected: Bool
    let isDownloading: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)

                // Topic info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(topic.orderIndex + 1).")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(topic.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }

                    if !topic.description.isEmpty {
                        Text(topic.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 12) {
                        if topic.hasTranscript {
                            Label("\(topic.segmentCount) segments", systemImage: "text.quote")
                        }
                        if topic.assessmentCount > 0 {
                            Label("\(topic.assessmentCount) quizzes", systemImage: "checkmark.circle")
                        }
                        if let duration = topic.duration {
                            Label(formatDuration(duration), systemImage: "clock")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .opacity(isDownloading ? 0.6 : 1.0)
    }

    private func formatDuration(_ ptDuration: String) -> String {
        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: ptDuration, range: NSRange(ptDuration.startIndex..., in: ptDuration)) else {
            return ptDuration
        }

        var hours = 0
        var minutes = 0

        if let hourRange = Range(match.range(at: 1), in: ptDuration) {
            hours = Int(ptDuration[hourRange]) ?? 0
        }
        if let minRange = Range(match.range(at: 2), in: ptDuration) {
            minutes = Int(ptDuration[minRange]) ?? 0
        }

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Preview

#Preview {
    TopicSelectionView(
        curriculum: CurriculumSummary(
            id: "test",
            title: "Test Curriculum",
            description: "A test curriculum",
            version: "1.0",
            topicCount: 5,
            totalDuration: "PT2H",
            difficulty: "Intermediate",
            ageRange: nil,
            keywords: ["test", "example"]
        ),
        detail: nil,
        onDownload: { _ in },
        onCancel: { }
    )
}
