//
//  KBRegionalConfig.swift
//  UnaMentis
//
//  Regional configuration for Knowledge Bowl competitions
//  Supports Colorado, Minnesota, and Washington rules
//

import Foundation

// MARK: - Region

/// Supported Knowledge Bowl regions with distinct rule sets
enum KBRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case colorado
    case coloradoSprings  // Special sub-region with stricter hand signal rules
    case minnesota
    case washington

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .colorado: return "Colorado"
        case .coloradoSprings: return "Colorado Springs"
        case .minnesota: return "Minnesota"
        case .washington: return "Washington"
        }
    }

    var abbreviation: String {
        switch self {
        case .colorado, .coloradoSprings: return "CO"
        case .minnesota: return "MN"
        case .washington: return "WA"
        }
    }

    /// Get the configuration for this region
    var config: KBRegionalConfig {
        KBRegionalConfig.forRegion(self)
    }
}

// MARK: - Regional Configuration

/// Complete rule configuration for a Knowledge Bowl region
struct KBRegionalConfig: Codable, Equatable, Sendable {
    let region: KBRegion

    // MARK: - Team Configuration
    let teamsPerMatch: Int
    let minTeamSize: Int
    let maxTeamSize: Int
    let activePlayersInOral: Int

    // MARK: - Written Round
    let writtenQuestionCount: Int
    let writtenTimeLimit: TimeInterval  // in seconds
    let writtenPointsPerCorrect: Int

    // MARK: - Oral Round
    let oralQuestionCount: Int
    let oralPointsPerCorrect: Int
    let reboundEnabled: Bool

    // MARK: - Conference Rules
    let conferenceTime: TimeInterval  // in seconds
    let verbalConferringAllowed: Bool
    let handSignalsAllowed: Bool

    // MARK: - Scoring
    let negativeScoring: Bool
    let sosBonus: Bool  // "Speed of Sound" bonus for quick answers

    // MARK: - Computed Properties

    /// Points per question for display
    var writtenPointsDisplay: String {
        "\(writtenPointsPerCorrect) pt\(writtenPointsPerCorrect == 1 ? "" : "s")"
    }

    var oralPointsDisplay: String {
        "\(oralPointsPerCorrect) pts"
    }

    /// Time limit formatted for display
    var writtenTimeLimitDisplay: String {
        let minutes = Int(writtenTimeLimit) / 60
        return "\(minutes) min"
    }

    /// Conference time formatted for display
    var conferenceTimeDisplay: String {
        "\(Int(conferenceTime)) sec"
    }

    /// Conferring rule description
    var conferringRuleDescription: String {
        if verbalConferringAllowed {
            return "Verbal discussion allowed"
        } else if handSignalsAllowed {
            return "Hand signals only (no verbal)"
        } else {
            return "No conferring"
        }
    }
}

// MARK: - Regional Configuration Factory

extension KBRegionalConfig {
    /// Get the configuration for a specific region
    static func forRegion(_ region: KBRegion) -> KBRegionalConfig {
        switch region {
        case .colorado:
            return KBRegionalConfig(
                region: .colorado,
                teamsPerMatch: 3,
                minTeamSize: 1,
                maxTeamSize: 4,
                activePlayersInOral: 4,
                writtenQuestionCount: 60,
                writtenTimeLimit: 900,  // 15 minutes
                writtenPointsPerCorrect: 1,
                oralQuestionCount: 50,
                oralPointsPerCorrect: 5,
                reboundEnabled: true,
                conferenceTime: 15,
                verbalConferringAllowed: false,  // CRITICAL: Colorado prohibits verbal conferring
                handSignalsAllowed: true,
                negativeScoring: false,
                sosBonus: false
            )

        case .coloradoSprings:
            return KBRegionalConfig(
                region: .coloradoSprings,
                teamsPerMatch: 3,
                minTeamSize: 1,
                maxTeamSize: 4,
                activePlayersInOral: 4,
                writtenQuestionCount: 60,
                writtenTimeLimit: 900,  // 15 minutes
                writtenPointsPerCorrect: 1,
                oralQuestionCount: 50,
                oralPointsPerCorrect: 5,
                reboundEnabled: true,
                conferenceTime: 15,
                verbalConferringAllowed: false,
                handSignalsAllowed: true,  // Stricter hand signal rules
                negativeScoring: false,
                sosBonus: false
            )

        case .minnesota:
            return KBRegionalConfig(
                region: .minnesota,
                teamsPerMatch: 3,
                minTeamSize: 3,
                maxTeamSize: 6,
                activePlayersInOral: 4,
                writtenQuestionCount: 60,
                writtenTimeLimit: 900,  // 15 minutes
                writtenPointsPerCorrect: 2,  // 2 points per question
                oralQuestionCount: 50,
                oralPointsPerCorrect: 5,
                reboundEnabled: true,
                conferenceTime: 15,
                verbalConferringAllowed: true,  // Verbal discussion allowed
                handSignalsAllowed: true,
                negativeScoring: false,
                sosBonus: true  // Minnesota has SOS bonus
            )

        case .washington:
            return KBRegionalConfig(
                region: .washington,
                teamsPerMatch: 3,
                minTeamSize: 3,
                maxTeamSize: 5,
                activePlayersInOral: 4,
                writtenQuestionCount: 50,  // Only 50 questions
                writtenTimeLimit: 2700,  // 45 minutes (much longer!)
                writtenPointsPerCorrect: 2,
                oralQuestionCount: 50,
                oralPointsPerCorrect: 5,
                reboundEnabled: true,
                conferenceTime: 15,
                verbalConferringAllowed: true,
                handSignalsAllowed: true,
                negativeScoring: false,
                sosBonus: false
            )
        }
    }

    /// Default configuration (Colorado)
    static var `default`: KBRegionalConfig {
        forRegion(.colorado)
    }
}

// MARK: - Rule Comparison Table

extension KBRegionalConfig {
    /// Key differences from other regions
    func keyDifferences(from other: KBRegionalConfig) -> [String] {
        var differences: [String] = []

        if writtenQuestionCount != other.writtenQuestionCount {
            differences.append("Written: \(writtenQuestionCount) vs \(other.writtenQuestionCount) questions")
        }

        if writtenTimeLimit != other.writtenTimeLimit {
            differences.append("Written time: \(writtenTimeLimitDisplay) vs \(other.writtenTimeLimitDisplay)")
        }

        if writtenPointsPerCorrect != other.writtenPointsPerCorrect {
            differences.append("Written points: \(writtenPointsPerCorrect) vs \(other.writtenPointsPerCorrect) per question")
        }

        if verbalConferringAllowed != other.verbalConferringAllowed {
            let selfVerbal = verbalConferringAllowed ? "verbal allowed" : "no verbal"
            let otherVerbal = other.verbalConferringAllowed ? "verbal allowed" : "no verbal"
            differences.append("Conferring: \(selfVerbal) vs \(otherVerbal)")
        }

        if sosBonus != other.sosBonus {
            let selfSOS = sosBonus ? "has SOS bonus" : "no SOS"
            let otherSOS = other.sosBonus ? "has SOS bonus" : "no SOS"
            differences.append("SOS: \(selfSOS) vs \(otherSOS)")
        }

        return differences
    }
}

// MARK: - Session Configuration

/// Configuration for a practice session
struct KBSessionConfig: Codable, Sendable {
    let region: KBRegion
    let roundType: KBRoundType
    let questionCount: Int
    let timeLimit: TimeInterval?
    let domains: [KBDomain]?
    let difficulty: KBDifficulty?
    let gradeLevel: KBGradeLevel?

    /// Create from regional defaults
    static func writtenPractice(
        region: KBRegion,
        questionCount: Int? = nil,
        timeLimit: TimeInterval? = nil,
        domains: [KBDomain]? = nil,
        difficulty: KBDifficulty? = nil,
        gradeLevel: KBGradeLevel? = nil
    ) -> KBSessionConfig {
        let config = region.config
        return KBSessionConfig(
            region: region,
            roundType: .written,
            questionCount: questionCount ?? config.writtenQuestionCount,
            timeLimit: timeLimit ?? config.writtenTimeLimit,
            domains: domains,
            difficulty: difficulty,
            gradeLevel: gradeLevel
        )
    }

    static func oralPractice(
        region: KBRegion,
        questionCount: Int? = nil,
        domains: [KBDomain]? = nil,
        difficulty: KBDifficulty? = nil,
        gradeLevel: KBGradeLevel? = nil
    ) -> KBSessionConfig {
        let config = region.config
        return KBSessionConfig(
            region: region,
            roundType: .oral,
            questionCount: questionCount ?? config.oralQuestionCount,
            timeLimit: nil,  // Oral rounds don't have overall time limit
            domains: domains,
            difficulty: difficulty,
            gradeLevel: gradeLevel
        )
    }

    /// Quick practice with custom question count
    static func quickPractice(
        region: KBRegion,
        roundType: KBRoundType,
        questionCount: Int = 10
    ) -> KBSessionConfig {
        let config = region.config
        let timePerQuestion: TimeInterval = roundType == .written ? 15 : 0
        return KBSessionConfig(
            region: region,
            roundType: roundType,
            questionCount: questionCount,
            timeLimit: roundType == .written ? TimeInterval(questionCount) * timePerQuestion : nil,
            domains: nil,
            difficulty: nil,
            gradeLevel: nil
        )
    }
}

// MARK: - Preview Support

#if DEBUG
extension KBRegionalConfig {
    /// Summary for debugging/preview
    var debugSummary: String {
        """
        \(region.displayName) (\(region.abbreviation))
        Teams: \(teamsPerMatch) per match, \(minTeamSize)-\(maxTeamSize) players
        Written: \(writtenQuestionCount) questions, \(writtenTimeLimitDisplay), \(writtenPointsPerCorrect) pt each
        Oral: \(oralQuestionCount) questions, \(oralPointsPerCorrect) pts each
        Conference: \(conferenceTimeDisplay), \(conferringRuleDescription)
        SOS Bonus: \(sosBonus ? "Yes" : "No")
        """
    }
}
#endif
