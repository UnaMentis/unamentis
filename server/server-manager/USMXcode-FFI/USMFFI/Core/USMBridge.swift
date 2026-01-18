// USMBridge.swift
// Low-level FFI wrapper for USM Core with proper memory management

import Foundation

/// Low-level FFI wrapper that provides safe Swift access to USM Core C functions
final class USMBridge {
    private var handle: OpaquePointer?
    /// Serial queue for thread-safe FFI access
    private let queue = DispatchQueue(label: "com.unamentis.usm-ffi.bridge")

    /// Initialize with path to USM Core config file
    /// - Parameter configPath: Path to services.toml configuration
    init?(configPath: String) {
        guard let h = configPath.withCString({ usm_create($0) }) else {
            print("[USMBridge] Failed to create USM Core handle")
            return nil
        }
        handle = h
        print("[USMBridge] Initialized with config: \(configPath)")
    }

    deinit {
        if let h = handle {
            usm_destroy(h)
            print("[USMBridge] Destroyed USM Core handle")
        }
    }

    /// Get all service instances from USM Core
    /// - Returns: Array of ServiceInfo, empty if error
    func getServices() -> [ServiceInfo] {
        queue.sync {
            guard let h = handle else {
                print("[USMBridge] No handle available")
                return []
            }

            guard let array = usm_get_services(h) else {
                print("[USMBridge] usm_get_services returned null")
                return []
            }
            defer { usm_free_services(array) }

            let count = Int(array.pointee.len)
            guard count > 0, array.pointee.data != nil else {
                return []
            }

            var services: [ServiceInfo] = []
            services.reserveCapacity(count)

            for i in 0..<count {
                let cService = array.pointee.data[i]

                let id = cService.id != nil ? String(cString: cService.id) : "unknown"
                let templateId = cService.template_id != nil ? String(cString: cService.template_id) : ""
                let displayName = cService.display_name != nil ? String(cString: cService.display_name) : id

                let service = ServiceInfo(
                    id: id,
                    templateId: templateId,
                    displayName: displayName,
                    port: Int(cService.port),
                    status: ServiceStatus(rawValue: Int(cService.status)) ?? .unknown,
                    cpuPercent: cService.cpu_percent,
                    memoryMB: Int(cService.memory_mb)
                )
                services.append(service)
            }

            return services
        }
    }

    /// Start a service instance
    /// - Parameter instanceId: Service instance ID
    /// - Returns: True if successful
    func startService(_ instanceId: String) -> Bool {
        queue.sync {
            guard let h = handle else { return false }

            let result = instanceId.withCString { cId in
                usm_start_service(h, cId)
            }

            if result == 0 {
                print("[USMBridge] Started service: \(instanceId)")
                return true
            } else {
                print("[USMBridge] Failed to start service: \(instanceId)")
                return false
            }
        }
    }

    /// Stop a service instance
    /// - Parameter instanceId: Service instance ID
    /// - Returns: True if successful
    func stopService(_ instanceId: String) -> Bool {
        queue.sync {
            guard let h = handle else { return false }

            let result = instanceId.withCString { cId in
                usm_stop_service(h, cId)
            }

            if result == 0 {
                print("[USMBridge] Stopped service: \(instanceId)")
                return true
            } else {
                print("[USMBridge] Failed to stop service: \(instanceId)")
                return false
            }
        }
    }

    /// Restart a service instance
    /// - Parameter instanceId: Service instance ID
    /// - Returns: True if successful
    func restartService(_ instanceId: String) -> Bool {
        queue.sync {
            guard let h = handle else { return false }

            let result = instanceId.withCString { cId in
                usm_restart_service(h, cId)
            }

            if result == 0 {
                print("[USMBridge] Restarted service: \(instanceId)")
                return true
            } else {
                print("[USMBridge] Failed to restart service: \(instanceId)")
                return false
            }
        }
    }

    /// Get the USM Core server port
    static var serverPort: Int {
        Int(usm_get_server_port())
    }

    /// Get the USM Core version string
    static var version: String {
        guard let versionPtr = usm_version() else {
            return "unknown"
        }
        return String(cString: versionPtr)
    }
}
