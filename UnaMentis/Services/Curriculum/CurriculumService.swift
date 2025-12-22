// UnaMentis - Curriculum Service
// Network service for fetching UMLCF curricula from the management server
//
// Part of Curriculum Layer (TDD Section 4)

import Foundation
import CoreData

// MARK: - API Response Types

/// Summary of a curriculum (for listing)
public struct CurriculumSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let version: String
    public let topicCount: Int
    public let totalDuration: String?
    public let difficulty: String?
    public let ageRange: String?
    public let keywords: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, description, version
        case topicCount = "topic_count"
        case totalDuration = "total_duration"
        case difficulty
        case ageRange = "age_range"
        case keywords
    }
}

/// Detailed curriculum info with topics (for browsing)
public struct CurriculumDetail: Codable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let version: String
    public let difficulty: String?
    public let ageRange: String?
    public let duration: String?
    public let keywords: [String]
    public let topics: [TopicSummary]
    public let glossaryTerms: [GlossaryTermInfo]
    public let learningObjectives: [LearningObjectiveInfo]

    enum CodingKeys: String, CodingKey {
        case id, title, description, version, difficulty
        case ageRange = "age_range"
        case duration, keywords, topics
        case glossaryTerms = "glossary_terms"
        case learningObjectives = "learning_objectives"
    }
}

/// Summary of a topic (for listing)
public struct TopicSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let description: String
    public let orderIndex: Int
    public let duration: String?
    public let hasTranscript: Bool
    public let segmentCount: Int
    public let assessmentCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case orderIndex = "order_index"
        case duration
        case hasTranscript = "has_transcript"
        case segmentCount = "segment_count"
        case assessmentCount = "assessment_count"
    }
}

/// Glossary term info
public struct GlossaryTermInfo: Codable, Sendable {
    public let term: String
    public let definition: String?
    public let pronunciation: String?
    public let spokenDefinition: String?
}

/// Learning objective info
public struct LearningObjectiveInfo: Codable, Sendable {
    public let statement: String?
    public let bloomsLevel: String?

    // Allow flexible decoding since the backend might send strings directly
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as a string first
        if let statement = try? container.decode(String.self) {
            self.statement = statement
            self.bloomsLevel = nil
            return
        }

        // Try to decode as an object
        let objectContainer = try decoder.container(keyedBy: CodingKeys.self)
        self.statement = try? objectContainer.decode(String.self, forKey: .statement)
        self.bloomsLevel = try? objectContainer.decode(String.self, forKey: .bloomsLevel)
    }

    enum CodingKeys: String, CodingKey {
        case statement
        case bloomsLevel = "blooms_level"
    }
}

/// Topic transcript response
public struct TopicTranscriptResponse: Codable, Sendable {
    public let topicId: String
    public let topicTitle: String?
    public let segments: [TranscriptSegmentInfo]

    enum CodingKeys: String, CodingKey {
        case topicId = "topic_id"
        case topicTitle = "topic_title"
        case segments
    }
}

/// Transcript segment info
public struct TranscriptSegmentInfo: Codable, Sendable {
    public let id: String
    public let type: String
    public let content: String
    public let speakingNotes: SpeakingNotesInfo?
    public let checkpoint: CheckpointInfo?

    enum CodingKeys: String, CodingKey {
        case id, type, content
        case speakingNotes = "speaking_notes"
        case checkpoint
    }
}

public struct SpeakingNotesInfo: Codable, Sendable {
    public let pace: String?
    public let emotionalTone: String?
    public let pauseAfter: String?

    enum CodingKeys: String, CodingKey {
        case pace
        case emotionalTone = "emotional_tone"
        case pauseAfter = "pause_after"
    }
}

public struct CheckpointInfo: Codable, Sendable {
    public let type: String?
    public let question: String?
}

/// API response wrapper for curricula list
public struct CurriculaListResponse: Codable, Sendable {
    public let curricula: [CurriculumSummary]
    public let total: Int
}

// MARK: - Curriculum Service Errors

public enum CurriculumServiceError: Error, LocalizedError, Sendable {
    case invalidURL
    case networkError(String)
    case serverError(Int, String?)
    case decodingError(String)
    case notFound(String)
    case noServerConfigured

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL configuration"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .notFound(let id):
            return "Curriculum not found: \(id)"
        case .noServerConfigured:
            return "No management server configured"
        }
    }
}

// MARK: - Curriculum Service

/// Service for fetching curricula from the management server
public actor CurriculumService {
    private let session: URLSession
    private var baseURL: URL?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Configuration

    /// Configure the base URL for the management server
    public func configure(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Configure using host and port
    public func configure(host: String, port: Int) throws {
        guard let url = URL(string: "http://\(host):\(port)") else {
            throw CurriculumServiceError.invalidURL
        }
        self.baseURL = url
    }

    // MARK: - API Methods

    /// Fetch list of available curricula
    public func fetchCurricula(
        search: String? = nil,
        difficulty: String? = nil
    ) async throws -> [CurriculumSummary] {
        guard let baseURL = baseURL else {
            throw CurriculumServiceError.noServerConfigured
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("api/curricula"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []

        if let search = search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let difficulty = difficulty, !difficulty.isEmpty {
            queryItems.append(URLQueryItem(name: "difficulty", value: difficulty))
        }

        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw CurriculumServiceError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CurriculumServiceError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)
            throw CurriculumServiceError.serverError(httpResponse.statusCode, message)
        }

        do {
            let response = try JSONDecoder().decode(CurriculaListResponse.self, from: data)
            return response.curricula
        } catch {
            throw CurriculumServiceError.decodingError(error.localizedDescription)
        }
    }

    /// Fetch detailed curriculum info including topics
    public func fetchCurriculumDetail(id: String) async throws -> CurriculumDetail {
        guard let baseURL = baseURL else {
            throw CurriculumServiceError.noServerConfigured
        }

        let url = baseURL.appendingPathComponent("api/curricula/\(id)")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CurriculumServiceError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw CurriculumServiceError.notFound(id)
            }
            let message = String(data: data, encoding: .utf8)
            throw CurriculumServiceError.serverError(httpResponse.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(CurriculumDetail.self, from: data)
        } catch {
            throw CurriculumServiceError.decodingError(error.localizedDescription)
        }
    }

    /// Fetch full UMLCF curriculum for download
    public func fetchFullCurriculum(id: String) async throws -> UMLCFDocument {
        guard let baseURL = baseURL else {
            throw CurriculumServiceError.noServerConfigured
        }

        let url = baseURL.appendingPathComponent("api/curricula/\(id)/full")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CurriculumServiceError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw CurriculumServiceError.notFound(id)
            }
            let message = String(data: data, encoding: .utf8)
            throw CurriculumServiceError.serverError(httpResponse.statusCode, message)
        }

        do {
            // The response is a UMLCFDocument wrapper
            struct FullCurriculumResponse: Codable {
                let curriculum: UMLCFDocument
            }
            let response = try JSONDecoder().decode(FullCurriculumResponse.self, from: data)
            return response.curriculum
        } catch {
            // Try direct decoding
            do {
                return try JSONDecoder().decode(UMLCFDocument.self, from: data)
            } catch let decodingError as DecodingError {
                // Provide detailed decoding error information
                let errorDetail: String
                switch decodingError {
                case .keyNotFound(let key, let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    errorDetail = "Missing key '\(key.stringValue)' at path: \(path.isEmpty ? "root" : path)"
                case .typeMismatch(let type, let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    errorDetail = "Type mismatch: expected \(type) at path: \(path.isEmpty ? "root" : path). \(context.debugDescription)"
                case .valueNotFound(let type, let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    errorDetail = "Value not found: expected \(type) at path: \(path.isEmpty ? "root" : path)"
                case .dataCorrupted(let context):
                    let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
                    errorDetail = "Data corrupted at path: \(path.isEmpty ? "root" : path). \(context.debugDescription)"
                @unknown default:
                    errorDetail = decodingError.localizedDescription
                }
                throw CurriculumServiceError.decodingError(errorDetail)
            } catch {
                throw CurriculumServiceError.decodingError(error.localizedDescription)
            }
        }
    }

    /// Fetch transcript for a specific topic
    public func fetchTopicTranscript(
        curriculumId: String,
        topicId: String
    ) async throws -> TopicTranscriptResponse {
        guard let baseURL = baseURL else {
            throw CurriculumServiceError.noServerConfigured
        }

        let url = baseURL.appendingPathComponent("api/curricula/\(curriculumId)/topics/\(topicId)/transcript")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CurriculumServiceError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw CurriculumServiceError.notFound("\(curriculumId)/\(topicId)")
            }
            let message = String(data: data, encoding: .utf8)
            throw CurriculumServiceError.serverError(httpResponse.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(TopicTranscriptResponse.self, from: data)
        } catch {
            throw CurriculumServiceError.decodingError(error.localizedDescription)
        }
    }

    /// Reload curricula on server (triggers re-scan of curriculum files)
    public func reloadCurricula() async throws {
        guard let baseURL = baseURL else {
            throw CurriculumServiceError.noServerConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/curricula/reload"))
        request.httpMethod = "POST"

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CurriculumServiceError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)
            throw CurriculumServiceError.serverError(httpResponse.statusCode, message)
        }
    }

    // MARK: - Download and Import

    /// Download and import a curriculum to Core Data
    @MainActor
    public func downloadAndImport(
        curriculumId: String,
        parser: UMLCFParser
    ) async throws -> Curriculum {
        // Fetch full UMLCF document (crosses from MainActor to CurriculumService actor)
        let umlcfDocument = try await fetchFullCurriculum(id: curriculumId)

        // Import to Core Data (runs on MainActor)
        return try await parser.importToCoreData(document: umlcfDocument, replaceExisting: true)
    }
}

// MARK: - Singleton Access

extension CurriculumService {
    /// Shared instance for app-wide use
    public static let shared = CurriculumService()
}
