//
//  KBQuestionEngine.swift
//  UnaMentis
//
//  Question loading, filtering, and selection engine for Knowledge Bowl
//

import Foundation
import OSLog

// MARK: - Question Engine

/// Service for loading, filtering, and managing Knowledge Bowl questions
@MainActor
final class KBQuestionEngine: ObservableObject {
    // MARK: - Published State

    @Published private(set) var questions: [KBQuestion] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: Error?

    // MARK: - Private State

    private var attemptedQuestionIds: Set<UUID> = []
    private let logger = Logger(subsystem: "com.unamentis", category: "KBQuestionEngine")

    // MARK: - Initialization

    init() {}

    // MARK: - Loading

    /// Load questions from the bundled JSON file
    func loadBundledQuestions() async throws {
        isLoading = true
        loadError = nil

        defer { isLoading = false }

        guard let url = Bundle.main.url(forResource: "kb-sample-questions", withExtension: "json") else {
            let error = KBQuestionError.bundleNotFound
            loadError = error
            logger.error("Failed to find bundled questions: \(error.localizedDescription)")
            throw error
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bundle = try decoder.decode(KBQuestionBundle.self, from: data)
            questions = bundle.questions
            logger.info("Loaded \(bundle.questions.count) questions from bundle v\(bundle.version)")
        } catch {
            loadError = error
            logger.error("Failed to decode questions: \(error.localizedDescription)")
            throw error
        }
    }

    /// Load questions from a custom URL (for testing or external sources)
    func loadQuestions(from url: URL) async throws {
        isLoading = true
        loadError = nil

        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bundle = try decoder.decode(KBQuestionBundle.self, from: data)
            questions = bundle.questions
            logger.info("Loaded \(bundle.questions.count) questions from \(url.lastPathComponent)")
        } catch {
            loadError = error
            logger.error("Failed to load questions from URL: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Filtering

    /// Filter questions by various criteria
    func filter(
        domains: [KBDomain]? = nil,
        difficulty: KBDifficulty? = nil,
        gradeLevel: KBGradeLevel? = nil,
        forWritten: Bool? = nil,
        forOral: Bool? = nil,
        excludeAttempted: Bool = false
    ) -> [KBQuestion] {
        var filtered = questions

        // Filter by domains
        if let domains = domains, !domains.isEmpty {
            filtered = filtered.filter { domains.contains($0.domain) }
        }

        // Filter by difficulty
        if let difficulty = difficulty {
            filtered = filtered.filter { $0.difficulty == difficulty }
        }

        // Filter by grade level
        if let gradeLevel = gradeLevel {
            filtered = filtered.filter { $0.gradeLevel == gradeLevel }
        }

        // Filter by suitability for written round
        if let forWritten = forWritten {
            filtered = filtered.filter { $0.suitability.forWritten == forWritten }
        }

        // Filter by suitability for oral round
        if let forOral = forOral {
            filtered = filtered.filter { $0.suitability.forOral == forOral }
        }

        // Exclude already attempted questions
        if excludeAttempted {
            filtered = filtered.filter { !attemptedQuestionIds.contains($0.id) }
        }

        return filtered
    }

    // MARK: - Selection

    /// Select a random subset of questions
    func selectRandom(
        count: Int,
        from filteredQuestions: [KBQuestion]? = nil
    ) -> [KBQuestion] {
        let pool = filteredQuestions ?? questions
        guard !pool.isEmpty else { return [] }

        let actualCount = min(count, pool.count)
        return Array(pool.shuffled().prefix(actualCount))
    }

    /// Select questions for a practice session based on configuration
    func selectForSession(config: KBSessionConfig) -> [KBQuestion] {
        // Only filter by the suitability of the round type we're using
        // Pass nil for the other type to avoid filtering out questions that are suitable for both
        let filtered = filter(
            domains: config.domains,
            difficulty: config.difficulty,
            gradeLevel: config.gradeLevel,
            forWritten: config.roundType == .written ? true : nil,
            forOral: config.roundType == .oral ? true : nil
        )

        return selectRandom(count: config.questionCount, from: filtered)
    }

    /// Select questions with weighted domain distribution
    func selectWeighted(
        count: Int,
        respectDomainWeights: Bool = true,
        from filteredQuestions: [KBQuestion]? = nil
    ) -> [KBQuestion] {
        let pool = filteredQuestions ?? questions
        guard !pool.isEmpty else { return [] }

        if !respectDomainWeights {
            return selectRandom(count: count, from: pool)
        }

        // Group questions by domain
        var byDomain: [KBDomain: [KBQuestion]] = [:]
        for question in pool {
            byDomain[question.domain, default: []].append(question)
        }

        // Calculate how many questions per domain based on weights
        var selected: [KBQuestion] = []
        var remaining = count

        for domain in KBDomain.allCases {
            guard let domainQuestions = byDomain[domain], !domainQuestions.isEmpty else { continue }

            let targetCount = Int(Double(count) * domain.weight)
            let actualCount = min(targetCount, domainQuestions.count, remaining)

            if actualCount > 0 {
                selected.append(contentsOf: domainQuestions.shuffled().prefix(actualCount))
                remaining -= actualCount
            }
        }

        // Fill any remaining slots randomly
        if remaining > 0 {
            let alreadySelected = Set(selected.map { $0.id })
            let additionalPool = pool.filter { !alreadySelected.contains($0.id) }
            selected.append(contentsOf: additionalPool.shuffled().prefix(remaining))
        }

        return selected.shuffled()
    }

    // MARK: - Attempt Tracking

    /// Mark a question as attempted
    func markAttempted(_ questionId: UUID) {
        attemptedQuestionIds.insert(questionId)
    }

    /// Mark multiple questions as attempted
    func markAttempted(_ questionIds: [UUID]) {
        attemptedQuestionIds.formUnion(questionIds)
    }

    /// Clear attempted question tracking
    func clearAttemptedQuestions() {
        attemptedQuestionIds.removeAll()
    }

    /// Check if a question has been attempted
    func hasAttempted(_ questionId: UUID) -> Bool {
        attemptedQuestionIds.contains(questionId)
    }

    // MARK: - Statistics

    /// Get question counts by domain
    var questionsByDomain: [KBDomain: Int] {
        var counts: [KBDomain: Int] = [:]
        for question in questions {
            counts[question.domain, default: 0] += 1
        }
        return counts
    }

    /// Get question counts by difficulty
    var questionsByDifficulty: [KBDifficulty: Int] {
        var counts: [KBDifficulty: Int] = [:]
        for question in questions {
            counts[question.difficulty, default: 0] += 1
        }
        return counts
    }

    /// Get question counts by grade level
    var questionsByGradeLevel: [KBGradeLevel: Int] {
        var counts: [KBGradeLevel: Int] = [:]
        for question in questions {
            counts[question.gradeLevel, default: 0] += 1
        }
        return counts
    }

    /// Total number of questions available
    var totalQuestionCount: Int { questions.count }

    /// Number of questions not yet attempted
    var unattemptedCount: Int {
        questions.count - attemptedQuestionIds.count
    }
}

// MARK: - Errors

enum KBQuestionError: LocalizedError, Sendable {
    case bundleNotFound
    case decodingFailed(String)  // Store error message instead of Error for Sendable
    case insufficientQuestions(needed: Int, available: Int)

    var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "Question bundle not found in app resources"
        case .decodingFailed(let message):
            return "Failed to decode questions: \(message)"
        case .insufficientQuestions(let needed, let available):
            return "Not enough questions available: need \(needed), have \(available)"
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension KBQuestionEngine {
    /// Create an engine with sample questions for previews
    static func preview() -> KBQuestionEngine {
        let engine = KBQuestionEngine()
        engine.questions = [
            KBQuestion(
                id: UUID(),
                text: "What is the chemical symbol for gold?",
                answer: KBAnswer(primary: "Au", acceptable: ["AU"], answerType: .scientific),
                domain: .science,
                subdomain: "chemistry",
                difficulty: .foundational,
                gradeLevel: .middleSchool,
                mcqOptions: ["Au", "Ag", "Fe", "Cu"]
            ),
            KBQuestion(
                id: UUID(),
                text: "What is the square root of 144?",
                answer: KBAnswer(primary: "12", acceptable: ["twelve"], answerType: .number),
                domain: .mathematics,
                difficulty: .foundational,
                gradeLevel: .middleSchool,
                mcqOptions: ["12", "11", "13", "14"]
            ),
            KBQuestion(
                id: UUID(),
                text: "Who wrote Romeo and Juliet?",
                answer: KBAnswer(primary: "William Shakespeare", acceptable: ["Shakespeare"], answerType: .person),
                domain: .literature,
                difficulty: .foundational,
                gradeLevel: .middleSchool,
                mcqOptions: ["William Shakespeare", "Charles Dickens", "Jane Austen", "Mark Twain"]
            )
        ]
        return engine
    }
}
#endif
