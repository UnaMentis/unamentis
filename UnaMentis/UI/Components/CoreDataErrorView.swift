// UnaMentis - Core Data Error Recovery View
// Shown when the persistent store fails to load, preventing crash loops

import SwiftUI

/// Recovery view displayed when Core Data store fails to load.
/// Offers the user options to retry or reset the data store.
@MainActor
struct CoreDataErrorView: View {
    let error: Error
    @State private var isResetting = false
    @State private var resetComplete = false
    @State private var resetError: String?
    @State private var showRestartPrompt = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text("Unable to Load Data", comment: "Core Data error view title")
                .font(.title2.bold())

            Text("UnaMentis was unable to load your saved data. This can happen if the device storage is full or the data file was corrupted.", comment: "Core Data error view explanation")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                if showRestartPrompt {
                    Text("Please close and reopen UnaMentis to retry loading your data.", comment: "Core Data restart prompt after user taps retry")
                        .font(.callout)
                        .foregroundStyle(.blue)
                        .multilineTextAlignment(.center)
                } else {
                    Button {
                        showRestartPrompt = true
                        AccessibilityNotification.Announcement(
                            String(localized: "Please close and reopen UnaMentis to retry loading your data.", comment: "Core Data restart announcement for VoiceOver")
                        ).post()
                    } label: {
                        Label(String(localized: "Quit and Retry", comment: "Core Data error retry button"), systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(Text("Quit and retry loading data", comment: "Core Data error retry accessibility"))
                }

                Button(role: .destructive) {
                    Task { await resetStore() }
                } label: {
                    if isResetting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(String(localized: "Reset All Data", comment: "Core Data error reset button"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isResetting)
                .accessibilityLabel(isResetting
                    ? Text("Resetting data", comment: "Core Data reset in progress accessibility")
                    : Text("Reset all data and start fresh", comment: "Core Data error reset accessibility"))
            }
            .padding(.horizontal, 48)

            if resetComplete {
                Text("Data reset complete. Please relaunch the app.", comment: "Core Data reset success message")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            if let resetError {
                Text(String(localized: "Some files could not be removed: \(resetError)", comment: "Core Data reset partial failure message"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Text(String(localized: "Error: \(error.localizedDescription)", comment: "Core Data error details with error description"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private func resetStore() async {
        isResetting = true
        resetError = nil
        resetComplete = false

        AccessibilityNotification.Announcement(
            String(localized: "Resetting data", comment: "Core Data reset started announcement for VoiceOver")
        ).post()

        let container = PersistenceController.shared.container
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            let message = String(localized: "Unable to locate data store files.", comment: "Core Data reset failure when no store URL available")
            resetError = message
            isResetting = false
            AccessibilityNotification.Announcement(
                String(localized: "Reset failed. Unable to locate data store files.", comment: "Core Data reset failure announcement for VoiceOver")
            ).post()
            return
        }

        let coordinator = container.persistentStoreCoordinator
        let result = await Task.detached(priority: .userInitiated) { () -> (success: Bool, error: String?) in
            do {
                try coordinator.destroyPersistentStore(
                    at: storeURL,
                    type: .sqlite
                )
                return (true, nil)
            } catch {
                let fileManager = FileManager.default
                let storePath = storeURL.path
                var failedFiles: [String] = []
                for suffix in ["", "-shm", "-wal"] {
                    let path = storePath + suffix
                    do {
                        if fileManager.fileExists(atPath: path) {
                            try fileManager.removeItem(atPath: path)
                        }
                    } catch {
                        failedFiles.append(suffix.isEmpty ? "database" : suffix)
                    }
                }
                if failedFiles.isEmpty {
                    return (true, nil)
                } else {
                    return (false, failedFiles.joined(separator: ", "))
                }
            }
        }.value

        resetComplete = result.success
        resetError = result.error
        isResetting = false

        if result.success {
            AccessibilityNotification.Announcement(
                String(localized: "Data reset complete. Please relaunch the app.", comment: "Core Data reset success announcement for VoiceOver")
            ).post()
        } else if let error = result.error {
            AccessibilityNotification.Announcement(
                String(localized: "Some files could not be removed: \(error)", comment: "Core Data reset failure announcement for VoiceOver")
            ).post()
        }
    }
}
