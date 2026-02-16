// UnaMentis - ReinforcementItem Core Data Class
// Manual NSManagedObject subclass for SPM compatibility
//
// Review items captured via voice command ("flag") during learning activities.
// Each item records the current and previous segment text plus a link back
// to the source material and the bookmark created alongside it.

import Foundation
import CoreData

// MARK: - Source Type

/// Where the reinforcement item was captured from
public enum ReinforcementSourceType: String, Codable, Sendable, CaseIterable {
    case readingList = "reading_list"
    case curriculum = "curriculum"
    case session = "session"
    case knowledgeBowl = "knowledge_bowl"

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .readingList: return "Reading List"
        case .curriculum: return "Curriculum"
        case .session: return "Session"
        case .knowledgeBowl: return "Knowledge Bowl"
        }
    }

    /// SF Symbol icon
    public var iconName: String {
        switch self {
        case .readingList: return "book.pages"
        case .curriculum: return "book.fill"
        case .session: return "bubble.left.and.bubble.right"
        case .knowledgeBowl: return "trophy"
        }
    }
}

// MARK: - Review Status

/// Lifecycle status of a reinforcement item
public enum ReinforcementStatus: String, Codable, Sendable, CaseIterable {
    case pending = "pending"
    case reviewed = "reviewed"
    case mastered = "mastered"

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .reviewed: return "Reviewed"
        case .mastered: return "Mastered"
        }
    }

    /// SF Symbol icon
    public var iconName: String {
        switch self {
        case .pending: return "circle"
        case .reviewed: return "checkmark.circle"
        case .mastered: return "checkmark.circle.fill"
        }
    }
}

// MARK: - ReinforcementItem

@objc(ReinforcementItem)
public class ReinforcementItem: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ReinforcementItem> {
        return NSFetchRequest<ReinforcementItem>(entityName: "ReinforcementItem")
    }

    // MARK: - Core Attributes

    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var currentSegmentText: String?
    @NSManaged public var previousSegmentText: String?
    @NSManaged public var segmentIndex: Int32
    @NSManaged public var totalSegments: Int32
    @NSManaged public var sourceTypeRaw: String?
    @NSManaged public var sourceId: UUID?
    @NSManaged public var sourceTitle: String?
    @NSManaged public var bookmarkId: UUID?
    @NSManaged public var snippetPreview: String?
    @NSManaged public var statusRaw: String?
    @NSManaged public var reviewedAt: Date?

    // MARK: - Computed Properties

    /// Typed source type
    public var sourceType: ReinforcementSourceType {
        get { ReinforcementSourceType(rawValue: sourceTypeRaw ?? "reading_list") ?? .readingList }
        set { sourceTypeRaw = newValue.rawValue }
    }

    /// Typed status
    public var status: ReinforcementStatus {
        get { ReinforcementStatus(rawValue: statusRaw ?? "pending") ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// Display text (snippet preview or truncated current segment)
    public var displayText: String {
        if let preview = snippetPreview, !preview.isEmpty {
            return preview
        }
        guard let text = currentSegmentText, !text.isEmpty else {
            return "Review Item"
        }
        if text.count <= 80 {
            return text
        }
        // Truncate at word boundary
        let truncated = String(text.prefix(80))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }

    // MARK: - Initialization Helper

    /// Configure a new ReinforcementItem with required fields
    public func configure(
        currentSegmentText: String,
        previousSegmentText: String?,
        segmentIndex: Int32,
        totalSegments: Int32,
        sourceType: ReinforcementSourceType,
        sourceId: UUID?,
        sourceTitle: String,
        bookmarkId: UUID?
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.currentSegmentText = currentSegmentText
        self.previousSegmentText = previousSegmentText
        self.segmentIndex = segmentIndex
        self.totalSegments = totalSegments
        self.sourceTypeRaw = sourceType.rawValue
        self.sourceId = sourceId
        self.sourceTitle = sourceTitle
        self.bookmarkId = bookmarkId
        self.statusRaw = ReinforcementStatus.pending.rawValue

        // Auto-generate snippet preview
        if currentSegmentText.count <= 80 {
            self.snippetPreview = currentSegmentText
        } else {
            let truncated = String(currentSegmentText.prefix(80))
            if let lastSpace = truncated.lastIndex(of: " ") {
                self.snippetPreview = String(truncated[..<lastSpace]) + "..."
            } else {
                self.snippetPreview = truncated + "..."
            }
        }
    }
}

// MARK: - Identifiable Conformance

extension ReinforcementItem: Identifiable { }

// MARK: - Comparable for Sorting

extension ReinforcementItem: Comparable {
    public static func < (lhs: ReinforcementItem, rhs: ReinforcementItem) -> Bool {
        // Sort by creation date, newest first
        guard let lhsDate = lhs.createdAt, let rhsDate = rhs.createdAt else {
            return false
        }
        return lhsDate > rhsDate
    }
}

// NOTE: Do NOT override hash/isEqual on NSManagedObject subclasses!
// Core Data uses these internally for object tracking and faulting.
