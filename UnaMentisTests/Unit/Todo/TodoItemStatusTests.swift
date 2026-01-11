// UnaMentis - TodoItemStatus Tests
// Comprehensive tests for TodoItemStatus enum
//
// Part of Todo System Testing

import XCTest
@testable import UnaMentis

final class TodoItemStatusTests: XCTestCase {

    // MARK: - Raw Value Tests

    func testRawValues_areCorrect() {
        XCTAssertEqual(TodoItemStatus.pending.rawValue, "pending")
        XCTAssertEqual(TodoItemStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(TodoItemStatus.completed.rawValue, "completed")
        XCTAssertEqual(TodoItemStatus.archived.rawValue, "archived")
    }

    func testAllCases_containsAllStatuses() {
        XCTAssertEqual(TodoItemStatus.allCases.count, 4)
        XCTAssertTrue(TodoItemStatus.allCases.contains(.pending))
        XCTAssertTrue(TodoItemStatus.allCases.contains(.inProgress))
        XCTAssertTrue(TodoItemStatus.allCases.contains(.completed))
        XCTAssertTrue(TodoItemStatus.allCases.contains(.archived))
    }

    // MARK: - Display Name Tests

    func testDisplayName_pending_returnsPending() {
        XCTAssertEqual(TodoItemStatus.pending.displayName, "Pending")
    }

    func testDisplayName_inProgress_returnsInProgress() {
        XCTAssertEqual(TodoItemStatus.inProgress.displayName, "In Progress")
    }

    func testDisplayName_completed_returnsCompleted() {
        XCTAssertEqual(TodoItemStatus.completed.displayName, "Completed")
    }

    func testDisplayName_archived_returnsArchived() {
        XCTAssertEqual(TodoItemStatus.archived.displayName, "Archived")
    }

    // MARK: - Accessibility Description Tests

    func testAccessibilityDescription_allStatusesHaveDescriptions() {
        for status in TodoItemStatus.allCases {
            XCTAssertFalse(
                status.accessibilityDescription.isEmpty,
                "Accessibility description should not be empty for \(status)"
            )
        }
    }

    func testAccessibilityDescription_pending_returnsNotStarted() {
        XCTAssertEqual(TodoItemStatus.pending.accessibilityDescription, "not started")
    }

    func testAccessibilityDescription_inProgress_returnsInProgress() {
        XCTAssertEqual(TodoItemStatus.inProgress.accessibilityDescription, "in progress")
    }

    func testAccessibilityDescription_completed_returnsCompleted() {
        XCTAssertEqual(TodoItemStatus.completed.accessibilityDescription, "completed")
    }

    func testAccessibilityDescription_archived_returnsArchived() {
        XCTAssertEqual(TodoItemStatus.archived.accessibilityDescription, "archived")
    }

    // MARK: - Icon Name Tests

    func testIconName_allStatusesHaveIcons() {
        for status in TodoItemStatus.allCases {
            XCTAssertFalse(status.iconName.isEmpty, "Icon name should not be empty for \(status)")
        }
    }

    func testIconName_pending_returnsCircle() {
        XCTAssertEqual(TodoItemStatus.pending.iconName, "circle")
    }

    func testIconName_inProgress_returnsHalfFilledCircle() {
        XCTAssertEqual(TodoItemStatus.inProgress.iconName, "circle.lefthalf.filled")
    }

    func testIconName_completed_returnsCheckmark() {
        XCTAssertEqual(TodoItemStatus.completed.iconName, "checkmark.circle.fill")
    }

    func testIconName_archived_returnsArchivebox() {
        XCTAssertEqual(TodoItemStatus.archived.iconName, "archivebox")
    }

    // MARK: - isActive Tests

    func testIsActive_pendingAndInProgress_returnsTrue() {
        XCTAssertTrue(TodoItemStatus.pending.isActive)
        XCTAssertTrue(TodoItemStatus.inProgress.isActive)
    }

    func testIsActive_completedAndArchived_returnsFalse() {
        XCTAssertFalse(TodoItemStatus.completed.isActive)
        XCTAssertFalse(TodoItemStatus.archived.isActive)
    }

    // MARK: - canStart Tests

    func testCanStart_pendingAndInProgress_returnsTrue() {
        XCTAssertTrue(TodoItemStatus.pending.canStart)
        XCTAssertTrue(TodoItemStatus.inProgress.canStart)
    }

    func testCanStart_completedAndArchived_returnsFalse() {
        XCTAssertFalse(TodoItemStatus.completed.canStart)
        XCTAssertFalse(TodoItemStatus.archived.canStart)
    }

    // MARK: - Codable Tests

    func testCodable_encodeDecode_preservesValue() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in TodoItemStatus.allCases {
            let encoded = try encoder.encode(status)
            let decoded = try decoder.decode(TodoItemStatus.self, from: encoded)
            XCTAssertEqual(status, decoded, "Codable round-trip failed for \(status)")
        }
    }

    func testCodable_decodeFromRawValue_works() throws {
        let jsonData = "\"in_progress\"".data(using: .utf8)!
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TodoItemStatus.self, from: jsonData)
        XCTAssertEqual(decoded, .inProgress)
    }

    // MARK: - Sendable Conformance

    func testSendable_canPassAcrossActors() async {
        let status: TodoItemStatus = .pending

        await Task.detached {
            let capturedStatus = status
            XCTAssertEqual(capturedStatus, .pending)
        }.value
    }

    // MARK: - State Transition Logic Tests

    func testStateTransitions_pendingCanBecomeInProgress() {
        // This tests the logical flow, not actual state machine
        let pending = TodoItemStatus.pending
        XCTAssertTrue(pending.canStart, "Pending items should be startable")
    }

    func testStateTransitions_completedCannotBeRestarted() {
        let completed = TodoItemStatus.completed
        XCTAssertFalse(completed.canStart, "Completed items should not be restartable")
    }
}
