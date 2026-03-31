// UnaMentis - Core Data Error Recovery View
// Shown when the persistent store fails to load, preventing crash loops

import SwiftUI

/// Recovery view displayed when Core Data store fails to load.
/// Offers the user options to retry or reset the data store.
struct CoreDataErrorView: View {
    let error: Error
    @State private var isResetting = false
    @State private var resetComplete = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text("Unable to Load Data")
                .font(.title2.bold())

            Text("UnaMentis was unable to load your saved data. This can happen if the device storage is full or the data file was corrupted.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button {
                    // Force quit and relaunch to retry
                    exit(0)
                } label: {
                    Label("Quit and Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Quit and retry loading data")

                Button(role: .destructive) {
                    resetStore()
                } label: {
                    if isResetting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Reset All Data", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isResetting)
                .accessibilityLabel("Reset all data and start fresh")
            }
            .padding(.horizontal, 48)

            if resetComplete {
                Text("Data reset complete. Please relaunch the app.")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            Spacer()

            Text("Error: \(error.localizedDescription)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private func resetStore() {
        isResetting = true
        let container = PersistenceController.shared.container
        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            isResetting = false
            return
        }

        do {
            try container.persistentStoreCoordinator.destroyPersistentStore(
                at: storeURL,
                type: .sqlite
            )
            resetComplete = true
        } catch {
            // If we can't destroy it, try deleting the files directly
            let fileManager = FileManager.default
            let storePath = storeURL.path
            for suffix in ["", "-shm", "-wal"] {
                try? fileManager.removeItem(atPath: storePath + suffix)
            }
            resetComplete = true
        }
        isResetting = false
    }
}
