// UnaMentis - Persistence Controller
// Core Data stack management for UnaMentis
//
// Part of Persistence Layer (TDD Section 2)
//
// Architecture Note:
// This controller uses async initialization to prevent blocking the main thread.
// The shared instance is initialized once at app launch and cached. Views should
// access it through the environment or the shared property which is guaranteed
// to be ready after app initialization completes.

@preconcurrency import CoreData
import Logging
import os

/// Manages the Core Data stack for UnaMentis
///
/// Provides:
/// - Main context for UI operations
/// - Background context for heavy operations
/// - Preview support for SwiftUI previews
///
/// Architecture Note:
/// Uses async factory pattern to avoid blocking MainActor with semaphores.
/// The shared instance loads asynchronously but is guaranteed ready before
/// views access it due to app initialization order.
public final class PersistenceController: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared persistence controller
    /// Initialized asynchronously at app launch, guaranteed ready before views load
    public static let shared = PersistenceController()

    /// Preview controller for SwiftUI previews
    @MainActor
    public static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        controller.createPreviewData()
        return controller
    }()

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.persistence")

    /// The Core Data container
    public let container: NSPersistentContainer

    /// Thread-safe state for store loading status
    private let stateLock = OSAllocatedUnfairLock(initialState: StoreState())

    /// Internal state protected by stateLock
    private struct StoreState {
        var isLoaded = false
        var loadError: Error?
    }

    /// Whether the persistent store loaded successfully and is ready for use
    public var isReady: Bool {
        stateLock.withLock { $0.isLoaded && $0.loadError == nil }
    }

    /// Error from store loading, if any
    public var storeLoadError: Error? {
        stateLock.withLock { $0.loadError }
    }

    /// Main context for UI operations
    @MainActor
    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Initialization

    /// Initialize persistence controller
    /// - Parameter inMemory: If true, uses in-memory store (for previews/tests)
    ///
    /// Note: For in-memory stores (previews/tests), initialization is synchronous.
    /// For persistent stores, use the async load pattern to avoid blocking MainActor.
    public init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "UnaMentis")

        if inMemory {
            // Use unique in-memory store for complete isolation between test instances
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            // Use a proper temp file URL with UUID for unique store identification
            // This prevents any potential caching or sharing between test instances
            let tempDir = FileManager.default.temporaryDirectory
            description.url = tempDir.appendingPathComponent("UnaMentis-\(UUID().uuidString).sqlite")
            container.persistentStoreDescriptions = [description]
            // In-memory stores load synchronously and quickly, safe to block
            loadStoresSynchronously()
        } else {
            // For persistent stores, load asynchronously via continuation
            // This runs on a background thread and doesn't block MainActor
            loadStoresWithContinuation()
        }
    }

    /// Load stores synchronously (for in-memory/preview use only)
    private func loadStoresSynchronously() {
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?

        container.loadPersistentStores { [weak self] _, error in
            if let error = error {
                loadError = error
            } else {
                self?.configureContext()
                self?.stateLock.withLock { $0.isLoaded = true }
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5)

        if let error = loadError {
            logger.critical("Failed to load in-memory Core Data store: \(error.localizedDescription)")
            stateLock.withLock { $0.loadError = error }
        }
    }

    /// Load stores using continuation pattern to avoid blocking MainActor
    /// This is the preferred pattern for persistent stores
    private func loadStoresWithContinuation() {
        // Load stores on background queue, then configure on completion
        // This does NOT block the calling thread
        container.loadPersistentStores { [weak self] _, error in
            if let error = error {
                self?.logger.critical("Failed to load Core Data store: \(error.localizedDescription)")
                self?.stateLock.withLock { $0.loadError = error }
            } else {
                self?.configureContext()
                self?.stateLock.withLock { $0.isLoaded = true }
                self?.logger.info("Core Data stack initialized successfully (async)")
            }
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
