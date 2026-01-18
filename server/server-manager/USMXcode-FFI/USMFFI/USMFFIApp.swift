// USMFFIApp.swift
// USM-FFI: Rust-based service manager using USM Core FFI

import SwiftUI

@main
struct USMFFIApp: App {
    @StateObject private var manager = USMCoreManager()

    var body: some Scene {
        MenuBarExtra {
            PopoverContent(manager: manager)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("UnaMentis Server Manager")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(manager: manager)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var manager: USMCoreManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UnaMentis Server Manager")
                .font(.headline)

            Divider()

            Text("Connection")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Circle()
                    .fill(manager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(manager.isConnected ? "Connected to USM Core" : "Disconnected")
                    .font(.caption)
            }

            HStack {
                Text("USM Core Port:")
                    .font(.caption)
                Text("8767")
                    .font(.caption)
                    .monospacedDigit()
            }

            HStack {
                Text("FFI Version:")
                    .font(.caption)
                Text(USMBridge.version)
                    .font(.caption)
                    .monospacedDigit()
            }

            Divider()

            Text("Preferences")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Toggle(isOn: $manager.developmentMode) {
                Text("Development Mode")
            }
            .help("Show development tools like Feature Flags, Latency Harness")

            Spacer()
        }
        .padding()
        .frame(width: 320, minHeight: 250, maxHeight: 400)
    }
}
