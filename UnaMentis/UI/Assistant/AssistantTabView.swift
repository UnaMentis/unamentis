// UnaMentis - Assistant Tab View
// Container view with segmented control for To-Do and Reading List
//
// Part of UI/Assistant

import SwiftUI

// MARK: - Assistant Segment

/// The segments available in the Assistant tab
public enum AssistantSegment: String, CaseIterable, Identifiable {
    case todo = "To-Do"
    case readingList = "Reading"
    case review = "Review"

    public var id: String { rawValue }

    /// SF Symbol icon for the segment
    var iconName: String {
        switch self {
        case .todo: return "checklist"
        case .readingList: return "book.pages"
        case .review: return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Assistant Tab View

/// Container view for the Assistant tab with segmented navigation
///
/// Contains:
/// - To-Do list for tracking learning tasks
/// - Reading List for uploaded documents
public struct AssistantTabView: View {

    // MARK: - State

    @State private var selectedSegment: AssistantSegment = .todo
    @State private var showReadingFilePicker = false
    @State private var showImportOptions = false
    @State private var showURLImportSheet = false
    @StateObject private var readingViewModel = ReadingListViewModel()

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            segmentedPicker

            switch selectedSegment {
            case .todo:
                TodoListView()
            case .readingList:
                NavigationStack {
                    ReadingListView(
                        viewModel: readingViewModel,
                        showFilePicker: $showReadingFilePicker,
                        showImportOptions: $showImportOptions
                    )
                    .navigationTitle("Reading List")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showImportOptions = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Import content")
                        }
                    }
                    .confirmationDialog(
                        "Import to Reading List",
                        isPresented: $showImportOptions
                    ) {
                        Button("Import File") {
                            showReadingFilePicker = true
                        }
                        Button("Import from URL") {
                            showURLImportSheet = true
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Choose how to add content")
                    }
                    .sheet(isPresented: $showURLImportSheet) {
                        URLImportSheet(viewModel: readingViewModel)
                    }
                }
            case .review:
                NavigationStack {
                    ReviewListView()
                        .navigationTitle("Review")
                }
            }
        }
    }

    // MARK: - Subviews

    private var segmentedPicker: some View {
        VStack(spacing: 0) {
            Picker("Assistant Section", selection: $selectedSegment) {
                ForEach(AssistantSegment.allCases) { segment in
                    Text(segment.rawValue)
                        .tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()
        }
        .background(.bar)
    }
}

// MARK: - Preview

#Preview {
    AssistantTabView()
}
