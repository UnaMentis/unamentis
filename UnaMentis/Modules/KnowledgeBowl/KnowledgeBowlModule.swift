// UnaMentis - Knowledge Bowl Module
// Specialized training module for Knowledge Bowl competition preparation
//
// Knowledge Bowl is an academic competition where teams answer questions
// across 12+ subject domains with emphasis on speed and breadth.
// This module provides:
// - Directed study across all domains
// - Speed training with sub-3-second response targets
// - Competition simulation with buzzer mechanics
// - Team collaboration mode

import SwiftUI
import Logging

/// Knowledge Bowl training module
///
/// Implements the ModuleProtocol to provide Knowledge Bowl-specific
/// training features within the UnaMentis app.
public struct KnowledgeBowlModule: ModuleProtocol {
    public let id = "knowledge-bowl"
    public let name = "Knowledge Bowl"
    public let shortDescription = "Academic competition prep across 12 subject domains"
    public let longDescription = """
        Prepare for Knowledge Bowl competitions with directed study, \
        speed training, and realistic competition simulation. \
        Track your mastery across Science, Math, Literature, History, \
        and 8 other domains. Practice solo or with your team.
        """
    public let iconName = "brain.head.profile"
    public let themeColor = Color.purple
    public let supportsTeamMode = true
    public let supportsSpeedTraining = true
    public let supportsCompetitionSim = true
    public let version = "1.0.0"

    private static let logger = Logger(label: "com.unamentis.modules.knowledgebowl")

    public init() {
        Self.logger.info("Knowledge Bowl module initialized")
    }

    @MainActor
    public func makeRootView() -> AnyView {
        AnyView(KBDashboardView())
    }

    @MainActor
    public func makeDashboardView() -> AnyView {
        AnyView(KBDashboardSummary())
    }
}

// MARK: - Domain Definitions

/// Knowledge Bowl subject domains with their competition weights
public enum KBDomain: String, CaseIterable, Identifiable {
    case science = "Science"
    case mathematics = "Mathematics"
    case literature = "Literature"
    case history = "History"
    case socialStudies = "Social Studies"
    case arts = "Arts"
    case currentEvents = "Current Events"
    case language = "Language"
    case technology = "Technology"
    case popCulture = "Pop Culture"
    case religionPhilosophy = "Religion & Philosophy"
    case miscellaneous = "Miscellaneous"

    public var id: String { rawValue }

    /// Competition weight (percentage of questions)
    public var weight: Double {
        switch self {
        case .science: return 0.20
        case .mathematics: return 0.15
        case .literature: return 0.12
        case .history: return 0.12
        case .socialStudies: return 0.10
        case .arts: return 0.08
        case .currentEvents: return 0.08
        case .language: return 0.05
        case .technology: return 0.04
        case .popCulture: return 0.03
        case .religionPhilosophy: return 0.02
        case .miscellaneous: return 0.01
        }
    }

    /// SF Symbol for the domain
    public var iconName: String {
        switch self {
        case .science: return "atom"
        case .mathematics: return "function"
        case .literature: return "book.closed"
        case .history: return "clock.arrow.circlepath"
        case .socialStudies: return "globe.americas"
        case .arts: return "paintpalette"
        case .currentEvents: return "newspaper"
        case .language: return "character.book.closed"
        case .technology: return "cpu"
        case .popCulture: return "star"
        case .religionPhilosophy: return "sparkles"
        case .miscellaneous: return "puzzlepiece"
        }
    }

    /// Theme color for the domain
    public var color: Color {
        switch self {
        case .science: return .blue
        case .mathematics: return .orange
        case .literature: return .brown
        case .history: return .red
        case .socialStudies: return .green
        case .arts: return .pink
        case .currentEvents: return .cyan
        case .language: return .indigo
        case .technology: return .gray
        case .popCulture: return .yellow
        case .religionPhilosophy: return .purple
        case .miscellaneous: return .mint
        }
    }

    /// Subcategories within the domain
    public var subcategories: [String] {
        switch self {
        case .science:
            return ["Biology", "Chemistry", "Physics", "Earth Science", "Astronomy"]
        case .mathematics:
            return ["Arithmetic", "Algebra", "Geometry", "Calculus", "Statistics"]
        case .literature:
            return ["American", "British", "World", "Poetry", "Drama"]
        case .history:
            return ["US", "World", "Ancient", "Modern", "Military"]
        case .socialStudies:
            return ["Geography", "Government", "Economics", "Sociology"]
        case .arts:
            return ["Visual Arts", "Music", "Theater", "Architecture"]
        case .currentEvents:
            return ["Politics", "Science", "Culture", "Sports", "Technology"]
        case .language:
            return ["Grammar", "Vocabulary", "Etymology", "Foreign Languages"]
        case .technology:
            return ["Computer Science", "Engineering", "Inventions"]
        case .popCulture:
            return ["Entertainment", "Media", "Sports", "Games"]
        case .religionPhilosophy:
            return ["World Religions", "Ethics", "Philosophy"]
        case .miscellaneous:
            return ["Trivia", "Cross-domain", "Puzzles"]
        }
    }
}
