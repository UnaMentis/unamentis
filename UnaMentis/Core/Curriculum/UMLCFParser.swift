// UnaMentis - UMLCF Parser
// Converts Una Mentis Learning Curriculum Format (UMLCF) JSON to Core Data models
//
// Part of Curriculum Layer (TDD Section 4)

import Foundation
import CoreData

// MARK: - UMLCF Data Transfer Objects

/// Root UMLCF document structure
public struct UMLCFDocument: Codable, Sendable {
    public let umlcf: String
    public let id: UMLCFIdentifier
    public let title: String
    public let description: String?
    public let version: UMLCFVersionInfo
    public let lifecycle: UMLCFLifecycle?
    public let metadata: UMLCFMetadata?
    public let educational: UMLCFEducationalContext?
    public let content: [UMLCFContentNode]
    public let glossary: UMLCFGlossary?

    enum CodingKeys: String, CodingKey {
        case umlcf, id, title, description, version, lifecycle, metadata, educational, content, glossary
    }
}

/// Flexible identifier that can decode from either a simple string or an object with catalog/value
public struct UMLCFIdentifier: Codable, Sendable {
    public let catalog: String?
    public let value: String

    public init(catalog: String? = nil, value: String) {
        self.catalog = catalog
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        // Try to decode as a simple string first
        if let container = try? decoder.singleValueContainer(),
           let stringValue = try? container.decode(String.self) {
            self.catalog = nil
            self.value = stringValue
            return
        }

        // Try to decode as an object with catalog and value
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.catalog = try container.decodeIfPresent(String.self, forKey: .catalog)
        self.value = try container.decode(String.self, forKey: .value)
    }

    enum CodingKeys: String, CodingKey {
        case catalog, value
    }
}

public struct UMLCFVersionInfo: Codable, Sendable {
    public let number: String
    public let date: String?
    public let changelog: String?
}

public struct UMLCFLifecycle: Codable, Sendable {
    public let status: String?
    public let contributors: [UMLCFContributor]?
    public let created: String?
    public let modified: String?
}

public struct UMLCFContributor: Codable, Sendable {
    public let name: String
    public let role: String
    public let organization: String?
}

public struct UMLCFMetadata: Codable, Sendable {
    public let language: String?
    public let keywords: [String]?
    public let subject: [String]?
    public let coverage: [String]?
}

public struct UMLCFEducationalContext: Codable, Sendable {
    // Server-provided fields
    public let interactivityType: String?
    public let interactivityLevel: String?
    public let learningResourceType: [String]?
    public let intendedEndUserRole: [String]?
    public let context: [String]?
    public let typicalAgeRange: String?
    public let difficulty: String?
    public let typicalLearningTime: String?
    public let educationalAlignment: [UMLCFEducationalAlignment]?
    public let audienceProfile: UMLCFAudienceProfile?

    // Legacy/alternative fields (for backwards compatibility)
    public let alignment: UMLCFAlignment?
    public let targetAudience: UMLCFTargetAudience?
    public let prerequisites: [UMLCFPrerequisite]?
    public let estimatedDuration: String?
}

public struct UMLCFEducationalAlignment: Codable, Sendable {
    public let alignmentType: String?
    public let educationalFramework: String?
    public let targetName: String?
    public let targetDescription: String?
}

public struct UMLCFAudienceProfile: Codable, Sendable {
    public let educationLevel: String?
    public let gradeLevel: String?
    public let prerequisites: [UMLCFPrerequisite]?
}

public struct UMLCFAlignment: Codable, Sendable {
    public let standards: [UMLCFStandard]?
    public let frameworks: [String]?
    public let gradeLevel: [String]?
}

public struct UMLCFStandard: Codable, Sendable {
    public let id: UMLCFIdentifier
    public let name: String
    public let description: String?
    public let url: String?
}

public struct UMLCFTargetAudience: Codable, Sendable {
    public let type: String?
    public let ageRange: UMLCFAgeRange?
    public let educationalRole: [String]?
    public let industry: [String]?
    public let skillLevel: String?
}

public struct UMLCFAgeRange: Codable, Sendable {
    public let minimum: Int?
    public let maximum: Int?
    public let typical: String?
}

public struct UMLCFPrerequisite: Codable, Sendable {
    public let id: UMLCFIdentifier?
    public let type: String?
    public let description: String?
    public let required: Bool?
}

public struct UMLCFContentNode: Codable, Sendable {
    public let id: UMLCFIdentifier
    public let title: String
    public let type: String
    public let orderIndex: Int?
    public let description: String?
    public let learningObjectives: [UMLCFLearningObjective]?
    public let timeEstimates: UMLCFTimeEstimates?
    public let transcript: UMLCFTranscript?
    public let examples: [UMLCFExample]?
    public let assessments: [UMLCFAssessment]?
    public let glossaryTerms: [UMLCFGlossaryTerm]?
    public let misconceptions: [UMLCFMisconception]?
    public let children: [UMLCFContentNode]?
    public let tutoringConfig: UMLCFTutoringConfig?
}

public struct UMLCFLearningObjective: Codable, Sendable {
    public let id: UMLCFIdentifier
    public let statement: String
    public let abbreviatedStatement: String?
    public let bloomsLevel: String?
}

public struct UMLCFTimeEstimates: Codable, Sendable {
    public let overview: String?
    public let introductory: String?
    public let intermediate: String?
    public let advanced: String?
    public let graduate: String?
    public let research: String?
}

public struct UMLCFTranscript: Codable, Sendable {
    public let segments: [UMLCFTranscriptSegment]?
    public let totalDuration: String?
    public let voiceProfile: UMLCFVoiceProfile?
}

public struct UMLCFTranscriptSegment: Codable, Sendable {
    public let id: String
    public let type: String
    public let content: String
    public let speakingNotes: UMLCFSpeakingNotes?
    public let checkpoint: UMLCFCheckpoint?
    public let stoppingPoint: UMLCFStoppingPoint?
    public let glossaryRefs: [String]?
    public let alternativeExplanations: [UMLCFAlternativeExplanation]?
}

public struct UMLCFSpeakingNotes: Codable, Sendable {
    public let pace: String?
    public let emphasis: [String]?
    public let pronunciation: [String: String]?
    public let emotionalTone: String?
    public let pauseAfter: String?
}

public struct UMLCFCheckpoint: Codable, Sendable {
    public let type: String?
    public let question: String?
    public let expectedResponse: UMLCFExpectedResponse?
    public let celebrationMessage: String?
}

public struct UMLCFExpectedResponse: Codable, Sendable {
    public let type: String?
    public let acceptablePatterns: [String]?
    public let keywords: [String]?
}

public struct UMLCFStoppingPoint: Codable, Sendable {
    public let type: String?
    public let promptForContinue: Bool?
    public let suggestedPrompt: String?
}

public struct UMLCFAlternativeExplanation: Codable, Sendable {
    public let style: String?
    public let content: String?
}

public struct UMLCFVoiceProfile: Codable, Sendable {
    public let tone: String?
    public let pace: String?
    public let accent: String?
}

public struct UMLCFExample: Codable, Sendable {
    public let id: UMLCFIdentifier
    public let type: String?
    public let title: String?
    public let content: String?
    public let explanation: String?
}

public struct UMLCFAssessment: Codable, Sendable {
    public let id: UMLCFIdentifier
    public let type: String?
    public let question: String?
    public let options: [UMLCFAssessmentOption]?
    public let correctAnswer: String?
    public let hint: String?
    public let feedback: UMLCFFeedback?
}

public struct UMLCFAssessmentOption: Codable, Sendable {
    public let id: String
    public let text: String
    public let isCorrect: Bool?
}

public struct UMLCFFeedback: Codable, Sendable {
    public let correct: String?
    public let incorrect: String?
    public let partial: String?
}

public struct UMLCFMisconception: Codable, Sendable {
    public let id: UMLCFIdentifier
    public let trigger: [String]?
    public let misconception: String?
    public let correction: String?
    public let explanation: String?
}

public struct UMLCFTutoringConfig: Codable, Sendable {
    public let contentDepth: String?
    public let interactionMode: String?
    public let checkpointFrequency: String?
    public let adaptationRules: [String: String]?
}

public struct UMLCFGlossary: Codable, Sendable {
    public let terms: [UMLCFGlossaryTerm]?
}

public struct UMLCFGlossaryTerm: Codable, Sendable {
    public let term: String
    public let definition: String?
    public let pronunciation: String?
    public let spokenDefinition: String?
    public let examples: [String]?
    public let relatedTerms: [String]?
    public let simpleDefinition: String?
}

// MARK: - UMLCF Parser

/// Parser for converting UMLCF JSON to Core Data models
public actor UMLCFParser {
    private let persistenceController: PersistenceController

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Parsing

    /// Parse UMLCF JSON data into a UMLCFDocument
    public func parse(data: Data) throws -> UMLCFDocument {
        let decoder = JSONDecoder()
        return try decoder.decode(UMLCFDocument.self, from: data)
    }

    /// Parse UMLCF JSON from URL
    public func parse(from url: URL) throws -> UMLCFDocument {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    // MARK: - Core Data Import

    /// Import a UMLCF document into Core Data
    /// - Parameters:
    ///   - document: Parsed UMLCF document
    ///   - replaceExisting: If true, replace existing curriculum with same ID
    /// - Returns: Created or updated Curriculum Core Data object
    @MainActor
    public func importToCoreData(
        document: UMLCFDocument,
        replaceExisting: Bool = true
    ) throws -> Curriculum {
        let context = persistenceController.container.viewContext

        // Check for existing curriculum with same ID
        let curriculumIdValue = document.id.value
        if replaceExisting {
            let fetchRequest: NSFetchRequest<Curriculum> = Curriculum.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", curriculumIdValue)

            if let existing = try? context.fetch(fetchRequest).first {
                // Delete existing and all related data
                context.delete(existing)
            }
        }

        // Create new Curriculum
        let curriculum = Curriculum(context: context)
        curriculum.id = UUID(uuidString: curriculumIdValue) ?? UUID()
        curriculum.sourceId = curriculumIdValue  // Store UMLCF ID for server sync
        curriculum.name = document.title
        curriculum.summary = document.description
        curriculum.createdAt = parseDate(document.lifecycle?.created) ?? Date()
        curriculum.updatedAt = parseDate(document.lifecycle?.modified) ?? Date()

        // Process content nodes to create topics
        var orderIndex: Int32 = 0
        for contentNode in document.content {
            orderIndex = createTopics(
                from: contentNode,
                curriculum: curriculum,
                context: context,
                startingIndex: orderIndex,
                glossary: document.glossary
            )
        }

        try context.save()
        return curriculum
    }

    /// Create topics from a content node and its children
    @MainActor
    private func createTopics(
        from node: UMLCFContentNode,
        curriculum: Curriculum,
        context: NSManagedObjectContext,
        startingIndex: Int32,
        glossary: UMLCFGlossary?,
        parentObjectives: [String]? = nil
    ) -> Int32 {
        var currentIndex = startingIndex

        // Only create Topic entities for topic-level content nodes
        if node.type == "topic" || node.type == "subtopic" || node.type == "lesson" {
            let topic = Topic(context: context)
            topic.id = UUID(uuidString: node.id.value) ?? UUID()
            topic.sourceId = node.id.value  // Store UMLCF ID for server sync
            topic.title = node.title
            topic.orderIndex = currentIndex
            topic.mastery = 0.0

            // Set outline from description
            topic.outline = node.description

            // Set depth level from tutoring config
            if let depthString = node.tutoringConfig?.contentDepth,
               let depth = ContentDepth(rawValue: depthString) {
                topic.depthLevel = depth
            } else {
                topic.depthLevel = .intermediate
            }

            // Set learning objectives
            var objectives: [String] = []
            if let nodeObjectives = node.learningObjectives {
                objectives = nodeObjectives.map { $0.statement }
            }
            if let parentObjectives = parentObjectives {
                objectives.append(contentsOf: parentObjectives)
            }
            if !objectives.isEmpty {
                topic.objectives = objectives
            }

            // Create a Document for the transcript if available
            if let transcript = node.transcript {
                let document = createTranscriptDocument(
                    for: topic,
                    transcript: transcript,
                    context: context
                )
                topic.addToDocuments(document)
            }

            // Link to curriculum
            curriculum.addToTopics(topic)

            currentIndex += 1
        }

        // Process children recursively
        if let children = node.children {
            // Collect parent objectives to pass down
            let nodeObjectives = node.learningObjectives?.map { $0.statement }

            for child in children {
                currentIndex = createTopics(
                    from: child,
                    curriculum: curriculum,
                    context: context,
                    startingIndex: currentIndex,
                    glossary: glossary,
                    parentObjectives: nodeObjectives
                )
            }
        }

        return currentIndex
    }

    /// Create a Document entity for a transcript
    @MainActor
    private func createTranscriptDocument(
        for topic: Topic,
        transcript: UMLCFTranscript,
        context: NSManagedObjectContext
    ) -> Document {
        let document = Document(context: context)
        document.id = UUID()
        document.title = "Transcript: \(topic.title ?? "Untitled")"
        document.type = DocumentType.transcript.rawValue

        // Convert transcript segments to content string
        let contentParts = transcript.segments?.map { segment -> String in
            var text = segment.content

            // Add segment metadata as prefix for parsing later
            text = "[\(segment.type.uppercased())] \(text)"

            // Add speaking notes if available
            if let notes = segment.speakingNotes {
                if let pace = notes.pace {
                    text += "\n[PACE: \(pace)]"
                }
                if let tone = notes.emotionalTone {
                    text += "\n[TONE: \(tone)]"
                }
            }

            return text
        } ?? []

        document.content = contentParts.joined(separator: "\n\n---\n\n")

        // Store raw transcript as JSON in embedding field for later use
        if let segments = transcript.segments {
            let transcriptData = TranscriptData(
                segments: segments.map { seg in
                    TranscriptData.Segment(
                        id: seg.id,
                        type: seg.type,
                        content: seg.content,
                        speakingNotes: seg.speakingNotes.map { notes in
                            TranscriptData.SpeakingNotes(
                                pace: notes.pace,
                                emotionalTone: notes.emotionalTone,
                                pauseAfter: notes.pauseAfter
                            )
                        },
                        checkpointQuestion: seg.checkpoint?.question,
                        stoppingPointType: seg.stoppingPoint?.type
                    )
                },
                totalDuration: transcript.totalDuration
            )

            if let jsonData = try? JSONEncoder().encode(transcriptData) {
                document.embedding = jsonData
            }
        }

        return document
    }

    // MARK: - Helpers

    nonisolated private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: dateString) {
            return date
        }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateString)
    }
}

// MARK: - Transcript Data Storage

/// Structured storage for transcript data
public struct TranscriptData: Codable, Sendable {
    public let segments: [Segment]
    public let totalDuration: String?

    public struct Segment: Codable, Sendable {
        public let id: String
        public let type: String
        public let content: String
        public let speakingNotes: SpeakingNotes?
        public let checkpointQuestion: String?
        public let stoppingPointType: String?
    }

    public struct SpeakingNotes: Codable, Sendable {
        public let pace: String?
        public let emotionalTone: String?
        public let pauseAfter: String?
    }
}

// MARK: - Document Extension for Transcript Access

extension Document {
    /// Decode transcript data from the embedding field
    public func decodedTranscript() -> TranscriptData? {
        guard let data = embedding, documentType == .transcript else { return nil }
        return try? JSONDecoder().decode(TranscriptData.self, from: data)
    }
}

// MARK: - Backward Compatibility Type Aliases

/// Type alias for backward compatibility with existing code
public typealias VLCFDocument = UMLCFDocument
public typealias VLCFParser = UMLCFParser
public typealias VLCFIdentifier = UMLCFIdentifier
public typealias VLCFVersionInfo = UMLCFVersionInfo
public typealias VLCFLifecycle = UMLCFLifecycle
public typealias VLCFContributor = UMLCFContributor
public typealias VLCFMetadata = UMLCFMetadata
public typealias VLCFEducationalContext = UMLCFEducationalContext
public typealias VLCFAlignment = UMLCFAlignment
public typealias VLCFStandard = UMLCFStandard
public typealias VLCFTargetAudience = UMLCFTargetAudience
public typealias VLCFAgeRange = UMLCFAgeRange
public typealias VLCFPrerequisite = UMLCFPrerequisite
public typealias VLCFContentNode = UMLCFContentNode
public typealias VLCFLearningObjective = UMLCFLearningObjective
public typealias VLCFTimeEstimates = UMLCFTimeEstimates
public typealias VLCFTranscript = UMLCFTranscript
public typealias VLCFTranscriptSegment = UMLCFTranscriptSegment
public typealias VLCFSpeakingNotes = UMLCFSpeakingNotes
public typealias VLCFCheckpoint = UMLCFCheckpoint
public typealias VLCFExpectedResponse = UMLCFExpectedResponse
public typealias VLCFStoppingPoint = UMLCFStoppingPoint
public typealias VLCFAlternativeExplanation = UMLCFAlternativeExplanation
public typealias VLCFVoiceProfile = UMLCFVoiceProfile
public typealias VLCFExample = UMLCFExample
public typealias VLCFAssessment = UMLCFAssessment
public typealias VLCFAssessmentOption = UMLCFAssessmentOption
public typealias VLCFFeedback = UMLCFFeedback
public typealias VLCFMisconception = UMLCFMisconception
public typealias VLCFTutoringConfig = UMLCFTutoringConfig
public typealias VLCFGlossary = UMLCFGlossary
public typealias VLCFGlossaryTerm = UMLCFGlossaryTerm
