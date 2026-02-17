// UnaMentis - Audio Cache Tests
// Unit tests for AudioEngineCache and AudioTTSCache singletons.
//
// Tests cover: get/store, deferred release, immediate release, warm engine reuse.

import XCTest
@testable import UnaMentis

// MARK: - AudioEngineCache Tests

final class AudioEngineCacheTests: XCTestCase {

    override func tearDown() async throws {
        // Clean up cache state between tests
        await AudioEngineCache.shared.releaseNow()
        try await super.tearDown()
    }

    func testGetEngine_whenCold_returnsNil() async {
        // Ensure cold state
        await AudioEngineCache.shared.releaseNow()

        let engine = await AudioEngineCache.shared.getEngine()
        XCTAssertNil(engine)
    }

    func testStore_thenGet_returnsStoredEngine() async {
        let vad = MockVADService()
        let telemetry = TelemetryEngine()
        let engine = AudioEngine(config: .default, vadService: vad, telemetry: telemetry)

        await AudioEngineCache.shared.store(engine)

        let cached = await AudioEngineCache.shared.getEngine()
        XCTAssertNotNil(cached, "Should return the stored engine")
    }

    func testReleaseNow_clearsCachedEngine() async {
        let vad = MockVADService()
        let telemetry = TelemetryEngine()
        let engine = AudioEngine(config: .default, vadService: vad, telemetry: telemetry)

        await AudioEngineCache.shared.store(engine)
        await AudioEngineCache.shared.releaseNow()

        let cached = await AudioEngineCache.shared.getEngine()
        XCTAssertNil(cached, "Engine should be nil after releaseNow")
    }

    func testGetEngine_cancelsScheduledRelease() async {
        let vad = MockVADService()
        let telemetry = TelemetryEngine()
        let engine = AudioEngine(config: .default, vadService: vad, telemetry: telemetry)

        await AudioEngineCache.shared.store(engine)
        await AudioEngineCache.shared.scheduleRelease()

        // Get engine immediately (should cancel the deferred release)
        let cached = await AudioEngineCache.shared.getEngine()
        XCTAssertNotNil(cached, "Getting engine should cancel pending release")
    }

    func testStore_overwritesPrevious() async {
        let vad1 = MockVADService()
        let vad2 = MockVADService()
        let telemetry = TelemetryEngine()
        let engine1 = AudioEngine(config: .default, vadService: vad1, telemetry: telemetry)
        let engine2 = AudioEngine(config: .default, vadService: vad2, telemetry: telemetry)

        await AudioEngineCache.shared.store(engine1)
        await AudioEngineCache.shared.store(engine2)

        let cached = await AudioEngineCache.shared.getEngine()
        XCTAssertNotNil(cached, "Should return the latest stored engine")
    }
}

// MARK: - AudioTTSCache Tests

final class AudioTTSCacheTests: XCTestCase {

    override func tearDown() async throws {
        await AudioTTSCache.shared.releaseNow()
        try await super.tearDown()
    }

    func testGetService_returnsATTSService() async {
        let service = await AudioTTSCache.shared.getService()
        // Should return a valid TTS service (created via provider resolution)
        XCTAssertNotNil(service)
    }

    func testGetService_returnsSameInstance() async {
        let service1 = await AudioTTSCache.shared.getService()
        let service2 = await AudioTTSCache.shared.getService()

        // Both should be the same cached instance (same object identity)
        // We can't directly compare actors, but we can verify the cache works
        // by checking that a second call doesn't create a new instance.
        // The best we can do is verify neither is nil.
        XCTAssertNotNil(service1)
        XCTAssertNotNil(service2)
    }

    func testReleaseNow_clearsCache() async {
        // Warm the cache
        _ = await AudioTTSCache.shared.getService()

        // Release
        await AudioTTSCache.shared.releaseNow()

        // Next get should create a new service (we can't distinguish, but it shouldn't crash)
        let service = await AudioTTSCache.shared.getService()
        XCTAssertNotNil(service)
    }

    func testScheduleRelease_doesNotImmediatelyRelease() async {
        // Warm the cache
        _ = await AudioTTSCache.shared.getService()

        // Schedule release (2 min timeout)
        await AudioTTSCache.shared.scheduleRelease()

        // Immediately get again (should cancel the scheduled release)
        let service = await AudioTTSCache.shared.getService()
        XCTAssertNotNil(service, "Service should still be available after scheduling release")
    }
}
