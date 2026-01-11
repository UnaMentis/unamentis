// UnaMentis - TodoItemType Tests
// Comprehensive tests for TodoItemType enum
//
// Part of Todo System Testing

import XCTest
@testable import UnaMentis

final class TodoItemTypeTests: XCTestCase {

    // MARK: - Raw Value Tests

    func testRawValues_areCorrect() {
        XCTAssertEqual(TodoItemType.curriculum.rawValue, "curriculum")
        XCTAssertEqual(TodoItemType.module.rawValue, "module")
        XCTAssertEqual(TodoItemType.topic.rawValue, "topic")
        XCTAssertEqual(TodoItemType.learningTarget.rawValue, "learning_target")
        XCTAssertEqual(TodoItemType.reinforcement.rawValue, "reinforcement")
        XCTAssertEqual(TodoItemType.autoResume.rawValue, "auto_resume")
    }

    func testAllCases_containsAllTypes() {
        XCTAssertEqual(TodoItemType.allCases.count, 6)
        XCTAssertTrue(TodoItemType.allCases.contains(.curriculum))
        XCTAssertTrue(TodoItemType.allCases.contains(.module))
        XCTAssertTrue(TodoItemType.allCases.contains(.topic))
        XCTAssertTrue(TodoItemType.allCases.contains(.learningTarget))
        XCTAssertTrue(TodoItemType.allCases.contains(.reinforcement))
        XCTAssertTrue(TodoItemType.allCases.contains(.autoResume))
    }

    // MARK: - Display Name Tests

    func testDisplayName_curriculum_returnsCurriculum() {
        XCTAssertEqual(TodoItemType.curriculum.displayName, "Curriculum")
    }

    func testDisplayName_module_returnsModule() {
        XCTAssertEqual(TodoItemType.module.displayName, "Module")
    }

    func testDisplayName_topic_returnsTopic() {
        XCTAssertEqual(TodoItemType.topic.displayName, "Topic")
    }

    func testDisplayName_learningTarget_returnsLearningGoal() {
        XCTAssertEqual(TodoItemType.learningTarget.displayName, "Learning Goal")
    }

    func testDisplayName_reinforcement_returnsReviewItem() {
        XCTAssertEqual(TodoItemType.reinforcement.displayName, "Review Item")
    }

    func testDisplayName_autoResume_returnsContinueSession() {
        XCTAssertEqual(TodoItemType.autoResume.displayName, "Continue Session")
    }

    // MARK: - Icon Name Tests

    func testIconName_allTypesHaveValidIcons() {
        for type in TodoItemType.allCases {
            XCTAssertFalse(type.iconName.isEmpty, "Icon name should not be empty for \(type)")
        }
    }

    func testIconName_curriculum_returnsBookFill() {
        XCTAssertEqual(TodoItemType.curriculum.iconName, "book.fill")
    }

    func testIconName_module_returnsFolderFill() {
        XCTAssertEqual(TodoItemType.module.iconName, "folder.fill")
    }

    func testIconName_topic_returnsDocTextFill() {
        XCTAssertEqual(TodoItemType.topic.iconName, "doc.text.fill")
    }

    func testIconName_learningTarget_returnsTarget() {
        XCTAssertEqual(TodoItemType.learningTarget.iconName, "target")
    }

    func testIconName_reinforcement_returnsCirclePath() {
        XCTAssertEqual(TodoItemType.reinforcement.iconName, "arrow.triangle.2.circlepath")
    }

    func testIconName_autoResume_returnsPlayCircle() {
        XCTAssertEqual(TodoItemType.autoResume.iconName, "play.circle.fill")
    }

    // MARK: - Accessibility Description Tests

    func testAccessibilityDescription_allTypesHaveDescriptions() {
        for type in TodoItemType.allCases {
            XCTAssertFalse(
                type.accessibilityDescription.isEmpty,
                "Accessibility description should not be empty for \(type)"
            )
        }
    }

    func testAccessibilityDescription_curriculum() {
        XCTAssertEqual(TodoItemType.curriculum.accessibilityDescription, "curriculum item")
    }

    func testAccessibilityDescription_learningTarget() {
        XCTAssertEqual(TodoItemType.learningTarget.accessibilityDescription, "learning goal")
    }

    // MARK: - Curriculum Link Tests

    func testIsLinkedToCurriculum_curriculumModuleTopicAutoResume_returnsTrue() {
        XCTAssertTrue(TodoItemType.curriculum.isLinkedToCurriculum)
        XCTAssertTrue(TodoItemType.module.isLinkedToCurriculum)
        XCTAssertTrue(TodoItemType.topic.isLinkedToCurriculum)
        XCTAssertTrue(TodoItemType.autoResume.isLinkedToCurriculum)
    }

    func testIsLinkedToCurriculum_learningTargetReinforcement_returnsFalse() {
        XCTAssertFalse(TodoItemType.learningTarget.isLinkedToCurriculum)
        XCTAssertFalse(TodoItemType.reinforcement.isLinkedToCurriculum)
    }

    // MARK: - Color Name Tests

    func testColorName_allTypesHaveColors() {
        for type in TodoItemType.allCases {
            XCTAssertFalse(type.colorName.isEmpty, "Color name should not be empty for \(type)")
        }
    }

    func testColorName_curriculum_returnsBlue() {
        XCTAssertEqual(TodoItemType.curriculum.colorName, "blue")
    }

    func testColorName_learningTarget_returnsOrange() {
        XCTAssertEqual(TodoItemType.learningTarget.colorName, "orange")
    }

    func testColorName_autoResume_returnsGreen() {
        XCTAssertEqual(TodoItemType.autoResume.colorName, "green")
    }

    // MARK: - Codable Tests

    func testCodable_encodeDecode_preservesValue() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for type in TodoItemType.allCases {
            let encoded = try encoder.encode(type)
            let decoded = try decoder.decode(TodoItemType.self, from: encoded)
            XCTAssertEqual(type, decoded, "Codable round-trip failed for \(type)")
        }
    }

    func testCodable_decodeFromRawValue_works() throws {
        let jsonData = "\"curriculum\"".data(using: .utf8)!
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TodoItemType.self, from: jsonData)
        XCTAssertEqual(decoded, .curriculum)
    }

    // MARK: - Sendable Conformance

    func testSendable_canPassAcrossActors() async {
        let type: TodoItemType = .curriculum

        await Task.detached {
            // This compiles because TodoItemType is Sendable
            let capturedType = type
            XCTAssertEqual(capturedType, .curriculum)
        }.value
    }
}
