import Foundation
import XCTest
@testable import GTAFreeSTEM

final class FreeOpportunityEligibilityTests: XCTestCase {
    func testExplicitFreeEligibilityRejectsMissingAmbiguousAndPaidCosts() {
        XCTAssertTrue(OpportunityCostEligibility.isExplicitlyFree("Free"))
        XCTAssertTrue(OpportunityCostEligibility.isExplicitlyFree("Free to join"))
        XCTAssertTrue(OpportunityCostEligibility.isExplicitlyFree("FREE LISTING"))
        XCTAssertTrue(OpportunityCostEligibility.isExplicitlyFree("$0"))

        XCTAssertFalse(OpportunityCostEligibility.isExplicitlyFree(nil))
        XCTAssertFalse(OpportunityCostEligibility.isExplicitlyFree("   "))
        XCTAssertFalse(OpportunityCostEligibility.isExplicitlyFree("Cost not listed"))
        XCTAssertFalse(OpportunityCostEligibility.isExplicitlyFree("$25 per workshop"))
        XCTAssertFalse(OpportunityCostEligibility.isExplicitlyFree("Free to join; $15 materials fee"))
        XCTAssertFalse(OpportunityCostEligibility.isExplicitlyFree("First session free; $30 after"))
    }

    func testFeedFiltersPaidMissingAndMalformedCostsWithoutCallingThemFree() throws {
        let data = """
        {
          "count": 5,
          "lastDataChange": "2026-08-06T12:00:00Z",
          "opportunities": [
            { "id": "verified", "title": "Verified", "cost": "Free to join", "sourceUrl": "https://example.com/verified" },
            { "id": "paid", "title": "Paid", "cost": "$25 per workshop", "sourceUrl": "https://example.com/paid" },
            { "id": "ambiguous", "title": "Ambiguous", "cost": "Free to join; $15 materials fee", "sourceUrl": "https://example.com/ambiguous" },
            { "id": "missing", "title": "Missing", "sourceUrl": "https://example.com/missing" },
            { "id": "malformed", "title": "Malformed", "cost": { "amount": 0 }, "sourceUrl": "https://example.com/malformed" }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpportunityListResponse.self, from: data)

        XCTAssertEqual(response.data.map(\.id), ["verified"])
        XCTAssertEqual(response.meta?.activeCount, 1)
        XCTAssertEqual(response.data.first?.cost, "Free to join")
    }

    func testSearchFilterDefendsAgainstPaidRecordsCreatedOutsideTheFeedDecoder() {
        let results = LocalOpportunitySnapshot.filter(
            [opportunity(id: "free", cost: "Free to join"), opportunity(id: "paid", cost: "$25")],
            query: "",
            mode: .all,
            filters: OpportunityFilters()
        )

        XCTAssertEqual(results.map(\.id), ["free"])
    }

    func testBundledFeedKeepsAllCurrentExplicitlyFreeListings() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundleURL = repoRoot.appendingPathComponent("GTAFreeSTEM/Resources/opportunities.json")
        let data = try Data(contentsOf: bundleURL)
        let rawFeed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let rawListings = try XCTUnwrap(rawFeed["opportunities"] as? [[String: Any]])
        let response = try JSONDecoder().decode(OpportunityListResponse.self, from: data)

        XCTAssertFalse(response.data.isEmpty)
        XCTAssertEqual(response.data.count, rawListings.count)
        XCTAssertTrue(response.data.allSatisfy(\.isExplicitlyFree))
    }

    private func opportunity(id: String, cost: String) -> Opportunity {
        Opportunity(
            id: id,
            title: id,
            organization: "Community Lab",
            description: "STEM opportunity.",
            summary: nil,
            category: "Coding & Robotics",
            city: "Toronto",
            region: "Toronto",
            address: nil,
            latitude: nil,
            longitude: nil,
            startDate: nil,
            endDate: nil,
            deadline: nil,
            ageMin: 10,
            ageMax: 18,
            language: ["en"],
            cost: cost,
            sourceUrl: "https://example.com/\(id)",
            registrationUrl: nil,
            status: "active",
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: [],
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil
        )
    }
}
