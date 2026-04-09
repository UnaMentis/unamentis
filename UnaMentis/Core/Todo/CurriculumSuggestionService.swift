// UnaMentis - Curriculum Suggestion Service
// Suggests matching curricula for learning targets
//
// Part of Todo System

import Foundation
import CoreData
import Logging

/// Service for suggesting curricula matching learning targets
public actor CurriculumSuggestionService {
    // MARK: - Singleton

    public static let shared = CurriculumSuggestionService()

    // MARK: - Properties

    private let logger = Logger(label: "com.unamentis.todo.suggestions")
    private var isConfigured = false
    private var serverHost = "localhost"
    private var serverPort = 8766

    // MARK: - Configuration

    /// Configure the service with server settings
    public func configure(host: String, port: Int) {
        self.serverHost = host
        self.serverPort = port
        self.isConfigured = true
        logger.info("CurriculumSuggestionService configured with \(host):\(port)")
    }

    // MARK: - Suggestion Fetching

    /// Fetch curriculum suggestions for a learning target
    /// - Parameter query: The learning target text to match
    /// - Returns: Array of curriculum IDs that match the query
    public func fetchSuggestions(for query: String) async throws -> [String] {
        // Configure from UserDefaults if not already configured
        if !isConfigured {
            let serverIP = UserDefaults.standard.string(forKey: "primaryServerIP") ?? ""
            let host = serverIP.isEmpty ? "localhost" : serverIP
            configure(host: host, port: 8766)
        }

        logger.info("Fetching curriculum suggestions for: \(query)")

        // Build URL for suggestion endpoint
        let urlString = "http://\(serverHost):\(serverPort)/api/curricula/suggest"
        guard let url = URL(string: urlString) else {
            logger.error("Invalid suggestion URL: \(urlString)")
            throw CurriculumSuggestionError.invalidURL
        }

        // Create request with query parameter
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = SuggestionRequest(query: query)
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CurriculumSuggestionError.invalidResponse
            }

            // Handle 404 gracefully - endpoint may not exist on server yet
            if httpResponse.statusCode == 404 {
                logger.info("Suggestion endpoint not available, falling back to local search")
                return try await localSuggestions(for: query)
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("Suggestion request failed with status: \(httpResponse.statusCode)")
                throw CurriculumSuggestionError.serverError(httpResponse.statusCode)
            }

            let suggestionResponse = try JSONDecoder().decode(SuggestionResponse.self, from: data)
            logger.info("Received \(suggestionResponse.curriculumIds.count) suggestions from server")
            return suggestionResponse.curriculumIds

        } catch let error as CurriculumSuggestionError {
            throw error
        } catch is URLError {
            // Network error - fall back to local search
            logger.warning("Network error, falling back to local suggestions")
            return try await localSuggestions(for: query)
        } catch {
            logger.error("Suggestion request failed: \(error)")
            // Fall back to local search on any error
            return try await localSuggestions(for: query)
        }
    }

    // MARK: - Local Suggestions

    /// Search local Core Data for matching curricula
    private func localSuggestions(for query: String) async throws -> [String] {
        logger.info("Performing local curriculum search for: \(query)")

        let context = PersistenceController.shared.newBackgroundContext()

        // Build predicate outside the closure to avoid capturing self
        let words = query.lowercased().split(separator: " ").map { String($0) }
        var predicates: [NSPredicate] = []

        for word in words {
            let namePredicate = NSPredicate(format: "name CONTAINS[cd] %@", word)
            let summaryPredicate = NSPredicate(format: "summary CONTAINS[cd] %@", word)
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [namePredicate, summaryPredicate]))
        }

        let compoundPredicate: NSCompoundPredicate? = predicates.isEmpty
            ? nil
            : NSCompoundPredicate(orPredicateWithSubpredicates: predicates)

        let ids: [String] = await context.perform {
            let request = Curriculum.fetchRequest()
            request.predicate = compoundPredicate
            request.fetchLimit = 5

            do {
                let results = try context.fetch(request)
                return results.compactMap { $0.id?.uuidString }
            } catch {
                return []
            }
        }

        logger.info("Found \(ids.count) local curriculum matches")
        return ids
    }

    // MARK: - Update Todo Item

    /// Update a todo item with curriculum suggestions.
    /// - Parameters:
    ///   - itemID: The managed object ID for the `TodoItem` to update (Sendable).
    ///   - title: The item's title, pre-extracted by the caller on the correct actor.
    public func updateTodoWithSuggestions(itemID: NSManagedObjectID, title: String) async {
        let objectID = itemID
        do {
            let suggestions = try await fetchSuggestions(for: title)

            if !suggestions.isEmpty {
                await MainActor.run {
                    // Refetch the object using the viewContext
                    guard let context = PersistenceController.shared.container.viewContext
                        .object(with: objectID) as? TodoItem else {
                        return
                    }
                    context.suggestedCurriculumIds = suggestions
                    context.markUpdated()

                    do {
                        try context.managedObjectContext?.save()
                        logger.info("Updated todo with \(suggestions.count) suggestions")
                    } catch {
                        logger.error("Failed to save suggestions: \(error)")
                    }
                }
            }
        } catch {
            logger.error("Failed to fetch suggestions: \(error)")
        }
    }
}

// MARK: - Request/Response Models

private struct SuggestionRequest: Codable {
    let query: String
}

private struct SuggestionResponse: Codable {
    let curriculumIds: [String]
}

// MARK: - Errors

public enum CurriculumSuggestionError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid suggestion URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
