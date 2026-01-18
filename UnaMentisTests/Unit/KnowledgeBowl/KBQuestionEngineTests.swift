//
//  KBQuestionEngineTests.swift
//  UnaMentisTests
//
//  Tests for KBQuestionEngine question loading, filtering, and selection
//

import XCTest
@testable import UnaMentis

@MainActor
final class KBQuestionEngineTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeEngine(with questions: [KBQuestion] = []) -> KBQuestionEngine {
        let engine = KBQuestionEngine()
        // Inject test questions using reflection or test-specific method
        // For now, we'll test with loadQuestions(from:) using temporary files
        return engine
    }

    private func makeQuestion(
        domain: KBDomain = .science,
        difficulty: KBDifficulty = .varsity,
        gradeLevel: KBGradeLevel = .highSchool,
        forWritten: Bool = true,
        forOral: Bool = true
    ) -> KBQuestion {
        KBQuestion(
            text: "Test question for \(domain.displayName)",
            answer: KBAnswer(primary: "Test answer"),
            domain: domain,
            difficulty: difficulty,
            gradeLevel: gradeLevel,
            suitability: KBSuitability(forWritten: forWritten, forOral: forOral)
        )
    }

    private func makeTestBundle(questions: [KBQuestion]) throws -> URL {
        let bundle = KBQuestionBundle(version: "1.0.0", generatedAt: Date(), questions: questions)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-questions-\(UUID().uuidString).json")
        try data.write(to: fileURL)

        return fileURL
    }

    // MARK: - Initialization Tests

    func testInit_startsWithEmptyState() {
        let engine = KBQuestionEngine()

        XCTAssertTrue(engine.questions.isEmpty)
        XCTAssertFalse(engine.isLoading)
        XCTAssertNil(engine.loadError)
        XCTAssertEqual(engine.totalQuestionCount, 0)
    }

    // MARK: - Loading Tests

    func testLoadQuestions_fromValidURL_loadsSuccessfully() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(domain: .science),
            makeQuestion(domain: .mathematics)
        ]
        let url = try makeTestBundle(questions: questions)

        defer { try? FileManager.default.removeItem(at: url) }

        try await engine.loadQuestions(from: url)

        XCTAssertEqual(engine.questions.count, 2)
        XCTAssertFalse(engine.isLoading)
        XCTAssertNil(engine.loadError)
    }

    func testLoadQuestions_fromInvalidURL_setsError() async {
        let engine = KBQuestionEngine()
        let invalidURL = URL(fileURLWithPath: "/nonexistent/path.json")

        do {
            try await engine.loadQuestions(from: invalidURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertNotNil(engine.loadError)
            XCTAssertFalse(engine.isLoading)
        }
    }

    func testLoadQuestions_fromInvalidJSON_setsError() async throws {
        let engine = KBQuestionEngine()

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("invalid-\(UUID().uuidString).json")
        try "{ invalid json }".write(to: fileURL, atomically: true, encoding: .utf8)

        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            try await engine.loadQuestions(from: fileURL)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertNotNil(engine.loadError)
        }
    }

    // MARK: - Filtering Tests

    func testFilter_byDomain_returnsMatchingQuestions() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(domain: .science),
            makeQuestion(domain: .science),
            makeQuestion(domain: .mathematics),
            makeQuestion(domain: .literature)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let filtered = engine.filter(domains: [.science])

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.domain == .science })
    }

    func testFilter_byMultipleDomains_returnsMatchingQuestions() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(domain: .science),
            makeQuestion(domain: .mathematics),
            makeQuestion(domain: .literature),
            makeQuestion(domain: .history)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let filtered = engine.filter(domains: [.science, .mathematics])

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.domain == .science || $0.domain == .mathematics })
    }

    func testFilter_byDifficulty_returnsMatchingQuestions() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(difficulty: .foundational),
            makeQuestion(difficulty: .foundational),
            makeQuestion(difficulty: .varsity),
            makeQuestion(difficulty: .championship)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let filtered = engine.filter(difficulty: .foundational)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.difficulty == .foundational })
    }

    func testFilter_byGradeLevel_returnsMatchingQuestions() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(gradeLevel: .middleSchool),
            makeQuestion(gradeLevel: .highSchool),
            makeQuestion(gradeLevel: .highSchool),
            makeQuestion(gradeLevel: .advanced)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let filtered = engine.filter(gradeLevel: .highSchool)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.gradeLevel == .highSchool })
    }

    func testFilter_forWrittenRound_returnsWrittenSuitable() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(forWritten: true, forOral: true),
            makeQuestion(forWritten: true, forOral: false),
            makeQuestion(forWritten: false, forOral: true)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let filtered = engine.filter(forWritten: true)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.suitability.forWritten })
    }

    func testFilter_forOralRound_returnsOralSuitable() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(forWritten: true, forOral: true),
            makeQuestion(forWritten: true, forOral: false),
            makeQuestion(forWritten: false, forOral: true)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let filtered = engine.filter(forOral: true)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.suitability.forOral })
    }

    func testFilter_multipleFilters_combinesCorrectly() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(domain: .science, difficulty: .varsity, gradeLevel: .highSchool),
            makeQuestion(domain: .science, difficulty: .foundational, gradeLevel: .highSchool),
            makeQuestion(domain: .mathematics, difficulty: .varsity, gradeLevel: .highSchool),
            makeQuestion(domain: .science, difficulty: .varsity, gradeLevel: .middleSchool)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let filtered = engine.filter(domains: [.science], difficulty: .varsity, gradeLevel: .highSchool)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.domain, .science)
        XCTAssertEqual(filtered.first?.difficulty, .varsity)
        XCTAssertEqual(filtered.first?.gradeLevel, .highSchool)
    }

    func testFilter_excludeAttempted_excludesMarkedQuestions() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(domain: .science),
            makeQuestion(domain: .mathematics),
            makeQuestion(domain: .literature)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        // Mark first question as attempted
        engine.markAttempted(engine.questions[0].id)

        let filtered = engine.filter(excludeAttempted: true)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertFalse(filtered.contains { $0.id == engine.questions[0].id })
    }

    // MARK: - Selection Tests

    func testSelectRandom_returnsRequestedCount() async throws {
        let engine = KBQuestionEngine()
        let questions = (0..<10).map { _ in makeQuestion() }
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let selected = engine.selectRandom(count: 5)

        XCTAssertEqual(selected.count, 5)
    }

    func testSelectRandom_respectsMaxAvailable() async throws {
        let engine = KBQuestionEngine()
        let questions = (0..<3).map { _ in makeQuestion() }
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let selected = engine.selectRandom(count: 10)

        XCTAssertEqual(selected.count, 3)  // Only 3 available
    }

    func testSelectRandom_fromEmptyPool_returnsEmpty() {
        let engine = KBQuestionEngine()

        let selected = engine.selectRandom(count: 5)

        XCTAssertTrue(selected.isEmpty)
    }

    func testSelectRandom_fromFilteredPool_usesFilteredQuestions() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(domain: .science),
            makeQuestion(domain: .science),
            makeQuestion(domain: .mathematics)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let filtered = engine.filter(domains: [.science])
        let selected = engine.selectRandom(count: 10, from: filtered)

        XCTAssertEqual(selected.count, 2)
        XCTAssertTrue(selected.allSatisfy { $0.domain == .science })
    }

    func testSelectForSession_usesConfigFilters() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(domain: .science, forWritten: true),
            makeQuestion(domain: .mathematics, forWritten: true),
            makeQuestion(domain: .science, forWritten: false)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let config = KBSessionConfig.writtenPractice(
            region: .colorado,
            questionCount: 10,
            domains: [.science]
        )
        let selected = engine.selectForSession(config: config)

        XCTAssertEqual(selected.count, 1)  // Only 1 science question suitable for written
    }

    // MARK: - Attempt Tracking Tests

    func testMarkAttempted_addsToTracking() async throws {
        let engine = KBQuestionEngine()
        let questions = [makeQuestion()]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let questionId = engine.questions[0].id
        engine.markAttempted(questionId)

        XCTAssertTrue(engine.hasAttempted(questionId))
    }

    func testMarkAttempted_multipleIds_addsAllToTracking() async throws {
        let engine = KBQuestionEngine()
        let questions = [makeQuestion(), makeQuestion(), makeQuestion()]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let ids = engine.questions.map { $0.id }
        engine.markAttempted(Array(ids.prefix(2)))

        XCTAssertTrue(engine.hasAttempted(ids[0]))
        XCTAssertTrue(engine.hasAttempted(ids[1]))
        XCTAssertFalse(engine.hasAttempted(ids[2]))
    }

    func testClearAttemptedQuestions_resetsTracking() async throws {
        let engine = KBQuestionEngine()
        let questions = [makeQuestion(), makeQuestion()]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        engine.markAttempted(engine.questions.map { $0.id })
        engine.clearAttemptedQuestions()

        XCTAssertFalse(engine.hasAttempted(engine.questions[0].id))
        XCTAssertFalse(engine.hasAttempted(engine.questions[1].id))
    }

    func testUnattemptedCount_calculatesCorrectly() async throws {
        let engine = KBQuestionEngine()
        let questions = [makeQuestion(), makeQuestion(), makeQuestion()]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        XCTAssertEqual(engine.unattemptedCount, 3)

        engine.markAttempted(engine.questions[0].id)
        XCTAssertEqual(engine.unattemptedCount, 2)

        engine.markAttempted(engine.questions[1].id)
        XCTAssertEqual(engine.unattemptedCount, 1)
    }

    // MARK: - Statistics Tests

    func testQuestionsByDomain_countsCorrectly() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(domain: .science),
            makeQuestion(domain: .science),
            makeQuestion(domain: .mathematics),
            makeQuestion(domain: .literature),
            makeQuestion(domain: .literature),
            makeQuestion(domain: .literature)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let byDomain = engine.questionsByDomain

        XCTAssertEqual(byDomain[.science], 2)
        XCTAssertEqual(byDomain[.mathematics], 1)
        XCTAssertEqual(byDomain[.literature], 3)
        XCTAssertNil(byDomain[.history])
    }

    func testQuestionsByDifficulty_countsCorrectly() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(difficulty: .foundational),
            makeQuestion(difficulty: .varsity),
            makeQuestion(difficulty: .varsity),
            makeQuestion(difficulty: .championship)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let byDifficulty = engine.questionsByDifficulty

        XCTAssertEqual(byDifficulty[.foundational], 1)
        XCTAssertEqual(byDifficulty[.varsity], 2)
        XCTAssertEqual(byDifficulty[.championship], 1)
    }

    func testQuestionsByGradeLevel_countsCorrectly() async throws {
        let engine = KBQuestionEngine()
        let questions = [
            makeQuestion(gradeLevel: .middleSchool),
            makeQuestion(gradeLevel: .highSchool),
            makeQuestion(gradeLevel: .highSchool),
            makeQuestion(gradeLevel: .advanced)
        ]
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let byGrade = engine.questionsByGradeLevel

        XCTAssertEqual(byGrade[.middleSchool], 1)
        XCTAssertEqual(byGrade[.highSchool], 2)
        XCTAssertEqual(byGrade[.advanced], 1)
    }

    func testTotalQuestionCount_matchesQuestionArray() async throws {
        let engine = KBQuestionEngine()
        let questions = (0..<7).map { _ in makeQuestion() }
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        XCTAssertEqual(engine.totalQuestionCount, 7)
        XCTAssertEqual(engine.totalQuestionCount, engine.questions.count)
    }

    // MARK: - Weighted Selection Tests

    func testSelectWeighted_respectsDomainWeights() async throws {
        let engine = KBQuestionEngine()
        // Create many questions in each domain
        var questions: [KBQuestion] = []
        for domain in KBDomain.allCases {
            questions.append(contentsOf: (0..<20).map { _ in makeQuestion(domain: domain) })
        }
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let selected = engine.selectWeighted(count: 50, respectDomainWeights: true)

        // Verify selection was made
        XCTAssertEqual(selected.count, 50)

        // Verify multiple domains are represented (weighted selection)
        let domains = Set(selected.map { $0.domain })
        XCTAssertGreaterThan(domains.count, 1)
    }

    func testSelectWeighted_withoutWeights_selectsRandomly() async throws {
        let engine = KBQuestionEngine()
        let questions = (0..<20).map { _ in makeQuestion(domain: .science) }
        let url = try makeTestBundle(questions: questions)
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.loadQuestions(from: url)

        let selected = engine.selectWeighted(count: 10, respectDomainWeights: false)

        XCTAssertEqual(selected.count, 10)
    }
}
