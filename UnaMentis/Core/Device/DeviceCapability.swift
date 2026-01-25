//
//  DeviceCapability.swift
//  UnaMentis
//
//  Device capability detection for tiered features
//  Determines support for embeddings and LLM validation
//

@preconcurrency import Darwin
import Foundation
import UIKit

// MARK: - Device Capability

/// Device capability detection for tiered validation features
enum DeviceCapability {
    // MARK: - Device Information

    /// Get the current device model identifier (e.g., "iPhone13,2")
    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    /// Extract model number from identifier (e.g., "iPhone13,2" -> 13)
    static var modelNumber: Int? {
        let identifier = modelIdentifier
        guard identifier.hasPrefix("iPhone") else { return nil }

        let numberString = identifier.dropFirst("iPhone".count)
            .split(separator: ",")
            .first
            .map(String.init) ?? ""

        return Int(numberString)
    }

    /// Get available physical memory in bytes
    static var physicalMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// Get available memory in MB
    static var availableMemoryMB: Int {
        let memory = physicalMemory
        return Int(memory / 1_000_000)
    }

    // MARK: - Tier Support

    /// Check if device supports Tier 2 (sentence embeddings)
    /// Requires iPhone XS+ (A12+) with 3GB+ RAM
    static func supportsEmbeddings() -> Bool {
        // Check device model
        guard let modelNum = modelNumber else {
            // Unknown device, assume not supported
            return false
        }

        // iPhone XS is iPhone11,x (released 2018)
        // Require iPhone 11 or newer
        guard modelNum >= 11 else {
            return false
        }

        // Check available memory (require 3GB+)
        guard availableMemoryMB >= 3000 else {
            return false
        }

        return true
    }

    /// Check if device supports Tier 3 (LLM validation)
    /// Requires iPhone 12+ (A14+) with 4GB+ RAM
    static func supportsLLMValidation() -> Bool {
        // Check device model
        guard let modelNum = modelNumber else {
            return false
        }

        // iPhone 12 is iPhone13,x (released 2020)
        // Require iPhone 12 (iPhone13,x) or newer
        guard modelNum >= 13 else {
            return false
        }

        // Check available memory (require 4GB+)
        guard availableMemoryMB >= 4000 else {
            return false
        }

        return true
    }

    /// Get the maximum supported validation tier for this device
    static var maxSupportedTier: Int {
        if supportsLLMValidation() {
            return 3
        } else if supportsEmbeddings() {
            return 2
        } else {
            return 1
        }
    }

    /// Get device description for user-facing messages
    static var deviceDescription: String {
        let model = modelIdentifier
        let memoryGB = Double(availableMemoryMB) / 1000.0
        let tier = maxSupportedTier

        return """
        Device: \(model)
        Memory: \(String(format: "%.1f", memoryGB)) GB
        Max Tier: \(tier) (Tier 1: All devices, Tier 2: Embeddings, Tier 3: LLM)
        """
    }
}

// MARK: - Memory Monitor

/// Monitor memory usage and pressure
actor MemoryMonitor {
    // MARK: - Memory Pressure

    /// Memory pressure levels
    enum MemoryPressure: Int, Comparable {
        case normal = 0
        case warning = 1
        case critical = 2

        static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Get current memory pressure level
    nonisolated func currentPressure() -> MemoryPressure {
        // Get memory statistics
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        // Capture task port locally to avoid Swift 6 concurrency warning
        // (mach_task_self_ is a process-global constant, safe to read)
        let taskSelf = mach_task_self_
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(taskSelf, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return .normal
        }

        let usedMemoryMB = Int(taskInfo.resident_size) / 1_000_000
        let totalMemoryMB = DeviceCapability.availableMemoryMB

        let percentUsed = Double(usedMemoryMB) / Double(totalMemoryMB)

        if percentUsed > 0.85 {
            return .critical
        } else if percentUsed > 0.70 {
            return .warning
        } else {
            return .normal
        }
    }

    /// Get available memory in MB
    nonisolated func availableMemoryMB() -> Int {
        DeviceCapability.availableMemoryMB
    }
}

// MARK: - Preview Support

#if DEBUG
extension DeviceCapability {
    /// Preview device info
    static var previewInfo: String {
        deviceDescription
    }
}
#endif
