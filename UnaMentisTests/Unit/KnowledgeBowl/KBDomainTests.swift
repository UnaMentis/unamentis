//
//  KBDomainTests.swift
//  UnaMentisTests
//
//  Tests for KBDomain enum - academic domain definitions
//  Critical for competition accuracy: weights, names, icons must be correct
//

import XCTest
@testable import UnaMentis

final class KBDomainTests: XCTestCase {

    // MARK: - All Cases Tests

    func testAllCases_has12Domains() {
        XCTAssertEqual(KBDomain.allCases.count, 12, "Knowledge Bowl has exactly 12 academic domains")
    }

    // MARK: - Display Name Tests

    func testDisplayName_allDomainsHaveNonEmptyNames() {
        for domain in KBDomain.allCases {
            XCTAssertFalse(domain.displayName.isEmpty, "\(domain) should have a display name")
        }
    }

    func testDisplayName_specificValues() {
        XCTAssertEqual(KBDomain.science.displayName, "Science")
        XCTAssertEqual(KBDomain.mathematics.displayName, "Mathematics")
        XCTAssertEqual(KBDomain.literature.displayName, "Literature")
        XCTAssertEqual(KBDomain.history.displayName, "History")
        XCTAssertEqual(KBDomain.socialStudies.displayName, "Social Studies")
        XCTAssertEqual(KBDomain.arts.displayName, "Arts")
        XCTAssertEqual(KBDomain.currentEvents.displayName, "Current Events")
        XCTAssertEqual(KBDomain.language.displayName, "Language")
        XCTAssertEqual(KBDomain.technology.displayName, "Technology")
        XCTAssertEqual(KBDomain.popCulture.displayName, "Pop Culture")
        XCTAssertEqual(KBDomain.religionPhilosophy.displayName, "Religion/Philosophy")
        XCTAssertEqual(KBDomain.miscellaneous.displayName, "Miscellaneous")
    }

    // MARK: - Icon Tests

    func testIcon_allDomainsHaveIcons() {
        for domain in KBDomain.allCases {
            XCTAssertFalse(domain.icon.isEmpty, "\(domain) should have an icon")
        }
    }

    func testIcon_usesValidSFSymbols() {
        // These are known valid SF Symbols
        let validSymbols = ["atom", "function", "book.closed", "clock.arrow.circlepath",
                           "globe.americas", "paintpalette", "newspaper", "textformat",
                           "cpu", "star", "sparkles", "questionmark.circle"]

        for domain in KBDomain.allCases {
            XCTAssertTrue(
                validSymbols.contains(domain.icon),
                "\(domain.icon) should be a valid SF Symbol for \(domain)"
            )
        }
    }

    // MARK: - Weight Tests (Critical for Competition Accuracy)

    func testWeight_allDomainsHavePositiveWeight() {
        for domain in KBDomain.allCases {
            XCTAssertGreaterThan(domain.weight, 0, "\(domain) should have positive weight")
        }
    }

    func testWeight_totalSumsTo100Percent() {
        let totalWeight = KBDomain.allCases.reduce(0.0) { $0 + $1.weight }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.001, "All domain weights should sum to 100%")
    }

    func testWeight_scienceHasHighestWeight() {
        // Science is traditionally the largest category in Knowledge Bowl
        let scienceWeight = KBDomain.science.weight
        for domain in KBDomain.allCases where domain != .science {
            XCTAssertGreaterThanOrEqual(
                scienceWeight,
                domain.weight,
                "Science should have the highest or equal weight"
            )
        }
    }

    func testWeight_specificValues() {
        // These weights represent typical Knowledge Bowl question distribution
        XCTAssertEqual(KBDomain.science.weight, 0.20, accuracy: 0.001)
        XCTAssertEqual(KBDomain.mathematics.weight, 0.15, accuracy: 0.001)
        XCTAssertEqual(KBDomain.literature.weight, 0.12, accuracy: 0.001)
        XCTAssertEqual(KBDomain.history.weight, 0.12, accuracy: 0.001)
        XCTAssertEqual(KBDomain.socialStudies.weight, 0.10, accuracy: 0.001)
        XCTAssertEqual(KBDomain.arts.weight, 0.08, accuracy: 0.001)
        XCTAssertEqual(KBDomain.currentEvents.weight, 0.08, accuracy: 0.001)
        XCTAssertEqual(KBDomain.language.weight, 0.05, accuracy: 0.001)
        XCTAssertEqual(KBDomain.technology.weight, 0.04, accuracy: 0.001)
        XCTAssertEqual(KBDomain.popCulture.weight, 0.03, accuracy: 0.001)
        XCTAssertEqual(KBDomain.religionPhilosophy.weight, 0.02, accuracy: 0.001)
        XCTAssertEqual(KBDomain.miscellaneous.weight, 0.01, accuracy: 0.001)
    }

    // MARK: - Identifiable Tests

    func testIdentifiable_idMatchesRawValue() {
        for domain in KBDomain.allCases {
            XCTAssertEqual(domain.id, domain.rawValue)
        }
    }

    // MARK: - Codable Tests

    func testCodable_encodesAsRawValue() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(KBDomain.science)
        let string = String(data: data, encoding: .utf8)
        XCTAssertEqual(string, "\"science\"")
    }

    func testCodable_decodesFromRawValue() throws {
        let json = "\"mathematics\""
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let domain = try decoder.decode(KBDomain.self, from: data)
        XCTAssertEqual(domain, .mathematics)
    }

    func testCodable_roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in KBDomain.allCases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(KBDomain.self, from: data)
            XCTAssertEqual(decoded, original, "Round-trip failed for \(original)")
        }
    }
}
