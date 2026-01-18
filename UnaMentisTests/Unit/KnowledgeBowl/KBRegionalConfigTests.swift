//
//  KBRegionalConfigTests.swift
//  UnaMentisTests
//
//  Tests for KBRegionalConfig and KBRegion regional rule configurations
//

import XCTest
@testable import UnaMentis

final class KBRegionalConfigTests: XCTestCase {

    // MARK: - KBRegion Tests

    func testRegion_allCases_containsAllRegions() {
        let allCases = KBRegion.allCases

        XCTAssertTrue(allCases.contains(.colorado))
        XCTAssertTrue(allCases.contains(.coloradoSprings))
        XCTAssertTrue(allCases.contains(.minnesota))
        XCTAssertTrue(allCases.contains(.washington))
        XCTAssertEqual(allCases.count, 4)
    }

    func testRegion_displayName_returnsHumanReadableName() {
        XCTAssertEqual(KBRegion.colorado.displayName, "Colorado")
        XCTAssertEqual(KBRegion.coloradoSprings.displayName, "Colorado Springs")
        XCTAssertEqual(KBRegion.minnesota.displayName, "Minnesota")
        XCTAssertEqual(KBRegion.washington.displayName, "Washington")
    }

    func testRegion_abbreviation_returnsStateCode() {
        XCTAssertEqual(KBRegion.colorado.abbreviation, "CO")
        XCTAssertEqual(KBRegion.coloradoSprings.abbreviation, "CO")
        XCTAssertEqual(KBRegion.minnesota.abbreviation, "MN")
        XCTAssertEqual(KBRegion.washington.abbreviation, "WA")
    }

    func testRegion_id_matchesRawValue() {
        for region in KBRegion.allCases {
            XCTAssertEqual(region.id, region.rawValue)
        }
    }

    func testRegion_config_returnsCorrectConfiguration() {
        let coloradoConfig = KBRegion.colorado.config
        XCTAssertEqual(coloradoConfig.region, .colorado)

        let minnesotaConfig = KBRegion.minnesota.config
        XCTAssertEqual(minnesotaConfig.region, .minnesota)
    }

    func testRegion_codable_encodesAndDecodes() throws {
        let region = KBRegion.colorado

        let encoder = JSONEncoder()
        let data = try encoder.encode(region)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(KBRegion.self, from: data)

        XCTAssertEqual(decoded, region)
    }

    // MARK: - Colorado Configuration Tests

    func testColoradoConfig_teamConfiguration() {
        let config = KBRegionalConfig.forRegion(.colorado)

        XCTAssertEqual(config.teamsPerMatch, 3)
        XCTAssertEqual(config.minTeamSize, 1)
        XCTAssertEqual(config.maxTeamSize, 4)
        XCTAssertEqual(config.activePlayersInOral, 4)
    }

    func testColoradoConfig_writtenRound() {
        let config = KBRegionalConfig.forRegion(.colorado)

        XCTAssertEqual(config.writtenQuestionCount, 60)
        XCTAssertEqual(config.writtenTimeLimit, 900)  // 15 minutes
        XCTAssertEqual(config.writtenPointsPerCorrect, 1)
    }

    func testColoradoConfig_oralRound() {
        let config = KBRegionalConfig.forRegion(.colorado)

        XCTAssertEqual(config.oralQuestionCount, 50)
        XCTAssertEqual(config.oralPointsPerCorrect, 5)
        XCTAssertTrue(config.reboundEnabled)
    }

    func testColoradoConfig_conferenceRules() {
        let config = KBRegionalConfig.forRegion(.colorado)

        XCTAssertEqual(config.conferenceTime, 15)
        XCTAssertFalse(config.verbalConferringAllowed)  // CRITICAL: Colorado prohibits verbal
        XCTAssertTrue(config.handSignalsAllowed)
    }

    func testColoradoConfig_scoringRules() {
        let config = KBRegionalConfig.forRegion(.colorado)

        XCTAssertFalse(config.negativeScoring)
        XCTAssertFalse(config.sosBonus)
    }

    // MARK: - Minnesota Configuration Tests

    func testMinnesotaConfig_teamConfiguration() {
        let config = KBRegionalConfig.forRegion(.minnesota)

        XCTAssertEqual(config.teamsPerMatch, 3)
        XCTAssertEqual(config.minTeamSize, 3)  // Different from Colorado
        XCTAssertEqual(config.maxTeamSize, 6)  // Different from Colorado
        XCTAssertEqual(config.activePlayersInOral, 4)
    }

    func testMinnesotaConfig_writtenRound() {
        let config = KBRegionalConfig.forRegion(.minnesota)

        XCTAssertEqual(config.writtenQuestionCount, 60)
        XCTAssertEqual(config.writtenTimeLimit, 900)
        XCTAssertEqual(config.writtenPointsPerCorrect, 2)  // 2 points, not 1
    }

    func testMinnesotaConfig_conferenceRules() {
        let config = KBRegionalConfig.forRegion(.minnesota)

        XCTAssertEqual(config.conferenceTime, 15)
        XCTAssertTrue(config.verbalConferringAllowed)  // Minnesota allows verbal
        XCTAssertTrue(config.handSignalsAllowed)
    }

    func testMinnesotaConfig_scoringRules() {
        let config = KBRegionalConfig.forRegion(.minnesota)

        XCTAssertFalse(config.negativeScoring)
        XCTAssertTrue(config.sosBonus)  // Minnesota has SOS bonus
    }

    // MARK: - Washington Configuration Tests

    func testWashingtonConfig_teamConfiguration() {
        let config = KBRegionalConfig.forRegion(.washington)

        XCTAssertEqual(config.teamsPerMatch, 3)
        XCTAssertEqual(config.minTeamSize, 3)
        XCTAssertEqual(config.maxTeamSize, 5)  // Different from others
    }

    func testWashingtonConfig_writtenRound() {
        let config = KBRegionalConfig.forRegion(.washington)

        XCTAssertEqual(config.writtenQuestionCount, 50)  // Only 50 questions
        XCTAssertEqual(config.writtenTimeLimit, 2700)  // 45 minutes (much longer)
        XCTAssertEqual(config.writtenPointsPerCorrect, 2)
    }

    func testWashingtonConfig_conferenceRules() {
        let config = KBRegionalConfig.forRegion(.washington)

        XCTAssertTrue(config.verbalConferringAllowed)
        XCTAssertTrue(config.handSignalsAllowed)
    }

    // MARK: - Colorado Springs Configuration Tests

    func testColoradoSpringsConfig_matchesColoradoBase() {
        let colorado = KBRegionalConfig.forRegion(.colorado)
        let coloradoSprings = KBRegionalConfig.forRegion(.coloradoSprings)

        // Should match most settings
        XCTAssertEqual(coloradoSprings.teamsPerMatch, colorado.teamsPerMatch)
        XCTAssertEqual(coloradoSprings.writtenQuestionCount, colorado.writtenQuestionCount)
        XCTAssertEqual(coloradoSprings.oralPointsPerCorrect, colorado.oralPointsPerCorrect)
        XCTAssertEqual(coloradoSprings.verbalConferringAllowed, colorado.verbalConferringAllowed)
    }

    // MARK: - Display Formatting Tests

    func testWrittenPointsDisplay_singularAndPlural() {
        let colorado = KBRegionalConfig.forRegion(.colorado)
        XCTAssertEqual(colorado.writtenPointsDisplay, "1 pt")

        let minnesota = KBRegionalConfig.forRegion(.minnesota)
        XCTAssertEqual(minnesota.writtenPointsDisplay, "2 pts")
    }

    func testOralPointsDisplay_formatsCorrectly() {
        let config = KBRegionalConfig.forRegion(.colorado)
        XCTAssertEqual(config.oralPointsDisplay, "5 pts")
    }

    func testWrittenTimeLimitDisplay_formatsAsMinutes() {
        let colorado = KBRegionalConfig.forRegion(.colorado)
        XCTAssertEqual(colorado.writtenTimeLimitDisplay, "15 min")

        let washington = KBRegionalConfig.forRegion(.washington)
        XCTAssertEqual(washington.writtenTimeLimitDisplay, "45 min")
    }

    func testConferenceTimeDisplay_formatsAsSeconds() {
        let config = KBRegionalConfig.forRegion(.colorado)
        XCTAssertEqual(config.conferenceTimeDisplay, "15 sec")
    }

    func testConferringRuleDescription_returnsCorrectDescription() {
        let colorado = KBRegionalConfig.forRegion(.colorado)
        XCTAssertEqual(colorado.conferringRuleDescription, "Hand signals only (no verbal)")

        let minnesota = KBRegionalConfig.forRegion(.minnesota)
        XCTAssertEqual(minnesota.conferringRuleDescription, "Verbal discussion allowed")
    }

    // MARK: - Default Configuration Tests

    func testDefault_returnsColoradoConfig() {
        let defaultConfig = KBRegionalConfig.default
        let colorado = KBRegionalConfig.forRegion(.colorado)

        XCTAssertEqual(defaultConfig.region, colorado.region)
        XCTAssertEqual(defaultConfig.writtenQuestionCount, colorado.writtenQuestionCount)
        XCTAssertEqual(defaultConfig.oralPointsPerCorrect, colorado.oralPointsPerCorrect)
    }

    // MARK: - Key Differences Tests

    func testKeyDifferences_coloradoVsMinnesota_identifiesConferring() {
        let colorado = KBRegionalConfig.forRegion(.colorado)
        let minnesota = KBRegionalConfig.forRegion(.minnesota)

        let differences = colorado.keyDifferences(from: minnesota)

        XCTAssertTrue(differences.contains { $0.contains("Conferring") })
        XCTAssertTrue(differences.contains { $0.contains("Written points") })
        XCTAssertTrue(differences.contains { $0.contains("SOS") })
    }

    func testKeyDifferences_coloradoVsWashington_identifiesTimeAndCount() {
        let colorado = KBRegionalConfig.forRegion(.colorado)
        let washington = KBRegionalConfig.forRegion(.washington)

        let differences = colorado.keyDifferences(from: washington)

        XCTAssertTrue(differences.contains { $0.contains("Written:") && $0.contains("questions") })
        XCTAssertTrue(differences.contains { $0.contains("Written time") })
    }

    func testKeyDifferences_sameRegion_returnsEmpty() {
        let colorado = KBRegionalConfig.forRegion(.colorado)

        let differences = colorado.keyDifferences(from: colorado)

        XCTAssertTrue(differences.isEmpty)
    }

    // MARK: - Equatable Tests

    func testEquatable_sameConfigs_areEqual() {
        let config1 = KBRegionalConfig.forRegion(.colorado)
        let config2 = KBRegionalConfig.forRegion(.colorado)

        XCTAssertEqual(config1, config2)
    }

    func testEquatable_differentConfigs_areNotEqual() {
        let colorado = KBRegionalConfig.forRegion(.colorado)
        let minnesota = KBRegionalConfig.forRegion(.minnesota)

        XCTAssertNotEqual(colorado, minnesota)
    }

    // MARK: - Codable Tests

    func testCodable_encodesAndDecodes() throws {
        let config = KBRegionalConfig.forRegion(.minnesota)

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(KBRegionalConfig.self, from: data)

        XCTAssertEqual(decoded.region, config.region)
        XCTAssertEqual(decoded.writtenQuestionCount, config.writtenQuestionCount)
        XCTAssertEqual(decoded.verbalConferringAllowed, config.verbalConferringAllowed)
        XCTAssertEqual(decoded.sosBonus, config.sosBonus)
    }

    // MARK: - KBSessionConfig Tests

    func testSessionConfig_writtenPractice_usesRegionDefaults() {
        let config = KBSessionConfig.writtenPractice(region: .colorado)

        XCTAssertEqual(config.region, .colorado)
        XCTAssertEqual(config.roundType, .written)
        XCTAssertEqual(config.questionCount, 60)  // Colorado default
        XCTAssertEqual(config.timeLimit, 900)  // 15 minutes
    }

    func testSessionConfig_writtenPractice_allowsCustomization() {
        let config = KBSessionConfig.writtenPractice(
            region: .colorado,
            questionCount: 20,
            timeLimit: 300,
            domains: [.science, .mathematics],
            difficulty: .varsity
        )

        XCTAssertEqual(config.questionCount, 20)
        XCTAssertEqual(config.timeLimit, 300)
        XCTAssertEqual(config.domains, [.science, .mathematics])
        XCTAssertEqual(config.difficulty, .varsity)
    }

    func testSessionConfig_oralPractice_usesRegionDefaults() {
        let config = KBSessionConfig.oralPractice(region: .minnesota)

        XCTAssertEqual(config.region, .minnesota)
        XCTAssertEqual(config.roundType, .oral)
        XCTAssertEqual(config.questionCount, 50)
        XCTAssertNil(config.timeLimit)  // Oral rounds have no time limit
    }

    func testSessionConfig_quickPractice_usesCustomCount() {
        let config = KBSessionConfig.quickPractice(region: .washington, roundType: .written, questionCount: 10)

        XCTAssertEqual(config.questionCount, 10)
        XCTAssertEqual(config.roundType, .written)
        // Time limit should be proportional: 10 questions * 15 seconds
        XCTAssertEqual(config.timeLimit, 150)
    }

    func testSessionConfig_quickPractice_oralHasNoTimeLimit() {
        let config = KBSessionConfig.quickPractice(region: .colorado, roundType: .oral, questionCount: 10)

        XCTAssertEqual(config.roundType, .oral)
        XCTAssertNil(config.timeLimit)
    }

    func testSessionConfig_codable_encodesAndDecodes() throws {
        let config = KBSessionConfig.writtenPractice(
            region: .minnesota,
            questionCount: 30,
            domains: [.science]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(KBSessionConfig.self, from: data)

        XCTAssertEqual(decoded.region, config.region)
        XCTAssertEqual(decoded.roundType, config.roundType)
        XCTAssertEqual(decoded.questionCount, config.questionCount)
        XCTAssertEqual(decoded.domains, config.domains)
    }

    // MARK: - Rule Validation Tests (Important for Competition Accuracy)

    func testColorado_verbalConferringProhibited() {
        // CRITICAL: Colorado explicitly prohibits verbal conferring
        let config = KBRegionalConfig.forRegion(.colorado)
        XCTAssertFalse(
            config.verbalConferringAllowed,
            "Colorado rules prohibit verbal conferring. This is a critical competition rule."
        )
    }

    func testMinnesota_hasSOSBonus() {
        // Minnesota has Speed of Sound (SOS) bonus for quick answers
        let config = KBRegionalConfig.forRegion(.minnesota)
        XCTAssertTrue(
            config.sosBonus,
            "Minnesota rules include SOS bonus. This is a distinguishing feature."
        )
    }

    func testWashington_longerWrittenTime() {
        // Washington has significantly longer written round
        let washington = KBRegionalConfig.forRegion(.washington)
        let colorado = KBRegionalConfig.forRegion(.colorado)

        XCTAssertGreaterThan(
            washington.writtenTimeLimit,
            colorado.writtenTimeLimit * 2,
            "Washington written round should be significantly longer than Colorado's."
        )
    }

    func testAllRegions_haveRebound() {
        // All regions support rebound (answering after opponent misses)
        for region in KBRegion.allCases {
            let config = KBRegionalConfig.forRegion(region)
            XCTAssertTrue(config.reboundEnabled, "\(region.displayName) should have rebound enabled")
        }
    }

    func testAllRegions_haveNoNegativeScoring() {
        // No regions use negative scoring
        for region in KBRegion.allCases {
            let config = KBRegionalConfig.forRegion(region)
            XCTAssertFalse(config.negativeScoring, "\(region.displayName) should not have negative scoring")
        }
    }
}
