// UnaMentis - Routing Condition
// Defines conditions for auto-routing rules in the Patch Panel
//
// Part of Core/Routing (Patch Panel Architecture)
//
// Conditions are used in auto-routing rules to dynamically adjust
// routing based on runtime state (thermal, memory, network, budget, etc.)

import Foundation

// MARK: - Routing Condition

/// Conditions that can trigger auto-routing rules
///
/// Each condition evaluates a specific aspect of the current runtime
/// context and returns true/false. Conditions are combined in rules
/// using AND/OR logic.
public enum RoutingCondition: Codable, Sendable {

    // MARK: - Device Conditions

    /// Thermal state of the device
    case thermalState(ThermalStateCondition)

    /// Memory pressure level
    case memoryPressure(MemoryPressureCondition)

    /// Battery level comparison
    case batteryLevel(ComparisonCondition)

    /// Device capability tier
    case deviceTier(DeviceCapabilityTier)

    // MARK: - Network Conditions

    /// Network connection type
    case networkType(NetworkTypeCondition)

    /// Network latency comparison (in milliseconds)
    case networkLatency(ComparisonCondition)

    // MARK: - Endpoint Conditions

    /// Specific endpoint status requirement
    case endpointStatus(String, EndpointStatus)

    /// Endpoint latency comparison (in milliseconds)
    case endpointLatency(String, ComparisonCondition)

    // MARK: - Cost Conditions

    /// Session cost budget remaining comparison (in USD)
    case sessionCostBudget(ComparisonCondition)

    /// Estimated task cost comparison (in USD)
    case taskCostEstimate(ComparisonCondition)

    // MARK: - Time Conditions

    /// Time of day within range
    case timeOfDay(TimeRange)

    /// Session duration comparison (in seconds)
    case sessionDuration(ComparisonCondition)

    // MARK: - Task Conditions

    /// Prompt length comparison (in tokens)
    case promptLength(ComparisonCondition)

    /// Context length comparison (in tokens)
    case contextLength(ComparisonCondition)

    // MARK: - Evaluation

    /// Evaluate this condition against a routing context
    /// - Parameter context: The current routing context
    /// - Returns: True if condition is met
    public func evaluate(with context: RoutingContext) -> Bool {
        switch self {
        case .thermalState(let condition):
            return condition.matches(context.thermalState)

        case .memoryPressure(let condition):
            return condition.matches(context.memoryPressure)

        case .batteryLevel(let comparison):
            return comparison.evaluate(against: Double(context.batteryLevel))

        case .deviceTier(let requiredTier):
            return context.deviceTier == requiredTier

        case .networkType(let condition):
            return condition.matches(context.networkType)

        case .networkLatency(let comparison):
            return comparison.evaluate(against: context.networkLatencyMs)

        case .endpointStatus(let endpointId, let requiredStatus):
            return context.endpointStatuses[endpointId] == requiredStatus

        case .endpointLatency(let endpointId, let comparison):
            guard let latency = context.endpointLatencies[endpointId] else {
                return false
            }
            return comparison.evaluate(against: latency)

        case .sessionCostBudget(let comparison):
            return comparison.evaluate(against: Double(truncating: context.remainingBudget as NSNumber))

        case .taskCostEstimate(let comparison):
            return comparison.evaluate(against: Double(truncating: context.estimatedTaskCost as NSNumber))

        case .timeOfDay(let range):
            let hour = Calendar.current.component(.hour, from: Date())
            return range.contains(hour: hour)

        case .sessionDuration(let comparison):
            return comparison.evaluate(against: context.sessionDurationSeconds)

        case .promptLength(let comparison):
            return comparison.evaluate(against: Double(context.promptTokenCount))

        case .contextLength(let comparison):
            return comparison.evaluate(against: Double(context.contextTokenCount))
        }
    }
}

// MARK: - Comparison Condition

/// A numeric comparison condition
public struct ComparisonCondition: Codable, Sendable {
    /// The comparison operator
    public var comparison: Comparison

    /// The value to compare against
    public var value: Double

    public init(comparison: Comparison, value: Double) {
        self.comparison = comparison
        self.value = value
    }

    /// Comparison operators
    public enum Comparison: String, Codable, Sendable {
        case lessThan
        case lessThanOrEqual
        case greaterThan
        case greaterThanOrEqual
        case equals
    }

    /// Evaluate this comparison against a value
    public func evaluate(against actual: Double) -> Bool {
        switch comparison {
        case .lessThan:
            return actual < value
        case .lessThanOrEqual:
            return actual <= value
        case .greaterThan:
            return actual > value
        case .greaterThanOrEqual:
            return actual >= value
        case .equals:
            return actual == value
        }
    }
}

// MARK: - Thermal State Condition

/// Conditions for device thermal state
public enum ThermalStateCondition: String, Codable, Sendable {
    /// Exactly nominal thermal state
    case nominal

    /// Exactly fair thermal state
    case fair

    /// Exactly serious thermal state
    case serious

    /// Exactly critical thermal state
    case critical

    /// Fair or worse (fair, serious, critical)
    case atLeastFair

    /// Serious or worse (serious, critical)
    case atLeastSerious

    /// Check if a thermal state matches this condition
    public func matches(_ state: ThermalState) -> Bool {
        switch self {
        case .nominal:
            return state == .nominal
        case .fair:
            return state == .fair
        case .serious:
            return state == .serious
        case .critical:
            return state == .critical
        case .atLeastFair:
            return state == .fair || state == .serious || state == .critical
        case .atLeastSerious:
            return state == .serious || state == .critical
        }
    }
}

// MARK: - Memory Pressure Condition

/// Conditions for system memory pressure
public enum MemoryPressureCondition: String, Codable, Sendable {
    /// Exactly normal memory pressure
    case normal

    /// Exactly warning memory pressure
    case warning

    /// Exactly critical memory pressure
    case critical

    /// Warning or worse (warning, critical)
    case atLeastWarning

    /// Check if a memory pressure level matches this condition
    public func matches(_ pressure: MemoryPressure) -> Bool {
        switch self {
        case .normal:
            return pressure == .normal
        case .warning:
            return pressure == .warning
        case .critical:
            return pressure == .critical
        case .atLeastWarning:
            return pressure == .warning || pressure == .critical
        }
    }
}

// MARK: - Network Type Condition

/// Conditions for network connection type
public enum NetworkTypeCondition: String, Codable, Sendable {
    /// Connected via WiFi
    case wifi

    /// Connected via cellular
    case cellular

    /// No network connection
    case none

    /// Any network type (always matches)
    case any

    /// Check if a network type matches this condition
    public func matches(_ type: NetworkType) -> Bool {
        switch self {
        case .wifi:
            return type == .wifi
        case .cellular:
            return type == .cellular
        case .none:
            return type == .none
        case .any:
            return true
        }
    }
}

// MARK: - Time Range

/// A time range defined by start and end hours
public struct TimeRange: Codable, Sendable {
    /// Start hour (0-23)
    public var startHour: Int

    /// End hour (0-23)
    public var endHour: Int

    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }

    /// Check if an hour falls within this range
    /// - Note: Handles wrap-around midnight correctly
    public func contains(hour: Int) -> Bool {
        if startHour <= endHour {
            // Normal range (e.g., 9-17)
            return hour >= startHour && hour < endHour
        } else {
            // Wraps around midnight (e.g., 22-6)
            return hour >= startHour || hour < endHour
        }
    }
}

// MARK: - Routing Context

/// Runtime context used for evaluating routing conditions
///
/// This captures the current state of the device, network, session,
/// and endpoints to enable intelligent routing decisions.
public struct RoutingContext: Sendable {

    // MARK: - Device State

    /// Current thermal state of the device
    public var thermalState: ThermalState

    /// Current memory pressure level
    public var memoryPressure: MemoryPressure

    /// Available memory in megabytes
    public var availableMemoryMB: Int

    /// Current battery level (0.0 - 1.0)
    public var batteryLevel: Float

    /// Whether low power mode is enabled
    public var isLowPowerMode: Bool

    /// Device capability tier
    public var deviceTier: DeviceCapabilityTier

    // MARK: - Network State

    /// Current network connection type
    public var networkType: NetworkType

    /// Current network latency in milliseconds
    public var networkLatencyMs: Double

    // MARK: - Endpoint State

    /// Current status of each endpoint
    public var endpointStatuses: [String: EndpointStatus]

    /// Recent latency for each endpoint in milliseconds
    public var endpointLatencies: [String: Double]

    // MARK: - Cost State

    /// Remaining session cost budget in USD
    public var remainingBudget: Decimal

    /// Estimated cost for current task in USD
    public var estimatedTaskCost: Decimal

    // MARK: - Session State

    /// Session duration in seconds
    public var sessionDurationSeconds: Double

    // MARK: - Task State

    /// Estimated prompt token count
    public var promptTokenCount: Int

    /// Estimated context token count
    public var contextTokenCount: Int

    // MARK: - Initialization

    public init(
        thermalState: ThermalState = .nominal,
        memoryPressure: MemoryPressure = .normal,
        availableMemoryMB: Int = 4000,
        batteryLevel: Float = 1.0,
        isLowPowerMode: Bool = false,
        deviceTier: DeviceCapabilityTier = .proMax,
        networkType: NetworkType = .wifi,
        networkLatencyMs: Double = 50.0,
        endpointStatuses: [String: EndpointStatus] = [:],
        endpointLatencies: [String: Double] = [:],
        remainingBudget: Decimal = 1.0,
        estimatedTaskCost: Decimal = 0.01,
        sessionDurationSeconds: Double = 0,
        promptTokenCount: Int = 0,
        contextTokenCount: Int = 0
    ) {
        self.thermalState = thermalState
        self.memoryPressure = memoryPressure
        self.availableMemoryMB = availableMemoryMB
        self.batteryLevel = batteryLevel
        self.isLowPowerMode = isLowPowerMode
        self.deviceTier = deviceTier
        self.networkType = networkType
        self.networkLatencyMs = networkLatencyMs
        self.endpointStatuses = endpointStatuses
        self.endpointLatencies = endpointLatencies
        self.remainingBudget = remainingBudget
        self.estimatedTaskCost = estimatedTaskCost
        self.sessionDurationSeconds = sessionDurationSeconds
        self.promptTokenCount = promptTokenCount
        self.contextTokenCount = contextTokenCount
    }
}

// MARK: - Supporting Types

/// Device thermal state
public enum ThermalState: String, Codable, Sendable, Comparable {
    case nominal
    case fair
    case serious
    case critical

    /// Ordinal value for comparison (lower is better)
    private var ordinal: Int {
        switch self {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: ThermalState, rhs: ThermalState) -> Bool {
        return lhs.ordinal < rhs.ordinal
    }
}

/// System memory pressure level
public enum MemoryPressure: String, Codable, Sendable {
    case normal
    case warning
    case critical
}

/// Network connection type
public enum NetworkType: String, Codable, Sendable {
    case wifi
    case cellular
    case none
}

/// Device capability tier
public enum DeviceCapabilityTier: String, Codable, Sendable {
    /// Tier 1: Pro Max devices (iPhone 15/16/17 Pro Max)
    case proMax

    /// Tier 2: Pro devices (iPhone 14 Pro+, 15 Pro, 16 Pro)
    case proStandard

    /// Below minimum requirements
    case unsupported
}
