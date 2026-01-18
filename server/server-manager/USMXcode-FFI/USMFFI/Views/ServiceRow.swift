// ServiceRow.swift
// Individual service row in the popover list

import SwiftUI

struct ServiceRow: View {
    let service: ServiceInfo
    let nameWidth: CGFloat
    @ObservedObject var manager: USMCoreManager

    /// Tooltip showing port info
    private var serviceTooltip: String {
        if service.status == .running && service.port > 0 {
            return "\(service.displayName) running on port \(service.port)"
        } else if service.port > 0 {
            return "Port \(service.port)"
        } else {
            return service.displayName
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(service.status.color)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.3), value: service.status)

            // Service name - fixed width, no wrapping
            Text(service.displayName)
                .lineLimit(1)
                .frame(width: nameWidth, alignment: .leading)
                .help(serviceTooltip)

            // CPU - always show value
            HStack(spacing: 2) {
                Image(systemName: "cpu")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f%%", service.cpuPercent))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(service.status == .running ? .primary : .secondary)
            }
            .frame(width: 55, alignment: .trailing)

            // Memory - always show value
            HStack(spacing: 2) {
                Image(systemName: "memorychip")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(service.memoryMB)MB")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(service.status == .running ? .primary : .secondary)
            }
            .frame(width: 60, alignment: .trailing)

            // Action buttons
            HStack(spacing: 4) {
                // Start button
                Button(action: { manager.start(service.id) }) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(service.status == .running || service.status == .starting)
                .opacity(service.status == .running || service.status == .starting ? 0.3 : 1.0)
                .help("Start")
                .accessibilityLabel("Start \(service.displayName)")

                // Stop button
                Button(action: { manager.stop(service.id) }) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(service.status != .running)
                .opacity(service.status != .running ? 0.3 : 1.0)
                .help("Stop")
                .accessibilityLabel("Stop \(service.displayName)")

                // Restart button
                Button(action: { manager.restart(service.id) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(service.status != .running)
                .opacity(service.status != .running ? 0.3 : 1.0)
                .help("Restart")
                .accessibilityLabel("Restart \(service.displayName)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.clear)
    }
}

// MARK: - Preview

#if DEBUG
struct ServiceRow_Previews: PreviewProvider {
    static var previews: some View {
        let runningService = ServiceInfo(
            id: "management-api",
            templateId: "management-api",
            displayName: "Management API",
            port: 8766,
            status: .running,
            cpuPercent: 2.5,
            memoryMB: 128
        )

        let stoppedService = ServiceInfo(
            id: "web-client",
            templateId: "web-client",
            displayName: "Web Client",
            port: 3001,
            status: .stopped,
            cpuPercent: 0,
            memoryMB: 0
        )

        VStack {
            ServiceRow(
                service: runningService,
                nameWidth: 120,
                manager: USMCoreManager()
            )
            ServiceRow(
                service: stoppedService,
                nameWidth: 120,
                manager: USMCoreManager()
            )
        }
        .frame(width: 370)
        .padding()
    }
}
#endif
