// UnaMentis - History View
// Session history and playback
//
// Part of UI/UX (TDD Section 10)

import SwiftUI
import CoreData
import Logging
#if os(iOS)
import UIKit
#endif

/// Session history view showing past conversations
public struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    
    public init() { }
    
    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty {
                    EmptyHistoryView()
                } else {
                    SessionListView(sessions: viewModel.sessions)
                }
            }
            .navigationTitle("History")
            #if os(iOS)
            .toolbar {
                if !viewModel.sessions.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("Export All") {
                                viewModel.exportAllSessions()
                            }
                            Button("Clear History", role: .destructive) {
                                viewModel.showClearConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            #endif
            .confirmationDialog(
                "Clear History",
                isPresented: $viewModel.showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Sessions", role: .destructive) {
                    viewModel.clearHistory()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all session history.")
            }
            #if os(iOS)
            .sheet(isPresented: $viewModel.showExportSheet) {
                if let url = viewModel.exportURL {
                    ShareSheet(items: [url])
                }
            }
            #endif
        }
    }
}

// MARK: - Share Sheet

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Empty State

struct EmptyHistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "No Sessions Yet",
            systemImage: "clock.badge.questionmark",
            description: Text("Your conversation history will appear here after your first session.")
        )
    }
}

// MARK: - Session List

struct SessionListView: View {
    let sessions: [SessionSummary]
    
    var body: some View {
        List {
            ForEach(groupedSessions, id: \.0) { date, daySessions in
                Section {
                    ForEach(daySessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRowView(session: session)
                        }
                    }
                } header: {
                    Text(formatDate(date))
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
    
    private var groupedSessions: [(Date, [SessionSummary])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startTime)
        }
        return grouped.sorted { $0.key > $1.key }
    }
    
    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: SessionSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.topicName ?? "General Conversation")
                    .font(.headline)
                Spacer()
                Text(formatTime(session.startTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 16) {
                Label(formatDuration(session.duration), systemImage: "clock")
                Label("\(session.turnCount) turns", systemImage: "message")
                Label(formatCost(session.totalCost), systemImage: "dollarsign.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return "\(minutes)m"
    }
    
    private func formatCost(_ cost: Decimal) -> String {
        String(format: "$%.2f", NSDecimalNumber(decimal: cost).doubleValue)
    }
}

// MARK: - Session Detail

struct SessionDetailView: View {
    let session: SessionSummary
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Session info
                SessionInfoCard(session: session)
                
                // Transcript
                TranscriptCard(entries: session.transcriptPreview)
                
                // Metrics
                MetricsCard(latency: session.avgLatency, cost: session.totalCost)
            }
            .padding()
        }
        .navigationTitle("Session Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Export Transcript") { }
                    Button("Share") { }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        #endif
    }
}

struct SessionInfoCard: View {
    let session: SessionSummary
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(session.topicName ?? "General")
                        .font(.headline)
                    Text(formatDate(session.startTime))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(formatDuration(session.duration))
                        .font(.headline)
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct TranscriptCard: View {
    let entries: [TranscriptPreview]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transcript", systemImage: "text.quote")
                .font(.headline)
            
            ForEach(entries) { entry in
                HStack(alignment: .top) {
                    Image(systemName: entry.isUser ? "person.fill" : "cpu")
                        .foregroundStyle(entry.isUser ? .blue : .purple)
                    Text(entry.content)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
}

struct MetricsCard: View {
    let latency: TimeInterval
    let cost: Decimal
    
    var body: some View {
        HStack {
            VStack {
                Text(String(format: "%.0fms", latency * 1000))
                    .font(.title2.bold())
                Text("Avg Latency")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            VStack {
                Text(String(format: "$%.3f", NSDecimalNumber(decimal: cost).doubleValue))
                    .font(.title2.bold())
                Text("Total Cost")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - View Model

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var sessions: [SessionSummary] = []
    @Published var showClearConfirmation = false
    @Published var exportURL: URL?
    @Published var showExportSheet = false

    private let persistence = PersistenceController.shared
    private let logger = Logger(label: "com.unamentis.ui.history")

    init() {
        loadFromCoreData()
    }

    func loadFromCoreData() {
        do {
            let coreDataSessions = try persistence.fetchRecentSessions(limit: 100)
            sessions = coreDataSessions.compactMap { session -> SessionSummary? in
                guard let id = session.id,
                      let startTime = session.startTime else {
                    return nil
                }

                // Get transcript entries for preview
                let transcriptEntries = (session.transcript?.array as? [TranscriptEntry]) ?? []
                let preview = transcriptEntries.prefix(3).compactMap { entry -> TranscriptPreview? in
                    guard let content = entry.content, let role = entry.role else { return nil }
                    return TranscriptPreview(isUser: role == "user", content: String(content.prefix(100)))
                }

                // Calculate average latency from metrics snapshot if available
                var avgLatency: TimeInterval = 0.3 // default
                if let metricsData = session.metricsSnapshot {
                    // Try decoding the full MetricsSnapshot format first
                    if let metrics = try? JSONDecoder().decode(MetricsSnapshot.self, from: metricsData) {
                        avgLatency = TimeInterval(metrics.latencies.e2eMedianMs) / 1000.0
                    } else if let legacyMetrics = try? JSONDecoder().decode(SessionMetricsData.self, from: metricsData),
                              let lat = legacyMetrics.avgLatency {
                        avgLatency = lat
                    }
                }

                return SessionSummary(
                    id: id,
                    startTime: startTime,
                    duration: session.duration,
                    topicName: session.topic?.title,
                    turnCount: transcriptEntries.count,
                    totalCost: session.totalCost as Decimal? ?? 0,
                    avgLatency: avgLatency,
                    transcriptPreview: preview
                )
            }
        } catch {
            logger.error("Failed to fetch sessions: \(error.localizedDescription)")
            sessions = []
        }
    }

    func exportAllSessions() {
        do {
            let coreDataSessions = try persistence.fetchRecentSessions(limit: 1000)
            let exportData = coreDataSessions.map { session -> [String: Any] in
                var dict: [String: Any] = [
                    "id": session.id?.uuidString ?? "",
                    "startTime": session.startTime?.ISO8601Format() ?? "",
                    "duration": session.duration,
                    "totalCost": (session.totalCost as NSDecimalNumber?)?.doubleValue ?? 0
                ]

                if let topic = session.topic {
                    dict["topic"] = topic.title ?? "Unknown"
                }

                // Include transcript
                if let entries = session.transcript?.array as? [TranscriptEntry] {
                    dict["transcript"] = entries.map { entry in
                        [
                            "role": entry.role ?? "unknown",
                            "content": entry.content ?? "",
                            "timestamp": entry.timestamp?.ISO8601Format() ?? ""
                        ]
                    }
                }

                return dict
            }

            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)

            // Write to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "voicelearn_sessions_\(Date().ISO8601Format()).json"
            let fileURL = tempDir.appendingPathComponent(fileName)
            try jsonData.write(to: fileURL)

            exportURL = fileURL
            showExportSheet = true
        } catch {
            logger.error("Failed to export sessions: \(error.localizedDescription)")
        }
    }

    func clearHistory() {
        let context = persistence.viewContext

        // Fetch all sessions
        let request = Session.fetchRequest()
        do {
            let sessions = try context.fetch(request)
            for session in sessions {
                context.delete(session)
            }
            try persistence.save()
            self.sessions.removeAll()
        } catch {
            logger.error("Failed to clear sessions: \(error.localizedDescription)")
        }
    }
}

// Helper struct for session metrics decoding from legacy format
private struct SessionMetricsData: Codable {
    let avgLatency: TimeInterval?
    let totalCost: Double?
}

// MARK: - Data Models

struct SessionSummary: Identifiable {
    let id: UUID
    let startTime: Date
    let duration: TimeInterval
    let topicName: String?
    let turnCount: Int
    let totalCost: Decimal
    let avgLatency: TimeInterval
    let transcriptPreview: [TranscriptPreview]
}

struct TranscriptPreview: Identifiable {
    let id = UUID()
    let isUser: Bool
    let content: String
}

// MARK: - Preview

#Preview {
    HistoryView()
}
