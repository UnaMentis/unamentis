// UnaMentis - Topic Entity for App Intents
// Exposes topics to Siri and Shortcuts
//
// Part of Apple Intelligence Integration (iOS 18+)

import AppIntents
import CoreData

/// App Entity representing a Topic for Siri and Shortcuts integration
///
/// This entity allows users to:
/// - Say "Start a lesson on Quantum Mechanics" to Siri
/// - Browse topics within a curriculum
/// - Create Shortcuts that target specific topics
public struct TopicEntity: AppEntity {
    /// Unique identifier for the topic
    public var id: UUID

    /// Display title of the topic
    public var title: String

    /// Outline/description of the topic
    public var outline: String?

    /// Name of the parent curriculum
    public var curriculumName: String?

    /// Current mastery level (0-1)
    public var mastery: Float

    /// Topic status description
    public var statusDescription: String

    /// Entity display representation for Siri UI
    public static let defaultQuery = TopicEntityQuery()

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("Topic"),
            numericFormat: LocalizedStringResource("\(placeholder: .int) topics")
        )
    }

    public var displayRepresentation: DisplayRepresentation {
        var subtitle = ""
        if let curriculumName = curriculumName {
            subtitle = curriculumName
        }
        if mastery > 0 {
            let percentage = Int(mastery * 100)
            subtitle += subtitle.isEmpty ? "\(percentage)% mastered" : " - \(percentage)% mastered"
        }

        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: subtitle.isEmpty ? nil : LocalizedStringResource(stringLiteral: subtitle),
            image: .init(systemName: masteryIcon)
        )
    }

    /// Icon based on mastery level
    private var masteryIcon: String {
        switch mastery {
        case 0.8...: return "checkmark.circle.fill"
        case 0.5..<0.8: return "circle.lefthalf.filled"
        case 0.01..<0.5: return "circle.bottomhalf.filled"
        default: return "circle"
        }
    }

    /// Initialize from Core Data Topic object
    public init(from topic: Topic) {
        self.id = topic.id ?? UUID()
        self.title = topic.title ?? "Untitled Topic"
        self.outline = topic.outline
        self.curriculumName = topic.curriculum?.name
        self.mastery = topic.mastery
        self.statusDescription = topic.status.displayName
    }

    /// Initialize with explicit values (for testing)
    public init(
        id: UUID,
        title: String,
        outline: String? = nil,
        curriculumName: String? = nil,
        mastery: Float = 0,
        statusDescription: String = "Not Started"
    ) {
        self.id = id
        self.title = title
        self.outline = outline
        self.curriculumName = curriculumName
        self.mastery = mastery
        self.statusDescription = statusDescription
    }
}

// MARK: - Entity Query

/// Query provider for TopicEntity
/// Enables Siri to search and suggest topics
public struct TopicEntityQuery: EntityQuery {
    public init() {}

    /// Fetch topics by ID for Siri
    public func entities(for identifiers: [UUID]) async throws -> [TopicEntity] {
        let context = PersistenceController.shared.container.viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<Topic> = Topic.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", identifiers)

            guard let topics = try? context.fetch(fetchRequest) else {
                return []
            }

            return topics.map { TopicEntity(from: $0) }
        }
    }

    /// Provide suggested topics for Siri
    /// Prioritizes in-progress and recently accessed topics
    public func suggestedEntities() async throws -> [TopicEntity] {
        let context = PersistenceController.shared.container.viewContext

        return await context.perform {
            // First, get in-progress topics
            let inProgressRequest: NSFetchRequest<Topic> = Topic.fetchRequest()
            inProgressRequest.predicate = NSPredicate(format: "mastery > 0 AND mastery < 0.8")
            inProgressRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Topic.mastery, ascending: false)]
            inProgressRequest.fetchLimit = 5

            var results: [TopicEntity] = []

            if let inProgressTopics = try? context.fetch(inProgressRequest) {
                results.append(contentsOf: inProgressTopics.map { TopicEntity(from: $0) })
            }

            // Then, get some not-started topics
            if results.count < 10 {
                let notStartedRequest: NSFetchRequest<Topic> = Topic.fetchRequest()
                notStartedRequest.predicate = NSPredicate(format: "mastery == 0")
                notStartedRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Topic.orderIndex, ascending: true)]
                notStartedRequest.fetchLimit = 10 - results.count

                if let notStartedTopics = try? context.fetch(notStartedRequest) {
                    results.append(contentsOf: notStartedTopics.map { TopicEntity(from: $0) })
                }
            }

            return results
        }
    }
}

// MARK: - String Search Query

extension TopicEntityQuery: EntityStringQuery {
    /// Search topics by title for Siri voice input
    public func entities(matching query: String) async throws -> [TopicEntity] {
        let context = PersistenceController.shared.container.viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<Topic> = Topic.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "title CONTAINS[cd] %@ OR outline CONTAINS[cd] %@",
                query, query
            )
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Topic.title, ascending: true)]
            fetchRequest.fetchLimit = 10

            guard let topics = try? context.fetch(fetchRequest) else {
                return []
            }

            return topics.map { TopicEntity(from: $0) }
        }
    }
}
