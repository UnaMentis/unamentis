// UnaMentis - Remote Log Handler
// Sends logs to a remote HTTP server for centralized viewing
//
// This enables real-time log viewing from simulator/device on development machine

import Foundation
import Logging
#if os(iOS)
import UIKit
#endif

/// Log entry structure for JSON serialization
public struct LogEntry: Codable, Sendable {
    public let timestamp: String
    public let level: String
    public let label: String
    public let message: String
    public let metadata: [String: String]?
    public let file: String
    public let function: String
    public let line: UInt

    public init(
        timestamp: Date,
        level: Logger.Level,
        label: String,
        message: String,
        metadata: Logger.Metadata?,
        file: String,
        function: String,
        line: UInt
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = formatter.string(from: timestamp)
        self.level = level.rawValue.uppercased()
        self.label = label
        self.message = message
        self.metadata = metadata?.mapValues { "\($0)" }
        self.file = (file as NSString).lastPathComponent
        self.function = function
        self.line = line
    }
}

/// Thread-safe configuration storage for remote logging
private final class RemoteLogConfiguration: @unchecked Sendable {
    private let lock = NSLock()

    private var _serverURL: URL = URL(string: "http://localhost:8766/api/logs")!
    private var _isEnabled: Bool
    private var _clientID: String
    private var _clientName: String

    init() {
        #if DEBUG
        _isEnabled = true
        #else
        _isEnabled = false
        #endif

        // Generate stable client ID based on device
        // Use a stable UUID as fallback since UIDevice requires main actor in Swift 6
        #if os(iOS)
        if Thread.isMainThread {
            _clientID = MainActor.assumeIsolated {
                UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            }
            _clientName = MainActor.assumeIsolated {
                UIDevice.current.name
            }
        } else {
            // Fallback for non-main thread initialization
            _clientID = UUID().uuidString
            _clientName = "UnaMentis"
        }
        #else
        _clientID = UUID().uuidString
        _clientName = Host.current().localizedName ?? "Unknown"
        #endif
    }

    var serverURL: URL {
        get { lock.withLock { _serverURL } }
        set { lock.withLock { _serverURL = newValue } }
    }

    var isEnabled: Bool {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }

    var clientID: String {
        get { lock.withLock { _clientID } }
        set { lock.withLock { _clientID = newValue } }
    }

    var clientName: String {
        get { lock.withLock { _clientName } }
        set { lock.withLock { _clientName = newValue } }
    }

    static let shared = RemoteLogConfiguration()
}

/// A LogHandler that sends logs to a remote HTTP server
///
/// Usage:
/// ```swift
/// LoggingSystem.bootstrap { label in
///     MultiplexLogHandler([
///         StreamLogHandler.standardOutput(label: label),
///         RemoteLogHandler(label: label, serverURL: URL(string: "http://192.168.1.x:8766/api/logs")!)
///     ])
/// }
/// ```
public struct RemoteLogHandler: LogHandler {

    // MARK: - Configuration

    /// Default server URL (localhost for simulator, configure for device)
    public static var defaultServerURL: URL {
        get { RemoteLogConfiguration.shared.serverURL }
        set { RemoteLogConfiguration.shared.serverURL = newValue }
    }

    /// Whether remote logging is enabled (default: true in DEBUG)
    public static var isEnabled: Bool {
        get { RemoteLogConfiguration.shared.isEnabled }
        set { RemoteLogConfiguration.shared.isEnabled = newValue }
    }

    /// Client ID for identifying this device
    public static var clientID: String {
        get { RemoteLogConfiguration.shared.clientID }
        set { RemoteLogConfiguration.shared.clientID = newValue }
    }

    /// Client name for display in dashboard
    public static var clientName: String {
        get { RemoteLogConfiguration.shared.clientName }
        set { RemoteLogConfiguration.shared.clientName = newValue }
    }

    /// Shared URLSession for log sending
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 5.0
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - LogHandler Protocol

    public var logLevel: Logger.Level = .debug
    public var metadata: Logger.Metadata = [:]

    private let label: String
    private let serverURL: URL

    public init(label: String, serverURL: URL? = nil) {
        self.label = label
        self.serverURL = serverURL ?? Self.defaultServerURL
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard Self.isEnabled else { return }

        // Merge metadata
        let mergedMetadata: Logger.Metadata?
        if let localMetadata = metadata, !localMetadata.isEmpty {
            mergedMetadata = self.metadata.merging(localMetadata) { _, new in new }
        } else if !self.metadata.isEmpty {
            mergedMetadata = self.metadata
        } else {
            mergedMetadata = nil
        }

        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            label: label,
            message: "\(message)",
            metadata: mergedMetadata,
            file: file,
            function: function,
            line: line
        )

        // Send immediately for simplicity (could batch for efficiency)
        sendLog(entry)
    }

    // MARK: - Network

    private func sendLog(_ entry: LogEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }

        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.clientID, forHTTPHeaderField: "X-Client-ID")
        request.setValue(Self.clientName, forHTTPHeaderField: "X-Client-Name")
        request.httpBody = data

        // Fire and forget - don't block on logging
        Self.session.dataTask(with: request) { _, _, _ in
            // Ignore errors silently to not affect app performance
        }.resume()
    }
}

// MARK: - Remote Logging Configuration

/// Configuration for remote logging
public enum RemoteLogging {

    /// Configure remote logging with auto-discovery
    /// Attempts to find the logging server on the local network
    public static func configure(serverIP: String? = nil, port: Int = 8766) {
        if let ip = serverIP {
            RemoteLogHandler.defaultServerURL = URL(string: "http://\(ip):\(port)/api/logs")!
        } else {
            // For simulator, localhost works
            // For device, you need to specify the IP
            #if targetEnvironment(simulator)
            RemoteLogHandler.defaultServerURL = URL(string: "http://localhost:\(port)/api/logs")!
            #else
            // Device needs actual IP - will be set from settings
            // Default to localhost which won't work but won't crash either
            RemoteLogHandler.defaultServerURL = URL(string: "http://localhost:\(port)/api/logs")!
            #endif
        }

        RemoteLogHandler.isEnabled = true
    }

    /// Disable remote logging
    public static func disable() {
        RemoteLogHandler.isEnabled = false
    }

    /// Enable remote logging
    public static func enable() {
        RemoteLogHandler.isEnabled = true
    }
}
