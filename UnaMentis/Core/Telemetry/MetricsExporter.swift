// UnaMentis - Metrics Exporter
// ============================
//
// Exports latency and telemetry metrics to the management server
// in a unified format compatible with both iOS and web clients.
//
// UNIFIED METRIC FORMAT
// ---------------------
// This exporter uses the same metric schema as the web client,
// enabling cross-platform analytics and comparison:
//
// ```json
// {
//   "client": "ios",
//   "clientId": "device-uuid",
//   "sessionId": "session-uuid",
//   "timestamp": "2024-01-01T12:00:00Z",
//   "metrics": {
//     "stt_latency_ms": 150.0,
//     "llm_ttfb_ms": 200.0,
//     "llm_completion_ms": 800.0,
//     "tts_ttfb_ms": 100.0,
//     "tts_completion_ms": 400.0,
//     "e2e_latency_ms": 1250.0
//   },
//   "providers": {
//     "stt": "deepgram-nova3",
//     "llm": "anthropic/claude-3-5-haiku",
//     "tts": "chatterbox"
//   },
//   "resources": {
//     "cpu_percent": 45.2,
//     "memory_mb": 256.0,
//     "thermal_state": "nominal"
//   }
// }
// ```
//
// BATCHING & RELIABILITY
// ----------------------
// - Metrics are queued locally if network is unavailable
// - Batch uploads reduce network overhead
// - Automatic retry with exponential backoff
// - Queue persisted to disk for crash recovery
//
// SEE ALSO
// --------
// - MetricsUploadService.swift: Session metrics upload
// - TestResult.swift: Test result data model
// - server/management/latency_harness_api.py: Server endpoints

import Foundation
import Logging
#if os(iOS)
import UIKit
#endif

// MARK: - Unified Metric Payload

/// Unified metric payload compatible with web client format
public struct UnifiedMetricPayload: Codable, Sendable {
    public let client: String
    public let clientId: String
    public let clientName: String?
    public let sessionId: String
    public let timestamp: String
    public let metrics: MetricValues
    public let providers: ProviderInfo
    public let resources: ResourceInfo?
    public let networkProfile: String?
    public let networkProjections: [String: Double]?
    public let quality: QualityInfo?

    public init(
        client: String = "ios",
        clientId: String,
        clientName: String? = nil,
        sessionId: String,
        timestamp: Date = Date(),
        metrics: MetricValues,
        providers: ProviderInfo,
        resources: ResourceInfo? = nil,
        networkProfile: String? = nil,
        networkProjections: [String: Double]? = nil,
        quality: QualityInfo? = nil
    ) {
        self.client = client
        self.clientId = clientId
        self.clientName = clientName
        self.sessionId = sessionId
        self.timestamp = ISO8601DateFormatter().string(from: timestamp)
        self.metrics = metrics
        self.providers = providers
        self.resources = resources
        self.networkProfile = networkProfile
        self.networkProjections = networkProjections
        self.quality = quality
    }
}

/// Latency metric values
public struct MetricValues: Codable, Sendable {
    public let sttLatencyMs: Double?
    public let llmTtfbMs: Double
    public let llmCompletionMs: Double
    public let ttsTtfbMs: Double
    public let ttsCompletionMs: Double
    public let e2eLatencyMs: Double
    public let sttConfidence: Float?
    public let llmInputTokens: Int?
    public let llmOutputTokens: Int?
    public let ttsAudioDurationMs: Double?

    enum CodingKeys: String, CodingKey {
        case sttLatencyMs = "stt_latency_ms"
        case llmTtfbMs = "llm_ttfb_ms"
        case llmCompletionMs = "llm_completion_ms"
        case ttsTtfbMs = "tts_ttfb_ms"
        case ttsCompletionMs = "tts_completion_ms"
        case e2eLatencyMs = "e2e_latency_ms"
        case sttConfidence = "stt_confidence"
        case llmInputTokens = "llm_input_tokens"
        case llmOutputTokens = "llm_output_tokens"
        case ttsAudioDurationMs = "tts_audio_duration_ms"
    }

    public init(
        sttLatencyMs: Double? = nil,
        llmTtfbMs: Double,
        llmCompletionMs: Double,
        ttsTtfbMs: Double,
        ttsCompletionMs: Double,
        e2eLatencyMs: Double,
        sttConfidence: Float? = nil,
        llmInputTokens: Int? = nil,
        llmOutputTokens: Int? = nil,
        ttsAudioDurationMs: Double? = nil
    ) {
        self.sttLatencyMs = sttLatencyMs
        self.llmTtfbMs = llmTtfbMs
        self.llmCompletionMs = llmCompletionMs
        self.ttsTtfbMs = ttsTtfbMs
        self.ttsCompletionMs = ttsCompletionMs
        self.e2eLatencyMs = e2eLatencyMs
        self.sttConfidence = sttConfidence
        self.llmInputTokens = llmInputTokens
        self.llmOutputTokens = llmOutputTokens
        self.ttsAudioDurationMs = ttsAudioDurationMs
    }
}

/// Provider configuration info
public struct ProviderInfo: Codable, Sendable {
    public let stt: String
    public let llm: String
    public let llmModel: String
    public let tts: String
    public let ttsVoice: String?

    enum CodingKeys: String, CodingKey {
        case stt
        case llm
        case llmModel = "llm_model"
        case tts
        case ttsVoice = "tts_voice"
    }

    public init(
        stt: String,
        llm: String,
        llmModel: String,
        tts: String,
        ttsVoice: String? = nil
    ) {
        self.stt = stt
        self.llm = llm
        self.llmModel = llmModel
        self.tts = tts
        self.ttsVoice = ttsVoice
    }
}

/// Resource utilization info
public struct ResourceInfo: Codable, Sendable {
    public let cpuPercent: Double
    public let memoryMb: Double
    public let thermalState: String
    public let batteryLevel: Float?
    public let batteryState: String?

    enum CodingKeys: String, CodingKey {
        case cpuPercent = "cpu_percent"
        case memoryMb = "memory_mb"
        case thermalState = "thermal_state"
        case batteryLevel = "battery_level"
        case batteryState = "battery_state"
    }

    public init(
        cpuPercent: Double,
        memoryMb: Double,
        thermalState: String,
        batteryLevel: Float? = nil,
        batteryState: String? = nil
    ) {
        self.cpuPercent = cpuPercent
        self.memoryMb = memoryMb
        self.thermalState = thermalState
        self.batteryLevel = batteryLevel
        self.batteryState = batteryState
    }
}

/// Quality metrics info
public struct QualityInfo: Codable, Sendable {
    public let success: Bool
    public let errors: [String]?
    public let scenarioName: String?
    public let repetition: Int?

    public init(
        success: Bool,
        errors: [String]? = nil,
        scenarioName: String? = nil,
        repetition: Int? = nil
    ) {
        self.success = success
        self.errors = errors
        self.scenarioName = scenarioName
        self.repetition = repetition
    }
}

// MARK: - Metrics Exporter Actor

/// Exports metrics to the management server
///
/// Features:
/// - Unified format compatible with web client
/// - Automatic batching for efficiency
/// - Offline queue with disk persistence
/// - Retry with exponential backoff
public actor MetricsExporter {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.metrics-exporter")
    private var serverURL: URL?
    private var clientId: String
    private var clientName: String
    private var isExporting = false

    // Queue for offline storage
    private var pendingPayloads: [UnifiedMetricPayload] = []
    private let maxQueueSize = 1000

    // Batch settings
    private let batchSize = 50
    private var batchTimer: Task<Void, Never>?

    // MARK: - Initialization

    public init() {
        // Get or generate client ID
        if let stored = UserDefaults.standard.string(forKey: "MetricsExporterClientId") {
            self.clientId = stored
        } else {
            self.clientId = UUID().uuidString
            UserDefaults.standard.set(self.clientId, forKey: "MetricsExporterClientId")
        }
        self.clientName = UserDefaults.standard.string(forKey: "MetricsExporterClientName")
            ?? "UnaMentis iOS"

        // Load persisted queue
        loadPersistedQueue()
    }

    // MARK: - Configuration

    /// Configure server connection
    public func configure(serverHost: String, port: Int = 8766) {
        self.serverURL = URL(string: "http://\(serverHost):\(port)/api/metrics/ingest")
        logger.info("MetricsExporter configured: \(serverHost):\(port)")

        // Start batch timer
        startBatchTimer()

        // Try to drain any pending items
        Task {
            await drainQueue()
        }
    }

    /// Update device info (call from MainActor)
    @MainActor
    public func updateDeviceInfo() async {
        #if os(iOS)
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let deviceName = UIDevice.current.name
        UserDefaults.standard.set(deviceId, forKey: "MetricsExporterClientId")
        UserDefaults.standard.set(deviceName, forKey: "MetricsExporterClientName")
        await setDeviceInfo(id: deviceId, name: deviceName)
        #endif
    }

    private func setDeviceInfo(id: String, name: String) {
        self.clientId = id
        self.clientName = name
    }

    // MARK: - Export Methods

    /// Export a single test result
    public func export(_ result: TestResult) async {
        let payload = createPayload(from: result)
        await enqueue(payload)
    }

    /// Export multiple test results
    public func exportBatch(_ results: [TestResult]) async {
        for result in results {
            let payload = createPayload(from: result)
            await enqueue(payload)
        }
    }

    /// Export a raw metric payload
    public func exportRaw(_ payload: UnifiedMetricPayload) async {
        await enqueue(payload)
    }

    // MARK: - Queue Management

    private func enqueue(_ payload: UnifiedMetricPayload) async {
        // Respect queue size limit
        if pendingPayloads.count >= maxQueueSize {
            pendingPayloads.removeFirst()
            logger.warning("Queue full, dropping oldest metric")
        }

        pendingPayloads.append(payload)

        // If we have enough for a batch, send immediately
        if pendingPayloads.count >= batchSize {
            await drainQueue()
        }
    }

    /// Attempt to send all queued metrics
    public func drainQueue() async {
        guard let serverURL = serverURL else {
            logger.debug("Cannot drain queue: server not configured")
            return
        }

        guard !isExporting else {
            logger.debug("Already exporting, skipping")
            return
        }

        guard !pendingPayloads.isEmpty else {
            return
        }

        isExporting = true
        defer { isExporting = false }

        // Take a batch
        let batch = Array(pendingPayloads.prefix(batchSize))
        logger.info("Exporting batch of \(batch.count) metrics")

        do {
            try await sendBatch(batch, to: serverURL)

            // Remove sent items
            pendingPayloads.removeFirst(min(batch.count, pendingPayloads.count))
            persistQueue()

            logger.info("Successfully exported \(batch.count) metrics")

        } catch {
            logger.error("Failed to export metrics: \(error.localizedDescription)")
            // Keep in queue for retry
        }
    }

    // MARK: - Network

    private func sendBatch(_ batch: [UnifiedMetricPayload], to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let body: [String: Any] = [
            "client": "ios",
            "clientId": clientId,
            "clientName": clientName,
            "batchSize": batch.count,
            "metrics": try batch.map { payload in
                try JSONSerialization.jsonObject(with: encoder.encode(payload))
            }
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientId, forHTTPHeaderField: "X-Client-ID")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetricsExporterError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MetricsExporterError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Persistence

    private var queueFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("metrics_queue.json")
    }

    private func persistQueue() {
        do {
            let data = try JSONEncoder().encode(pendingPayloads)
            try data.write(to: queueFileURL)
        } catch {
            logger.error("Failed to persist queue: \(error.localizedDescription)")
        }
    }

    private func loadPersistedQueue() {
        guard FileManager.default.fileExists(atPath: queueFileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: queueFileURL)
            pendingPayloads = try JSONDecoder().decode([UnifiedMetricPayload].self, from: data)
            logger.info("Loaded \(pendingPayloads.count) persisted metrics")
        } catch {
            logger.error("Failed to load persisted queue: \(error.localizedDescription)")
        }
    }

    // MARK: - Batch Timer

    private func startBatchTimer() {
        batchTimer?.cancel()
        batchTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                await drainQueue()
            }
        }
    }

    // MARK: - Payload Creation

    private func createPayload(from result: TestResult) -> UnifiedMetricPayload {
        UnifiedMetricPayload(
            client: "ios",
            clientId: clientId,
            clientName: clientName,
            sessionId: result.configId,
            timestamp: result.timestamp,
            metrics: MetricValues(
                sttLatencyMs: result.sttLatencyMs,
                llmTtfbMs: result.llmTTFBMs,
                llmCompletionMs: result.llmCompletionMs,
                ttsTtfbMs: result.ttsTTFBMs,
                ttsCompletionMs: result.ttsCompletionMs,
                e2eLatencyMs: result.e2eLatencyMs,
                sttConfidence: result.sttConfidence,
                llmInputTokens: result.llmInputTokens,
                llmOutputTokens: result.llmOutputTokens,
                ttsAudioDurationMs: result.ttsAudioDurationMs
            ),
            providers: ProviderInfo(
                stt: result.sttConfig.provider.identifier,
                llm: result.llmConfig.provider.identifier,
                llmModel: result.llmConfig.model,
                tts: result.ttsConfig.provider.identifier,
                ttsVoice: result.ttsConfig.voice
            ),
            resources: ResourceInfo(
                cpuPercent: result.peakCPUPercent,
                memoryMb: result.peakMemoryMB,
                thermalState: result.thermalState
            ),
            networkProfile: result.networkProfile.rawValue,
            networkProjections: result.networkProjections,
            quality: QualityInfo(
                success: result.isSuccess,
                errors: result.errors.isEmpty ? nil : result.errors,
                scenarioName: result.scenarioName,
                repetition: result.repetition
            )
        )
    }

    // MARK: - Status

    /// Get current queue size
    public var queueSize: Int {
        pendingPayloads.count
    }

    /// Check if configured
    public var isConfigured: Bool {
        serverURL != nil
    }
}

// MARK: - Errors

public enum MetricsExporterError: Error, LocalizedError {
    case notConfigured
    case invalidResponse
    case serverError(statusCode: Int)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MetricsExporter not configured"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code):
            return "Server error: HTTP \(code)"
        case .encodingFailed:
            return "Failed to encode metrics"
        }
    }
}

// MARK: - Provider Identifier Extensions

extension STTProvider {
    /// Identifier string for the unified format
    public var identifier: String {
        switch self {
        case .deepgramNova3:
            return "deepgram-nova3"
        case .assemblyAI:
            return "assemblyai"
        case .openAIWhisper:
            return "openai-whisper"
        case .groqWhisper:
            return "groq-whisper"
        case .appleSpeech:
            return "apple-speech"
        case .glmASRNano:
            return "glm-asr-nano"
        case .glmASROnDevice:
            return "glm-asr-ondevice"
        }
    }
}

extension LLMProvider {
    /// Identifier string for the unified format
    public var identifier: String {
        switch self {
        case .anthropic:
            return "anthropic"
        case .openAI:
            return "openai"
        case .selfHosted:
            return "selfhosted"
        case .localMLX:
            return "local-mlx"
        }
    }
}

extension TTSProvider {
    /// Identifier string for the unified format
    public var identifier: String {
        switch self {
        case .chatterbox:
            return "chatterbox"
        case .elevenLabsFlash:
            return "elevenlabs-flash"
        case .elevenLabsTurbo:
            return "elevenlabs-turbo"
        case .deepgramAura2:
            return "deepgram-aura2"
        case .appleTTS:
            return "apple-tts"
        case .selfHosted:
            return "selfhosted"
        case .vibeVoice:
            return "vibevoice"
        case .playHT:
            return "playht"
        }
    }
}
