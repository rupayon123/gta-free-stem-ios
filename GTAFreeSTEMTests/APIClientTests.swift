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

    func testOpportunityDecodesFromSharedPublicFeed() throws {
        let json = """
        {
          "name": "GTA FREE STEM Opportunities public feed",
          "schemaVersion": 1,
          "count": 1,
          "lastDataChange": "2026-06-12",
          "opportunities": [{
            "id": "feed-1",
            "title": "Library Coding Lab",
            "organization": "Public Library",
            "description": "Free coding workshop.",
            "category": "Coding & Robotics",
            "city": "Markham",
            "region": "York",
            "ageMin": 8,
            "ageMax": 12,
            "language": ["en"],
            "cost": "Free",
            "sourceUrl": "https://example.com",
            "status": "active",
            "tags": ["coding"],
            "volunteerHoursEligible": false,
            "coopEligible": false
          }]
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(OpportunityListResponse.self, from: json)
        XCTAssertEqual(payload.data.first?.title, "Library Coding Lab")
        XCTAssertEqual(payload.meta?.activeCount, 1)
        XCTAssertEqual(payload.meta?.lastUpdated, "2026-06-12")
    }

    func testAppTextLoadsLaunchLanguages() {
        XCTAssertEqual(AppLanguage.allCases.count, 18)
        XCTAssertEqual(AppText.shared.string("browse", language: .ko), "둘러보기")
        XCTAssertEqual(AppText.shared.string("settings", language: .bn), "সেটিংস")
        XCTAssertEqual(AppText.shared.string("filters", language: .hu), "Szűrők")
    }

    func testEveryLaunchLanguageHasEveryEnglishKey() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "app_strings", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let english = try XCTUnwrap(json["en"] as? [String: String])

        for language in AppLanguage.allCases {
            let strings = try XCTUnwrap(json[language.rawValue] as? [String: String])
            for key in english.keys {
                XCTAssertNotNil(strings[key], "\(language.rawValue) is missing \(key)")
            }
        }
    }

    func testPermissionCopyIsLocalizedForLaunchLanguages() {
        for language in AppLanguage.allCases {
            XCTAssertNotNil(
                Bundle.main.path(
                    forResource: "InfoPlist",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language.localeIdentifier
                ),
                "\(language.rawValue) is missing localized permission copy"
            )
        }
    }

    func testAPIClientRejectsPlainHTTP() async throws {
        let client = APIClient(feedURL: URL(string: "http://example.com/opportunities.json")!)

        do {
            let _: OpportunityListResponse = try await client.opportunities(query: "", mode: .all, filters: OpportunityFilters())
            XCTFail("Plain HTTP should not be accepted by the app API client.")
        } catch APIError.insecureConnection {
            return
        } catch {
            XCTFail("Expected insecureConnection, got \(error)")
        }
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
