// UnaMentis - Curriculum Core Data Class
// Manual NSManagedObject subclass for SPM compatibility
//
// This file enables Core Data entities to work with Swift Package Manager builds.
// The .xcdatamodeld must have codeGenerationType set to "Manual/None".

import Foundation
import CoreData

@objc(Curriculum)
public class Curriculum: NSManagedObject, Identifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Curriculum> {
        return NSFetchRequest<Curriculum>(entityName: "Curriculum")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var sourceId: String?  // UMLCF identifier for server sync
    @NSManaged public var summary: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var topics: NSOrderedSet?
}

// MARK: - Generated Accessors for Topics

extension Curriculum {
    @objc(insertObject:inTopicsAtIndex:)
    @NSManaged public func insertIntoTopics(_ value: Topic, at idx: Int)

    @objc(removeObjectFromTopicsAtIndex:)
    @NSManaged public func removeFromTopics(at idx: Int)

    @objc(insertTopics:atIndexes:)
    @NSManaged public func insertIntoTopics(_ values: [Topic], at indexes: NSIndexSet)

    @objc(removeTopicsAtIndexes:)
    @NSManaged public func removeFromTopics(at indexes: NSIndexSet)

    @objc(replaceObjectInTopicsAtIndex:withObject:)
    @NSManaged public func replaceTopics(at idx: Int, with value: Topic)

    @objc(replaceTopicsAtIndexes:withTopics:)
    @NSManaged public func replaceTopics(at indexes: NSIndexSet, with values: [Topic])

    @objc(addTopicsObject:)
    @NSManaged public func addToTopics(_ value: Topic)

    @objc(removeTopicsObject:)
    @NSManaged public func removeFromTopics(_ value: Topic)

    @objc(addTopics:)
    @NSManaged public func addToTopics(_ values: NSOrderedSet)

    @objc(removeTopics:)
    @NSManaged public func removeFromTopics(_ values: NSOrderedSet)
}
