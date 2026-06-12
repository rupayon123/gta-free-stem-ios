import XCTest
@testable import GTAFreeSTEM

final class APIClientTests: XCTestCase {
    func testOpportunityDecodesFromRailsPayload() throws {
        let json = """
        {
          "data": [{
            "id": "tpl-1",
            "title": "Robotics Club",
            "organization": "Public Library",
            "description": "Build robots.",
            "summary": "Build robots.",
            "category": "Coding & Robotics",
            "city": "Toronto",
            "region": "Toronto",
            "address": "100 Queen St W",
            "latitude": 43.65,
            "longitude": -79.38,
            "startDate": "2026-06-20T12:00:00Z",
            "endDate": null,
            "deadline": null,
            "ageMin": 12,
            "ageMax": 18,
            "language": ["en"],
            "cost": "Free to join",
            "sourceUrl": "https://example.com",
            "registrationUrl": "https://example.com/register",
            "status": "active",
            "volunteerHoursEligible": true,
            "coopEligible": false,
            "tags": ["robotics"]
          }],
          "meta": { "activeCount": 1, "lastUpdated": "2026-06-12T00:00:00Z" }
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(OpportunityListResponse.self, from: json)
        XCTAssertEqual(payload.data.first?.title, "Robotics Club")
        XCTAssertEqual(payload.meta?.activeCount, 1)
    }

    func testAppTextLoadsLaunchLanguages() {
        XCTAssertEqual(AppLanguage.allCases.count, 18)
        XCTAssertEqual(AppText.shared.string("browse", language: .ko), "둘러보기")
        XCTAssertEqual(AppText.shared.string("settings", language: .bn), "সেটিংস")
        XCTAssertEqual(AppText.shared.string("filters", language: .hu), "Szűrők")
    }

    func testLocalOpportunitySnapshotFiltersByLanguage() throws {
        var filters = OpportunityFilters()
        filters.language = "en"

        let response = try LocalOpportunitySnapshot.load(query: "", mode: .all, filters: filters)

        XCTAssertFalse(response.data.isEmpty)
        XCTAssertTrue(response.data.allSatisfy { $0.language.contains("en") })
        XCTAssertEqual(response.meta?.activeCount, response.data.count)
    }
}
