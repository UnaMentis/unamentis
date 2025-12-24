// UnaMentis - Show Progress Intent
// Enables "Hey Siri, show my learning progress" voice commands
//
// Part of Apple Intelligence Integration (iOS 18+)

import AppIntents
import CoreData

/// App Intent for displaying learning progress
///
/// Enables voice commands like:
/// - "Hey Siri, show my learning progress"
/// - "Hey Siri, how am I doing in UnaMentis?"
/// - "Hey Siri, what have I learned?"
public struct ShowProgressIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Learning Progress"

    public static let description = IntentDescription(
        "View your learning progress and statistics",
        categoryName: "Learning",
        searchKeywords: ["progress", "stats", "statistics", "mastery", "completed"]
    )

    /// Optional: filter to a specific curriculum
    @Parameter(
        title: "Curriculum",
        description: "Show progress for a specific curriculum"
    )
    public var curriculum: CurriculumEntity?

    public init() {}

    /// Perform the intent
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.container.viewContext

        let stats = await context.perform { () -> LearningStats in
            var stats = LearningStats()

            // Fetch all topics, optionally filtered by curriculum
            let request: NSFetchRequest<Topic> = Topic.fetchRequest()
            if let curriculumId = curriculum?.id {
                request.predicate = NSPredicate(format: "curriculum.id == %@", curriculumId as CVarArg)
            }

            guard let topics = try? context.fetch(request) else {
                return stats
            }

            stats.totalTopics = topics.count

            for topic in topics {
                if topic.mastery >= 0.8 {
                    stats.completedTopics += 1
                } else if topic.mastery > 0 {
                    stats.inProgressTopics += 1
                }

                if let progress = topic.progress {
                    stats.totalTimeMinutes += Int(progress.timeSpent / 60)
                }
            }

            // Calculate overall mastery
            if !topics.isEmpty {
                let totalMastery = topics.reduce(Float(0)) { $0 + $1.mastery }
                stats.overallMastery = totalMastery / Float(topics.count)
            }

            return stats
        }

        // Build the response dialog
        let curriculumName = curriculum?.name ?? "all curricula"
        let masteryPercent = Int(stats.overallMastery * 100)

        let dialog: IntentDialog
        if stats.totalTopics == 0 {
            dialog = "You haven't started any lessons yet. Say 'Start a lesson' to begin learning!"
        } else {
            dialog = """
            For \(curriculumName): \
            You've completed \(stats.completedTopics) of \(stats.totalTopics) topics \
            with \(masteryPercent)% overall mastery. \
            You have \(stats.inProgressTopics) topics in progress \
            and have studied for \(stats.totalTimeMinutes) minutes total.
            """
        }

        return .result(dialog: dialog)
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Show learning progress") {
            \.$curriculum
        }
    }
}

// MARK: - Learning Stats

/// Statistics about learning progress
private struct LearningStats {
    var totalTopics: Int = 0
    var completedTopics: Int = 0
    var inProgressTopics: Int = 0
    var totalTimeMinutes: Int = 0
    var overallMastery: Float = 0
}
