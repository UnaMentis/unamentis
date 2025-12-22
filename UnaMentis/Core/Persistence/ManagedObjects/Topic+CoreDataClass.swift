// UnaMentis - Topic Core Data Class
// Manual NSManagedObject subclass for SPM compatibility
//
// This file enables Core Data entities to work with Swift Package Manager builds.
// The .xcdatamodeld must have codeGenerationType set to "Manual/None".

import Foundation
import CoreData

@objc(Topic)
public class Topic: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Topic> {
        return NSFetchRequest<Topic>(entityName: "Topic")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var title: String?
    @NSManaged public var sourceId: String?  // UMLCF identifier for server sync
    @NSManaged public var outline: String?
    @NSManaged public var objectives: [String]?
    @NSManaged public var orderIndex: Int32
    @NSManaged public var mastery: Float
    @NSManaged public var depthLevelRaw: String?
    @NSManaged public var curriculum: Curriculum?
    @NSManaged public var documents: NSSet?
    @NSManaged public var progress: TopicProgress?
    @NSManaged public var sessions: NSSet?

    /// Content depth level (defaults to intermediate if not set)
    public var depthLevel: ContentDepth {
        get {
            guard let raw = depthLevelRaw else { return .intermediate }
            return ContentDepth(rawValue: raw) ?? .intermediate
        }
        set {
            depthLevelRaw = newValue.rawValue
        }
    }
}

// MARK: - Generated Accessors for Documents

extension Topic {
    @objc(addDocumentsObject:)
    @NSManaged public func addToDocuments(_ value: Document)

    @objc(removeDocumentsObject:)
    @NSManaged public func removeFromDocuments(_ value: Document)

    @objc(addDocuments:)
    @NSManaged public func addToDocuments(_ values: NSSet)

    @objc(removeDocuments:)
    @NSManaged public func removeFromDocuments(_ values: NSSet)
}

// MARK: - Generated Accessors for Sessions

extension Topic {
    @objc(addSessionsObject:)
    @NSManaged public func addToSessions(_ value: Session)

    @objc(removeSessionsObject:)
    @NSManaged public func removeFromSessions(_ value: Session)

    @objc(addSessions:)
    @NSManaged public func addToSessions(_ values: NSSet)

    @objc(removeSessions:)
    @NSManaged public func removeFromSessions(_ values: NSSet)
}

// MARK: - Identifiable Conformance

extension Topic: Identifiable { }

// NOTE: Do NOT override hash/isEqual on NSManagedObject subclasses!
// Core Data uses these internally for object tracking and faulting.
// Overriding them causes: "Class 'Topic' has an illegal override of NSManagedObject -isEqual:"
