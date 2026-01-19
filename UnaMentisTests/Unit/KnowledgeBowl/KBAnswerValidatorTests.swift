//
//  KBAnswerValidatorTests.swift
//  UnaMentisTests
//
//  Tests for KBAnswerValidator answer matching logic
//

import XCTest
@testable import UnaMentis

final class KBAnswerValidatorTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeQuestion(
        primary: String,
        acceptable: [String]? = nil,
        answerType: KBAnswerType = .text
    ) -> KBQuestion {
        KBQuestion(
            text: "Test question",
            answer: KBAnswer(primary: primary, acceptable: acceptable, answerType: answerType),
            domain: .science
        )
    }

    // MARK: - Initialization Tests

    func testInit_withDefaultConfig_usesStandardSettings() {
        let validator = KBAnswerValidator()
        // Default config allows fuzzy matching
        let question = makeQuestion(primary: "Paris")
        let result = validator.validate(userAnswer: "Pars", question: question)  // 1 char off
        XCTAssertTrue(result.isCorrect)  // Should match with fuzzy
    }

    func testInit_withStrictConfig_disablesFuzzyMatching() {
        let validator = KBAnswerValidator(config: .strict)
        let question = makeQuestion(primary: "Paris")
        let result = validator.validate(userAnswer: "Pars", question: question)
        XCTAssertFalse(result.isCorrect)  // Strict mode requires exact
    }

    func testInit_withLenientConfig_allowsMoreErrors() {
        let validator = KBAnswerValidator(config: .lenient)
        let question = makeQuestion(primary: "Mississippi")
        let result = validator.validate(userAnswer: "Missisipi", question: question)  // 2 chars off
        XCTAssertTrue(result.isCorrect)
    }

    // MARK: - Exact Match Tests

    func testValidate_exactMatch_returnsCorrectWithFullConfidence() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Paris")

        let result = validator.validate(userAnswer: "Paris", question: question)

        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.confidence, 1.0)
        XCTAssertEqual(result.matchType, .exact)
        XCTAssertEqual(result.matchedAnswer, "Paris")
    }

    func testValidate_caseInsensitive_matchesExactly() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Paris")

        XCTAssertTrue(validator.validate(userAnswer: "paris", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "PARIS", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "PaRiS", question: question).isCorrect)
    }

    func testValidate_withWhitespace_trimsAndMatches() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Paris")

        XCTAssertTrue(validator.validate(userAnswer: "  Paris  ", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "\nParis\n", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "Paris ", question: question).isCorrect)
    }

    // MARK: - Acceptable Alternatives Tests

    func testValidate_acceptableAlternative_returnsCorrect() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(
            primary: "George Washington",
            acceptable: ["Washington", "G. Washington"]
        )

        let result = validator.validate(userAnswer: "Washington", question: question)

        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.matchType, .acceptable)
        XCTAssertEqual(result.matchedAnswer, "Washington")
    }

    func testValidate_multipleAcceptable_matchesAny() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(
            primary: "United States",
            acceptable: ["USA", "US", "United States of America", "America"]
        )

        XCTAssertTrue(validator.validate(userAnswer: "USA", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "US", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "America", question: question).isCorrect)
    }

    // MARK: - Fuzzy Match Tests

    func testValidate_fuzzyMatch_acceptsSmallTypos() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Mississippi")

        let result = validator.validate(userAnswer: "Mississipi", question: question)

        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.matchType, .fuzzy)
        XCTAssertLessThan(result.confidence, 1.0)
        XCTAssertGreaterThan(result.confidence, 0.6)
    }

    func testValidate_fuzzyMatch_rejectsLargeErrors() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Paris")

        let result = validator.validate(userAnswer: "London", question: question)

        XCTAssertFalse(result.isCorrect)
        XCTAssertEqual(result.matchType, .none)
    }

    func testValidate_fuzzyMatch_confidenceDecreasesWithErrors() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "California")

        let exactResult = validator.validate(userAnswer: "California", question: question)
        let fuzzyResult = validator.validate(userAnswer: "Californa", question: question)

        XCTAssertGreaterThan(exactResult.confidence, fuzzyResult.confidence)
    }

    // MARK: - Text Normalization Tests

    func testValidate_textType_removesPunctuation() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Hello World", answerType: .text)

        XCTAssertTrue(validator.validate(userAnswer: "Hello, World!", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "Hello World", question: question).isCorrect)
    }

    func testValidate_textType_removesArticles() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Eiffel Tower", answerType: .text)

        XCTAssertTrue(validator.validate(userAnswer: "The Eiffel Tower", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "Eiffel Tower", question: question).isCorrect)
    }

    // MARK: - Person Name Tests

    func testValidate_personType_removesTitles() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Albert Einstein", answerType: .person)

        XCTAssertTrue(validator.validate(userAnswer: "Dr. Albert Einstein", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "Professor Albert Einstein", question: question).isCorrect)
    }

    func testValidate_personType_handlesLastFirstFormat() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Albert Einstein", answerType: .person)

        XCTAssertTrue(validator.validate(userAnswer: "Einstein, Albert", question: question).isCorrect)
    }

    // MARK: - Place Name Tests

    func testValidate_placeType_handlesAbbreviations() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "United States", answerType: .place)

        XCTAssertTrue(validator.validate(userAnswer: "US", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "USA", question: question).isCorrect)
    }

    func testValidate_placeType_expandsCommonAbbreviations() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Mount Everest", answerType: .place)

        XCTAssertTrue(validator.validate(userAnswer: "Mt Everest", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "Mt. Everest", question: question).isCorrect)
    }

    // MARK: - Number Tests

    func testValidate_numberType_parsesWrittenNumbers() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "12", answerType: .number)

        XCTAssertTrue(validator.validate(userAnswer: "twelve", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "12", question: question).isCorrect)
    }

    func testValidate_numberType_handlesCommas() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "1000000", answerType: .number)

        XCTAssertTrue(validator.validate(userAnswer: "1,000,000", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "1000000", question: question).isCorrect)
    }

    // MARK: - Date Tests

    func testValidate_dateType_handlesMonthNames() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "7 4", answerType: .date)

        XCTAssertTrue(validator.validate(userAnswer: "July 4", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "Jul 4", question: question).isCorrect)
    }

    // MARK: - Title Tests

    func testValidate_titleType_removesLeadingThe() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Great Gatsby", answerType: .title)

        XCTAssertTrue(validator.validate(userAnswer: "The Great Gatsby", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "Great Gatsby", question: question).isCorrect)
    }

    func testValidate_titleType_removesSubtitle() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Star Wars", answerType: .title)

        XCTAssertTrue(validator.validate(userAnswer: "Star Wars: A New Hope", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "Star Wars", question: question).isCorrect)
    }

    // MARK: - Scientific Tests

    func testValidate_scientificType_removesSpaces() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "h2o", answerType: .scientific)

        XCTAssertTrue(validator.validate(userAnswer: "H2O", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "H 2 O", question: question).isCorrect)
    }

    // MARK: - MCQ Tests

    func testValidateMCQ_correctSelection_returnsCorrect() {
        let validator = KBAnswerValidator()
        let question = KBQuestion(
            text: "What is 2+2?",
            answer: KBAnswer(primary: "4"),
            domain: .mathematics,
            mcqOptions: ["3", "4", "5", "6"]
        )

        let result = validator.validateMCQ(selectedIndex: 1, question: question)

        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.confidence, 1.0)
        XCTAssertEqual(result.matchedAnswer, "4")
    }

    func testValidateMCQ_incorrectSelection_returnsIncorrect() {
        let validator = KBAnswerValidator()
        let question = KBQuestion(
            text: "What is 2+2?",
            answer: KBAnswer(primary: "4"),
            domain: .mathematics,
            mcqOptions: ["3", "4", "5", "6"]
        )

        let result = validator.validateMCQ(selectedIndex: 0, question: question)

        XCTAssertFalse(result.isCorrect)
        XCTAssertEqual(result.confidence, 0)
    }

    func testValidateMCQ_invalidIndex_returnsIncorrect() {
        let validator = KBAnswerValidator()
        let question = KBQuestion(
            text: "What is 2+2?",
            answer: KBAnswer(primary: "4"),
            domain: .mathematics,
            mcqOptions: ["3", "4", "5", "6"]
        )

        XCTAssertFalse(validator.validateMCQ(selectedIndex: -1, question: question).isCorrect)
        XCTAssertFalse(validator.validateMCQ(selectedIndex: 4, question: question).isCorrect)
        XCTAssertFalse(validator.validateMCQ(selectedIndex: 100, question: question).isCorrect)
    }

    func testValidateMCQ_noOptions_returnsIncorrect() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "4")

        let result = validator.validateMCQ(selectedIndex: 0, question: question)

        XCTAssertFalse(result.isCorrect)
    }

    // MARK: - Incorrect Answer Tests

    func testValidate_completelyWrong_returnsIncorrect() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Paris")

        let result = validator.validate(userAnswer: "Tokyo", question: question)

        XCTAssertFalse(result.isCorrect)
        XCTAssertEqual(result.confidence, 0)
        XCTAssertEqual(result.matchType, .none)
        XCTAssertNil(result.matchedAnswer)
    }

    func testValidate_emptyAnswer_returnsIncorrect() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Paris")

        XCTAssertFalse(validator.validate(userAnswer: "", question: question).isCorrect)
        XCTAssertFalse(validator.validate(userAnswer: "   ", question: question).isCorrect)
    }

    // MARK: - Points Earned Tests

    func testValidationResult_pointsEarned_oneForCorrect() {
        let result = KBValidationResult(
            isCorrect: true,
            confidence: 1.0,
            matchType: .exact,
            matchedAnswer: "Paris"
        )

        XCTAssertEqual(result.pointsEarned, 1)
    }

    func testValidationResult_pointsEarned_zeroForIncorrect() {
        let result = KBValidationResult(
            isCorrect: false,
            confidence: 0,
            matchType: .none,
            matchedAnswer: nil
        )

        XCTAssertEqual(result.pointsEarned, 0)
    }

    // MARK: - Config Tests

    func testConfig_standard_hasExpectedDefaults() {
        let config = KBAnswerValidator.Config.standard

        XCTAssertEqual(config.fuzzyThresholdPercent, 0.20, accuracy: 0.01)
        XCTAssertEqual(config.minimumConfidence, 0.6)
        XCTAssertFalse(config.strictMode)
    }

    func testConfig_strict_enablesStrictMode() {
        let config = KBAnswerValidator.Config.strict

        XCTAssertTrue(config.strictMode)
    }

    func testConfig_lenient_hasHigherThreshold() {
        let config = KBAnswerValidator.Config.lenient

        XCTAssertEqual(config.fuzzyThresholdPercent, 0.30, accuracy: 0.01)
        XCTAssertEqual(config.minimumConfidence, 0.5)
    }

    // MARK: - Edge Cases

    func testValidate_singleCharacterAnswer_handlesCorrectly() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "A")

        XCTAssertTrue(validator.validate(userAnswer: "A", question: question).isCorrect)
        XCTAssertTrue(validator.validate(userAnswer: "a", question: question).isCorrect)
    }

    func testValidate_veryLongAnswer_handlesCorrectly() {
        let validator = KBAnswerValidator()
        let longAnswer = String(repeating: "a", count: 1000)
        let question = makeQuestion(primary: longAnswer)

        XCTAssertTrue(validator.validate(userAnswer: longAnswer, question: question).isCorrect)
    }

    func testValidate_unicodeCharacters_handlesCorrectly() {
        let validator = KBAnswerValidator()
        let question = makeQuestion(primary: "Café")

        XCTAssertTrue(validator.validate(userAnswer: "café", question: question).isCorrect)
    }
}
