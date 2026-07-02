import XCTest
@testable import GTAFreeSTEM
import SwiftData

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

    func testOpportunityDecodesTranslatedDynamicFields() throws {
        let json = """
        {
          "opportunities": [{
            "id": "translated-1",
            "title": "Robotics Club",
            "organization": "Public Library",
            "description": "Build robots.",
            "summary": "Build robots.",
            "category": "Coding & Robotics",
            "city": "Toronto",
            "region": "Toronto",
            "ageMin": 12,
            "ageMax": 18,
            "language": ["en"],
            "cost": "Free",
            "sourceUrl": "https://example.com",
            "status": "active",
            "tags": ["robotics"],
            "translations": {
              "es": {
                "title": "Club de robótica",
                "provider": "Biblioteca pública",
                "description": "Construye robots.",
                "summary": "Construye robots.",
                "category": "Programación y robótica",
                "city": "Toronto",
                "region": "Toronto",
                "cost": "Gratis",
                "tags": ["robótica"]
              },
              "zh-Hans": {
                "title": "机器人俱乐部"
              }
            }
          }]
        }
        """.data(using: .utf8)!

        let opportunity = try XCTUnwrap(JSONDecoder().decode(OpportunityListResponse.self, from: json).data.first)

        XCTAssertEqual(opportunity.localizedTitle(language: .es), "Club de robótica")
        XCTAssertEqual(opportunity.localizedOrganization(language: .es), "Biblioteca pública")
        XCTAssertEqual(opportunity.localizedSummary(language: .es), "Construye robots.")
        XCTAssertEqual(opportunity.localizedCategory(language: .es), "Programación y robótica")
        XCTAssertEqual(opportunity.localizedCost(language: .es), "Gratis")
        XCTAssertEqual(opportunity.localizedTags(language: .es), ["robótica"])
        XCTAssertEqual(opportunity.localizedTitle(language: .zh), "机器人俱乐部")
        XCTAssertEqual(opportunity.localizedTitle(language: .fr), "Robotics Club")
    }

    func testAppTextLoadsLaunchLanguages() {
        XCTAssertEqual(AppLanguage.allCases.count, 18)
        XCTAssertEqual(AppText.shared.string("browse", language: .ko), "둘러보기")
        XCTAssertEqual(AppText.shared.string("settings", language: .bn), "সেটিংস")
        XCTAssertEqual(AppText.shared.string("filters", language: .hu), "Szűrők")
        XCTAssertEqual(AppText.shared.string("openDetailsHint", language: .es), "Abre los detalles de la oportunidad.")
    }

    @MainActor
    func testCategoryNamesUseLocalizedStringsWhenAvailable() {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: "preferredLanguageCode")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "preferredLanguageCode")
            } else {
                defaults.removeObject(forKey: "preferredLanguageCode")
            }
        }

        let session = SessionStore()
        session.preferredLanguageCode = AppLanguage.es.rawValue

        XCTAssertEqual(
            session.categoryName("Coding & Robotics"),
            AppText.shared.string("categoryCodingAndRobotics", language: .es)
        )
        XCTAssertEqual(session.categoryName("Mystery Category"), "Mystery Category")
    }

    @MainActor
    func testSessionUsesTranslatedOpportunityFieldsWhenAvailable() {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: "preferredLanguageCode")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "preferredLanguageCode")
            } else {
                defaults.removeObject(forKey: "preferredLanguageCode")
            }
        }

        let session = SessionStore()
        session.preferredLanguageCode = AppLanguage.es.rawValue
        let translated = opportunity(
            id: "session-translated",
            title: "Robotics Club",
            organization: "Public Library",
            description: "Build robots.",
            summary: "Build robots.",
            translations: [
                "es": OpportunityTranslation(
                    title: "Club de robótica",
                    organization: "Biblioteca pública",
                    summary: "Construye robots.",
                    category: "Programación y robótica",
                    city: "Toronto",
                    region: "Ontario",
                    cost: "Gratis"
                )
            ]
        )

        XCTAssertEqual(session.title(for: translated), "Club de robótica")
        XCTAssertEqual(session.organization(for: translated), "Biblioteca pública")
        XCTAssertEqual(session.summary(for: translated), "Construye robots.")
        XCTAssertEqual(session.categoryName(for: translated), "Programación y robótica")
        XCTAssertEqual(session.city(for: translated), "Toronto")
        XCTAssertEqual(session.region(for: translated), "Ontario")
        XCTAssertEqual(session.cost(for: translated), "Gratis")
    }

    func testEveryLaunchLanguageHasEveryEnglishKey() throws {
        let url = try XCTUnwrap(AppResources.url(forResource: "app_strings", withExtension: "json"))
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

    func testEveryLaunchLanguageHasMetadataAndNonEmptyStrings() throws {
        let url = try XCTUnwrap(AppResources.url(forResource: "app_strings", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let meta = try XCTUnwrap(json["languageMeta"] as? [String: [String: String]])
        let english = try XCTUnwrap(json["en"] as? [String: String])

        for language in AppLanguage.allCases {
            let info = try XCTUnwrap(meta[language.rawValue], "\(language.rawValue) is missing language metadata")
            XCTAssertFalse((info["label"] ?? "").isEmpty, "\(language.rawValue) is missing a language label")
            XCTAssertFalse((info["native"] ?? "").isEmpty, "\(language.rawValue) is missing a native language label")
            XCTAssertEqual(info["dir"], [.ar, .fa, .ur].contains(language) ? "rtl" : "ltr")

            let strings = try XCTUnwrap(json[language.rawValue] as? [String: String])
            for key in english.keys {
                let value = try XCTUnwrap(strings[key], "\(language.rawValue) is missing \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language.rawValue).\(key) is empty")
            }
        }
    }

    func testReleaseStringsDoNotExposeBackendSetupInstructions() throws {
        let url = try XCTUnwrap(AppResources.url(forResource: "app_strings", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let forbiddenPhrases = ["connect rails", "oauth callback", "before testflight"]

        for language in AppLanguage.allCases {
            let strings = try XCTUnwrap(json[language.rawValue] as? [String: String])
            for (key, value) in strings {
                let lowercased = value.lowercased()
                for phrase in forbiddenPhrases {
                    XCTAssertFalse(
                        lowercased.contains(phrase),
                        "\(language.rawValue).\(key) exposes developer setup copy: \(value)"
                    )
                }
            }
        }
    }

    func testSettingsDoesNotExposeAppleSignInWithoutTokenExchange() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsView = repoRoot.appendingPathComponent("GTAFreeSTEM/SettingsView.swift")
        let sessionStore = repoRoot.appendingPathComponent("GTAFreeSTEM/SessionStore.swift")

        XCTAssertFalse(
            try String(contentsOf: settingsView).contains("SignInWithAppleButton"),
            "Do not show Sign in with Apple until iOS exchanges Apple credentials for a backend API token."
        )
        XCTAssertFalse(
            try String(contentsOf: sessionStore).contains("ASAuthorization"),
            "SessionStore should not handle Apple authorization without a backend token exchange."
        )
    }

    func testPermissionCopyIsLocalizedForLaunchLanguages() {
        for language in AppLanguage.allCases {
            XCTAssertNotNil(
                AppResources.path(
                    forResource: "InfoPlist",
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: language.localeIdentifier
                ),
                "\(language.rawValue) is missing localized permission copy"
            )
        }
    }

    func testPrivacyManifestDeclaresAppOnlyUserDefaultsAccess() throws {
        let url = try XCTUnwrap(AppResources.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue((plist["NSPrivacyTrackingDomains"] as? [String] ?? []).isEmpty)
        XCTAssertTrue((plist["NSPrivacyCollectedDataTypes"] as? [Any] ?? []).isEmpty)

        let accessedAPITypes = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaultsEntry = accessedAPITypes.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = try XCTUnwrap(userDefaultsEntry?["NSPrivacyAccessedAPITypeReasons"] as? [String])
        XCTAssertTrue(reasons.contains("CA92.1"))
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

    func testOpportunitiesApplyBundledTranslationFallbackToSearch() async throws {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: "preferredLanguageCode")
        defaults.set("fr", forKey: "preferredLanguageCode")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "preferredLanguageCode")
            } else {
                defaults.removeObject(forKey: "preferredLanguageCode")
            }
            URLProtocolStub.reset()
        }

        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)

        let liveOnly = """
        {
          "opportunities": [{
            "id": "cvc-conservation-youth-corps-2026",
            "title": "Conservation Volunteer Day",
            "organization": "Credit Valley Conservation",
            "description": "Volunteer in support of conservation projects.",
            "category": "Volunteer Hours",
            "city": "Mississauga",
            "region": "Peel",
            "ageMin": 14,
            "ageMax": 18,
            "language": ["en"],
            "cost": "Free",
            "sourceUrl": "https://example.com/cvc",
            "status": "active",
            "volunteerHoursEligible": true,
            "coopEligible": false,
            "tags": ["volunteer"],
            "sourceConfidence": "generated"
          }]
        }
        """

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: liveOnly.data(using: .utf8)!
        )

        let response = try await client.opportunities(query: "benevolat", mode: .all, filters: OpportunityFilters())

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.id, "cvc-conservation-youth-corps-2026")
        XCTAssertEqual(
            response.data.first?.localizedSummary(language: .fr),
            "Occasion gratuite de Heures de benevolat offerte par Credit Valley Conservation a Mississauga. Ages 14-18. Consultez la source pour les details."
        )
        XCTAssertEqual(response.data.first?.localizedCategory(language: .fr), "Heures de benevolat")
    }

    func testLocalOpportunitySnapshotFiltersByLanguage() throws {
        var filters = OpportunityFilters()
        filters.language = "en"

        let response = try LocalOpportunitySnapshot.load(query: "", mode: .all, filters: filters)

        XCTAssertFalse(response.data.isEmpty)
        XCTAssertTrue(response.data.allSatisfy { $0.language.contains("en") })
        XCTAssertEqual(response.meta?.activeCount, response.data.count)
    }

    func testLocalOpportunitySnapshotMatchesLocaleAwareLanguageFilters() {
        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "enca", title: "Metro STEM Day", language: ["en-CA"]),
                opportunity(id: "es", title: "Día de STEM", language: ["es"])
            ],
            query: "",
            mode: .all,
            filters: { var filters = OpportunityFilters(); filters.language = "en"; return filters }()
        )

        XCTAssertEqual(results.map(\.id), ["enca"])
    }

    func testSearchMatchesMultipleTermsAcrossFields() {
        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "match", title: "Robotics Lab", organization: "Library", city: "Toronto", tags: ["makerspace"]),
                opportunity(id: "miss", title: "Robotics Lab", organization: "Library", city: "Markham", region: "York", tags: ["makerspace"])
            ],
            query: "robotics toronto",
            mode: .all,
            filters: OpportunityFilters()
        )

        XCTAssertEqual(results.map(\.id), ["match"])
    }

    func testSearchIsCaseAndDiacriticInsensitive() {
        let results = LocalOpportunitySnapshot.filter(
            [opportunity(id: "accented", title: "Cafe Coding Club", organization: "STEM Cafe", description: "Robotics and AI")],
            query: "café ROBOTICS",
            mode: .all,
            filters: OpportunityFilters()
        )

        XCTAssertEqual(results.map(\.id), ["accented"])
    }

    func testSearchMatchesTranslatedFieldsAndEnglishFallback() {
        let translated = opportunity(
            id: "spanish",
            title: "Library Lab",
            description: "Build machines.",
            category: "Makerspace & Fabrication",
            tags: ["makerspace"],
            translations: [
                "es": OpportunityTranslation(
                    title: "Club de robótica",
                    summary: "Aprende programación con robots.",
                    tags: ["robótica", "programación"]
                )
            ]
        )
        let englishFallback = opportunity(id: "english", title: "Robotics Workshop", tags: ["robotics"])

        let spanishResults = LocalOpportunitySnapshot.filter(
            [translated, englishFallback],
            query: "robótica",
            mode: .all,
            filters: OpportunityFilters(),
            displayLanguage: .es
        )
        let englishResults = LocalOpportunitySnapshot.filter(
            [translated, englishFallback],
            query: "robotics",
            mode: .all,
            filters: OpportunityFilters(),
            displayLanguage: .es
        )

        XCTAssertEqual(spanishResults.map(\.id), ["spanish"])
        XCTAssertEqual(englishResults.map(\.id), ["english"])
    }

    func testSearchFiltersModesAndNewFinds() {
        var filters = OpportunityFilters()
        filters.includeNewFinds = false

        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "volunteer", title: "Teen Lab", volunteerHoursEligible: true, tags: ["teen"]),
                opportunity(id: "coop", title: "Co-op Lab", coopEligible: true, tags: ["shsm"]),
                opportunity(id: "review", title: "Needs Review Lab", status: "needs_review", tags: ["teen"], isNewFind: true)
            ],
            query: "lab",
            mode: .highSchool,
            filters: filters
        )

        XCTAssertEqual(Set(results.map { $0.id }), Set(["volunteer", "coop"]))
    }

    func testSearchFiltersModesAndHighSchoolTagsWithSynonyms() {
        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "co-op", title: "Co-op Program", tags: ["co-op"]),
                opportunity(id: "high-school", title: "High-school Mentorship Lab", tags: ["high-school"]),
                opportunity(id: "other", title: "Community Lab")
            ],
            query: "",
            mode: .highSchool,
            filters: OpportunityFilters()
        )

        XCTAssertEqual(Set(results.map { $0.id }), Set(["co-op", "high-school"]))
    }

    func testSearchFiltersPathwayTogglesAndScholarships() {
        let opportunities = [
            opportunity(id: "volunteer", title: "Volunteer Lab", category: "Volunteer Hours", volunteerHoursEligible: true),
            opportunity(id: "coop", title: "Co-op Lab", category: "Co-op & SHSM", coopEligible: true),
            opportunity(id: "mentor", title: "Mentor Lab", category: "Career & Mentorship", tags: ["mentor"]),
            opportunity(id: "scholarship", title: "Scholarship Award", category: "Scholarships"),
            opportunity(id: "other", title: "General Lab")
        ]

        var filters = OpportunityFilters()
        filters.volunteerHours = true
        XCTAssertEqual(LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .all, filters: filters).map(\.id), ["volunteer"])

        filters = OpportunityFilters()
        filters.coop = true
        XCTAssertEqual(LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .all, filters: filters).map(\.id), ["coop"])

        filters = OpportunityFilters()
        filters.mentorship = true
        XCTAssertEqual(LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .all, filters: filters).map(\.id), ["mentor"])

        filters = OpportunityFilters()
        filters.scholarships = true
        XCTAssertEqual(LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .all, filters: filters).map(\.id), ["scholarship"])

        let highSchoolResults = LocalOpportunitySnapshot.filter(opportunities, query: "", mode: .highSchool, filters: OpportunityFilters())
        XCTAssertEqual(Set(highSchoolResults.map(\.id)), Set(["volunteer", "coop", "mentor", "scholarship"]))
    }

    func testMapPinsAreSubsetOfFilteredListResults() {
        let opportunities = [
            opportunity(id: "mapped", title: "Mapped Lab", city: "Toronto", latitude: 43.654, longitude: -79.384, startDate: "2026-07-01T04:00:00.000Z"),
            opportunity(id: "list-only", title: "List Lab", city: "Toronto", startDate: "2026-07-02T04:00:00.000Z"),
            opportunity(id: "filtered-out", title: "Map Lab", city: "Markham", latitude: 43.856, longitude: -79.337, startDate: "2026-07-03T04:00:00.000Z")
        ]
        var filters = OpportunityFilters()
        filters.city = "Toronto"

        let filteredListResults = LocalOpportunitySnapshot.filter(opportunities, query: "lab", mode: .all, filters: filters)
        let mapPins = OpportunityMapProjection.pins(from: filteredListResults)

        XCTAssertEqual(filteredListResults.map(\.id), ["mapped", "list-only"])
        XCTAssertEqual(mapPins.map(\.id), ["mapped"])
        XCTAssertTrue(Set(mapPins.map(\.id)).isSubset(of: Set(filteredListResults.map(\.id))))
    }

    func testSearchSortsByRelevanceThenDate() {
        var filters = OpportunityFilters()
        filters.sort = .relevance

        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "tag", title: "General Program", startDate: "2026-06-01T04:00:00.000Z", tags: ["robotics"]),
                opportunity(id: "title", title: "Robotics Program", startDate: "2026-08-01T04:00:00.000Z", tags: [])
            ],
            query: "robotics",
            mode: .all,
            filters: filters
        )

        XCTAssertEqual(results.map(\.id), ["title", "tag"])
    }

    func testSearchSortsByDistanceWhenLocationIsPresent() {
        var filters = OpportunityFilters()
        filters.latitude = 43.6532
        filters.longitude = -79.3832
        filters.distanceKm = 100
        filters.sort = .distance

        let results = LocalOpportunitySnapshot.filter(
            [
                opportunity(id: "far", title: "Far Lab", latitude: 43.8561, longitude: -79.3370),
                opportunity(id: "near", title: "Near Lab", latitude: 43.6540, longitude: -79.3840)
            ],
            query: "lab",
            mode: .all,
            filters: filters
        )

        XCTAssertEqual(results.map(\.id), ["near", "far"])
    }

    @MainActor
    func testSessionFormatsLocalizedDates() {
        let session = SessionStore()
        let formatted = session.formattedDate("2026-06-01T04:00:00.000Z")
        XCTAssertTrue(formatted.contains("6"))
        XCTAssertFalse(formatted.contains("T"))
        XCTAssertFalse(formatted.contains(".000Z"))
    }

    func testLayoutDirectionFollowsLanguage() {
        let rtlLanguages: [AppLanguage] = [.ar, .fa, .ur]
        for language in AppLanguage.allCases {
            let direction = language.layoutDirection
            if rtlLanguages.contains(language) {
                XCTAssertEqual(direction, .rightToLeft, "\(language.rawValue) should use RTL layout direction")
            } else {
                XCTAssertEqual(direction, .leftToRight, "\(language.rawValue) should use LTR layout direction")
            }
        }
    }

    private func makeURLSessionForStub() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    func testSwiftUIViewStringsUseLocalizationHelpers() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repoRoot.appendingPathComponent("GTAFreeSTEM")
        let swiftFiles = try FileManager.default.contentsOfDirectory(at: sourceRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        let literalPatterns = [
            "Text(\"",
            "Label(\"",
            "Button(\"",
            "TextField(\"",
            "SecureField(\"",
            "Toggle(\"",
            "Picker(\"",
            "NavigationLink(\"",
            "Link(\"",
            ".navigationTitle(\"",
            ".navigationBarTitle(\"",
            ".accessibilityLabel(\"",
            ".accessibilityHint(\"",
            ".accessibilityValue(\"",
            ".alert(\"",
            ".confirmationDialog(\"",
            ".placeholder(\""
        ]
        var violations = [String]()

        for file in swiftFiles {
            let contents = try String(contentsOf: file)
            for (index, line) in contents.components(separatedBy: .newlines).enumerated() {
                for pattern in literalPatterns where line.contains(pattern) {
                    let tail = line.components(separatedBy: pattern).dropFirst().joined(separator: pattern)
                    if tail.hasPrefix("\\(") || tail.hasPrefix("\")") || line.contains(".accessibilityLabel(\"GTA FREE STEM\")") {
                        continue
                    }
                    violations.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, "Hardcoded visible SwiftUI strings must use session.text/AppText:\n\(violations.joined(separator: "\n"))")
    }

    func testOpportunityRowsExposeLocalizedOpenDetailsHint() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let browseView = repoRoot.appendingPathComponent("GTAFreeSTEM/BrowseView.swift")
        let contents = try String(contentsOf: browseView)

        XCTAssertTrue(
            contents.contains(".accessibilityHint(session.text(\"openDetailsHint\"))"),
            "Opportunity rows should expose a localized VoiceOver hint for opening detail pages."
        )
    }

    private func opportunity(
        id: String,
        title: String,
        organization: String = "Community Library",
        description: String = "Free STEM program.",
        summary: String? = nil,
        category: String = "Coding & Robotics",
        city: String = "Toronto",
        region: String = "Toronto",
        latitude: Double? = nil,
        longitude: Double? = nil,
        startDate: String? = "2026-07-01T04:00:00.000Z",
        ageMin: Int = 10,
        ageMax: Int? = 18,
        language: [String] = ["en"],
        status: String = "active",
        volunteerHoursEligible: Bool = false,
        coopEligible: Bool = false,
        tags: [String] = [],
        isNewFind: Bool? = nil,
        translations: [String: OpportunityTranslation] = [:]
    ) -> Opportunity {
        Opportunity(
            id: id,
            title: title,
            organization: organization,
            description: description,
            summary: summary,
            category: category,
            city: city,
            region: region,
            address: nil,
            latitude: latitude,
            longitude: longitude,
            startDate: startDate,
            endDate: nil,
            deadline: nil,
            ageMin: ageMin,
            ageMax: ageMax,
            language: language,
            cost: "Free",
            sourceUrl: "https://example.com/\(id)",
            registrationUrl: nil,
            status: status,
            volunteerHoursEligible: volunteerHoursEligible,
            coopEligible: coopEligible,
            tags: tags,
            distanceKm: nil,
            isNewFind: isNewFind,
            sourceConfidence: nil,
            translations: translations
        )
    }
}

final class OpportunityStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    @MainActor
    func testRefreshDeduplicatesConcurrentCalls() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: makeOpportunitiesJSON([
                opportunity(
                    id: "one",
                    title: "Alpha",
                    organization: "STEM Club",
                    summary: "A local science event.",
                    category: "Coding & Robotics",
                    city: "Toronto"
                )
            ]).data(using: .utf8)!,
            delaySeconds: 0.30
        )

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await store.refresh(cache: nil) }
            group.addTask { await store.refresh(cache: nil) }
        }

        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        XCTAssertEqual(store.opportunities.count, 1)
    }

    @MainActor
    func testRapidSequentialRefreshIsThrottledWithoutReplacingCurrentResults() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: makeOpportunitiesJSON([
                opportunity(id: "first", title: "First Result", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto")
            ]).data(using: .utf8)!
        )
        await store.refresh(cache: nil)

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: makeOpportunitiesJSON([
                opportunity(id: "second", title: "Second Result", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto")
            ]).data(using: .utf8)!
        )
        await store.refresh(cache: nil)

        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        XCTAssertEqual(store.opportunities.map(\.id), ["first"])
        XCTAssertEqual(store.huntPhase, .fresh)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testNewMatchesUseKnownIDsToAvoidDuplicateCountsAcrossRefreshes() async throws {
        let defaults = UserDefaults.standard
        let previousKnownIDs = defaults.stringArray(forKey: "knownOpportunityIDs")
        let previousNotification = defaults.object(forKey: "lastNewOpportunityNotificationAt")
        defaults.removeObject(forKey: "knownOpportunityIDs")
        defaults.removeObject(forKey: "lastNewOpportunityNotificationAt")
        defer {
            if let previousKnownIDs {
                defaults.set(previousKnownIDs, forKey: "knownOpportunityIDs")
            } else {
                defaults.removeObject(forKey: "knownOpportunityIDs")
            }
            if let previousNotification {
                defaults.set(previousNotification, forKey: "lastNewOpportunityNotificationAt")
            } else {
                defaults.removeObject(forKey: "lastNewOpportunityNotificationAt")
            }
        }

        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let payload = makeOpportunitiesJSON([
            opportunity(id: "known-once", title: "Known Once", organization: "STEM Club", category: "Coding & Robotics", city: "Toronto")
        ]).data(using: .utf8)!

        URLProtocolStub.register(responseFor: feedURL, statusCode: 200, body: payload)
        let firstStore = OpportunityStore(api: client)
        await firstStore.refresh(cache: nil)
        XCTAssertEqual(firstStore.newMatchesCount, 1)

        URLProtocolStub.register(responseFor: feedURL, statusCode: 200, body: payload)
        let secondStore = OpportunityStore(api: client)
        await secondStore.refresh(cache: nil)
        XCTAssertEqual(secondStore.newMatchesCount, 0)
    }

    @MainActor
    func testRefreshFallsBackToCachedResponse() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)
        let context = try makeInMemoryContext()

        let cached = OpportunityListResponse(
            data: [
                opportunity(
                    id: "cached",
                    title: "Cached Event",
                    organization: "Community Hub",
                    category: "Coding & Robotics",
                    city: "Toronto"
                )
            ],
            meta: OpportunityListResponse.Metadata(activeCount: 1, lastUpdated: "2026-06-12")
        )
        let payload = try JSONEncoder().encode(cached)
        context.insert(OpportunityCacheRecord(cacheKey: "latest-opportunities", payload: payload))
        try context.save()

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 500,
            body: "fail".data(using: .utf8)!
        )

        await store.refresh(cache: context)

        XCTAssertEqual(store.opportunities.map(\.id), ["cached"])
        XCTAssertEqual(store.dataSourceLabel, DataSource.savedAppCache)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testRefreshFallsBackToBundledSnapshotWithoutCache() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 500,
            body: "failed".data(using: .utf8)!
        )

        await store.refresh(cache: nil)

        XCTAssertGreaterThan(store.opportunities.count, 0)
        XCTAssertEqual(store.dataSourceLabel, DataSource.previewDatabase)
        XCTAssertEqual(store.huntPhase, .offline)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testLastHuntRestoresAllFiltersAndCachedResults() async throws {
        let feedURL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!
        let session = makeURLSessionForStub()
        let client = APIClient(feedURL: feedURL, session: session)
        let store = OpportunityStore(api: client)
        let context = try makeInMemoryContext()

        var filters = OpportunityFilters()
        filters.region = "Toronto"
        filters.city = "Toronto"
        filters.category = "Career & Mentorship"
        filters.age = "16"
        filters.language = "es"
        filters.latitude = 43.6532
        filters.longitude = -79.3832
        filters.distanceKm = 50
        filters.sort = .distance
        filters.includeNewFinds = false
        filters.volunteerHours = true
        filters.coop = true
        filters.mentorship = true
        filters.scholarships = true
        filters.blackFocused = true
        filters.girlsFocused = true
        filters.indigenousFocused = true
        filters.leadership = true

        store.query = "leadership"
        store.mode = .mentorship
        store.filters = filters

        URLProtocolStub.register(
            responseFor: feedURL,
            statusCode: 200,
            body: makeOpportunitiesJSON([
                Opportunity(
                    id: "restored",
                    title: "Leadership Mentorship Lab",
                    organization: "Community Hub",
                    description: "Black girls Indigenous leadership mentorship.",
                    summary: "Black girls Indigenous leadership mentorship.",
                    category: "Career & Mentorship",
                    city: "Toronto",
                    region: "Toronto",
                    address: nil,
                    latitude: 43.6540,
                    longitude: -79.3840,
                    startDate: nil,
                    endDate: nil,
                    deadline: nil,
                    ageMin: 14,
                    ageMax: 18,
                    language: ["es"],
                    cost: "Free",
                    sourceUrl: "https://example.com/restored",
                    registrationUrl: nil,
                    status: "active",
                    volunteerHoursEligible: true,
                    coopEligible: true,
                    tags: ["black", "girls", "indigenous", "leadership", "mentor", "scholarship"],
                    distanceKm: nil,
                    isNewFind: nil,
                    sourceConfidence: nil
                )
            ]).data(using: .utf8)!
        )

        await store.refresh(cache: context)

        let restoredStore = OpportunityStore(api: client)
        restoredStore.restoreLastHuntIfNeeded(in: context)

        XCTAssertEqual(restoredStore.query, "leadership")
        XCTAssertEqual(restoredStore.mode, .mentorship)
        XCTAssertEqual(restoredStore.filters, filters)
        XCTAssertEqual(restoredStore.opportunities.map(\.id), ["restored"])
        XCTAssertEqual(restoredStore.dataSourceLabel, DataSource.savedAppCache)
    }

    private func makeURLSessionForStub() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([
            OpportunityCacheRecord.self,
            SavedHuntRecord.self,
            SeenOpportunityRecord.self
        ])
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    private func makeOpportunitiesJSON(_ opportunities: [Opportunity]) -> String {
        let response = OpportunityListResponse(data: opportunities, meta: nil)
        let encoder = JSONEncoder()
        let data = try! encoder.encode(response)
        return String(decoding: data, as: UTF8.self)
    }

    private func opportunity(
        id: String,
        title: String,
        organization: String,
        summary: String? = nil,
        category: String,
        city: String
    ) -> Opportunity {
        Opportunity(
            id: id,
            title: title,
            organization: organization,
            description: summary ?? title,
            summary: summary,
            category: category,
            city: city,
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
            cost: "Free",
            sourceUrl: "https://example.com",
            registrationUrl: nil,
            status: "active",
            volunteerHoursEligible: false,
            coopEligible: false,
            tags: [],
            distanceKm: nil,
            isNewFind: nil,
            sourceConfidence: nil,
            translations: [:]
        )
    }
}

final class URLProtocolStub: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: Data
        let delaySeconds: TimeInterval
    }

    private final class State: @unchecked Sendable {
        private var responses = [String: Response]()
        private var requestCount = 0
        private let lock = NSLock()

        func register(responseFor url: URL, statusCode: Int, body: Data, delaySeconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            responses[url.absoluteString] = Response(statusCode: statusCode, body: body, delaySeconds: delaySeconds)
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            responses.removeAll()
            requestCount = 0
        }

        func takeResponse(for url: URL) -> Response? {
            lock.lock()
            defer { lock.unlock() }
            requestCount += 1
            return responses[url.absoluteString]
        }

        func currentRequestCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return requestCount
        }
    }

    private static let state = State()

    static var requestCount: Int {
        state.currentRequestCount()
    }

    static func register(responseFor url: URL, statusCode: Int, body: Data, delaySeconds: TimeInterval = 0.0) {
        state.register(responseFor: url, statusCode: statusCode, body: body, delaySeconds: delaySeconds)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool {
        return a == b
    }

    override func startLoading() {
        guard let url = request.url,
              let stub = Self.state.takeResponse(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)
        let body = stub.body
        let delay = stub.delaySeconds

        let action = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: action)
        } else {
            action.perform()
        }
    }

    override func stopLoading() {}
}
