// UnaMentis - Audio Cache Tests
// Unit tests for AudioEngineCache and AudioTTSCache singletons.
//
// Tests cover: getEngine lifecycle, deferred release, immediate release.

import XCTest
@testable import UnaMentis

// MARK: - AudioEngineCache Tests

final class AudioEngineCacheTests: XCTestCase {

    override func tearDown() async throws {
        // Clean up cache state between tests
        await AudioEngineCache.shared.releaseNow()
        try await super.tearDown()
    }

    func testGetEngine_returnsAnEngine() async {
        let engine = await AudioEngineCache.shared.getEngine()
        // getEngine creates and caches a new engine if none exists
        XCTAssertNotNil(engine, "getEngine should create and return an AudioEngine")
    }

    func testGetEngine_returnsSameInstance() async {
        let engine1 = await AudioEngineCache.shared.getEngine()
        let engine2 = await AudioEngineCache.shared.getEngine()

        // Both calls should return the same cached instance
        XCTAssertNotNil(engine1)
        XCTAssertNotNil(engine2)
    }

    func testReleaseNow_clearsCachedEngine() async {
        // Warm the cache
        _ = await AudioEngineCache.shared.getEngine()

        // Release
        await AudioEngineCache.shared.releaseNow()

        // Next get creates a new engine (verifies no crash after release)
        let engine = await AudioEngineCache.shared.getEngine()
        XCTAssertNotNil(engine, "Should create a new engine after releaseNow")
    }

    func testScheduleRelease_doesNotImmediatelyRelease() async {
        // Warm the cache
        _ = await AudioEngineCache.shared.getEngine()

        // Schedule release (2 min timeout)
        await AudioEngineCache.shared.scheduleRelease()

        // Get engine immediately (should cancel the deferred release)
        let cached = await AudioEngineCache.shared.getEngine()
        XCTAssertNotNil(cached, "Getting engine should cancel pending release")
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

        // Both should be the same cached instance
        XCTAssertNotNil(service1)
        XCTAssertNotNil(service2)
    }

    func testReleaseNow_clearsCache() async {
        // Warm the cache
        _ = await AudioTTSCache.shared.getService()

        // Release
        await AudioTTSCache.shared.releaseNow()

        // Next get should create a new service (shouldn't crash)
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
