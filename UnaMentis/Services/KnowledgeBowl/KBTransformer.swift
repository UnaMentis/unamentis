//
//  KBTransformer.swift
//  UnaMentis
//
//  Transforms questions from various formats into Knowledge Bowl format.
//  Implements QuestionTransformer protocol for cross-module question sharing.
//

import Foundation

// MARK: - KB Question Transformer

/// Transforms questions from import formats into Knowledge Bowl format.
///
/// This transformer supports two modes:
/// 1. Import mode: Transform `ImportedQuestion` from JSON/API sources
/// 2. Canonical mode: Transform `CanonicalQuestion` for cross-module sharing
struct KBTransformer: QuestionTransformer {
    typealias ModuleQuestion = KBQuestion
    // MARK: - Import Data Structures

    /// Raw question data from import sources (JSON, APIs, etc.)
    struct ImportedQuestion: Codable {
        let text: String
        let answer: String
        let acceptableAnswers: [String]?
        let domain: String
        let subdomain: String?
        let difficulty: String?
        let gradeLevel: String?
        let source: String
        let mcqOptions: [String]?
        let requiresCalculation: Bool?
        let hasFormula: Bool?
        let yearWritten: Int?
    }

    // MARK: - Transformation

    /// Transform an imported question into KB format
    func transform(_ imported: ImportedQuestion) -> KBQuestion? {
        // Map domain string to KBDomain
        guard let domain = mapDomain(imported.domain) else {
            print("[KBTransformer] Unknown domain: \(imported.domain)")
            return nil
        }

        // Map difficulty
        let difficulty = mapDifficulty(imported.difficulty)

        // Determine suitability
        let suitability = KBSuitability(
            forWritten: true,  // Most questions work for written
            forOral: !(imported.requiresCalculation ?? false),
            mcqPossible: imported.mcqOptions != nil && (imported.mcqOptions?.count ?? 0) >= 2,
            requiresVisual: imported.hasFormula ?? false
        )

        // Estimate read time (~150 words per minute for competition reading)
        let wordCount = imported.text.split(separator: " ").count
        let readTime = Double(wordCount) / 150.0 * 60.0  // seconds

        // Create answer model
        let answer = KBAnswer(
            primary: imported.answer,
            acceptable: imported.acceptableAnswers,
            answerType: inferAnswerType(imported.answer)
        )

        return KBQuestion(
            id: UUID(),
            text: imported.text,
            answer: answer,
            domain: domain,
            subdomain: imported.subdomain,
            difficulty: difficulty,
            suitability: suitability,
            estimatedReadTime: readTime,
            mcqOptions: imported.mcqOptions,
            source: imported.source
        )
    }

    /// Transform a batch of imported questions
    func transformBatch(_ imported: [ImportedQuestion]) -> [KBQuestion] {
        imported.compactMap { transform($0) }
    }

    // MARK: - Domain Mapping

    private func mapDomain(_ domainString: String) -> KBDomain? {
        let normalized = domainString.lowercased().trimmingCharacters(in: .whitespaces)

        switch normalized {
        case "science", "sciences", "natural science":
            return .science
        case "mathematics", "math", "maths":
            return .mathematics
        case "literature", "english", "language arts":
            return .literature
        case "history", "world history", "us history":
            return .history
        case "social studies", "social science", "civics", "geography":
            return .socialStudies
        case "arts", "fine arts", "visual arts", "music":
            return .arts
        case "current events", "current affairs", "news":
            return .currentEvents
        case "language", "foreign language", "linguistics":
            return .language
        case "technology", "computer science", "programming":
            return .technology
        case "pop culture", "popular culture", "entertainment":
            return .popCulture
        case "religion", "philosophy", "ethics":
            return .religionPhilosophy
        case "miscellaneous", "misc", "general knowledge", "other":
            return .miscellaneous
        default:
            return nil
        }
    }

    // MARK: - Difficulty Mapping

    private func mapDifficulty(_ difficultyString: String?) -> KBDifficulty {
        guard let difficultyString = difficultyString else {
            return .intermediate  // Default
        }

        let normalized = difficultyString.lowercased().trimmingCharacters(in: .whitespaces)

        switch normalized {
        case "novice", "beginner", "easy", "elementary", "grade 6-7":
            return .foundational
        case "competent", "intermediate", "medium", "middle school", "grade 8-9":
            return .intermediate
        case "varsity", "advanced", "hard", "high school", "grade 10-12":
            return .varsity
        default:
            // Try to infer from grade level
            if normalized.contains("6") || normalized.contains("7") {
                return .foundational
            } else if normalized.contains("8") || normalized.contains("9") {
                return .intermediate
            } else if normalized.contains("10") || normalized.contains("11") || normalized.contains("12") {
                return .varsity
            }
            return .intermediate  // Default
        }
    }

    // MARK: - Answer Type Inference

    private func inferAnswerType(_ answer: String) -> KBAnswerType {
        let normalized = answer.lowercased().trimmingCharacters(in: .whitespaces)

        // Check for numbers
        if Double(normalized) != nil || normalized.contains(where: { "0123456789".contains($0) }) {
            return .number
        }

        // Check for common person indicators
        let personIndicators = ["dr.", "mr.", "mrs.", "ms.", "president", "king", "queen", "emperor"]
        if personIndicators.contains(where: { normalized.contains($0) }) {
            return .person
        }

        // Check for dates
        let dateIndicators = ["january", "february", "march", "april", "may", "june",
                             "july", "august", "september", "october", "november", "december",
                             "19", "20"]  // Century indicators
        if dateIndicators.contains(where: { normalized.contains($0) }) {
            return .date
        }

        // Check for places (countries, cities, etc.)
        // This is simplified - a more robust implementation would use a gazetteer
        if normalized.contains("city") || normalized.contains("state") ||
           normalized.contains("country") || normalized.contains("ocean") ||
           normalized.contains("river") || normalized.contains("mountain") {
            return .place
        }

        // Check for titles (books, movies, etc.)
        if normalized.hasPrefix("the ") || normalized.contains("\"") {
            return .title
        }

        // Check for scientific terms
        if normalized.contains("acid") || normalized.contains("oxide") ||
           normalized.contains("element") || normalized.contains("compound") {
            return .scientific
        }

        // Default to text
        return .text
    }

    // MARK: - Quality Assessment

    /// Calculate quality score for an imported question (0.0 to 1.0)
    func qualityScore(_ imported: ImportedQuestion) -> Double {
        var score = 0.5

        // Has MCQ options (easier to grade)
        if let options = imported.mcqOptions, options.count >= 4 {
            score += 0.2
        }

        // Has acceptable answer alternatives
        if let acceptable = imported.acceptableAnswers, !acceptable.isEmpty {
            score += 0.1
        }

        // Appropriate length (not too short, not too long)
        let wordCount = imported.text.split(separator: " ").count
        if wordCount >= 10 && wordCount <= 50 {
            score += 0.1
        }

        // Not formula-heavy (voice-friendly)
        if !(imported.hasFormula ?? false) {
            score += 0.1
        }

        return min(1.0, score)
    }

    /// Filter questions by quality threshold
    func filterByQuality(_ imported: [ImportedQuestion], threshold: Double = 0.5) -> [ImportedQuestion] {
        imported.filter { qualityScore($0) >= threshold }
    }

    // MARK: - QuestionTransformer Protocol (Canonical Questions)

    /// Transform a canonical question to KB format.
    ///
    /// Uses the best available text form and maps domains/difficulty
    /// to KB-specific types.
    ///
    /// - Parameter canonical: Universal question format
    /// - Returns: KB-formatted question, or nil if incompatible
    func transform(_ canonical: CanonicalQuestion) -> KBQuestion? {
        guard isCompatible(canonical) else { return nil }

        // Map primary domain to KBDomain
        guard let firstDomain = canonical.domains.first,
              let domain = mapPrimaryDomain(firstDomain.primary) else {
            return nil
        }

        // Get best text form (prefer medium for KB)
        let text = canonical.content.mediumForm.isEmpty
            ? canonical.content.shortForm
            : canonical.content.mediumForm

        guard !text.isEmpty else { return nil }

        // Map difficulty
        let difficulty = mapCanonicalDifficulty(canonical.difficulty)

        // Determine suitability
        let suitability = KBSuitability(
            forWritten: true,
            forOral: !canonical.metadata.requiresCalculation,
            mcqPossible: canonical.transformationHints.mcqPossible,
            requiresVisual: canonical.transformationHints.requiresVisual
        )

        // Map answer
        let answer = KBAnswer(
            primary: canonical.answer.primary,
            acceptable: canonical.answer.acceptable,
            answerType: mapAnswerType(canonical.answer.answerType)
        )

        return KBQuestion(
            id: UUID(),
            text: text,
            answer: answer,
            domain: domain,
            subdomain: canonical.domains.first?.subdomain,
            difficulty: difficulty,
            gradeLevel: inferGradeLevel(from: difficulty),
            suitability: suitability,
            estimatedReadTime: canonical.transformationHints.estimatedReadTime,
            mcqOptions: canonical.transformationHints.suggestedDistractors,
            source: canonical.metadata.source,
            sourceAttribution: canonical.metadata.attribution
        )
    }

    /// Transform a KB question back to canonical format.
    ///
    /// Enables KB-created questions to be shared with other modules.
    ///
    /// - Parameter question: KB-formatted question
    /// - Returns: Canonical question format
    func canonicalize(_ question: KBQuestion) -> CanonicalQuestion {
        let content = QuestionContent(
            pyramidalFull: "", // KB doesn't have pyramidal form
            mediumForm: question.text,
            shortForm: question.text
        )

        let answer = AnswerSpec(
            primary: question.answer.primary,
            acceptable: question.answer.acceptable,
            answerType: mapKBAnswerType(question.answer.answerType)
        )

        let metadata = QuestionMetadata(
            source: question.source,
            attribution: question.sourceAttribution,
            requiresCalculation: !question.suitability.forOral,
            hasFormula: question.suitability.requiresVisual
        )

        let domains = [DomainTag(
            primary: mapKBDomainToPrimary(question.domain),
            subdomain: question.subdomain
        )]

        let difficulty = DifficultyRating(
            absoluteLevel: mapKBDifficultyToAbsolute(question.difficulty),
            competitionRelative: [
                .knowledgeBowl: RelativeDifficulty(
                    tier: mapKBDifficultyToTier(question.difficulty)
                )
            ]
        )

        let hints = TransformationHints(
            mcqPossible: question.suitability.mcqPossible,
            suggestedDistractors: question.mcqOptions,
            requiresVisual: question.suitability.requiresVisual,
            estimatedReadTime: question.estimatedReadTime
        )

        return CanonicalQuestion(
            id: UUID(),
            version: 1,
            content: content,
            answer: answer,
            metadata: metadata,
            domains: domains,
            difficulty: difficulty,
            compatibleFormats: [.knowledgeBowl],
            transformationHints: hints
        )
    }

    /// Check if a canonical question is compatible with KB format.
    func isCompatible(_ canonical: CanonicalQuestion) -> Bool {
        // Must have some text content
        guard !canonical.content.mediumForm.isEmpty ||
              !canonical.content.shortForm.isEmpty else {
            return false
        }

        // Must have at least one domain we can map
        guard let firstDomain = canonical.domains.first,
              mapPrimaryDomain(firstDomain.primary) != nil else {
            return false
        }

        return true
    }

    /// Calculate quality score for a canonical question in KB context.
    func qualityScore(_ canonical: CanonicalQuestion) -> Double {
        var score = 0.5

        // Prefer questions with medium form (ideal length for KB)
        if !canonical.content.mediumForm.isEmpty {
            score += 0.2
        }

        // Prefer questions that can be MCQ
        if canonical.transformationHints.mcqPossible {
            score += 0.1
        }

        // Prefer questions without complex formulas (voice-friendly)
        if !canonical.metadata.hasFormula {
            score += 0.1
        }

        // Prefer questions with acceptable alternatives
        if let acceptable = canonical.answer.acceptable, !acceptable.isEmpty {
            score += 0.05
        }

        // Domain weighting (some domains more common in KB)
        let kbCommonDomains: Set<PrimaryDomain> = [
            .literature, .history, .socialStudies, .science, .currentEvents
        ]
        if let firstDomain = canonical.domains.first,
           kbCommonDomains.contains(firstDomain.primary) {
            score += 0.05
        }

        return min(1.0, score)
    }

    // MARK: - Canonical Mapping Helpers

    private func mapPrimaryDomain(_ primary: PrimaryDomain) -> KBDomain? {
        switch primary {
        case .science: return .science
        case .mathematics: return .mathematics
        case .literature: return .literature
        case .history: return .history
        case .socialStudies: return .socialStudies
        case .arts: return .arts
        case .currentEvents: return .currentEvents
        case .language: return .language
        case .technology: return .technology
        case .popCulture: return .popCulture
        case .religionPhilosophy: return .religionPhilosophy
        case .miscellaneous: return .miscellaneous
        }
    }

    private func mapKBDomainToPrimary(_ domain: KBDomain) -> PrimaryDomain {
        switch domain {
        case .science: return .science
        case .mathematics: return .mathematics
        case .literature: return .literature
        case .history: return .history
        case .socialStudies: return .socialStudies
        case .arts: return .arts
        case .currentEvents: return .currentEvents
        case .language: return .language
        case .technology: return .technology
        case .popCulture: return .popCulture
        case .religionPhilosophy: return .religionPhilosophy
        case .miscellaneous: return .miscellaneous
        }
    }

    private func mapCanonicalDifficulty(_ difficulty: DifficultyRating) -> KBDifficulty {
        // Check for KB-specific difficulty first
        if let kbRelative = difficulty.competitionRelative?[.knowledgeBowl] {
            return mapTierToKBDifficulty(kbRelative.tier)
        }

        // Fall back to absolute level
        switch difficulty.absoluteLevel {
        case 1: return .overview
        case 2: return .foundational
        case 3: return .intermediate
        case 4: return .varsity
        case 5: return .championship
        case 6: return .research
        default: return .varsity
        }
    }

    private func mapTierToKBDifficulty(_ tier: DifficultyTier) -> KBDifficulty {
        switch tier {
        case .novice: return .foundational
        case .competent: return .intermediate
        case .varsity: return .varsity
        case .championship: return .championship
        }
    }

    private func mapKBDifficultyToAbsolute(_ difficulty: KBDifficulty) -> Int {
        switch difficulty {
        case .overview: return 1
        case .foundational: return 2
        case .intermediate: return 3
        case .varsity: return 4
        case .championship: return 5
        case .research: return 6
        }
    }

    private func mapKBDifficultyToTier(_ difficulty: KBDifficulty) -> DifficultyTier {
        switch difficulty {
        case .overview, .foundational: return .novice
        case .intermediate: return .competent
        case .varsity: return .varsity
        case .championship, .research: return .championship
        }
    }

    private func mapAnswerType(_ type: AnswerType) -> KBAnswerType {
        switch type {
        case .text: return .text
        case .person: return .person
        case .place: return .place
        case .number: return .number
        case .date: return .date
        case .title: return .title
        case .scientific: return .scientific
        case .thing: return .text
        }
    }

    private func mapKBAnswerType(_ type: KBAnswerType) -> AnswerType {
        switch type {
        case .text: return .text
        case .person: return .person
        case .place: return .place
        case .number: return .number
        case .date: return .date
        case .title: return .title
        case .scientific: return .scientific
        case .multipleChoice: return .text
        }
    }

    private func inferGradeLevel(from difficulty: KBDifficulty) -> KBGradeLevel {
        switch difficulty {
        case .overview, .foundational, .intermediate:
            return .middleSchool
        case .varsity, .championship:
            return .highSchool
        case .research:
            return .advanced
        }
    }
}

// MARK: - Legacy Suitability (Deprecated)

/// Type alias for backwards compatibility.
/// Use `KBSuitability` from `KBQuestion.swift` for new code.
@available(*, deprecated, renamed: "KBSuitability", message: "Use KBSuitability from KBQuestion.swift")
typealias KBQuestionSuitability = KBSuitability

// MARK: - Import Helpers

extension KBTransformer {
    /// Load questions from JSON file
    static func loadFromJSON(fileURL: URL) throws -> [ImportedQuestion] {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct ImportWrapper: Codable {
            let questions: [ImportedQuestion]
        }

        let wrapper = try decoder.decode(ImportWrapper.self, from: data)
        return wrapper.questions
    }

    /// Transform and save questions to KB format
    static func importAndSave(from fileURL: URL, to outputURL: URL) throws -> Int {
        let transformer = KBTransformer()

        // Load imported questions
        let imported = try loadFromJSON(fileURL: fileURL)
        print("[KBTransformer] Loaded \(imported.count) questions from \(fileURL.lastPathComponent)")

        // Filter by quality
        let filtered = transformer.filterByQuality(imported, threshold: 0.5)
        print("[KBTransformer] Filtered to \(filtered.count) quality questions")

        // Transform to KB format
        let kbQuestions = transformer.transformBatch(filtered)
        print("[KBTransformer] Transformed \(kbQuestions.count) questions to KB format")

        // Save to output file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        struct OutputWrapper: Codable {
            let questions: [KBQuestion]
            let metadata: ImportMetadata
        }

        struct ImportMetadata: Codable {
            let importDate: Date
            let sourceFile: String
            let totalImported: Int
            let qualityFiltered: Int
            let successfullyTransformed: Int
        }

        let output = OutputWrapper(
            questions: kbQuestions,
            metadata: ImportMetadata(
                importDate: Date(),
                sourceFile: fileURL.lastPathComponent,
                totalImported: imported.count,
                qualityFiltered: filtered.count,
                successfullyTransformed: kbQuestions.count
            )
        )

        let outputData = try encoder.encode(output)
        try outputData.write(to: outputURL, options: [.atomic])

        return kbQuestions.count
    }
}
