// UnaMentis - Curriculum Entity for App Intents
// Exposes curricula to Siri and Shortcuts
//
// Part of Apple Intelligence Integration (iOS 18+)

import AppIntents
import CoreData

/// App Entity representing a Curriculum for Siri and Shortcuts integration
///
/// This entity allows users to:
/// - Say "Start a lesson on Physics" to Siri
/// - Search for curricula in Spotlight
/// - Create Shortcuts workflows with curriculum selection
public struct CurriculumEntity: AppEntity {
    /// Unique identifier for the curriculum
    public var id: UUID

    /// Display name of the curriculum
    public var name: String

    /// Summary description
    public var summary: String?

    /// Number of topics in this curriculum
    public var topicCount: Int

    /// Entity display representation for Siri UI
    public static let defaultQuery = CurriculumEntityQuery()

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("Curriculum"),
            numericFormat: LocalizedStringResource("\(placeholder: .int) curricula")
        )
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: summary.map { LocalizedStringResource(stringLiteral: $0) },
            image: DisplayRepresentation.Image(systemName: "book.fill")
        )
    }

    /// Initialize from Core Data Curriculum object
    public init(from curriculum: Curriculum) {
        self.id = curriculum.id ?? UUID()
        self.name = curriculum.name ?? "Untitled Curriculum"
        self.summary = curriculum.summary
        self.topicCount = curriculum.topics?.count ?? 0
    }

    /// Initialize with explicit values (for testing)
    public init(id: UUID, name: String, summary: String? = nil, topicCount: Int = 0) {
        self.id = id
        self.name = name
        self.summary = summary
        self.topicCount = topicCount
    }
}

// MARK: - Entity Query

/// Query provider for CurriculumEntity
/// Enables Siri to search and suggest curricula
public struct CurriculumEntityQuery: EntityQuery {
    public init() {}

    /// Fetch all curricula for Siri suggestions
    public func entities(for identifiers: [UUID]) async throws -> [CurriculumEntity] {
        let context = PersistenceController.shared.container.viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<Curriculum> = Curriculum.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", identifiers)

            guard let curricula = try? context.fetch(fetchRequest) else {
                return []
            }

            return curricula.map { CurriculumEntity(from: $0) }
        }
    }

    /// Provide suggested curricula for Siri
    public func suggestedEntities() async throws -> [CurriculumEntity] {
        let context = PersistenceController.shared.container.viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<Curriculum> = Curriculum.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Curriculum.updatedAt, ascending: false)]
            fetchRequest.fetchLimit = 10

            guard let curricula = try? context.fetch(fetchRequest) else {
                return []
            }

            return curricula.map { CurriculumEntity(from: $0) }
        }
    }
}

// MARK: - String Search Query

extension CurriculumEntityQuery: EntityStringQuery {
    /// Search curricula by name for Siri voice input
    public func entities(matching query: String) async throws -> [CurriculumEntity] {
        let context = PersistenceController.shared.container.viewContext

        return await context.perform {
            let fetchRequest: NSFetchRequest<Curriculum> = Curriculum.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "name CONTAINS[cd] %@ OR summary CONTAINS[cd] %@",
                query, query
            )
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Curriculum.name, ascending: true)]
            fetchRequest.fetchLimit = 10

            guard let curricula = try? context.fetch(fetchRequest) else {
                return []
            }

            return curricula.map { CurriculumEntity(from: $0) }
        }
    }
}
