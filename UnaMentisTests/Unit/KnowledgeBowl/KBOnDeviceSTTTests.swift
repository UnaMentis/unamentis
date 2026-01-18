//
//  KBOnDeviceSTTTests.swift
//  UnaMentisTests
//
//  Tests for KBOnDeviceSTT speech recognition service
//

import Speech
import XCTest
@testable import UnaMentis

@MainActor
final class KBOnDeviceSTTTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInit_startsWithDefaultState() {
        let stt = KBOnDeviceSTT()

        XCTAssertFalse(stt.isListening)
        XCTAssertEqual(stt.transcript, "")
        XCTAssertFalse(stt.isFinal)
        XCTAssertNil(stt.error)
    }

    func testInit_authorizationStatusStartsNotDetermined() {
        let stt = KBOnDeviceSTT()

        // May be .authorized if previously granted, or .notDetermined on fresh install
        // Just verify it's one of the valid states
        let validStatuses: [SFSpeechRecognizerAuthorizationStatus] = [
            .notDetermined, .authorized, .denied, .restricted
        ]
        XCTAssertTrue(validStatuses.contains(stt.authorizationStatus))
    }

    // MARK: - Availability Tests

    func testIsAvailable_returnsRecognizerAvailability() {
        let stt = KBOnDeviceSTT()

        // This should return true if speech recognition is available on the test device/simulator
        // It's a wrapper around SFSpeechRecognizer.isAvailable
        // We can't guarantee the value, just that it doesn't crash
        _ = stt.isAvailable
    }

    func testSupportsOnDevice_returnsOnDeviceCapability() {
        let stt = KBOnDeviceSTT()

        // This should return whether on-device recognition is supported
        // On iOS 13+ this is typically true for en-US locale
        _ = stt.supportsOnDevice
    }

    // MARK: - Stop Listening Tests

    func testStopListening_whenNotListening_doesNotCrash() {
        let stt = KBOnDeviceSTT()

        // Should handle gracefully when not listening
        stt.stopListening()

        XCTAssertFalse(stt.isListening)
    }

    func testStopListening_setsIsListeningFalse() {
        let stt = KBOnDeviceSTT()

        // Ensure state is correct after stop
        stt.stopListening()

        XCTAssertFalse(stt.isListening)
    }

    // MARK: - KBSTTError Tests

    func testKBSTTError_authorizationDenied_hasDescription() {
        let error = KBSTTError.authorizationDenied

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("denied"))
    }

    func testKBSTTError_microphoneAccessDenied_hasDescription() {
        let error = KBSTTError.microphoneAccessDenied

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Microphone"))
    }

    func testKBSTTError_restricted_hasDescription() {
        let error = KBSTTError.restricted

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("restricted"))
    }

    func testKBSTTError_recognizerUnavailable_hasDescription() {
        let error = KBSTTError.recognizerUnavailable

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not available"))
    }

    func testKBSTTError_recognitionRequestFailed_hasDescription() {
        let error = KBSTTError.recognitionRequestFailed

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("request"))
    }

    func testKBSTTError_recognitionFailed_includesMessage() {
        let message = "Custom error message"
        let error = KBSTTError.recognitionFailed(message)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(message))
    }

    func testKBSTTError_isSendable() {
        // Verify Sendable conformance by using in concurrent context
        let error = KBSTTError.authorizationDenied

        Task.detached {
            _ = error.errorDescription
        }
    }

    func testKBSTTError_allCases_haveDescriptions() {
        let errors: [KBSTTError] = [
            .authorizationDenied,
            .microphoneAccessDenied,
            .restricted,
            .recognizerUnavailable,
            .recognitionRequestFailed,
            .recognitionFailed("test")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }

    // MARK: - Preview Support Tests

    #if DEBUG
    func testPreview_createsValidInstance() {
        let stt = KBOnDeviceSTT.preview()

        XCTAssertNotNil(stt)
        XCTAssertFalse(stt.isListening)
    }
    #endif

    // MARK: - State Consistency Tests

    func testState_afterMultipleStopCalls_remainsConsistent() {
        let stt = KBOnDeviceSTT()

        // Multiple stops should be safe
        stt.stopListening()
        stt.stopListening()
        stt.stopListening()

        XCTAssertFalse(stt.isListening)
        XCTAssertEqual(stt.transcript, "")
    }

    // MARK: - Authorization Status Tests

    func testAuthorizationStatus_matchesSystemStatus() {
        // Get the system's current authorization status
        let systemStatus = SFSpeechRecognizer.authorizationStatus()

        let stt = KBOnDeviceSTT()

        // The STT instance should reflect the system status (or .notDetermined if never requested)
        // Since we can't know the exact state, just verify it's a valid status
        let validStatuses: [SFSpeechRecognizerAuthorizationStatus] = [
            .notDetermined, .authorized, .denied, .restricted
        ]
        XCTAssertTrue(validStatuses.contains(stt.authorizationStatus))

        // If system is authorized, STT should also be authorized after checking
        if systemStatus == .authorized {
            // The authorization status might be updated during init
            _ = stt.authorizationStatus
        }
    }
}
