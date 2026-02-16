// UnaMentis - Review List View
// Hierarchical view of items flagged for review, organized by source material
//
// Part of UI/Review

import SwiftUI
import Logging

// MARK: - Review List View

/// Displays review items organized hierarchically by their source material.
///
/// Items are grouped by source (reading list document, curriculum topic, session)
/// so users can see all flagged items from a single source together. Each item
/// shows a snippet preview and can be tapped to see full context.
public struct ReviewListView: View {

    @StateObject private var viewModel = ReviewListViewModel()

    public init() {}

    public var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading...")
            } else if viewModel.groups.isEmpty {
                emptyState
            } else {
                groupedList
            }
        }
        .onAppear {
            viewModel.loadItems()
        }
    }

    // MARK: - Grouped List

    private var groupedList: some View {
        List {
            ForEach(viewModel.groups) { group in
                Section {
                    ForEach(group.items, id: \.id) { item in
                        ReviewItemRow(item: item) {
                            viewModel.selectedItem = item
                        }
                        .swipeActions(edge: .trailing) {
                            if item.status == .pending {
                                Button {
                                    viewModel.markReviewed(item)
                                } label: {
                                    Label("Reviewed", systemImage: "checkmark.circle")
                                }
                                .tint(.blue)
                            }
                            if item.status != .mastered {
                                Button {
                                    viewModel.markMastered(item)
                                } label: {
                                    Label("Mastered", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button(role: .destructive) {
                                viewModel.deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: group.sourceType.iconName)
                            .foregroundStyle(.secondary)
                        Text(group.sourceTitle)
                        Spacer()
                        Text("\(group.pendingCount) pending")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $viewModel.selectedItem) { item in
            ReviewItemDetailSheet(item: item)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Review Items", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("Say \"flag\" or \"flag this\" while listening to mark content for review.")
        }
    }
}

// MARK: - Review Item Row

private struct ReviewItemRow: View {
    let item: ReinforcementItemData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: item.status.iconName)
                        .foregroundStyle(statusColor)
                        .font(.caption)
                    Text(item.snippetPreview ?? item.currentSegmentText.prefix(80).description)
                        .font(.subheadline)
                        .lineLimit(2)
                }

                HStack {
                    Text("Segment \(item.segmentIndex + 1) of \(item.totalSegments)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch item.status {
        case .pending: return .orange
        case .reviewed: return .blue
        case .mastered: return .green
        }
    }
}

// MARK: - Review Item Detail Sheet

private struct ReviewItemDetailSheet: View {
    let item: ReinforcementItemData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Source info
                    HStack {
                        Image(systemName: item.sourceType.iconName)
                        Text(item.sourceTitle)
                            .font(.headline)
                    }
                    .foregroundStyle(.secondary)

                    Text("Segment \(item.segmentIndex + 1) of \(item.totalSegments)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    // Current segment
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Flagged Segment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(item.currentSegmentText)
                            .font(.body)
                    }

                    // Previous segment (context)
                    if let previousText = item.previousSegmentText, !previousText.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Previous Segment (Context)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(previousText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Status
                    HStack {
                        Text("Status:")
                            .foregroundStyle(.secondary)
                        Image(systemName: item.status.iconName)
                        Text(item.status.displayName)
                    }
                    .font(.subheadline)
                }
                .padding()
            }
            .navigationTitle("Review Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Review List View Model

@MainActor
final class ReviewListViewModel: ObservableObject {
    @Published var groups: [ReinforcementSourceGroup] = []
    @Published var isLoading = false
    @Published var selectedItem: ReinforcementItemData?

    private let logger = Logger(label: "com.unamentis.ui.review")

    func loadItems() {
        isLoading = true
        defer { isLoading = false }

        guard let manager = ReinforcementManager.shared else {
            logger.warning("ReinforcementManager not initialized")
            return
        }

        do {
            groups = try manager.fetchItemsGroupedBySource()
        } catch {
            logger.error("Failed to load review items: \(error.localizedDescription)")
        }
    }

    func markReviewed(_ item: ReinforcementItemData) {
        guard let manager = ReinforcementManager.shared else { return }

        do {
            let items = try manager.fetchAllItems()
            if let managedItem = items.first(where: { $0.id == item.id }) {
                try manager.markReviewed(managedItem)
                loadItems()
            }
        } catch {
            logger.error("Failed to mark reviewed: \(error.localizedDescription)")
        }
    }

    func markMastered(_ item: ReinforcementItemData) {
        guard let manager = ReinforcementManager.shared else { return }

        do {
            let items = try manager.fetchAllItems()
            if let managedItem = items.first(where: { $0.id == item.id }) {
                try manager.markMastered(managedItem)
                loadItems()
            }
        } catch {
            logger.error("Failed to mark mastered: \(error.localizedDescription)")
        }
    }

    func deleteItem(_ item: ReinforcementItemData) {
        guard let manager = ReinforcementManager.shared else { return }

        do {
            let items = try manager.fetchAllItems()
            if let managedItem = items.first(where: { $0.id == item.id }) {
                try manager.deleteItem(managedItem)
                loadItems()
            }
        } catch {
            logger.error("Failed to delete item: \(error.localizedDescription)")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ReviewListView()
            .navigationTitle("Review")
    }
}
