// UnaMentis - Start Lesson Intent
// Enables "Hey Siri, start a lesson on Physics" voice commands
//
// Part of Apple Intelligence Integration (iOS 18+)

import AppIntents
import CoreData

/// App Intent for starting a learning session on a specific topic
///
/// Enables voice commands like:
/// - "Hey Siri, start a lesson on Quantum Mechanics"
/// - "Hey Siri, start learning Physics with UnaMentis"
/// - "Hey Siri, teach me about Classical Mechanics"
public struct StartLessonIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Lesson"

    public static let description = IntentDescription(
        "Start a voice tutoring session on a specific topic",
        categoryName: "Learning",
        searchKeywords: ["learn", "study", "teach", "lesson", "tutor", "voice"]
    )

    /// The topic to study
    @Parameter(
        title: "Topic",
        description: "The topic you want to learn about"
    )
    public var topic: TopicEntity?

    /// The curriculum to study (alternative to specific topic)
    @Parameter(
        title: "Curriculum",
        description: "The curriculum to study from"
    )
    public var curriculum: CurriculumEntity?

    /// Depth level for the lesson
    @Parameter(
        title: "Depth",
        description: "How deep should the lesson go?",
        default: .intermediate
    )
    public var depth: LessonDepth

    public init() {}

    /// Perform the intent
    public func perform() async throws -> some IntentResult & OpensIntent {
        // Determine what to study
        let lessonTarget: String
        let targetId: UUID?

        if let topic = topic {
            lessonTarget = topic.title
            targetId = topic.id
        } else if let curriculum = curriculum {
            lessonTarget = curriculum.name
            targetId = curriculum.id
        } else {
            throw StartLessonError.noTopicSelected
        }

        // Create deep link URL to open the app at the session view
        // The app will handle starting the session with the specified topic
        let urlString = "unamentis://lesson?id=\(targetId?.uuidString ?? "")&depth=\(depth.rawValue)"
        guard let url = URL(string: urlString) else {
            throw StartLessonError.invalidConfiguration
        }

        // Return result that opens the app
        return .result(
            value: "Starting lesson on \(lessonTarget)",
            opensIntent: OpenURLIntent(url)
        )
    }

    /// Provide parameter options
    public static var parameterSummary: some ParameterSummary {
        Summary("Start lesson on \(\.$topic)") {
            \.$curriculum
            \.$depth
        }
    }
}

// MARK: - Lesson Depth Enum

/// Content depth for Siri-initiated lessons
public enum LessonDepth: String, AppEnum {
    case overview
    case introductory
    case intermediate
    case advanced
    case graduate

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Lesson Depth")
    }

    public static var caseDisplayRepresentations: [LessonDepth: DisplayRepresentation] {
        [
            .overview: DisplayRepresentation(
                title: "Overview",
                subtitle: "2-5 minute brief introduction"
            ),
            .introductory: DisplayRepresentation(
                title: "Introductory",
                subtitle: "5-15 minute beginner explanation"
            ),
            .intermediate: DisplayRepresentation(
                title: "Intermediate",
                subtitle: "15-30 minute solid coverage"
            ),
            .advanced: DisplayRepresentation(
                title: "Advanced",
                subtitle: "30-60 minute in-depth exploration"
            ),
            .graduate: DisplayRepresentation(
                title: "Graduate Level",
                subtitle: "60+ minute comprehensive lecture"
            )
        ]
    }
}

// MARK: - Errors

/// Errors for StartLessonIntent
public enum StartLessonError: Error, CustomLocalizedStringResourceConvertible {
    case noTopicSelected
    case topicNotFound
    case invalidConfiguration

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noTopicSelected:
            return "Please specify a topic or curriculum to study"
        case .topicNotFound:
            return "Could not find the specified topic"
        case .invalidConfiguration:
            return "Unable to start the lesson. Please try again."
        }
    }
}

// MARK: - Open URL Intent Helper

/// Helper intent to open a URL (for deep linking)
public struct OpenURLIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open URL"

    @Parameter(title: "URL")
    public var url: URL

    public init(_ url: URL) {
        self.url = url
    }

    public init() {
        self.url = URL(string: "unamentis://")!
    }

    public func perform() async throws -> some IntentResult {
        // The system will open this URL, launching UnaMentis to the lesson
        return .result()
    }

    public static let openAppWhenRun: Bool = true
}
