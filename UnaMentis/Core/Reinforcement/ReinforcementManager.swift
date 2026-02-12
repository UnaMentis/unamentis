// UnaMentis - Reinforcement Manager
// Manages CRUD operations for review items captured via voice commands
//
// Part of Reinforcement System

import Foundation
import CoreData
import Logging

// MARK: - Source Group

/// Groups review items by their source for hierarchical UI display
public struct ReinforcementSourceGroup: Identifiable, Sendable {
    public let sourceType: ReinforcementSourceType
    public let sourceId: UUID?
    public let sourceTitle: String
    public let items: [ReinforcementItemData]
    public var id: String { "\(sourceType.rawValue)-\(sourceId?.uuidString ?? "none")" }

    /// Total number of items in this group
    public var count: Int { items.count }

    /// Number of pending items
    public var pendingCount: Int { items.filter { $0.status == .pending }.count }
}

// MARK: - Item Data Transfer Object

/// Sendable DTO for ReinforcementItem data (safe to cross actor boundaries)
public struct ReinforcementItemData: Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let currentSegmentText: String
    public let previousSegmentText: String?
    public let segmentIndex: Int32
    public let totalSegments: Int32
    public let sourceType: ReinforcementSourceType
    public let sourceId: UUID?
    public let sourceTitle: String
    public let bookmarkId: UUID?
    public let snippetPreview: String?
    public let status: ReinforcementStatus
    public let reviewedAt: Date?
}

// MARK: - Reinforcement Manager

/// Manages CRUD operations for reinforcement review items
///
/// Responsibilities:
/// - Create review items from voice command captures
/// - Fetch items grouped by source for hierarchical display
/// - Manage item lifecycle (pending -> reviewed -> mastered)
public actor ReinforcementManager {

    // MARK: - Properties

    private let persistenceController: PersistenceController
    private let logger = Logger(label: "com.unamentis.reinforcement")

    /// Shared instance for convenience
    @MainActor
    public static var shared: ReinforcementManager?

    // MARK: - Initialization

    public init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        logger.info("ReinforcementManager initialized")
    }

    // MARK: - Create

    /// Create a review item linked to a bookmark
    @MainActor
    public func createItem(
        currentSegmentText: String,
        previousSegmentText: String?,
        segmentIndex: Int32,
        totalSegments: Int32,
        sourceType: ReinforcementSourceType,
        sourceId: UUID?,
        sourceTitle: String,
        bookmarkId: UUID?
    ) throws -> ReinforcementItem {
        let context = persistenceController.viewContext

        let item = ReinforcementItem(context: context)
        item.configure(
            currentSegmentText: currentSegmentText,
            previousSegmentText: previousSegmentText,
            segmentIndex: segmentIndex,
            totalSegments: totalSegments,
            sourceType: sourceType,
            sourceId: sourceId,
            sourceTitle: sourceTitle,
            bookmarkId: bookmarkId
        )

        try persistenceController.save()
        logger.info("Created reinforcement item: \(item.displayText)")

        return item
    }

    // MARK: - Read

    /// Fetch all items, grouped by source for hierarchical display
    @MainActor
    public func fetchItemsGroupedBySource() throws -> [ReinforcementSourceGroup] {
        let items = try fetchAllItems()
        let dtos = items.map { toDTO($0) }

        // Group by sourceType + sourceId
        var groups: [String: (type: ReinforcementSourceType, id: UUID?, title: String, items: [ReinforcementItemData])] = [:]

        for dto in dtos {
            let key = "\(dto.sourceType.rawValue)-\(dto.sourceId?.uuidString ?? "none")"
            if var group = groups[key] {
                group.items.append(dto)
                groups[key] = group
            } else {
                groups[key] = (dto.sourceType, dto.sourceId, dto.sourceTitle, [dto])
            }
        }

        return groups.values
            .map { ReinforcementSourceGroup(
                sourceType: $0.type,
                sourceId: $0.id,
                sourceTitle: $0.title,
                items: $0.items.sorted { $0.segmentIndex < $1.segmentIndex }
            )}
            .sorted { $0.sourceTitle < $1.sourceTitle }
    }

    /// Fetch all pending items
    @MainActor
    public func fetchPendingItems() throws -> [ReinforcementItem] {
        let context = persistenceController.viewContext
        let request = ReinforcementItem.fetchRequest()
        request.predicate = NSPredicate(format: "statusRaw == %@", ReinforcementStatus.pending.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    /// Fetch all items sorted by creation date
    @MainActor
    public func fetchAllItems() throws -> [ReinforcementItem] {
        let context = persistenceController.viewContext
        let request = ReinforcementItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    // MARK: - Update

    /// Mark an item as reviewed
    @MainActor
    public func markReviewed(_ item: ReinforcementItem) throws {
        item.status = .reviewed
        item.reviewedAt = Date()
        try persistenceController.save()
        logger.debug("Marked reinforcement item as reviewed: \(item.displayText)")
    }

    /// Mark an item as mastered
    @MainActor
    public func markMastered(_ item: ReinforcementItem) throws {
        item.status = .mastered
        item.reviewedAt = Date()
        try persistenceController.save()
        logger.debug("Marked reinforcement item as mastered: \(item.displayText)")
    }

    // MARK: - Delete

    /// Delete a reinforcement item
    @MainActor
    public func deleteItem(_ item: ReinforcementItem) throws {
        let context = persistenceController.viewContext
        context.delete(item)
        try persistenceController.save()
        logger.debug("Deleted reinforcement item")
    }

    // MARK: - Private

    private func toDTO(_ item: ReinforcementItem) -> ReinforcementItemData {
        ReinforcementItemData(
            id: item.id ?? UUID(),
            createdAt: item.createdAt ?? Date(),
            currentSegmentText: item.currentSegmentText ?? "",
            previousSegmentText: item.previousSegmentText,
            segmentIndex: item.segmentIndex,
            totalSegments: item.totalSegments,
            sourceType: item.sourceType,
            sourceId: item.sourceId,
            sourceTitle: item.sourceTitle ?? "",
            bookmarkId: item.bookmarkId,
            snippetPreview: item.snippetPreview,
            status: item.status,
            reviewedAt: item.reviewedAt
        )
    }
}
