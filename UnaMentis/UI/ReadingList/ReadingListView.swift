// UnaMentis - Reading List View
// Main view for the Reading List feature
//
// Part of UI/ReadingList

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Reading List View

/// Main view for managing reading list items
public struct ReadingListView: View {
    @ObservedObject var viewModel: ReadingListViewModel
    @Binding var showFilePicker: Bool
    @Binding var showImportOptions: Bool

    public var body: some View {
        contentView
            .sheet(isPresented: $showFilePicker) {
            DocumentPicker(viewModel: viewModel)
        }
        .task {
            await viewModel.loadItems()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.selectedFilter {
        case .active:
            if viewModel.activeItems.isEmpty && !viewModel.isLoading {
                emptyActiveView
            } else {
                activeListView
            }
        case .completed:
            if viewModel.completedItems.isEmpty && !viewModel.isLoading {
                emptyCompletedView
            } else {
                completedListView
            }
        case .archived:
            if viewModel.archivedItems.isEmpty && !viewModel.isLoading {
                emptyArchivedView
            } else {
                archivedListView
            }
        }
    }

    // MARK: - Filter Picker

    private var filterPicker: some View {
        Picker("Filter", selection: $viewModel.selectedFilter) {
            ForEach(ReadingListFilter.allCases, id: \.self) { filter in
                Text(filter.displayName).tag(filter)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - List Views

    private var activeListView: some View {
        VStack(spacing: 0) {
            ContextualHelpBanner(
                message: "Tap the headphones icon to listen, or tap an item to read. PDF images appear during playback.",
                storageKey: "reading_list_tips"
            )

            List {
                ForEach(viewModel.activeItems) { item in
                    ReadingItemRow(item: item, viewModel: viewModel)
                }
            }
            .listStyle(.plain)
        }
    }

    private var completedListView: some View {
        List {
            ForEach(viewModel.completedItems) { item in
                ReadingItemRow(item: item, viewModel: viewModel)
            }
        }
        .listStyle(.plain)
    }

    private var archivedListView: some View {
        List {
            ForEach(viewModel.archivedItems) { item in
                ReadingItemRow(item: item, viewModel: viewModel)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty Views

    private var emptyActiveView: some View {
        ContentUnavailableView {
            Label("No Reading Items", systemImage: "book.pages")
        } description: {
            Text("Add PDFs, text files, markdown, or web articles to your reading list. Images from PDFs are extracted and displayed during playback.")
        } actions: {
            Button {
                showImportOptions = true
            } label: {
                Text("Add Content")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyCompletedView: some View {
        ContentUnavailableView {
            Label("No Completed Items", systemImage: "checkmark.circle")
        } description: {
            Text("Items you finish reading will appear here.")
        }
    }

    private var emptyArchivedView: some View {
        ContentUnavailableView {
            Label("No Archived Items", systemImage: "archivebox")
        } description: {
            Text("Archived reading items will appear here.")
        }
    }
}

// MARK: - Reading Item Row

/// A row displaying a reading list item
struct ReadingItemRow: View {
    let item: ReadingListItem
    @ObservedObject var viewModel: ReadingListViewModel
    @State private var showReader = false
    @State private var showPlayback = false

    var body: some View {
        Button {
            showReader = true
        } label: {
            HStack(spacing: 12) {
                // Source type icon
                Image(systemName: item.sourceType.iconName)
                    .font(.title2)
                    .foregroundStyle(item.sourceType.iconColor)
                    .frame(width: 32)

                // Title and metadata
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let author = item.author, !author.isEmpty {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Progress indicator
                        if item.status == .inProgress {
                            ProgressView(value: Double(item.percentComplete))
                                .frame(width: 60)
                        }

                        // Chunk count
                        Text("\(item.totalChunks) segments")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Quick-listen button (goes straight to audio playback)
                Button {
                    showPlayback = true
                } label: {
                    Image(systemName: "headphones")
                        .font(.body)
                        .foregroundStyle(.blue)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                // Status indicator
                Image(systemName: item.status.iconName)
                    .foregroundStyle(item.status.iconColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if item.status != .archived {
                Button(role: .destructive) {
                    Task { await viewModel.deleteItem(item) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    Task { await viewModel.archiveItem(item) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.gray)
            } else {
                Button(role: .destructive) {
                    Task { await viewModel.deleteItem(item) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if item.status == .inProgress || item.status == .unread {
                Button {
                    Task { await viewModel.completeItem(item) }
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .sheet(isPresented: $showReader) {
            ReadingReaderView(item: item)
        }
        .sheet(isPresented: $showPlayback) {
            ReadingPlaybackView(item: item)
        }
    }
}

// MARK: - Document Picker

/// Document picker for importing files
struct DocumentPicker: UIViewControllerRepresentable {
    @ObservedObject var viewModel: ReadingListViewModel
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.pdf, .plainText, .text]
        // Add markdown support
        if let mdType = UTType(filenameExtension: "md") {
            types.append(mdType)
        }
        if let markdownType = UTType(filenameExtension: "markdown") {
            types.append(markdownType)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(_ parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            Task { @MainActor in
                await parent.viewModel.importDocument(from: url)
                parent.dismiss()
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ReadingListView(
            viewModel: ReadingListViewModel(),
            showFilePicker: .constant(false),
            showImportOptions: .constant(false)
        )
    }
}
