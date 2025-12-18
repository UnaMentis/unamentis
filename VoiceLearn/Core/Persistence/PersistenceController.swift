// VoiceLearn - Persistence Controller
// Core Data stack management for VoiceLearn
//
// Part of Persistence Layer (TDD Section 2)

@preconcurrency import CoreData
import Logging

/// Manages the Core Data stack for VoiceLearn
///
/// Provides:
/// - Main context for UI operations
/// - Background context for heavy operations
/// - Preview support for SwiftUI previews
public final class PersistenceController: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared persistence controller
    public static let shared = PersistenceController()
    
    /// Preview controller for SwiftUI previews
    @MainActor
    public static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        controller.createPreviewData()
        return controller
    }()
    
    // MARK: - Properties
    
    private let logger = Logger(label: "com.voicelearn.persistence")
    
    /// The Core Data container
    public let container: NSPersistentContainer
    
    /// Main context for UI operations
    @MainActor
    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }
    
    // MARK: - Initialization
    
    /// Initialize persistence controller
    /// - Parameter inMemory: If true, uses in-memory store (for previews/tests)
    public init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "VoiceLearn")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Use semaphore to ensure store loads synchronously before init completes
        // This prevents race conditions when views access viewContext before store is ready
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?

        container.loadPersistentStores { [weak self] description, error in
            if let error = error {
                loadError = error
            } else {
                self?.configureContext()
            }
            semaphore.signal()
        }

        // Wait for store to load (with timeout to prevent infinite hangs)
        let result = semaphore.wait(timeout: .now() + 10)

        if result == .timedOut {
            fatalError("Core Data store load timed out after 10 seconds")
        }

        if let error = loadError {
            fatalError("Failed to load Core Data store: \(error)")
        }
    }
    
    // MARK: - Configuration
    
    private func configureContext() {
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        logger.info("Core Data stack initialized successfully")
    }
    
    // MARK: - Background Operations
    
    /// Create a background context for heavy operations
    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }
    
    /// Perform work in a background context
    public func performBackgroundTask(_ block: @escaping @Sendable (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask(block)
    }
    
    // MARK: - Save Operations
    
    /// Save the view context if there are changes
    @MainActor
    public func save() throws {
        let context = container.viewContext
        guard context.hasChanges else { return }
        
        do {
            try context.save()
            logger.debug("View context saved successfully")
        } catch {
            logger.error("Failed to save view context: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Save a specific context
    public func save(context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        
        do {
            try context.save()
            logger.debug("Context saved successfully")
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Preview Data
    
    @MainActor
    private func createPreviewData() {
        let context = container.viewContext
        
        // Create sample curriculum
        let curriculum = Curriculum(context: context)
        curriculum.id = UUID()
        curriculum.name = "Introduction to Machine Learning"
        curriculum.summary = "A comprehensive introduction to ML concepts"
        curriculum.createdAt = Date()
        curriculum.updatedAt = Date()
        
        // Create sample topics
        let topics = [
            ("Neural Networks Fundamentals", 0),
            ("Backpropagation", 1),
            ("Gradient Descent", 2),
            ("Convolutional Networks", 3)
        ]
        
        for (title, index) in topics {
            let topic = Topic(context: context)
            topic.id = UUID()
            topic.title = title
            topic.orderIndex = Int32(index)
            topic.mastery = Float.random(in: 0...0.8)
            topic.curriculum = curriculum
            
            // Create progress for topic
            let progress = TopicProgress(context: context)
            progress.id = UUID()
            progress.timeSpent = Double.random(in: 0...3600)
            progress.lastAccessed = Date().addingTimeInterval(-Double.random(in: 0...86400))
            progress.topic = topic
        }
        
        do {
            try context.save()
            logger.info("Preview data created successfully")
        } catch {
            logger.error("Failed to create preview data: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Fetch Operations
    
    /// Fetch all curricula
    @MainActor
    public func fetchCurricula() throws -> [Curriculum] {
        let request = Curriculum.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Curriculum.updatedAt, ascending: false)]
        return try container.viewContext.fetch(request)
    }
    
    /// Fetch topics for a curriculum
    @MainActor
    public func fetchTopics(for curriculum: Curriculum) throws -> [Topic] {
        let request = Topic.fetchRequest()
        request.predicate = NSPredicate(format: "curriculum == %@", curriculum)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Topic.orderIndex, ascending: true)]
        return try container.viewContext.fetch(request)
    }
    
    /// Fetch recent sessions
    @MainActor
    public func fetchRecentSessions(limit: Int = 10) throws -> [Session] {
        let request = Session.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Session.startTime, ascending: false)]
        request.fetchLimit = limit
        return try container.viewContext.fetch(request)
    }
}
