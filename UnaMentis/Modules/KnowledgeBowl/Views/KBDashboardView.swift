// UnaMentis - Knowledge Bowl Dashboard View
// Main dashboard for the Knowledge Bowl training module
//
// Displays domain mastery radar, study session options,
// and quick access to competition simulation.

import SwiftUI
import Logging

/// Main dashboard view for Knowledge Bowl module
struct KBDashboardView: View {
    @State private var selectedStudyMode: KBStudyMode?
    @State private var showingDomainDetail: KBDomain?

    private static let logger = Logger(label: "com.unamentis.kb.dashboard")

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero section with mastery overview
                heroSection

                // Domain mastery radar chart
                domainRadarSection

                // Study session options
                studyModeSection

                // Quick stats
                statsSection
            }
            .padding()
        }
        .navigationTitle("Knowledge Bowl")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .sheet(item: $selectedStudyMode) { mode in
            NavigationStack {
                KBStudyModeView(mode: mode)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                selectedStudyMode = nil
                            }
                        }
                    }
            }
        }
        .sheet(item: $showingDomainDetail) { domain in
            NavigationStack {
                KBDomainDetailView(domain: domain)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingDomainDetail = nil
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: 12) {
            // Readiness score
            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.2), lineWidth: 12)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: 0.0)  // Will be dynamic
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("0%")
                        .font(.title.bold())
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Competition Readiness")
                .font(.headline)

            Text("Complete a diagnostic session to see your readiness score")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Domain Radar Section

    @ViewBuilder
    private var domainRadarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Domain Mastery")
                    .font(.headline)
                Spacer()
                Button("View All") {
                    // Show domain list
                }
                .font(.subheadline)
            }

            // Simplified radar visualization (placeholder for now)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(KBDomain.allCases.prefix(6)) { domain in
                    DomainMasteryCard(domain: domain, mastery: 0.0)
                        .onTapGesture {
                            showingDomainDetail = domain
                        }
                }
            }

            // Show remaining domains in smaller view
            if KBDomain.allCases.count > 6 {
                HStack(spacing: 8) {
                    ForEach(Array(KBDomain.allCases.dropFirst(6))) { domain in
                        DomainMasteryBadge(domain: domain, mastery: 0.0)
                            .onTapGesture {
                                showingDomainDetail = domain
                            }
                    }
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Study Mode Section

    @ViewBuilder
    private var studyModeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Study Sessions")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(KBStudyMode.allCases) { mode in
                    StudyModeCard(mode: mode)
                        .onTapGesture {
                            Self.logger.info("Selected study mode: \(mode.rawValue)")
                            selectedStudyMode = mode
                        }
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Stats Section

    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Stats")
                .font(.headline)

            HStack(spacing: 16) {
                KBStatCard(title: "Questions", value: "0", icon: "questionmark.circle")
                KBStatCard(title: "Avg Speed", value: "--", icon: "bolt")
                KBStatCard(title: "Accuracy", value: "--%", icon: "checkmark.circle")
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Study Modes

/// Available study session modes
enum KBStudyMode: String, CaseIterable, Identifiable {
    case diagnostic = "Diagnostic"
    case targeted = "Targeted"
    case breadth = "Breadth"
    case speed = "Speed Drill"
    case competition = "Competition"
    case team = "Team Practice"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .diagnostic: return "Assess all domains"
        case .targeted: return "Focus on weak areas"
        case .breadth: return "Maintain coverage"
        case .speed: return "Build quick recall"
        case .competition: return "Full simulation"
        case .team: return "Practice with team"
        }
    }

    var iconName: String {
        switch self {
        case .diagnostic: return "chart.pie"
        case .targeted: return "scope"
        case .breadth: return "rectangle.grid.3x2"
        case .speed: return "bolt.circle"
        case .competition: return "trophy"
        case .team: return "person.3"
        }
    }

    var color: Color {
        switch self {
        case .diagnostic: return .blue
        case .targeted: return .orange
        case .breadth: return .green
        case .speed: return .red
        case .competition: return .purple
        case .team: return .cyan
        }
    }
}

// MARK: - Supporting Views

struct DomainMasteryCard: View {
    let domain: KBDomain
    let mastery: Double

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: domain.iconName)
                .font(.title2)
                .foregroundStyle(domain.color)

            Text(domain.rawValue)
                .font(.caption)
                .lineLimit(1)

            Text("\(Int(mastery * 100))%")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(domain.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DomainMasteryBadge: View {
    let domain: KBDomain
    let mastery: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: domain.iconName)
                .font(.caption2)
            Text("\(Int(mastery * 100))%")
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(domain.color)
        .background(domain.color.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct StudyModeCard: View {
    let mode: KBStudyMode

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: mode.iconName)
                .font(.title2)
                .foregroundStyle(mode.color)

            Text(mode.rawValue)
                .font(.subheadline.bold())

            Text(mode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(mode.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct KBStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Dashboard Summary (for Module List)

/// Compact summary view shown in the modules list
struct KBDashboardSummary: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("0% Ready")
                    .font(.headline)
                Text("0 questions practiced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Placeholder Views

struct KBStudyModeView: View {
    let mode: KBStudyMode

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: mode.iconName)
                .font(.system(size: 60))
                .foregroundStyle(mode.color)

            Text(mode.rawValue)
                .font(.title)

            Text(mode.description)
                .foregroundStyle(.secondary)

            Text("Coming Soon")
                .font(.headline)
                .padding()
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .navigationTitle(mode.rawValue)
    }
}

struct KBDomainDetailView: View {
    let domain: KBDomain

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: domain.iconName)
                        .font(.largeTitle)
                        .foregroundStyle(domain.color)

                    VStack(alignment: .leading) {
                        Text(domain.rawValue)
                            .font(.title2.bold())
                        Text("\(Int(domain.weight * 100))% of competition questions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical)
            }

            Section("Subcategories") {
                ForEach(domain.subcategories, id: \.self) { subcategory in
                    HStack {
                        Text(subcategory)
                        Spacer()
                        Text("0%")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Stats") {
                LabeledContent("Questions Answered", value: "0")
                LabeledContent("Accuracy", value: "0%")
                LabeledContent("Average Speed", value: "--")
            }
        }
        .navigationTitle(domain.rawValue)
    }
}

// MARK: - Previews

#Preview("Dashboard") {
    NavigationStack {
        KBDashboardView()
    }
}

#Preview("Study Mode") {
    NavigationStack {
        KBStudyModeView(mode: .diagnostic)
    }
}

#Preview("Domain Detail") {
    NavigationStack {
        KBDomainDetailView(domain: .science)
    }
}
