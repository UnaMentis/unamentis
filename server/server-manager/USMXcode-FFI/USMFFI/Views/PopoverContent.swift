// PopoverContent.swift
// Main popover UI for USM-FFI menu bar app

import SwiftUI

struct PopoverContent: View {
    @ObservedObject var manager: USMCoreManager
    @State private var devToolsExpanded = true

    /// Max width for service names (for alignment)
    private var maxServiceNameWidth: CGFloat {
        let names = manager.visibleServices.map { $0.formattedName }
        let maxName = names.max(by: { $0.count < $1.count }) ?? ""
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes = [NSAttributedString.Key.font: font]
        let size = (maxName as NSString).size(withAttributes: attributes)
        return min(max(size.width + 8, 100), 200) // Clamp between 100-200
    }

    /// Core services (non-development)
    private var coreServices: [ServiceInfo] {
        manager.visibleServices.filter { $0.category != .development }
    }

    /// Development services
    private var developmentServices: [ServiceInfo] {
        manager.visibleServices.filter { $0.category == .development }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView

            Divider()

            // Connection status (if not connected)
            if !manager.isConnected {
                connectionStatusView
                Divider()
            }

            // Core Services List
            if !coreServices.isEmpty {
                VStack(spacing: 1) {
                    ForEach(coreServices) { service in
                        ServiceRow(
                            service: service,
                            nameWidth: maxServiceNameWidth,
                            manager: manager
                        )
                    }
                }
                .padding(.vertical, 4)
            } else if manager.isConnected {
                Text("No services configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }

            // Development Tools Section (only visible in dev mode)
            if manager.developmentMode && !developmentServices.isEmpty {
                Divider()
                developmentToolsSection
            }

            Divider()

            // Action Buttons
            actionButtonsView

            Divider()

            // Footer: Dev Mode Toggle and Quit
            footerView
        }
        .frame(width: 370)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Text("UnaMentis Server Manager")
                .font(.headline)

            // Connection indicator
            Circle()
                .fill(manager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .help(manager.isConnected ? "Connected to USM Core" : "Disconnected")

            Spacer()

            Button(action: { manager.refreshServices() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var connectionStatusView: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading) {
                Text("USM Core not available")
                    .font(.caption)
                    .fontWeight(.medium)
                if let error = manager.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button("Retry") {
                manager.checkConnection()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private var developmentToolsSection: some View {
        VStack(spacing: 0) {
            // Collapsible header
            Button(action: { devToolsExpanded.toggle() }) {
                HStack {
                    Image(systemName: devToolsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Development Tools")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if devToolsExpanded {
                VStack(spacing: 1) {
                    ForEach(developmentServices) { service in
                        ServiceRow(
                            service: service,
                            nameWidth: maxServiceNameWidth,
                            manager: manager
                        )
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var actionButtonsView: some View {
        HStack(spacing: 8) {
            Button("Start All") {
                manager.startAll()
            }
            .buttonStyle(.bordered)
            .disabled(!manager.isConnected)

            Button("Stop All") {
                manager.stopAll()
            }
            .buttonStyle(.bordered)
            .disabled(!manager.isConnected)

            Spacer()

            // Quick links
            Button(action: { openURL("http://localhost:3000") }) {
                Image(systemName: "globe")
            }
            .buttonStyle(.borderless)
            .help("Open Operations Console (localhost:3000)")
            .accessibilityLabel("Open Operations Console")

            Button(action: { openURL("http://localhost:3001") }) {
                Image(systemName: "laptopcomputer")
            }
            .buttonStyle(.borderless)
            .help("Open Web Client (localhost:3001)")
            .accessibilityLabel("Open Web Client")

            Button(action: { openURL("http://localhost:8765") }) {
                Image(systemName: "doc.text")
            }
            .buttonStyle(.borderless)
            .help("Open Logs (localhost:8765)")
            .accessibilityLabel("Open Logs")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footerView: some View {
        HStack {
            Toggle(isOn: $manager.developmentMode) {
                Label("Dev Mode", systemImage: "wrench.and.screwdriver")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .help("Show development tools")

            Spacer()

            Text("v\(USMBridge.version)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
