// UnaMentis - App Shortcuts Provider
// Registers App Intents with Siri and Shortcuts app
//
// Part of Apple Intelligence Integration (iOS 18+)

import AppIntents

/// Provides app shortcuts to the system for Siri and Shortcuts integration
///
/// This enables:
/// - Voice commands via Siri
/// - Shortcuts app integration
/// - Spotlight suggestions
/// - Control Center widgets (iOS 18+)
public struct UnaMentisShortcuts: AppShortcutsProvider {
    /// Define the shortcuts exposed to the system
    public static var appShortcuts: [AppShortcut] {
        // Start Lesson shortcut
        AppShortcut(
            intent: StartLessonIntent(),
            phrases: [
                "Start a lesson in \(.applicationName)",
                "Start learning in \(.applicationName)",
                "Teach me in \(.applicationName)",
                "Start a \(.applicationName) lesson",
                "Learn with \(.applicationName)",
                "Start lesson on \(\.$topic) in \(.applicationName)",
                "Study \(\.$topic) with \(.applicationName)",
                "Teach me about \(\.$topic) in \(.applicationName)"
            ],
            shortTitle: "Start Lesson",
            systemImageName: "book.fill"
        )

        // Resume Learning shortcut
        AppShortcut(
            intent: ResumeLearningIntent(),
            phrases: [
                "Resume learning in \(.applicationName)",
                "Continue my lesson in \(.applicationName)",
                "Pick up where I left off in \(.applicationName)",
                "Resume \(.applicationName)",
                "Continue \(.applicationName) lesson"
            ],
            shortTitle: "Resume Learning",
            systemImageName: "play.circle.fill"
        )

        // Show Progress shortcut
        AppShortcut(
            intent: ShowProgressIntent(),
            phrases: [
                "Show my progress in \(.applicationName)",
                "How am I doing in \(.applicationName)",
                "What have I learned in \(.applicationName)",
                "My \(.applicationName) progress",
                "Show \(.applicationName) stats"
            ],
            shortTitle: "Show Progress",
            systemImageName: "chart.bar.fill"
        )
    }
}

// MARK: - App Intent Documentation

/*
 ## Siri Voice Commands

 After building and running the app, users can use these voice commands:

 ### Starting a Lesson
 - "Hey Siri, start a lesson in UnaMentis"
 - "Hey Siri, teach me about Quantum Mechanics in UnaMentis"
 - "Hey Siri, study Physics with UnaMentis"

 ### Resuming Learning
 - "Hey Siri, resume learning in UnaMentis"
 - "Hey Siri, continue my lesson in UnaMentis"
 - "Hey Siri, pick up where I left off in UnaMentis"

 ### Checking Progress
 - "Hey Siri, show my progress in UnaMentis"
 - "Hey Siri, how am I doing in UnaMentis"

 ## Shortcuts App Integration

 Users can also create custom Shortcuts using:
 1. Open Shortcuts app
 2. Create new Shortcut
 3. Search for "UnaMentis"
 4. Add actions like "Start Lesson", "Resume Learning", "Show Progress"

 ## Spotlight Integration

 Topics and Curricula appear in Spotlight search:
 - Search for "Quantum Mechanics" to find matching topics
 - Search for "Physics" to find curricula

 ## Requirements

 - iOS 16.0+ for basic App Intents
 - iOS 17.0+ for enhanced Siri integration
 - iOS 18.0+ for Apple Intelligence features

 ## Deep Link URL Scheme

 The intents use deep links to open the app:
 - unamentis://lesson?id=UUID&depth=intermediate
 - unamentis://resume?id=UUID
 - unamentis://analytics

 Add URL scheme to Info.plist:
 ```xml
 <key>CFBundleURLTypes</key>
 <array>
     <dict>
         <key>CFBundleURLSchemes</key>
         <array>
             <string>unamentis</string>
         </array>
         <key>CFBundleURLName</key>
         <string>com.unamentis.app</string>
     </dict>
 </array>
 ```
 */
