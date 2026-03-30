//
//  OnDeviceLLMModelManagerTests.swift
//  UnaMentisTests
//
//  Unit tests for OnDeviceLLMModelManager
//

import XCTest
@testable import UnaMentis

/// Unit tests for OnDeviceLLMModelManager
///
/// Tests model configuration, state management, and file operations.
/// Note: Network download tests are skipped in CI to avoid hitting Hugging Face CDN.
final class OnDeviceLLMModelManagerTests: XCTestCase {

    // MARK: - Model Configuration Tests (Falcon-H1 1.5B Deep)

    func testFalconH1ConfigHasCorrectValues() {
        let config = OnDeviceLLMModel.falconH1_1_5B.config

        XCTAssertEqual(config.id, "falcon-h1-1.5b-deep-instruct-q4_k_m")
        XCTAssertEqual(config.displayName, "Falcon-H1 1.5B Deep")
        XCTAssertEqual(config.huggingFaceRepo, "tiiuae/Falcon-H1-1.5B-Deep-Instruct-GGUF")
        XCTAssertEqual(config.filename, "Falcon-H1-1.5B-Deep-Instruct-Q4_K_M.gguf")
        XCTAssertEqual(config.quantization, "Q4_K_M")
        XCTAssertEqual(config.contextSize, 8192)
        XCTAssertEqual(config.minimumRAMGB, 3)
        XCTAssertEqual(config.chatFormat, .chatML)
        XCTAssertEqual(config.publisher, "TII (UAE)")
        XCTAssertEqual(config.license, "Apache 2.0")
        XCTAssertLessThan(config.expectedSizeBytes, 1_000_000_000) // Under 1 GB
        XCTAssertGreaterThan(config.expectedSizeBytes, 900_000_000)
    }

    func testFalconH1ConfigDownloadURL() {
        let config = OnDeviceLLMModel.falconH1_1_5B.config
        let expectedURL = "https://huggingface.co/tiiuae/Falcon-H1-1.5B-Deep-Instruct-GGUF/resolve/main/Falcon-H1-1.5B-Deep-Instruct-Q4_K_M.gguf"

        XCTAssertEqual(config.downloadURL.absoluteString, expectedURL)
    }

    // MARK: - Model Configuration Tests (Qwen3.5 2B)

    func testQwen35ConfigHasCorrectValues() {
        let config = OnDeviceLLMModel.qwen35_2B.config

        XCTAssertEqual(config.id, "qwen3.5-2b-q4_k_m")
        XCTAssertEqual(config.displayName, "Qwen3.5 2B")
        XCTAssertEqual(config.huggingFaceRepo, "unsloth/Qwen3.5-2B-GGUF")
        XCTAssertEqual(config.filename, "Qwen3.5-2B-Q4_K_M.gguf")
        XCTAssertEqual(config.quantization, "Q4_K_M")
        XCTAssertEqual(config.contextSize, 32768)
        XCTAssertEqual(config.minimumRAMGB, 3)
        XCTAssertEqual(config.chatFormat, .chatML)
        XCTAssertEqual(config.publisher, "Alibaba (Qwen)")
        XCTAssertEqual(config.license, "Apache 2.0")
        XCTAssertGreaterThan(config.expectedSizeBytes, 1_200_000_000)
        XCTAssertLessThan(config.expectedSizeBytes, 1_400_000_000)
    }

    func testQwen35ConfigDownloadURL() {
        let config = OnDeviceLLMModel.qwen35_2B.config
        let expectedURL = "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf"

        XCTAssertEqual(config.downloadURL.absoluteString, expectedURL)
    }

    // MARK: - Model Configuration Tests (Ministral 3 3B)

    func testMinistralConfigHasCorrectValues() {
        let config = OnDeviceLLMModel.ministral3_3B.config

        XCTAssertEqual(config.id, "ministral-3-3b-instruct-2512")
        XCTAssertEqual(config.displayName, "Ministral 3 3B")
        XCTAssertEqual(config.huggingFaceRepo, "mistralai/Ministral-3-3B-Instruct-2512-GGUF")
        XCTAssertEqual(config.filename, "Ministral-3-3B-Instruct-2512-Q4_K_M.gguf")
        XCTAssertEqual(config.quantization, "Q4_K_M")
        XCTAssertEqual(config.contextSize, 4096)
        XCTAssertEqual(config.minimumRAMGB, 4)
        XCTAssertEqual(config.chatFormat, .mistral)
        XCTAssertEqual(config.publisher, "Mistral AI")
        XCTAssertEqual(config.license, "Apache 2.0")
        XCTAssertGreaterThan(config.expectedSizeBytes, 2_000_000_000) // > 2GB
    }

    func testMinistralConfigDownloadURL() {
        let config = OnDeviceLLMModel.ministral3_3B.config
        let expectedURL = "https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf"

        XCTAssertEqual(config.downloadURL.absoluteString, expectedURL)
    }

    func testMinistralConfigExpectedSizeMB() {
        let config = OnDeviceLLMModel.ministral3_3B.config
        XCTAssertEqual(config.expectedSizeMB, 2150)
    }

    // MARK: - Model Configuration Tests (Qwen3 1.7B)

    func testQwen3ConfigHasCorrectValues() {
        let config = OnDeviceLLMModel.qwen3_1_7B.config

        XCTAssertEqual(config.id, "qwen3-1.7b-q4_k_m")
        XCTAssertEqual(config.displayName, "Qwen3 1.7B")
        XCTAssertEqual(config.huggingFaceRepo, "unsloth/Qwen3-1.7B-GGUF")
        XCTAssertEqual(config.filename, "Qwen3-1.7B-Q4_K_M.gguf")
        XCTAssertEqual(config.quantization, "Q4_K_M")
        XCTAssertEqual(config.contextSize, 32768)
        XCTAssertEqual(config.minimumRAMGB, 3)
        XCTAssertEqual(config.chatFormat, .chatML)
        XCTAssertEqual(config.publisher, "Alibaba (Qwen)")
        XCTAssertEqual(config.license, "Apache 2.0")
        XCTAssertGreaterThan(config.expectedSizeBytes, 1_000_000_000) // > 1GB
        XCTAssertLessThan(config.expectedSizeBytes, 1_500_000_000)    // < 1.5GB
    }

    func testQwen3ConfigDownloadURL() {
        let config = OnDeviceLLMModel.qwen3_1_7B.config
        let expectedURL = "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"

        XCTAssertEqual(config.downloadURL.absoluteString, expectedURL)
    }

    // MARK: - Model Configuration Tests (SmolLM3 3B)

    func testSmolLM3ConfigHasCorrectValues() {
        let config = OnDeviceLLMModel.smolLM3_3B.config

        XCTAssertEqual(config.id, "smollm3-3b-q4_k_m")
        XCTAssertEqual(config.displayName, "SmolLM3 3B")
        XCTAssertEqual(config.huggingFaceRepo, "ggml-org/SmolLM3-3B-GGUF")
        XCTAssertEqual(config.filename, "SmolLM3-Q4_K_M.gguf")
        XCTAssertEqual(config.quantization, "Q4_K_M")
        XCTAssertEqual(config.contextSize, 32768)
        XCTAssertEqual(config.minimumRAMGB, 4)
        XCTAssertEqual(config.chatFormat, .chatML)
        XCTAssertEqual(config.publisher, "Hugging Face")
        XCTAssertEqual(config.license, "Apache 2.0")
        XCTAssertGreaterThan(config.expectedSizeBytes, 1_500_000_000) // > 1.5GB
        XCTAssertLessThan(config.expectedSizeBytes, 2_500_000_000)    // < 2.5GB
    }

    func testSmolLM3ConfigDownloadURL() {
        let config = OnDeviceLLMModel.smolLM3_3B.config
        let expectedURL = "https://huggingface.co/ggml-org/SmolLM3-3B-GGUF/resolve/main/SmolLM3-Q4_K_M.gguf"

        XCTAssertEqual(config.downloadURL.absoluteString, expectedURL)
    }

    // MARK: - Default Model Tests

    func testDefaultModelIsFalconH1() {
        XCTAssertEqual(OnDeviceLLMModel.defaultModel, .falconH1_1_5B)
    }

    func testRecommendedModelFlag() {
        XCTAssertTrue(OnDeviceLLMModel.falconH1_1_5B.isRecommended)
        XCTAssertFalse(OnDeviceLLMModel.qwen35_2B.isRecommended)
        XCTAssertFalse(OnDeviceLLMModel.qwen3_1_7B.isRecommended)
        XCTAssertFalse(OnDeviceLLMModel.smolLM3_3B.isRecommended)
        XCTAssertFalse(OnDeviceLLMModel.ministral3_3B.isRecommended)
    }

    // MARK: - Chat Format Tests

    func testChatFormatAssignment() {
        XCTAssertEqual(OnDeviceLLMModel.falconH1_1_5B.config.chatFormat, .chatML)
        XCTAssertEqual(OnDeviceLLMModel.qwen35_2B.config.chatFormat, .chatML)
        XCTAssertEqual(OnDeviceLLMModel.qwen3_1_7B.config.chatFormat, .chatML)
        XCTAssertEqual(OnDeviceLLMModel.smolLM3_3B.config.chatFormat, .chatML)
        XCTAssertEqual(OnDeviceLLMModel.ministral3_3B.config.chatFormat, .mistral)
    }

    // MARK: - Config Helpers Tests

    func testExpectedSizeFormatted() {
        // Qwen3 at ~1.11 GB should show as "1.1 GB"
        let qwenFormatted = OnDeviceLLMModel.qwen3_1_7B.config.expectedSizeFormatted
        XCTAssertTrue(qwenFormatted.contains("GB"), "Qwen3 should show size in GB: \(qwenFormatted)")

        // Ministral at ~2.15 GB should show as "2.2 GB"
        let ministralFormatted = OnDeviceLLMModel.ministral3_3B.config.expectedSizeFormatted
        XCTAssertTrue(ministralFormatted.contains("GB"), "Ministral should show size in GB: \(ministralFormatted)")
    }

    // MARK: - Model State Tests

    func testModelStateEquality() {
        // Same states should be equal
        XCTAssertEqual(OnDeviceLLMModelManager.ModelState.notDownloaded, .notDownloaded)
        XCTAssertEqual(OnDeviceLLMModelManager.ModelState.available, .available)
        XCTAssertEqual(OnDeviceLLMModelManager.ModelState.loaded, .loaded)
        XCTAssertEqual(OnDeviceLLMModelManager.ModelState.verifying, .verifying)

        // Progress states with same progress
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.downloading(0.5),
            .downloading(0.5)
        )
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.loading(0.75),
            .loading(0.75)
        )

        // Progress states with similar progress (within tolerance)
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.downloading(0.501),
            .downloading(0.505)
        )

        // Error states with same message
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.error("test error"),
            .error("test error")
        )
    }

    func testModelStateInequality() {
        // Different states should not be equal
        XCTAssertNotEqual(
            OnDeviceLLMModelManager.ModelState.notDownloaded,
            .available
        )
        XCTAssertNotEqual(
            OnDeviceLLMModelManager.ModelState.downloading(0.5),
            .downloading(0.8)
        )
        XCTAssertNotEqual(
            OnDeviceLLMModelManager.ModelState.error("error1"),
            .error("error2")
        )
    }

    func testModelStateIsReady() {
        XCTAssertTrue(OnDeviceLLMModelManager.ModelState.loaded.isReady)
        XCTAssertFalse(OnDeviceLLMModelManager.ModelState.available.isReady)
        XCTAssertFalse(OnDeviceLLMModelManager.ModelState.notDownloaded.isReady)
        XCTAssertFalse(OnDeviceLLMModelManager.ModelState.downloading(0.5).isReady)
    }

    func testModelStateIsAvailable() {
        XCTAssertTrue(OnDeviceLLMModelManager.ModelState.available.isAvailable)
        XCTAssertTrue(OnDeviceLLMModelManager.ModelState.loaded.isAvailable)
        XCTAssertFalse(OnDeviceLLMModelManager.ModelState.notDownloaded.isAvailable)
        XCTAssertFalse(OnDeviceLLMModelManager.ModelState.downloading(0.5).isAvailable)
    }

    func testModelStateDisplayText() {
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.notDownloaded.displayText,
            "Not Downloaded"
        )
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.downloading(0.5).displayText,
            "Downloading 50%"
        )
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.verifying.displayText,
            "Verifying..."
        )
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.available.displayText,
            "Ready to Load"
        )
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.loading(0.25).displayText,
            "Loading 25%"
        )
        XCTAssertEqual(
            OnDeviceLLMModelManager.ModelState.loaded.displayText,
            "Loaded"
        )
        XCTAssertTrue(
            OnDeviceLLMModelManager.ModelState.error("Network error").displayText.contains("Network error")
        )
    }

    // MARK: - Keep Model Reasons / Deletion Consequences

    func testKeepModelReasons() {
        XCTAssertFalse(OnDeviceLLMModelConfig.keepModelReasons.isEmpty)
        XCTAssertGreaterThanOrEqual(OnDeviceLLMModelConfig.keepModelReasons.count, 3)

        // Should mention offline capability
        let hasOfflineReason = OnDeviceLLMModelConfig.keepModelReasons.contains {
            $0.lowercased().contains("offline")
        }
        XCTAssertTrue(hasOfflineReason, "Should mention offline capability")

        // Should mention privacy
        let hasPrivacyReason = OnDeviceLLMModelConfig.keepModelReasons.contains {
            $0.lowercased().contains("private") || $0.lowercased().contains("privacy")
        }
        XCTAssertTrue(hasPrivacyReason, "Should mention privacy")
    }

    func testDeletionConsequences() {
        XCTAssertFalse(OnDeviceLLMModelConfig.deletionConsequences.isEmpty)
        XCTAssertGreaterThanOrEqual(OnDeviceLLMModelConfig.deletionConsequences.count, 3)

        // Should mention re-download option
        let hasRedownloadInfo = OnDeviceLLMModelConfig.deletionConsequences.contains {
            $0.lowercased().contains("re-download") || $0.lowercased().contains("download")
        }
        XCTAssertTrue(hasRedownloadInfo, "Should mention re-download option")
    }

    // MARK: - Model Error Tests

    func testModelErrorDescriptions() {
        XCTAssertNotNil(OnDeviceLLMModelError.modelNotDownloaded.errorDescription)
        XCTAssertTrue(
            OnDeviceLLMModelError.modelNotDownloaded.errorDescription!.contains("not downloaded")
        )

        XCTAssertNotNil(OnDeviceLLMModelError.downloadFailed("test").errorDescription)
        XCTAssertTrue(
            OnDeviceLLMModelError.downloadFailed("network").errorDescription!.contains("network")
        )

        XCTAssertNotNil(OnDeviceLLMModelError.deleteFailed("permission").errorDescription)
        XCTAssertTrue(
            OnDeviceLLMModelError.deleteFailed("permission").errorDescription!.contains("permission")
        )

        XCTAssertNotNil(OnDeviceLLMModelError.insufficientStorage.errorDescription)
        XCTAssertTrue(
            OnDeviceLLMModelError.insufficientStorage.errorDescription!.contains("storage")
        )

        XCTAssertNotNil(OnDeviceLLMModelError.insufficientRAM.errorDescription)
        XCTAssertTrue(
            OnDeviceLLMModelError.insufficientRAM.errorDescription!.contains("RAM")
        )

        XCTAssertNotNil(OnDeviceLLMModelError.networkUnavailable.errorDescription)
        XCTAssertTrue(
            OnDeviceLLMModelError.networkUnavailable.errorDescription!.contains("Network")
        )
    }

    // MARK: - Manager Tests

    func testManagerInitialState() async {
        let manager = OnDeviceLLMModelManager()

        // Give it time to check model availability
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let state = await manager.currentState()

        // Should be notDownloaded since model isn't bundled in tests
        // or available if model was previously downloaded
        XCTAssertTrue(
            state == .notDownloaded || state == .available,
            "Initial state should be notDownloaded or available"
        )
    }

    func testManagerModelPath() async {
        let manager = OnDeviceLLMModelManager()
        let path = await manager.modelPath

        XCTAssertTrue(path.path.contains("models/LLM"))
        // Path should contain the selected model's filename
        let selectedModel = await manager.selectedModel
        XCTAssertTrue(path.path.contains(selectedModel.config.filename))
    }

    func testManagerModelPathForSpecificModel() async {
        let manager = OnDeviceLLMModelManager()

        let falconPath = await manager.modelPath(for: .falconH1_1_5B)
        XCTAssertTrue(falconPath.path.contains("Falcon-H1-1.5B-Deep-Instruct-Q4_K_M.gguf"))

        let qwen35Path = await manager.modelPath(for: .qwen35_2B)
        XCTAssertTrue(qwen35Path.path.contains("Qwen3.5-2B-Q4_K_M.gguf"))

        let qwenPath = await manager.modelPath(for: .qwen3_1_7B)
        XCTAssertTrue(qwenPath.path.contains("Qwen3-1.7B-Q4_K_M.gguf"))

        let smolPath = await manager.modelPath(for: .smolLM3_3B)
        XCTAssertTrue(smolPath.path.contains("SmolLM3-Q4_K_M.gguf"))

        let ministralPath = await manager.modelPath(for: .ministral3_3B)
        XCTAssertTrue(ministralPath.path.contains("Ministral-3-3B-Instruct-2512-Q4_K_M.gguf"))
    }

    func testManagerPerModelState() async {
        let manager = OnDeviceLLMModelManager()

        // Give it time to initialize
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Each model should have its own state
        for model in OnDeviceLLMModel.allCases {
            let state = await manager.state(for: model)
            XCTAssertTrue(
                state == .notDownloaded || state == .available,
                "\(model.config.displayName) should be notDownloaded or available"
            )
        }
    }

    func testManagerAllModelStates() async {
        let manager = OnDeviceLLMModelManager()

        try? await Task.sleep(nanoseconds: 100_000_000)

        let states = await manager.allModelStates()
        XCTAssertEqual(states.count, OnDeviceLLMModel.allCases.count)

        for model in OnDeviceLLMModel.allCases {
            XCTAssertNotNil(states[model], "Should have state for \(model.config.displayName)")
        }
    }

    func testManagerSelectModel() async {
        let manager = OnDeviceLLMModelManager()

        await manager.selectModel(.smolLM3_3B)
        let selected = await manager.selectedModel
        XCTAssertEqual(selected, .smolLM3_3B)

        await manager.selectModel(.qwen3_1_7B)
        let selected2 = await manager.selectedModel
        XCTAssertEqual(selected2, .qwen3_1_7B)
    }

    func testManagerMarkLoadedAndUnloaded() async {
        let manager = OnDeviceLLMModelManager()

        // Mark as loaded
        await manager.markLoaded()
        var state = await manager.currentState()
        XCTAssertEqual(state, .loaded)

        // Mark as unloaded
        await manager.markUnloaded()
        state = await manager.currentState()
        // Should be available or notDownloaded depending on file existence
        XCTAssertTrue(
            state == .available || state == .notDownloaded,
            "After unload, state should be available or notDownloaded"
        )
    }

    func testManagerCancelDownload() async {
        let manager = OnDeviceLLMModelManager()

        // Cancel when not downloading should be safe
        await manager.cancelDownload()

        let state = await manager.currentState()
        XCTAssertEqual(state, .notDownloaded)
    }

    func testManagerCancelDownloadForSpecificModel() async {
        let manager = OnDeviceLLMModelManager()

        // Cancel for a specific model when not downloading should be safe
        await manager.cancelDownload(for: .smolLM3_3B)

        let state = await manager.state(for: .smolLM3_3B)
        XCTAssertEqual(state, .notDownloaded)
    }

    // MARK: - State Observer Tests

    @MainActor
    func testStateObserverInitialization() async {
        let manager = OnDeviceLLMModelManager()
        let observer = OnDeviceLLMModelStateObserver(manager: manager)

        // Give it time to refresh
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // State should be synced with manager
        let managerState = await manager.currentState()

        // Compare states
        XCTAssertEqual(observer.state, managerState)
    }

    @MainActor
    func testStateObserverRefresh() async {
        let manager = OnDeviceLLMModelManager()
        let observer = OnDeviceLLMModelStateObserver(manager: manager)

        await observer.refreshState()

        let managerState = await manager.currentState()
        XCTAssertEqual(observer.state, managerState)
    }

    @MainActor
    func testStateObserverAllStates() async {
        let manager = OnDeviceLLMModelManager()
        let observer = OnDeviceLLMModelStateObserver(manager: manager)

        await observer.refreshState()

        XCTAssertEqual(observer.allStates.count, OnDeviceLLMModel.allCases.count)
    }

    // MARK: - All Models Enumeration

    func testAllModelsAvailable() {
        let allModels = OnDeviceLLMModel.allCases

        XCTAssertEqual(allModels.count, 5, "Should have 5 on-device models")
        XCTAssertTrue(allModels.contains(.falconH1_1_5B))
        XCTAssertTrue(allModels.contains(.qwen35_2B))
        XCTAssertTrue(allModels.contains(.qwen3_1_7B))
        XCTAssertTrue(allModels.contains(.smolLM3_3B))
        XCTAssertTrue(allModels.contains(.ministral3_3B))
    }

    func testModelRawValues() {
        XCTAssertEqual(OnDeviceLLMModel.falconH1_1_5B.rawValue, "falcon-h1-1.5b")
        XCTAssertEqual(OnDeviceLLMModel.qwen35_2B.rawValue, "qwen3.5-2b")
        XCTAssertEqual(OnDeviceLLMModel.qwen3_1_7B.rawValue, "qwen3-1.7b")
        XCTAssertEqual(OnDeviceLLMModel.smolLM3_3B.rawValue, "smollm3-3b")
        XCTAssertEqual(OnDeviceLLMModel.ministral3_3B.rawValue, "ministral-3-3b")
    }

    // MARK: - All Models Have Valid Configs

    func testAllModelsHaveValidConfigs() {
        for model in OnDeviceLLMModel.allCases {
            let config = model.config

            XCTAssertFalse(config.id.isEmpty, "\(model) should have a non-empty id")
            XCTAssertFalse(config.displayName.isEmpty, "\(model) should have a display name")
            XCTAssertFalse(config.huggingFaceRepo.isEmpty, "\(model) should have a HF repo")
            XCTAssertFalse(config.filename.isEmpty, "\(model) should have a filename")
            XCTAssertTrue(config.filename.hasSuffix(".gguf"), "\(model) filename should end in .gguf")
            XCTAssertGreaterThan(config.expectedSizeBytes, 0, "\(model) should have a positive expected size")
            XCTAssertEqual(config.quantization, "Q4_K_M", "\(model) should use Q4_K_M quantization")
            XCTAssertGreaterThan(config.contextSize, 0, "\(model) should have a positive context size")
            XCTAssertGreaterThan(config.minimumRAMGB, 0, "\(model) should have a positive RAM requirement")
            XCTAssertFalse(config.description.isEmpty, "\(model) should have a description")
            XCTAssertFalse(config.publisher.isEmpty, "\(model) should have a publisher")
            XCTAssertEqual(config.license, "Apache 2.0", "\(model) should be Apache 2.0 licensed")
            XCTAssertFalse(config.version.isEmpty, "\(model) should have a version")

            // Download URL should be valid
            XCTAssertTrue(
                config.downloadURL.absoluteString.hasPrefix("https://huggingface.co/"),
                "\(model) download URL should point to HuggingFace"
            )
            XCTAssertTrue(
                config.downloadURL.absoluteString.contains(config.filename),
                "\(model) download URL should contain the filename"
            )
        }
    }
}
