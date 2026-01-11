// UnaMentis - TodoItemSource Tests
// Comprehensive tests for TodoItemSource enum
//
// Part of Todo System Testing

import XCTest
@testable import UnaMentis

final class TodoItemSourceTests: XCTestCase {

    // MARK: - Raw Value Tests

    func testRawValues_areCorrect() {
        XCTAssertEqual(TodoItemSource.manual.rawValue, "manual")
        XCTAssertEqual(TodoItemSource.voice.rawValue, "voice")
        XCTAssertEqual(TodoItemSource.autoResume.rawValue, "auto_resume")
        XCTAssertEqual(TodoItemSource.reinforcement.rawValue, "reinforcement")
    }

    func testAllCases_containsAllSources() {
        XCTAssertEqual(TodoItemSource.allCases.count, 4)
        XCTAssertTrue(TodoItemSource.allCases.contains(.manual))
        XCTAssertTrue(TodoItemSource.allCases.contains(.voice))
        XCTAssertTrue(TodoItemSource.allCases.contains(.autoResume))
        XCTAssertTrue(TodoItemSource.allCases.contains(.reinforcement))
    }

    // MARK: - Display Name Tests

    func testDisplayName_manual_returnsAddedManually() {
        XCTAssertEqual(TodoItemSource.manual.displayName, "Added Manually")
    }

    func testDisplayName_voice_returnsVoiceCommand() {
        XCTAssertEqual(TodoItemSource.voice.displayName, "Voice Command")
    }

    func testDisplayName_autoResume_returnsAutoResume() {
        XCTAssertEqual(TodoItemSource.autoResume.displayName, "Auto-Resume")
    }

    func testDisplayName_reinforcement_returnsSessionReview() {
        XCTAssertEqual(TodoItemSource.reinforcement.displayName, "Session Review")
    }

    // MARK: - Accessibility Description Tests

    func testAccessibilityDescription_allSourcesHaveDescriptions() {
        for source in TodoItemSource.allCases {
            XCTAssertFalse(
                source.accessibilityDescription.isEmpty,
                "Accessibility description should not be empty for \(source)"
            )
        }
    }

    func testAccessibilityDescription_manual_returnsAddedManually() {
        XCTAssertEqual(TodoItemSource.manual.accessibilityDescription, "added manually")
    }

    func testAccessibilityDescription_voice_returnsAddedByVoice() {
        XCTAssertEqual(TodoItemSource.voice.accessibilityDescription, "added by voice command")
    }

    func testAccessibilityDescription_autoResume_returnsAutoDescription() {
        XCTAssertEqual(
            TodoItemSource.autoResume.accessibilityDescription,
            "added automatically when session stopped"
        )
    }

    func testAccessibilityDescription_reinforcement_returnsSessionDescription() {
        XCTAssertEqual(
            TodoItemSource.reinforcement.accessibilityDescription,
            "added as review item during session"
        )
    }

    // MARK: - Icon Name Tests

    func testIconName_allSourcesHaveIcons() {
        for source in TodoItemSource.allCases {
            XCTAssertFalse(source.iconName.isEmpty, "Icon name should not be empty for \(source)")
        }
    }

    func testIconName_manual_returnsHandTap() {
        XCTAssertEqual(TodoItemSource.manual.iconName, "hand.tap")
    }

    func testIconName_voice_returnsWaveform() {
        XCTAssertEqual(TodoItemSource.voice.iconName, "waveform")
    }

    func testIconName_autoResume_returnsClockwise() {
        XCTAssertEqual(TodoItemSource.autoResume.iconName, "arrow.clockwise")
    }

    func testIconName_reinforcement_returnsQuoteBubble() {
        XCTAssertEqual(TodoItemSource.reinforcement.iconName, "quote.bubble")
    }

    // MARK: - Codable Tests

    func testCodable_encodeDecode_preservesValue() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for source in TodoItemSource.allCases {
            let encoded = try encoder.encode(source)
            let decoded = try decoder.decode(TodoItemSource.self, from: encoded)
            XCTAssertEqual(source, decoded, "Codable round-trip failed for \(source)")
        }
    }

    func testCodable_decodeFromRawValue_works() throws {
        let jsonData = "\"voice\"".data(using: .utf8)!
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TodoItemSource.self, from: jsonData)
        XCTAssertEqual(decoded, .voice)
    }

    // MARK: - Sendable Conformance

    func testSendable_canPassAcrossActors() async {
        let source: TodoItemSource = .manual

        await Task.detached {
            let capturedSource = source
            XCTAssertEqual(capturedSource, .manual)
        }.value
    }
}
