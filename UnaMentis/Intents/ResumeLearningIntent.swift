// UnaMentis - Resume Learning Intent
// Enables "Hey Siri, resume my lesson" voice commands
//
// Part of Apple Intelligence Integration (iOS 18+)

import AppIntents
import CoreData

/// App Intent for resuming the most recent learning session
///
/// Enables voice commands like:
/// - "Hey Siri, resume my lesson"
/// - "Hey Siri, continue learning with UnaMentis"
/// - "Hey Siri, pick up where I left off"
public struct ResumeLearningIntent: AppIntent {
    public static let title: LocalizedStringResource = "Resume Learning"

    public static let description = IntentDescription(
        "Continue your most recent learning session",
        categoryName: "Learning",
        searchKeywords: ["resume", "continue", "pick up", "last session"]
    )

    public init() {}

    /// Perform the intent
    public func perform() async throws -> some IntentResult & OpensIntent {
        // Find the most recent in-progress topic
        let context = PersistenceController.shared.container.viewContext

        let result: (UUID?, String?) = await context.perform {
            // First try to find an in-progress topic
            let inProgressRequest: NSFetchRequest<Topic> = Topic.fetchRequest()
            inProgressRequest.predicate = NSPredicate(format: "mastery > 0 AND mastery < 0.8")
            inProgressRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Topic.progress?.lastAccessed, ascending: false)
            ]
            inProgressRequest.fetchLimit = 1

            if let topic = try? context.fetch(inProgressRequest).first,
               let id = topic.id {
                return (id, topic.title ?? "your lesson")
            }

            // Fall back to most recently accessed topic
            let recentRequest: NSFetchRequest<Topic> = Topic.fetchRequest()
            recentRequest.predicate = NSPredicate(format: "progress != nil")
            recentRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \Topic.progress?.lastAccessed, ascending: false)
            ]
            recentRequest.fetchLimit = 1

            if let topic = try? context.fetch(recentRequest).first,
               let id = topic.id {
                return (id, topic.title ?? "your lesson")
            }

            return (nil, nil)
        }

        let (topicId, topicTitle) = result

        guard let id = topicId else {
            throw ResumeLearningError.noSessionToResume
        }

        // Create deep link URL
        let urlString = "unamentis://resume?id=\(id.uuidString)"
        guard let url = URL(string: urlString) else {
            throw ResumeLearningError.invalidConfiguration
        }

        return .result(
            value: "Resuming \(topicTitle ?? "your lesson")",
            opensIntent: OpenURLIntent(url)
        )
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Resume learning where you left off")
    }
}

// MARK: - Errors

/// Errors for ResumeLearningIntent
public enum ResumeLearningError: Error, CustomLocalizedStringResourceConvertible {
    case noSessionToResume
    case invalidConfiguration

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noSessionToResume:
            return "No lesson to resume. Start a new lesson to begin learning."
        case .invalidConfiguration:
            return "Unable to resume. Please try again."
        }
    }
}
