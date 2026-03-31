// UnaMentis - Todo Manager
// Manages CRUD operations, ordering, and archival for to-do items
//
// Part of Todo System

import Foundation
import CoreData
import Logging

/// Actor responsible for managing to-do items
///
/// Responsibilities:
/// - Create, read, update, delete to-do items
/// - Manage priority/ordering for drag-drop reordering
/// - Handle archival and restoration
/// - Provide filtered queries
public actor TodoManager {

    // MARK: - Properties

    private let persistenceController: PersistenceController
    private let logger = Logger(label: "com.unamentis.todomanager")

    /// Shared instance for convenience
    @MainActor
    public static var shared: TodoManager?

    // MARK: - Initialization

    /// Initialize todo manager with persistence controller
    /// - Parameter persistenceController: Core Data persistence controller
    public init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        logger.info("TodoManager initialized")
    }

    // MARK: - Create Operations

    /// Create a new to-do item
    /// - Parameters:
    ///   - title: Title of the item
    ///   - type: Type of to-do item
    ///   - source: How the item was created
    ///   - notes: Optional notes
    /// - Returns: Created TodoItem
    @MainActor
    public func createItem(
        title: String,
        type: TodoItemType,
        source: TodoItemSource = .manual,
        notes: String? = nil
    ) throws -> TodoItem {
        let context = persistenceController.viewContext

        // Get max priority BEFORE creating item to avoid including the new item in the search
        let maxPriority = try getMaxPriority(in: context)

        let item = TodoItem(context: context)
        item.configure(title: title, type: type, source: source, notes: notes)

        // Set priority to be at the end of the list
        item.priority = maxPriority + 1

        try persistenceController.save()
        logger.debug("Created to-do item: \(title) [\(type.displayName)]")

        // For learning targets, fetch curriculum suggestions asynchronously
        if type == .learningTarget {
            let itemID = item.objectID
            Task { @MainActor in
                let context = PersistenceController.shared.container.viewContext
                guard let todoItem = context.object(with: itemID) as? TodoItem else { return }
                await CurriculumSuggestionService.shared.updateTodoWithSuggestions(todoItem)
            }
        }

        return item
    }

    /// Create a curriculum-linked to-do item
    /// - Parameters:
    ///   - title: Title of the item
    ///   - curriculumId: ID of the linked curriculum
    ///   - topicId: Optional topic ID for topic-level items
    ///   - granularity: Granularity level (curriculum, module, topic)
    ///   - source: How the item was created
    /// - Returns: Created TodoItem
    @MainActor
    public func createCurriculumItem(
        title: String,
        curriculumId: UUID,
        topicId: UUID? = nil,
        granularity: String,
        source: TodoItemSource = .manual
    ) throws -> TodoItem {
        let context = persistenceController.viewContext

        // Get max priority BEFORE creating item to avoid including the new item in the search
        let maxPriority = try getMaxPriority(in: context)

        let itemType: TodoItemType
        switch granularity {
        case "curriculum": itemType = .curriculum
        case "module": itemType = .module
        case "topic": itemType = .topic
        default: itemType = .curriculum
        }

        let item = TodoItem(context: context)
        item.configure(title: title, type: itemType, source: source)
        item.configureCurriculumLink(curriculumId: curriculumId, topicId: topicId, granularity: granularity)

        item.priority = maxPriority + 1

        try persistenceController.save()
        logger.debug("Created curriculum to-do: \(title) [\(granularity)]")

        return item
    }

    /// Create an auto-resume to-do item
    /// - Parameters:
    ///   - title: Title (typically "Continue: [Topic Name]")
    ///   - topicId: ID of the topic to resume
    ///   - segmentIndex: Segment index to resume from
    ///   - conversationContext: Encoded conversation history for context
    /// - Returns: Created TodoItem
    @MainActor
    public func createAutoResumeItem(
        title: String,
        topicId: UUID,
        segmentIndex: Int32,
        conversationContext: Data?
    ) throws -> TodoItem {
        let context = persistenceController.viewContext

        // Check if we already have an auto-resume for this topic
        if let existing = try findAutoResumeItem(for: topicId, in: context) {
            // Update existing item
            existing.resumeSegmentIndex = segmentIndex
            existing.resumeConversationContext = conversationContext
            existing.markUpdated()
            try persistenceController.save()
            logger.debug("Updated existing auto-resume for topic: \(topicId)")
            return existing
        }

        // Create new auto-resume item
        let item = TodoItem(context: context)
        item.configure(title: title, type: .autoResume, source: .autoResume)
        item.configureAutoResume(topicId: topicId, segmentIndex: segmentIndex, conversationContext: conversationContext)

        // Shift existing items down BEFORE setting new item's priority
        // This ensures the new item isn't included in the shift
        try shiftPriorities(from: 0, in: context)

        // Auto-resume items get high priority (lower number = higher priority)
        item.priority = 0

        try persistenceController.save()
        logger.info("Created auto-resume to-do for topic: \(topicId) at segment \(segmentIndex)")

        return item
    }

    /// Create a reinforcement/review to-do item
    /// - Parameters:
    ///   - title: Title describing what to review
    ///   - notes: Additional context
    ///   - sessionId: ID of the session where this was captured
    /// - Returns: Created TodoItem
    @MainActor
    public func createReinforcementItem(
        title: String,
        notes: String?,
        sessionId: UUID?
    ) throws -> TodoItem {
        let context = persistenceController.viewContext

        // Get max priority BEFORE creating item to avoid including the new item in the search
        let maxPriority = try getMaxPriority(in: context)

        let item = TodoItem(context: context)
        item.configure(title: title, type: .reinforcement, source: .reinforcement, notes: notes)
        item.sourceSessionId = sessionId

        item.priority = maxPriority + 1

        try persistenceController.save()
        logger.debug("Created reinforcement to-do: \(title)")

        return item
    }

    // MARK: - Read Operations

    /// Fetch all active (non-archived, non-completed) to-do items
    /// - Returns: Array of active TodoItems sorted by priority
    @MainActor
    public func fetchActiveItems() throws -> [TodoItem] {
        let context = persistenceController.viewContext
        let request = TodoItem.fetchRequest()
        request.predicate = NSPredicate(
            format: "statusRaw != %@ AND statusRaw != %@",
            TodoItemStatus.archived.rawValue,
            TodoItemStatus.completed.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "priority", ascending: true)]

        return try context.fetch(request)
    }

    /// Fetch completed to-do items
    /// - Returns: Array of completed TodoItems sorted by update date
    @MainActor
    public func fetchCompletedItems() throws -> [TodoItem] {
        let context = persistenceController.viewContext
        let request = TodoItem.fetchRequest()
        request.predicate = NSPredicate(format: "statusRaw == %@", TodoItemStatus.completed.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        return try context.fetch(request)
    }

    /// Fetch archived to-do items
    /// - Returns: Array of archived TodoItems sorted by archive date
    @MainActor
    public func fetchArchivedItems() throws -> [TodoItem] {
        let context = persistenceController.viewContext
        let request = TodoItem.fetchRequest()
        request.predicate = NSPredicate(format: "statusRaw == %@", TodoItemStatus.archived.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "archivedAt", ascending: false)]

        return try context.fetch(request)
    }

    /// Fetch items by type
    /// - Parameter type: Type of items to fetch
    /// - Returns: Array of TodoItems of the specified type
    @MainActor
    public func fetchItems(ofType type: TodoItemType) throws -> [TodoItem] {
        let context = persistenceController.viewContext
        let request = TodoItem.fetchRequest()
        request.predicate = NSPredicate(format: "typeRaw == %@", type.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "priority", ascending: true)]

        return try context.fetch(request)
    }

    /// Fetch a specific item by ID
    /// - Parameter id: ID of the item
    /// - Returns: TodoItem or nil if not found
    @MainActor
    public func fetchItem(id: UUID) throws -> TodoItem? {
        let context = persistenceController.viewContext
        let request = TodoItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        return try context.fetch(request).first
    }

    // MARK: - Update Operations

    /// Update item status
    /// - Parameters:
    ///   - item: Item to update
    ///   - status: New status
    @MainActor
    public func updateStatus(item: TodoItem, status: TodoItemStatus) throws {
        item.status = status
        item.markUpdated()

        try persistenceController.save()
        logger.debug("Updated status for '\(item.title ?? "")' to \(status.displayName)")
    }

    /// Update item title and notes
    /// - Parameters:
    ///   - item: Item to update
    ///   - title: New title
    ///   - notes: New notes
    @MainActor
    public func updateItem(item: TodoItem, title: String?, notes: String?) throws {
        if let title = title {
            item.title = title
        }
        item.notes = notes
        item.markUpdated()

        try persistenceController.save()
        logger.debug("Updated to-do item: \(item.title ?? "")")
    }

    /// Mark item as completed
    /// - Parameter item: Item to complete
    @MainActor
    public func completeItem(_ item: TodoItem) throws {
        try updateStatus(item: item, status: .completed)
    }

    /// Archive an item
    /// - Parameter item: Item to archive
    @MainActor
    public func archiveItem(_ item: TodoItem) throws {
        try updateStatus(item: item, status: .archived)
    }

    /// Restore an archived item to pending
    /// - Parameter item: Item to restore
    @MainActor
    public func restoreItem(_ item: TodoItem) throws {
        item.archivedAt = nil
        try updateStatus(item: item, status: .pending)
    }

    // MARK: - Reordering Operations

    /// Move an item to a new position (for drag-drop reordering)
    /// - Parameters:
    ///   - item: Item to move
    ///   - newIndex: New position index
    @MainActor
    public func moveItem(_ item: TodoItem, to newIndex: Int) throws {
        let items = try fetchActiveItems()

        guard newIndex >= 0 && newIndex < items.count else {
            logger.warning("Invalid move index: \(newIndex)")
            return
        }

        let oldPriority = item.priority
        let newPriority = Int32(newIndex)
        let itemId = item.id

        if oldPriority < newPriority {
            // Moving down: shift items between old and new position up
            for otherItem in items where otherItem.id != itemId && otherItem.priority > oldPriority && otherItem.priority <= newPriority {
                otherItem.priority -= 1
            }
        } else if oldPriority > newPriority {
            // Moving up: shift items between new and old position down
            for otherItem in items where otherItem.id != itemId && otherItem.priority >= newPriority && otherItem.priority < oldPriority {
                otherItem.priority += 1
            }
        }

        item.priority = newPriority
        item.markUpdated()

        try persistenceController.save()
        logger.debug("Moved '\(item.title ?? "")' to position \(newIndex)")
    }

    /// Reorder items based on an array of IDs (for complete reorder)
    /// - Parameter orderedIds: Array of item IDs in desired order
    @MainActor
    public func reorderItems(orderedIds: [UUID]) throws {
        let context = persistenceController.viewContext

        for (index, id) in orderedIds.enumerated() {
            let request = TodoItem.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            if let item = try context.fetch(request).first {
                item.priority = Int32(index)
            }
        }

        try persistenceController.save()
        logger.debug("Reordered \(orderedIds.count) items")
    }

    // MARK: - Delete Operations

    /// Permanently delete an item
    /// - Parameter item: Item to delete
    @MainActor
    public func deleteItem(_ item: TodoItem) throws {
        let context = persistenceController.viewContext
        let title = item.title ?? "Unknown"

        context.delete(item)
        try persistenceController.save()

        logger.info("Deleted to-do item: \(title)")
    }

    /// Delete all completed items
    @MainActor
    public func deleteAllCompleted() throws {
        let context = persistenceController.viewContext
        let items = try fetchCompletedItems()

        for item in items {
            context.delete(item)
        }

        try persistenceController.save()
        logger.info("Deleted \(items.count) completed items")
    }

    // MARK: - Auto-Resume Specific

    /// Remove auto-resume item for a topic (called when session completes normally)
    /// - Parameter topicId: ID of the topic
    @MainActor
    public func clearAutoResume(for topicId: UUID) throws {
        let context = persistenceController.viewContext

        if let item = try findAutoResumeItem(for: topicId, in: context) {
            context.delete(item)
            try persistenceController.save()
            logger.debug("Cleared auto-resume for topic: \(topicId)")
        }
    }

    /// Get resume context for a topic
    /// - Parameter topicId: ID of the topic
    /// - Returns: Resume context data or nil
    @MainActor
    public func getResumeContext(for topicId: UUID) throws -> (segmentIndex: Int32, context: Data?)? {
        let context = persistenceController.viewContext

        if let item = try findAutoResumeItem(for: topicId, in: context) {
            return (item.resumeSegmentIndex, item.resumeConversationContext)
        }
        return nil
    }

    // MARK: - Learning Target Specific

    /// Update suggested curricula for a learning target
    /// - Parameters:
    ///   - item: Learning target item
    ///   - curriculumIds: Array of suggested curriculum IDs
    @MainActor
    public func updateSuggestedCurricula(item: TodoItem, curriculumIds: [String]) throws {
        guard item.itemType == .learningTarget else {
            logger.warning("Cannot set suggested curricula for non-learning-target item")
            return
        }

        item.suggestedCurriculumIds = curriculumIds
        item.markUpdated()

        try persistenceController.save()
        logger.debug("Updated suggested curricula for '\(item.title ?? "")': \(curriculumIds.count) suggestions")
    }

    // MARK: - Helper Methods

    @MainActor
    private func getMaxPriority(in context: NSManagedObjectContext) throws -> Int32 {
        let request = TodoItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "priority", ascending: false)]
        request.fetchLimit = 1

        if let lastItem = try context.fetch(request).first {
            return lastItem.priority
        }
        return -1
    }

    @MainActor
    private func shiftPriorities(from startIndex: Int32, in context: NSManagedObjectContext) throws {
        let request = TodoItem.fetchRequest()
        request.predicate = NSPredicate(format: "priority >= %d", startIndex)
        request.sortDescriptors = [NSSortDescriptor(key: "priority", ascending: false)]

        let items = try context.fetch(request)
        for item in items {
            item.priority += 1
        }
    }

    @MainActor
    private func findAutoResumeItem(for topicId: UUID, in context: NSManagedObjectContext) throws -> TodoItem? {
        let request = TodoItem.fetchRequest()
        request.predicate = NSPredicate(
            format: "typeRaw == %@ AND resumeTopicId == %@",
            TodoItemType.autoResume.rawValue,
            topicId as CVarArg
        )
        request.fetchLimit = 1

        return try context.fetch(request).first
    }
}

// MARK: - TodoManager Errors

public enum TodoError: Error, Sendable {
    case itemNotFound(UUID)
    case invalidOperation(String)
    case saveFailed(String)
}

extension TodoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .itemNotFound(let id):
            return "To-do item not found: \(id)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .saveFailed(let message):
            return "Failed to save: \(message)"
        }
    }
}
