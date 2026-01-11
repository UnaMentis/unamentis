// UnaMentis - Context Expansion Tool
// LLM tool for explicit context expansion requests
//
// Part of FOV Context Management System
//
// Allows the LLM to explicitly request more context when
// it determines it needs additional information to answer
// a question accurately.

import Foundation
import Logging

// MARK: - Context Expansion Tool

/// LLM tool that enables explicit context expansion requests
/// The LLM can call this tool to retrieve additional curriculum content
public struct ContextExpansionTool: Sendable {

    // MARK: - Properties

    /// Tool name for LLM function calling
    public static let name = "expand_context"

    /// Tool description for LLM
    public static let description = """
    Request additional curriculum context when you need more information to answer \
    the user's question accurately. Use this when you're uncertain about specific \
    details, need to reference related topics, or want to provide more comprehensive \
    information.
    """

    /// Get the LLM tool definition
    public static var toolDefinition: LLMToolDefinition {
        LLMToolDefinition(
            name: name,
            description: description,
            inputSchema: ToolInputSchema(
                properties: [
                    "query": ToolProperty(
                        type: "string",
                        description: "What information do you need? Be specific about the topic or concept."
                    ),
                    "scope": ToolProperty(
                        type: "string",
                        description: "Where to search for the information",
                        enumValues: ["current_topic", "current_unit", "full_curriculum", "related_topics"]
                    ),
                    "reason": ToolProperty(
                        type: "string",
                        description: "Why do you need this information? Helps prioritize retrieval."
                    )
                ],
                required: ["query"]
            )
        )
    }
}

// MARK: - Tool Handler

/// Handler for processing context expansion requests
public actor ContextExpansionHandler {

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.contextexpansion")

    /// Curriculum engine for semantic search
    private let curriculumEngine: CurriculumEngine

    /// FOV context manager to update
    private let contextManager: FOVContextManager

    /// Maximum tokens to retrieve per expansion
    private let maxRetrievalTokens: Int

    // MARK: - Initialization

    /// Initialize with required dependencies
    /// - Parameters:
    ///   - curriculumEngine: Engine for curriculum access and search
    ///   - contextManager: Context manager to update with expanded content
    ///   - maxRetrievalTokens: Maximum tokens to retrieve per expansion
    public init(
        curriculumEngine: CurriculumEngine,
        contextManager: FOVContextManager,
        maxRetrievalTokens: Int = 2000
    ) {
        self.curriculumEngine = curriculumEngine
        self.contextManager = contextManager
        self.maxRetrievalTokens = maxRetrievalTokens
        logger.info("ContextExpansionHandler initialized")
    }

    // MARK: - Execution

    /// Execute a context expansion request
    /// - Parameter request: The expansion request parameters
    /// - Returns: Result containing retrieved content
    public func execute(_ request: ExpansionRequest) async -> ExpansionToolResult {
        logger.info(
            "Processing expansion request",
            metadata: [
                "query": .string(request.query),
                "scope": .string(request.scope.rawValue)
            ]
        )

        let startTime = Date()

        // Perform semantic search based on scope
        let retrievedContent = await performSearch(
            query: request.query,
            scope: request.scope
        )

        // Update context manager with retrieved content
        await contextManager.expandWorkingBuffer(with: retrievedContent)

        // Format response for LLM
        let formattedContent = formatRetrievedContent(retrievedContent)

        let result = ExpansionToolResult(
            success: !retrievedContent.isEmpty,
            content: formattedContent,
            retrievedItems: retrievedContent.count,
            totalTokens: retrievedContent.reduce(0) { $0 + $1.estimatedTokens },
            searchDuration: Date().timeIntervalSince(startTime),
            scope: request.scope
        )

        logger.info(
            "Expansion complete",
            metadata: [
                "items": .stringConvertible(result.retrievedItems),
                "tokens": .stringConvertible(result.totalTokens),
                "duration": .stringConvertible(result.searchDuration)
            ]
        )

        return result
    }

    // MARK: - Search Implementation

    /// Perform semantic search based on scope
    private func performSearch(
        query: String,
        scope: ExpansionScope
    ) async -> [RetrievedContent] {
        switch scope {
        case .currentTopic:
            return await searchCurrentTopic(query: query)
        case .currentUnit:
            return await searchCurrentUnit(query: query)
        case .fullCurriculum:
            return await searchFullCurriculum(query: query)
        case .relatedTopics:
            return await searchRelatedTopics(query: query)
        }
    }

    /// Search within current topic only
    @MainActor
    private func searchCurrentTopic(query: String) async -> [RetrievedContent] {
        guard let topic = curriculumEngine.currentTopic else {
            return []
        }

        let context = await curriculumEngine.generateContextForQuery(
            query: query,
            topic: topic,
            maxTokens: maxRetrievalTokens
        )

        guard !context.isEmpty else { return [] }

        return [
            RetrievedContent(
                sourceTitle: topic.title ?? "Current Topic",
                content: context,
                relevanceScore: 1.0
            )
        ]
    }

    /// Search within current unit (adjacent topics)
    @MainActor
    private func searchCurrentUnit(query: String) async -> [RetrievedContent] {
        var results: [RetrievedContent] = []

        // Get current topic first
        results.append(contentsOf: await searchCurrentTopic(query: query))

        let topics = await curriculumEngine.getTopics()
        guard let currentTopic = curriculumEngine.currentTopic,
              let currentIndex = topics.firstIndex(where: { $0.id == currentTopic.id }) else {
            return results
        }

        // Search previous topic
        if currentIndex > 0 {
            let prevTopic = topics[currentIndex - 1]
            let prevContext = await curriculumEngine.generateContextForQuery(
                query: query,
                topic: prevTopic,
                maxTokens: maxRetrievalTokens / 3
            )
            if !prevContext.isEmpty {
                results.append(RetrievedContent(
                    sourceTitle: prevTopic.title ?? "Previous Topic",
                    content: prevContext,
                    relevanceScore: 0.8
                ))
            }
        }

        // Search next topic
        if currentIndex < topics.count - 1 {
            let nextTopic = topics[currentIndex + 1]
            let nextContext = await curriculumEngine.generateContextForQuery(
                query: query,
                topic: nextTopic,
                maxTokens: maxRetrievalTokens / 3
            )
            if !nextContext.isEmpty {
                results.append(RetrievedContent(
                    sourceTitle: nextTopic.title ?? "Next Topic",
                    content: nextContext,
                    relevanceScore: 0.7
                ))
            }
        }

        return results
    }

    /// Search the full curriculum
    @MainActor
    private func searchFullCurriculum(query: String) async -> [RetrievedContent] {
        var results: [RetrievedContent] = []
        let topics = await curriculumEngine.getTopics()

        // Search each topic (limited to avoid excessive results)
        for topic in topics.prefix(10) {
            let context = await curriculumEngine.generateContextForQuery(
                query: query,
                topic: topic,
                maxTokens: maxRetrievalTokens / 5
            )
            if !context.isEmpty {
                results.append(RetrievedContent(
                    sourceTitle: topic.title ?? "Topic",
                    content: context,
                    relevanceScore: 0.6
                ))
            }
        }

        // Sort by relevance and take top results
        return results.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(5).map { $0 }
    }

    /// Search related/prerequisite topics
    @MainActor
    private func searchRelatedTopics(query: String) async -> [RetrievedContent] {
        // For now, this is similar to currentUnit
        // In the future, this could use topic dependency graph
        return await searchCurrentUnit(query: query)
    }

    // MARK: - Formatting

    /// Format retrieved content for LLM consumption
    private func formatRetrievedContent(_ content: [RetrievedContent]) -> String {
        if content.isEmpty {
            return "No additional context found for your query."
        }

        var formatted = "Here is additional context from the curriculum:\n\n"

        for (index, item) in content.enumerated() {
            formatted += "**[\(item.sourceTitle)]**\n"
            formatted += item.content
            if index < content.count - 1 {
                formatted += "\n\n---\n\n"
            }
        }

        return formatted
    }
}

// MARK: - Supporting Types

/// Request for context expansion
public struct ExpansionRequest: Sendable, Codable {
    /// What information is needed
    public let query: String

    /// Where to search
    public let scope: ExpansionScope

    /// Why the information is needed
    public let reason: String?

    public init(query: String, scope: ExpansionScope = .currentTopic, reason: String? = nil) {
        self.query = query
        self.scope = scope
        self.reason = reason
    }

    /// Create from tool call JSON
    public init?(from json: [String: Any]) {
        guard let query = json["query"] as? String else {
            return nil
        }

        self.query = query

        if let scopeStr = json["scope"] as? String {
            self.scope = ExpansionScope(rawValue: scopeStr) ?? .currentTopic
        } else {
            self.scope = .currentTopic
        }

        self.reason = json["reason"] as? String
    }
}

/// Result from context expansion tool
public struct ExpansionToolResult: Sendable {
    /// Whether expansion was successful
    public let success: Bool

    /// Formatted content to inject into conversation
    public let content: String

    /// Number of items retrieved
    public let retrievedItems: Int

    /// Total tokens in retrieved content
    public let totalTokens: Int

    /// Time taken for search
    public let searchDuration: TimeInterval

    /// Scope that was searched
    public let scope: ExpansionScope

    /// Whether any content was found
    public var hasContent: Bool {
        retrievedItems > 0
    }
}

// MARK: - Expansion Scope Codable

extension ExpansionScope: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Handle both snake_case (from JSON) and camelCase
        switch rawValue {
        case "current_topic", "currentTopic":
            self = .currentTopic
        case "current_unit", "currentUnit":
            self = .currentUnit
        case "full_curriculum", "fullCurriculum":
            self = .fullCurriculum
        case "related_topics", "relatedTopics":
            self = .relatedTopics
        default:
            self = .currentTopic
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
