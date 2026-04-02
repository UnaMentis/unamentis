// UnaMentis - Curriculum Models
// Supporting types for the Curriculum Management System
//
// Part of Curriculum Layer (TDD Section 4)

import Foundation
import CoreData

// MARK: - Content Depth

/// Depth level for curriculum content, defining coverage expectations
public enum ContentDepth: String, Codable, Sendable, CaseIterable {
    case overview = "overview"              // Brief introduction, 2-5 minutes
    case introductory = "introductory"      // Basic concepts, 5-15 minutes
    case intermediate = "intermediate"      // Moderate detail, 15-30 minutes
    case advanced = "advanced"              // In-depth coverage, 30-60 minutes
    case graduate = "graduate"              // Comprehensive, 60+ minutes
    case research = "research"              // Research-level depth, extended

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .introductory: return "Introductory"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .graduate: return "Graduate Level"
        case .research: return "Research Level"
        }
    }

    /// Brief description of expectations at this level
    public var description: String {
        switch self {
        case .overview:
            return "Brief introduction covering key concepts only"
        case .introductory:
            return "Basic understanding, suitable for beginners"
        case .intermediate:
            return "Solid coverage with examples and applications"
        case .advanced:
            return "In-depth exploration with theoretical foundations"
        case .graduate:
            return "Comprehensive treatment with mathematical rigor"
        case .research:
            return "Research-level depth with current literature"
        }
    }

    /// Expected lecture duration range in minutes
    public var expectedDurationRange: ClosedRange<Int> {
        switch self {
        case .overview: return 2...5
        case .introductory: return 5...15
        case .intermediate: return 15...30
        case .advanced: return 30...60
        case .graduate: return 60...120
        case .research: return 90...180
        }
    }

    /// Whether to include mathematical derivations
    public var includeMathDerivations: Bool {
        switch self {
        case .overview, .introductory: return false
        case .intermediate: return false  // Just mention, don't derive
        case .advanced, .graduate, .research: return true
        }
    }

    /// How to present mathematical content for audio
    public var mathPresentationStyle: String {
        switch self {
        case .overview:
            return "Skip mathematical formulas entirely. Focus on intuition."
        case .introductory:
            return "Mention that formulas exist but describe their meaning in words."
        case .intermediate:
            return "Describe key equations verbally. Say 'x squared' not 'x^2'."
        case .advanced:
            return "Present equations verbally with full verbal notation. Derive important results step by step."
        case .graduate:
            return "Full mathematical rigor. Present all derivations verbally. Spell out each step clearly."
        case .research:
            return "Complete proofs and derivations. Reference key papers and theorems by name."
        }
    }

    /// Instructions for AI regarding depth
    public var aiInstructions: String {
        switch self {
        case .overview:
            return """
            Provide a brief overview only. Cover:
            - What this topic is about in 1-2 sentences
            - Why it matters
            - Key takeaways (3-5 bullet points spoken as a list)
            Keep it under 5 minutes. No technical details.
            """
        case .introductory:
            return """
            Provide an introductory explanation suitable for someone new to the topic:
            - Start with what the topic is and why it's important
            - Explain fundamental concepts with simple examples
            - Use analogies to make abstract ideas concrete
            - Avoid jargon or define it when first used
            Keep it accessible. Target 5-15 minutes.
            """
        case .intermediate:
            return """
            Provide a solid intermediate-level explanation:
            - Assume basic familiarity with the field
            - Cover key concepts in reasonable depth
            - Include practical examples and applications
            - Explain how concepts connect to each other
            - Mention relevant formulas by describing what they represent
            Target 15-30 minutes.
            """
        case .advanced:
            return """
            Provide an advanced-level treatment:
            - Assume solid foundational knowledge
            - Explore theoretical underpinnings
            - Present mathematical relationships verbally
            - Discuss edge cases and limitations
            - Connect to related advanced topics
            - Include derivations of important results
            Target 30-60 minutes.
            """
        case .graduate:
            return """
            Provide a graduate-level lecture:
            - Assume strong mathematical and conceptual background
            - Present with full mathematical rigor
            - Derive all key results step by step, speaking each equation
            - Discuss assumptions, theorems, and proofs
            - Cover multiple perspectives and approaches
            - Reference foundational papers and researchers
            - Address subtleties and common misconceptions
            Target 60+ minutes of comprehensive coverage.
            """
        case .research:
            return """
            Provide research-level depth:
            - Assume expert-level background in the field
            - Cover state-of-the-art developments
            - Present complete proofs and derivations verbally
            - Discuss open problems and current research directions
            - Reference specific papers, authors, and dates
            - Compare and contrast competing theories
            - Address methodological considerations
            Extended coverage, potentially multiple sessions.
            """
        }
    }
}

// MARK: - Topic Status

/// Status of a topic in the learning progression
public enum TopicStatus: String, Codable, Sendable, CaseIterable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case completed = "completed"
    case reviewing = "reviewing"

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .reviewing: return "Reviewing"
        }
    }

    /// Accessibility-friendly description for VoiceOver
    public var accessibilityDescription: String {
        switch self {
        case .notStarted: return "not started"
        case .inProgress: return "in progress"
        case .completed: return "completed"
        case .reviewing: return "needs review"
        }
    }
}

// MARK: - Document Type

/// Type of document in the curriculum
public enum DocumentType: String, Codable, Sendable, CaseIterable {
    case pdf = "pdf"
    case text = "text"
    case markdown = "markdown"
    case transcript = "transcript"

    /// File extensions associated with this type
    public var fileExtensions: [String] {
        switch self {
        case .pdf: return ["pdf"]
        case .text: return ["txt"]
        case .markdown: return ["md", "markdown"]
        case .transcript: return ["json"]
        }
    }

    /// Detect type from file extension
    public static func from(fileExtension: String) -> DocumentType? {
        let ext = fileExtension.lowercased()
        for type in DocumentType.allCases {
            if type.fileExtensions.contains(ext) {
                return type
            }
        }
        return nil
    }
}

// MARK: - Visual Asset Type

/// Type of visual asset in curriculum content
/// Aligned with IMS Content Packaging and HTML5 media types
public enum VisualAssetType: String, Codable, Sendable, CaseIterable {
    case image = "image"              // Static images (PNG, JPEG, WebP)
    case diagram = "diagram"          // Architectural/flow diagrams (often SVG)
    case equation = "equation"        // Mathematical formulas (LaTeX/MathML)
    case formula = "formula"          // Enhanced formula with semantics (LaTeX)
    case chart = "chart"              // Data visualizations
    case map = "map"                  // Geographic/educational maps
    case slideImage = "slideImage"    // Single slide from a presentation
    case slideDeck = "slideDeck"      // Full presentation reference
    case generated = "generated"      // AI-generated on-demand visual

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .image: return "Image"
        case .diagram: return "Diagram"
        case .equation: return "Equation"
        case .formula: return "Formula"
        case .chart: return "Chart"
        case .map: return "Map"
        case .slideImage: return "Slide"
        case .slideDeck: return "Slide Deck"
        case .generated: return "Generated"
        }
    }

    /// SF Symbol icon for this type
    public var iconName: String {
        switch self {
        case .image: return "photo"
        case .diagram: return "flowchart"
        case .equation: return "function"
        case .formula: return "x.squareroot"
        case .chart: return "chart.bar"
        case .map: return "map"
        case .slideImage: return "rectangle.on.rectangle"
        case .slideDeck: return "doc.richtext"
        case .generated: return "sparkles"
        }
    }

    /// Supported MIME types for this visual type
    public var supportedMimeTypes: [String] {
        switch self {
        case .image:
            return ["image/png", "image/jpeg", "image/webp", "image/gif"]
        case .diagram:
            return ["image/svg+xml", "image/png", "image/webp"]
        case .equation, .formula:
            return ["text/latex", "application/mathml+xml", "image/png", "image/svg+xml"]
        case .chart:
            return ["image/svg+xml", "image/png", "application/json"]
        case .map:
            return ["image/png", "image/svg+xml", "text/html"]
        case .slideImage:
            return ["image/png", "image/jpeg", "image/webp"]
        case .slideDeck:
            return ["application/pdf", "application/vnd.ms-powerpoint", "application/vnd.openxmlformats-officedocument.presentationml.presentation"]
        case .generated:
            return ["image/png", "image/webp"]
        }
    }
}

// MARK: - Visual Display Mode

/// How a visual asset is displayed during curriculum playback
public enum VisualDisplayMode: String, Codable, Sendable, CaseIterable {
    case persistent = "persistent"    // Visual stays on screen for entire segment range
    case highlight = "highlight"      // Visual appears prominently, then fades to thumbnail
    case popup = "popup"              // Visual appears as dismissible overlay
    case inline = "inline"            // Visual embedded in transcript text flow

    /// Human-readable description
    public var description: String {
        switch self {
        case .persistent: return "Stays visible throughout the segment"
        case .highlight: return "Appears prominently, then becomes a thumbnail"
        case .popup: return "Appears as an overlay that can be dismissed"
        case .inline: return "Displayed inline with the transcript text"
        }
    }
}

// MARK: - Checkpoint Type

/// Type of interactive checkpoint during tutoring
/// Source: UMCF Specification 1.1.0
public enum CheckpointType: String, Codable, Sendable, CaseIterable {
    case simpleConfirmation = "simple_confirmation"  // Quick "does that make sense?" check
    case comprehensionCheck = "comprehension_check"  // Verify basic understanding
    case knowledgeCheck = "knowledge_check"          // Test recall of facts
    case applicationCheck = "application_check"      // Verify ability to apply concept
    case teachback = "teachback"                     // Have learner explain in own words

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .simpleConfirmation: return "Quick Confirmation"
        case .comprehensionCheck: return "Comprehension Check"
        case .knowledgeCheck: return "Knowledge Check"
        case .applicationCheck: return "Application Check"
        case .teachback: return "Teach Back"
        }
    }

    /// Description of the evaluation approach
    public var evaluationApproach: String {
        switch self {
        case .simpleConfirmation: return "Accept acknowledgment"
        case .comprehensionCheck: return "Pattern matching on response"
        case .knowledgeCheck: return "Match against expected answers"
        case .applicationCheck: return "Evaluate worked example"
        case .teachback: return "AI evaluates depth and accuracy of explanation"
        }
    }

    /// Whether this checkpoint type requires LLM evaluation
    public var requiresLLMEvaluation: Bool {
        switch self {
        case .simpleConfirmation: return false
        case .comprehensionCheck: return false
        case .knowledgeCheck: return false
        case .applicationCheck: return true
        case .teachback: return true
        }
    }
}

// MARK: - Teachback Evaluation Result

/// Result of evaluating a teachback response
public struct TeachbackResult: Codable, Sendable {
    /// Overall score from 0.0 to 1.0
    public let score: Double

    /// Score tier: excellent, good, partial, struggling
    public let tier: TeachbackTier

    /// Concepts correctly mentioned
    public let correctConcepts: [String]

    /// Concepts missed in the explanation
    public let missedConcepts: [String]

    /// Bonus concepts mentioned
    public let bonusConcepts: [String]

    /// Feedback to give the learner
    public let feedback: String

    /// Recommended next action
    public let nextAction: TeachbackNextAction

    /// Time spent thinking before responding (seconds)
    public let thinkTime: TimeInterval

    public init(
        score: Double,
        tier: TeachbackTier,
        correctConcepts: [String],
        missedConcepts: [String],
        bonusConcepts: [String],
        feedback: String,
        nextAction: TeachbackNextAction,
        thinkTime: TimeInterval
    ) {
        self.score = score
        self.tier = tier
        self.correctConcepts = correctConcepts
        self.missedConcepts = missedConcepts
        self.bonusConcepts = bonusConcepts
        self.feedback = feedback
        self.nextAction = nextAction
        self.thinkTime = thinkTime
    }
}

/// Tier classification for teachback results
public enum TeachbackTier: String, Codable, Sendable, CaseIterable {
    case excellent = "excellent"    // Score >= 0.9
    case good = "good"              // Score >= 0.7
    case partial = "partial"        // Score >= 0.4
    case struggling = "struggling"  // Score < 0.4

    /// Threshold score for this tier
    public var threshold: Double {
        switch self {
        case .excellent: return 0.9
        case .good: return 0.7
        case .partial: return 0.4
        case .struggling: return 0.0
        }
    }

    /// Create tier from score
    public static func from(score: Double) -> TeachbackTier {
        if score >= 0.9 { return .excellent }
        if score >= 0.7 { return .good }
        if score >= 0.4 { return .partial }
        return .struggling
    }
}

/// Next action after teachback evaluation
public enum TeachbackNextAction: String, Codable, Sendable, CaseIterable {
    case continueProgress = "continue"      // Move forward
    case supplement = "supplement"          // Add clarification, then continue
    case guidedReview = "guided_review"     // Work through concept together
    case reteach = "reteach"                // Explain differently from scratch
}

// MARK: - Spaced Retrieval

/// Configuration for spaced retrieval of a key concept
public struct RetrievalConfig: Codable, Sendable {
    /// Difficulty level for retrieval
    public let difficulty: RetrievalDifficulty

    /// Questions to ask during retrieval checks
    public let retrievalPrompts: [String]

    /// Target retention rate (0.0 to 1.0)
    public let minimumRetention: Double

    /// Spacing algorithm to use
    public let spacingAlgorithm: SpacingAlgorithm

    /// Initial interval after learning
    public let initialInterval: TimeInterval

    /// Maximum interval between retrievals
    public let maxInterval: TimeInterval

    public init(
        difficulty: RetrievalDifficulty = .medium,
        retrievalPrompts: [String],
        minimumRetention: Double = 0.8,
        spacingAlgorithm: SpacingAlgorithm = .leitner,
        initialInterval: TimeInterval = 86400, // 1 day
        maxInterval: TimeInterval = 2592000    // 30 days
    ) {
        self.difficulty = difficulty
        self.retrievalPrompts = retrievalPrompts
        self.minimumRetention = minimumRetention
        self.spacingAlgorithm = spacingAlgorithm
        self.initialInterval = initialInterval
        self.maxInterval = maxInterval
    }
}

/// Difficulty level for retrieval
public enum RetrievalDifficulty: String, Codable, Sendable, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"

    /// Adjustment factor for spacing intervals
    public var intervalFactor: Double {
        switch self {
        case .easy: return 1.3
        case .medium: return 1.0
        case .hard: return 0.7
        }
    }
}

/// Spacing algorithm for retrieval scheduling
public enum SpacingAlgorithm: String, Codable, Sendable, CaseIterable {
    case leitner = "leitner"  // Box-based system
    case sm2 = "sm2"          // SuperMemo 2 algorithm
    case custom = "custom"    // Application-specific

    /// Human-readable description
    public var description: String {
        switch self {
        case .leitner: return "Box-based: success increases interval, failure resets"
        case .sm2: return "SuperMemo 2 algorithm with easiness factor"
        case .custom: return "Custom application-specific logic"
        }
    }
}

/// Tracking state for a single concept's retrieval schedule
public struct RetrievalSchedule: Codable, Sendable, Identifiable {
    public let id: UUID
    public let conceptId: UUID
    public let conceptTitle: String
    public var nextRetrievalDate: Date
    public var currentInterval: TimeInterval
    public var successCount: Int
    public var attemptCount: Int
    public var easinessFactor: Double  // For SM2 algorithm
    public var leitnerBox: Int         // For Leitner system (1-5)

    /// Success rate as a percentage
    public var successRate: Double {
        guard attemptCount > 0 else { return 0.0 }
        return Double(successCount) / Double(attemptCount)
    }

    /// Whether a retrieval is due
    public var isDue: Bool {
        Date() >= nextRetrievalDate
    }

    public init(
        id: UUID = UUID(),
        conceptId: UUID,
        conceptTitle: String,
        nextRetrievalDate: Date = Date().addingTimeInterval(86400),
        currentInterval: TimeInterval = 86400,
        successCount: Int = 0,
        attemptCount: Int = 0,
        easinessFactor: Double = 2.5,
        leitnerBox: Int = 1
    ) {
        self.id = id
        self.conceptId = conceptId
        self.conceptTitle = conceptTitle
        self.nextRetrievalDate = nextRetrievalDate
        self.currentInterval = currentInterval
        self.successCount = successCount
        self.attemptCount = attemptCount
        self.easinessFactor = easinessFactor
        self.leitnerBox = leitnerBox
    }

    /// Update schedule after a retrieval attempt
    /// - Parameters:
    ///   - success: Whether the attempt was successful
    ///   - algorithm: Which spacing algorithm to use
    ///   - maxInterval: Maximum interval cap
    ///   - quality: SM2 quality rating (0-5). Defaults to 4 for success if not provided. Ignored on failure (fixed -0.2 EF penalty).
    public mutating func recordAttempt(success: Bool, algorithm: SpacingAlgorithm, maxInterval: TimeInterval, quality: Double? = nil) {
        attemptCount += 1
        if success {
            successCount += 1
        }

        switch algorithm {
        case .leitner:
            updateLeitner(success: success, maxInterval: maxInterval)
        case .sm2:
            updateSM2(success: success, maxInterval: maxInterval, quality: quality)
        case .custom:
            // Custom logic handled externally
            break
        }
    }

    private mutating func updateLeitner(success: Bool, maxInterval: TimeInterval) {
        if success {
            leitnerBox = min(leitnerBox + 1, 5)
        } else {
            leitnerBox = 1 // Reset to first box
        }

        // Interval doubles with each box: 1d, 2d, 4d, 8d, 16d
        let baseInterval: TimeInterval = 86400 // 1 day
        currentInterval = min(baseInterval * pow(2.0, Double(leitnerBox - 1)), maxInterval)
        nextRetrievalDate = Date().addingTimeInterval(currentInterval)
    }

    /// Update using SM2 algorithm. Quality should be 0-5: 0=complete failure, 3=correct with difficulty, 5=perfect.
    /// If not provided, defaults to 4 for success and 2 for failure.
    private mutating func updateSM2(success: Bool, maxInterval: TimeInterval, quality: Double? = nil) {
        if success {
            // SuperMemo 2 formula for easiness factor
            // EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
            let q = quality ?? 4.0
            let efDelta = 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)
            easinessFactor = max(1.3, easinessFactor + efDelta)

            if attemptCount == 1 {
                currentInterval = 86400 // 1 day
            } else if attemptCount == 2 {
                currentInterval = 6 * 86400 // 6 days
            } else {
                currentInterval = min(currentInterval * easinessFactor, maxInterval)
            }
        } else {
            // Failed: reset to 1 day, reduce easiness
            currentInterval = 86400
            easinessFactor = max(1.3, easinessFactor - 0.2)
        }

        nextRetrievalDate = Date().addingTimeInterval(currentInterval)
    }
}

// MARK: - Productive Struggle Metrics

/// Metrics for tracking productive struggle in a learning session
public struct ProductiveStruggleMetrics: Codable, Sendable {
    /// Total think time before responding (seconds)
    public var totalThinkTime: TimeInterval

    /// Number of teachback attempts
    public var teachbackAttempts: Int

    /// Number of successful teachbacks
    public var teachbackSuccesses: Int

    /// Number of times learner asked for clarification
    public var clarificationRequests: Int

    /// Number of times learner asked for repetition
    public var repetitionRequests: Int

    /// Average think time per concept (seconds)
    public var averageThinkTimePerConcept: TimeInterval {
        guard teachbackAttempts > 0 else { return 0 }
        return totalThinkTime / Double(teachbackAttempts)
    }

    /// Teachback success rate
    public var teachbackSuccessRate: Double {
        guard teachbackAttempts > 0 else { return 0 }
        return Double(teachbackSuccesses) / Double(teachbackAttempts)
    }

    /// Encouragement message based on metrics
    public var encouragementMessage: String? {
        if totalThinkTime > 180 { // 3+ minutes of thinking
            return "You invested \(Int(totalThinkTime / 60)) minutes of deep thinking. That's how real learning happens."
        } else if teachbackSuccessRate >= 0.8 {
            return "Excellent explanations! You're really grasping these concepts."
        } else if teachbackAttempts >= 3 && teachbackSuccessRate >= 0.5 {
            return "Good effort working through these explanations. Each attempt strengthens your understanding."
        }
        return nil
    }

    public init(
        totalThinkTime: TimeInterval = 0,
        teachbackAttempts: Int = 0,
        teachbackSuccesses: Int = 0,
        clarificationRequests: Int = 0,
        repetitionRequests: Int = 0
    ) {
        self.totalThinkTime = totalThinkTime
        self.teachbackAttempts = teachbackAttempts
        self.teachbackSuccesses = teachbackSuccesses
        self.clarificationRequests = clarificationRequests
        self.repetitionRequests = repetitionRequests
    }

    /// Record a think time period
    public mutating func recordThinkTime(_ duration: TimeInterval) {
        totalThinkTime += duration
    }

    /// Record a teachback attempt
    public mutating func recordTeachbackAttempt(success: Bool) {
        teachbackAttempts += 1
        if success {
            teachbackSuccesses += 1
        }
    }
}

// MARK: - Document Chunk

/// A chunk of document text with embedding for semantic search
public struct DocumentChunk: Codable, Sendable, Identifiable {
    /// Unique identifier for this chunk
    public let id: UUID

    /// ID of the source document
    public let documentId: UUID

    /// Text content of this chunk
    public let text: String

    /// Vector embedding for semantic search
    public let embedding: [Float]

    /// Page number if from PDF (1-indexed)
    public let pageNumber: Int?

    /// Index of this chunk within the document (0-indexed)
    public let chunkIndex: Int

    public init(
        id: UUID = UUID(),
        documentId: UUID,
        text: String,
        embedding: [Float],
        pageNumber: Int? = nil,
        chunkIndex: Int
    ) {
        self.id = id
        self.documentId = documentId
        self.text = text
        self.embedding = embedding
        self.pageNumber = pageNumber
        self.chunkIndex = chunkIndex
    }
}

// MARK: - Learning Objective

/// A learning objective for a topic
public struct LearningObjective: Codable, Sendable, Identifiable {
    /// Unique identifier
    public let id: UUID

    /// Description of the objective
    public let description: String

    /// Whether the objective has been met
    public var isMet: Bool

    /// Evidence of meeting the objective (e.g., transcript excerpts)
    public var evidence: [String]?

    public init(
        id: UUID = UUID(),
        description: String,
        isMet: Bool = false,
        evidence: [String]? = nil
    ) {
        self.id = id
        self.description = description
        self.isMet = isMet
        self.evidence = evidence
    }
}

// MARK: - Transcript Turn

/// A single turn in a conversation transcript
public struct TranscriptTurn: Codable, Sendable {
    /// Speaker identifier ("user" or "assistant")
    public let speaker: String

    /// Transcribed text
    public let transcript: String

    /// Timestamp
    public let timestamp: Date

    public init(speaker: String, transcript: String, timestamp: Date = Date()) {
        self.speaker = speaker
        self.transcript = transcript
        self.timestamp = timestamp
    }
}

// MARK: - Curriculum Error

/// Errors that can occur in curriculum operations
public enum CurriculumError: Error, Sendable {
    case curriculumNotFound(UUID)
    case topicNotFound(UUID)
    case documentNotFound(UUID)
    case progressNotFound(UUID)
    case invalidTopicOrder
    case saveFailed(String)
    case loadFailed(String)
    case contextGenerationFailed(String)
}

extension CurriculumError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .curriculumNotFound(let id):
            return "Curriculum not found: \(id)"
        case .topicNotFound(let id):
            return "Topic not found: \(id)"
        case .documentNotFound(let id):
            return "Document not found: \(id)"
        case .progressNotFound(let id):
            return "Progress not found for topic: \(id)"
        case .invalidTopicOrder:
            return "Invalid topic order"
        case .saveFailed(let message):
            return "Failed to save: \(message)"
        case .loadFailed(let message):
            return "Failed to load: \(message)"
        case .contextGenerationFailed(let message):
            return "Failed to generate context: \(message)"
        }
    }
}

// MARK: - Document Error

/// Errors that can occur during document processing
public enum DocumentError: Error, Sendable {
    case unsupportedType(String)
    case fileNotFound(URL)
    case pdfLoadFailed(URL)
    case extractionFailed(String)
    case encodingFailed
    case embeddingFailed(String)
    case summaryGenerationFailed(String)
}

extension DocumentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let type):
            return "Unsupported document type: \(type)"
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .pdfLoadFailed(let url):
            return "Failed to load PDF: \(url.lastPathComponent)"
        case .extractionFailed(let message):
            return "Text extraction failed: \(message)"
        case .encodingFailed:
            return "Failed to encode document data"
        case .embeddingFailed(let message):
            return "Embedding generation failed: \(message)"
        case .summaryGenerationFailed(let message):
            return "Summary generation failed: \(message)"
        }
    }
}

// MARK: - Embedding Service Protocol

/// Protocol for embedding generation services
public protocol EmbeddingService: Actor {
    /// Generate embeddings for text
    /// - Parameter text: Text to embed
    /// - Returns: Vector embedding as array of floats
    func embed(text: String) async -> [Float]

    /// Embedding dimension (e.g., 1536 for OpenAI ada-002)
    var embeddingDimension: Int { get }
}

// MARK: - Cosine Similarity

/// Calculate cosine similarity between two vectors
/// - Parameters:
///   - a: First vector
///   - b: Second vector
/// - Returns: Similarity score between -1 and 1
public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }

    let dotProduct = zip(a, b).reduce(Float(0)) { $0 + ($1.0 * $1.1) }
    let magnitudeA = sqrt(a.reduce(Float(0)) { $0 + ($1 * $1) })
    let magnitudeB = sqrt(b.reduce(Float(0)) { $0 + ($1 * $1) })

    guard magnitudeA > 0, magnitudeB > 0 else { return 0 }

    return dotProduct / (magnitudeA * magnitudeB)
}

// MARK: - Core Data Extensions

extension Topic {
    /// Get the topic status from progress
    public var status: TopicStatus {
        guard let progress = progress else {
            return .notStarted
        }

        // If we have time spent and mastery > 0.8, consider completed
        if mastery >= 0.8 && progress.timeSpent > 0 {
            return .completed
        }

        // If we have time spent, in progress
        if progress.timeSpent > 0 {
            return .inProgress
        }

        return .notStarted
    }

    /// Get objectives as typed array
    public var learningObjectives: [String] {
        objectives ?? []
    }

    /// Get documents as typed set
    public var documentSet: Set<Document> {
        documents as? Set<Document> ?? []
    }

    /// Get visual assets as typed set
    public var visualAssetSet: Set<VisualAsset> {
        visualAssets as? Set<VisualAsset> ?? []
    }

    /// Get embedded visual assets (non-reference, shown during playback)
    public var embeddedVisualAssets: [VisualAsset] {
        visualAssetSet.filter { !$0.isReference }.sorted { $0.startSegment < $1.startSegment }
    }

    /// Get reference visual assets (user-requestable)
    public var referenceVisualAssets: [VisualAsset] {
        visualAssetSet.filter { $0.isReference }.sorted { ($0.title ?? "") < ($1.title ?? "") }
    }

    /// Get visual assets active for a specific segment index
    public func visualAssetsForSegment(_ segmentIndex: Int) -> [VisualAsset] {
        embeddedVisualAssets.filter { $0.isActiveForSegment(segmentIndex) }
    }

    /// Search reference assets matching a query (for barge-in requests)
    public func findReferenceAssets(matching query: String) -> [VisualAsset] {
        referenceVisualAssets.filter { $0.matchesQuery(query) }
    }
}

extension Document {
    /// Get the document type enum
    public var documentType: DocumentType {
        DocumentType(rawValue: type ?? "text") ?? .text
    }

    /// Get decoded document chunks from embedding data
    public func decodedChunks() -> [DocumentChunk]? {
        guard let data = embedding else { return nil }
        return try? JSONDecoder().decode([DocumentChunk].self, from: data)
    }
}
