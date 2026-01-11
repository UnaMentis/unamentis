// UnaMentis - FeatureFlagService Tests
// Unit tests for FeatureFlagService, FeatureFlagCache, and related types
//
// Part of Quality Infrastructure (Phase 3)

import XCTest
@testable import UnaMentis

/// Unit tests for FeatureFlagService
final class FeatureFlagServiceTests: XCTestCase {

    // MARK: - Properties

    var service: FeatureFlagService!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        // Create service with development config (doesn't connect to real server)
        service = FeatureFlagService(config: .development)
    }

    override func tearDown() async throws {
        await service.stop()
        service = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_createsWithDevelopmentConfig() async {
        let service = FeatureFlagService(config: .development)
        XCTAssertNotNil(service)
    }

    func testInit_createsWithCustomConfig() async {
        let config = FeatureFlagConfig(
            proxyURL: URL(string: "http://test.example.com/proxy")!,
            clientKey: "test-key",
            appName: "TestApp"
        )
        let service = FeatureFlagService(config: config)
        XCTAssertNotNil(service)
    }

    // MARK: - Flag Evaluation Tests

    func testIsEnabled_defaultsToFalse() async {
        // Without starting or fetching flags, should default to false
        let enabled = await service.isEnabled("nonexistent_flag")
        XCTAssertFalse(enabled)
    }

    func testIsEnabled_withContext_defaultsToFalse() async {
        let context = FeatureFlagContext(userId: "test-user")
        let enabled = await service.isEnabled("nonexistent_flag", context: context)
        XCTAssertFalse(enabled)
    }

    func testGetVariant_returnsNilForUnknownFlag() async {
        let variant = await service.getVariant("nonexistent_flag")
        XCTAssertNil(variant)
    }

    // MARK: - Multiple Flag Evaluation Tests

    func testAreEnabled_evaluatesMultipleFlags() async {
        let flags = ["flag_a", "flag_b", "flag_c"]
        let results = await service.areEnabled(flags)

        XCTAssertEqual(results.count, 3)
        XCTAssertFalse(results["flag_a"] ?? true)
        XCTAssertFalse(results["flag_b"] ?? true)
        XCTAssertFalse(results["flag_c"] ?? true)
    }

    // MARK: - Metrics Tests

    func testGetMetrics_returnsValidMetrics() async {
        // Perform some evaluations
        _ = await service.isEnabled("test_flag")
        _ = await service.isEnabled("test_flag")
        _ = await service.getVariant("test_flag")

        let metrics = await service.getMetrics()

        XCTAssertEqual(metrics.totalEvaluations, 3)
        XCTAssertGreaterThanOrEqual(metrics.cacheMisses, 0)
    }

    func testCacheHitRate_calculatesCorrectly() async {
        // Without any cache, all should be misses
        _ = await service.isEnabled("flag_1")
        _ = await service.isEnabled("flag_2")

        let metrics = await service.getMetrics()

        // All misses since no flags are loaded
        XCTAssertEqual(metrics.cacheHits + metrics.cacheMisses, 2)
    }

    // MARK: - Flag Names Tests

    func testFlagNames_emptyInitially() async {
        let names = await service.flagNames
        XCTAssertTrue(names.isEmpty)
    }
}

/// Unit tests for FeatureFlagCache
final class FeatureFlagCacheTests: XCTestCase {

    // MARK: - Properties

    var cache: FeatureFlagCache!

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        try await super.setUp()
        cache = FeatureFlagCache(maxCacheAge: 3600) // 1 hour
    }

    override func tearDown() async throws {
        try? await cache.clear()
        cache = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_createsWithDefaultMaxAge() async {
        let cache = FeatureFlagCache()
        XCTAssertNotNil(cache)
    }

    func testInit_createsWithCustomMaxAge() async {
        let cache = FeatureFlagCache(maxCacheAge: 7200)
        XCTAssertNotNil(cache)
    }

    // MARK: - Cache State Tests

    func testHasValidCache_falseInitially() async {
        let hasCache = await cache.hasValidCache
        XCTAssertFalse(hasCache)
    }

    func testCachedFlagNames_emptyInitially() async {
        let names = await cache.cachedFlagNames
        XCTAssertTrue(names.isEmpty)
    }

    func testStatistics_zeroInitially() async {
        let stats = await cache.statistics
        XCTAssertEqual(stats.count, 0)
        XCTAssertNil(stats.oldestAge)
    }

    // MARK: - Save and Retrieve Tests

    func testSave_storesFlags() async throws {
        let flags: [String: (enabled: Bool, variant: FeatureFlagVariant?)] = [
            "flag_a": (true, nil),
            "flag_b": (false, nil),
        ]

        try await cache.save(flags: flags)

        let hasCache = await cache.hasValidCache
        XCTAssertTrue(hasCache)
    }

    func testGet_retrievesSavedFlag() async throws {
        let flags: [String: (enabled: Bool, variant: FeatureFlagVariant?)] = [
            "test_flag": (true, nil),
        ]

        try await cache.save(flags: flags)

        let cached = await cache.get("test_flag")
        XCTAssertNotNil(cached)
        XCTAssertTrue(cached?.enabled ?? false)
    }

    func testGet_returnsNilForUnknownFlag() async {
        let cached = await cache.get("unknown_flag")
        XCTAssertNil(cached)
    }

    func testSave_storesFlagWithVariant() async throws {
        let variant = FeatureFlagVariant(
            name: "control",
            enabled: true,
            payload: .string("test-value")
        )

        let flags: [String: (enabled: Bool, variant: FeatureFlagVariant?)] = [
            "variant_flag": (true, variant),
        ]

        try await cache.save(flags: flags)

        let cached = await cache.get("variant_flag")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.variant?.name, "control")
        XCTAssertEqual(cached?.variant?.payload?.stringValue, "test-value")
    }

    // MARK: - Statistics Tests

    func testStatistics_updatesAfterSave() async throws {
        let flags: [String: (enabled: Bool, variant: FeatureFlagVariant?)] = [
            "flag_1": (true, nil),
            "flag_2": (false, nil),
            "flag_3": (true, nil),
        ]

        try await cache.save(flags: flags)

        let stats = await cache.statistics
        XCTAssertEqual(stats.count, 3)
        XCTAssertNotNil(stats.oldestAge)
    }

    // MARK: - Clear Tests

    func testClear_removesAllFlags() async throws {
        let flags: [String: (enabled: Bool, variant: FeatureFlagVariant?)] = [
            "flag_a": (true, nil),
        ]

        try await cache.save(flags: flags)
        try await cache.clear()

        let hasCache = await cache.hasValidCache
        XCTAssertFalse(hasCache)

        let stats = await cache.statistics
        XCTAssertEqual(stats.count, 0)
    }
}

/// Unit tests for FeatureFlagTypes
final class FeatureFlagTypesTests: XCTestCase {

    // MARK: - FeatureFlagContext Tests

    func testContext_createsWithDefaults() {
        let context = FeatureFlagContext()
        XCTAssertNil(context.userId)
        XCTAssertNil(context.sessionId)
        XCTAssertEqual(context.platform, "iOS")
    }

    func testContext_createsWithCustomValues() {
        let context = FeatureFlagContext(
            userId: "user-123",
            sessionId: "session-456",
            appVersion: "1.0.0",
            platform: "iOS",
            properties: ["tier": "premium"]
        )

        XCTAssertEqual(context.userId, "user-123")
        XCTAssertEqual(context.sessionId, "session-456")
        XCTAssertEqual(context.appVersion, "1.0.0")
        XCTAssertEqual(context.properties["tier"], "premium")
    }

    func testContext_current_returnsContext() {
        let context = FeatureFlagContext.current()
        XCTAssertEqual(context.platform, "iOS")
    }

    func testContext_equatable() {
        let context1 = FeatureFlagContext(userId: "user-1")
        let context2 = FeatureFlagContext(userId: "user-1")
        let context3 = FeatureFlagContext(userId: "user-2")

        XCTAssertEqual(context1, context2)
        XCTAssertNotEqual(context1, context3)
    }

    // MARK: - FeatureFlagVariant Tests

    func testVariant_createsWithoutPayload() {
        let variant = FeatureFlagVariant(name: "control", enabled: true)
        XCTAssertEqual(variant.name, "control")
        XCTAssertTrue(variant.enabled)
        XCTAssertNil(variant.payload)
    }

    func testVariant_createsWithPayload() {
        let variant = FeatureFlagVariant(
            name: "treatment",
            enabled: true,
            payload: .number(42.0)
        )

        XCTAssertEqual(variant.name, "treatment")
        XCTAssertEqual(variant.payload?.numberValue, 42.0)
    }

    // MARK: - FeatureFlagPayload Tests

    func testPayload_stringValue() {
        let payload = FeatureFlagPayload.string("test-value")
        XCTAssertEqual(payload.stringValue, "test-value")
        XCTAssertNil(payload.numberValue)
        XCTAssertNil(payload.jsonValue)
    }

    func testPayload_numberValue() {
        let payload = FeatureFlagPayload.number(3.14)
        XCTAssertEqual(payload.numberValue, 3.14)
        XCTAssertNil(payload.stringValue)
        XCTAssertNil(payload.jsonValue)
    }

    func testPayload_jsonValue() {
        let payload = FeatureFlagPayload.json(["key": "value"])
        XCTAssertEqual(payload.jsonValue, ["key": "value"])
        XCTAssertNil(payload.stringValue)
        XCTAssertNil(payload.numberValue)
    }

    func testPayload_equatable() {
        let payload1 = FeatureFlagPayload.string("test")
        let payload2 = FeatureFlagPayload.string("test")
        let payload3 = FeatureFlagPayload.string("different")

        XCTAssertEqual(payload1, payload2)
        XCTAssertNotEqual(payload1, payload3)
    }

    func testPayload_encodeDecode() throws {
        let original = FeatureFlagPayload.string("test-value")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FeatureFlagPayload.self, from: encoded)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - FeatureFlagConfig Tests

    func testConfig_development_hasDefaults() {
        let config = FeatureFlagConfig.development
        XCTAssertEqual(config.proxyURL.absoluteString, "http://localhost:3063/proxy")
        XCTAssertEqual(config.appName, "UnaMentis-iOS-Dev")
        XCTAssertTrue(config.enableOfflineMode)
    }

    func testConfig_customValues() {
        let config = FeatureFlagConfig(
            proxyURL: URL(string: "http://test.com/proxy")!,
            clientKey: "custom-key",
            appName: "CustomApp",
            refreshInterval: 60.0,
            enableOfflineMode: false,
            enableMetrics: false
        )

        XCTAssertEqual(config.clientKey, "custom-key")
        XCTAssertEqual(config.refreshInterval, 60.0)
        XCTAssertFalse(config.enableOfflineMode)
        XCTAssertFalse(config.enableMetrics)
    }

    // MARK: - FeatureFlagError Tests

    func testError_networkError_hasDescription() {
        let error = FeatureFlagError.networkError("Connection timeout")
        XCTAssertTrue(error.errorDescription?.contains("timeout") ?? false)
    }

    func testError_unauthorized_hasDescription() {
        let error = FeatureFlagError.unauthorized
        XCTAssertTrue(error.errorDescription?.contains("Unauthorized") ?? false)
    }

    func testError_serverError_includesCode() {
        let error = FeatureFlagError.serverError(503)
        XCTAssertTrue(error.errorDescription?.contains("503") ?? false)
    }

    func testError_cacheError_hasDescription() {
        let error = FeatureFlagError.cacheError("Disk full")
        XCTAssertTrue(error.errorDescription?.contains("Disk full") ?? false)
    }

    // MARK: - FeatureFlagMetrics Tests

    func testMetrics_cacheHitRate_calculatesCorrectly() {
        let metrics = FeatureFlagMetrics(
            totalEvaluations: 100,
            cacheHits: 75,
            cacheMisses: 25,
            lastRefreshTime: Date(),
            flagCount: 10
        )

        XCTAssertEqual(metrics.cacheHitRate, 0.75, accuracy: 0.001)
    }

    func testMetrics_cacheHitRate_zeroWhenNoEvaluations() {
        let metrics = FeatureFlagMetrics(
            totalEvaluations: 0,
            cacheHits: 0,
            cacheMisses: 0,
            lastRefreshTime: nil,
            flagCount: 0
        )

        XCTAssertEqual(metrics.cacheHitRate, 0)
    }
}
