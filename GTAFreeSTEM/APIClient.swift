import Foundation

enum APIError: Error, LocalizedError {
    case badURL
    case invalidResponse
    case insecureConnection
    case accountRequired

    var errorDescription: String? {
        switch self {
        case .badURL: Self.localized("serverAddressInvalid")
        case .invalidResponse: Self.localized("serverResponseInvalid")
        case .insecureConnection: Self.localized("serverAddressInvalid")
        case .accountRequired: Self.localized("signInToUseFeature")
        }
    }

    private static func localized(_ key: String) -> String {
        let stored = UserDefaults.standard.string(forKey: "preferredLanguageCode")
        let language = AppLanguage.normalized(stored ?? AppLanguage.en.rawValue)
        return AppText.shared.string(key, language: language)
    }
}

final class APIClient: @unchecked Sendable {
    let baseURL: URL
    let feedURL: URL
    private let session: URLSession
    private static let maxResponseBytes = 5_000_000
    private static let bundledTranslationIndex: [String: [String: OpportunityTranslation]] = {
        guard let url = AppResources.url(forResource: "opportunities", withExtension: "json") else {
            return [:]
        }
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        guard let response = try? JSONDecoder().decode(OpportunityListResponse.self, from: data) else {
            return [:]
        }

        var index: [String: [String: OpportunityTranslation]] = [:]
        for opportunity in response.data where !opportunity.id.isEmpty {
            guard !opportunity.translations.isEmpty else { continue }
            index[opportunity.id] = opportunity.translations
        }

        return index
    }()

    init(
        baseURL: URL = URL(string: "https://gta-free-stem.onrender.com/api/v1")!,
        feedURL: URL = URL(string: "https://gta-free-stem.vercel.app/opportunities.json")!,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.feedURL = feedURL
        self.session = session ?? Self.defaultSession
    }

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func opportunities(query: String, mode: SearchMode, filters: OpportunityFilters) async throws -> OpportunityListResponse {
        let response: OpportunityListResponse = try await get(feedURL)
        let localizedResponse = applyBundledTranslations(from: response)
        let filtered = LocalOpportunitySnapshot.filter(localizedResponse.data, query: query, mode: mode, filters: filters)
        return OpportunityListResponse(
            data: filtered,
            meta: OpportunityListResponse.Metadata(
                activeCount: filtered.count,
                lastUpdated: localizedResponse.meta?.lastUpdated
            )
        )
    }

    func opportunitiesFromRailsAPI(query: String, mode: SearchMode, filters: OpportunityFilters) async throws -> OpportunityListResponse {
        var components = URLComponents(url: baseURL.appending(path: "opportunities"), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem]()
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "query", value: query))
        }
        if filters.region != "All" {
            items.append(URLQueryItem(name: "region", value: filters.region))
        }
        if !filters.city.isEmpty {
            items.append(URLQueryItem(name: "city", value: filters.city))
        }
        if filters.category != "All" {
            items.append(URLQueryItem(name: "category", value: filters.category))
        }
        if !filters.age.isEmpty {
            items.append(URLQueryItem(name: "age", value: filters.age))
        }
        if filters.language != "all" {
            items.append(URLQueryItem(name: "language", value: filters.language))
        }
        if let latitude = filters.latitude, let longitude = filters.longitude {
            items.append(URLQueryItem(name: "latitude", value: String(latitude)))
            items.append(URLQueryItem(name: "longitude", value: String(longitude)))
            items.append(URLQueryItem(name: "distanceKm", value: String(filters.distanceKm)))
        }
        items.append(URLQueryItem(name: "sort", value: filters.sort.rawValue))
        items.append(URLQueryItem(name: "includeNewFinds", value: filters.includeNewFinds ? "true" : "false"))
        items.append(URLQueryItem(name: "limit", value: "200"))
        if filters.volunteerHours {
            items.append(URLQueryItem(name: "volunteerHours", value: "true"))
        }
        if filters.coop {
            items.append(URLQueryItem(name: "coop", value: "true"))
        }
        if filters.mentorship {
            items.append(URLQueryItem(name: "mentorship", value: "true"))
        }
        if filters.scholarships {
            items.append(URLQueryItem(name: "scholarships", value: "true"))
        }
        if filters.blackFocused {
            items.append(URLQueryItem(name: "blackFocused", value: "true"))
        }
        if filters.girlsFocused {
            items.append(URLQueryItem(name: "girlsFocused", value: "true"))
        }
        if filters.indigenousFocused {
            items.append(URLQueryItem(name: "indigenousFocused", value: "true"))
        }
        if filters.leadership {
            items.append(URLQueryItem(name: "leadership", value: "true"))
        }
        switch mode {
        case .all: break
        case .highSchool:
            items.append(URLQueryItem(name: "highSchool", value: "true"))
        case .volunteer:
            items.append(URLQueryItem(name: "volunteerHours", value: "true"))
            items.append(URLQueryItem(name: "highSchool", value: "true"))
        case .coop:
            items.append(URLQueryItem(name: "coop", value: "true"))
            items.append(URLQueryItem(name: "highSchool", value: "true"))
        case .mentorship:
            items.append(URLQueryItem(name: "mentorship", value: "true"))
            items.append(URLQueryItem(name: "highSchool", value: "true"))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw APIError.badURL }
        let response: OpportunityListResponse = try await get(url)
        return applyBundledTranslations(from: response)
    }

    func requestPrioritizedHunt(query: String, mode: SearchMode, filters: OpportunityFilters) async throws {
        guard ProcessInfo.processInfo.environment["GTA_FREE_STEM_ENABLE_PRIORITY_HUNT"] == "1" else {
            return
        }
        let url = baseURL.appending(path: "hunt_refresh")
        var payload: [String: String] = [
            "query": query,
            "mode": mode.rawValue,
            "region": filters.region,
            "city": filters.city,
            "category": filters.category,
            "age": filters.age,
            "language": filters.language,
            "distance_km": String(filters.distanceKm),
            "sort": filters.sort.rawValue,
            "include_new_finds": String(filters.includeNewFinds),
            "volunteer_hours": String(filters.volunteerHours),
            "coop": String(filters.coop),
            "mentorship": String(filters.mentorship),
            "scholarships": String(filters.scholarships),
            "black_focused": String(filters.blackFocused),
            "girls_focused": String(filters.girlsFocused),
            "indigenous_focused": String(filters.indigenousFocused),
            "leadership": String(filters.leadership)
        ]
        if let latitude = filters.latitude, let longitude = filters.longitude {
            payload["latitude"] = String(latitude)
            payload["longitude"] = String(longitude)
        }
        _ = try await send(url: url, method: "POST", token: nil, body: ["hunt": payload]) as APIStatusResponse
    }

    func save(opportunityID: String, token: String?) async throws {
        guard let token, !token.isEmpty else { throw APIError.accountRequired }
        let url = baseURL.appending(path: "saved_opportunities")
        let body = ["opportunity_id": opportunityID]
        _ = try await send(url: url, method: "POST", token: token, body: body) as APIStatusResponse
    }

    func sendFeedback(_ draft: FeedbackDraft, token: String?) async throws {
        guard let token, !token.isEmpty else { throw APIError.accountRequired }
        let url = baseURL.appending(path: "feedback")
        let body = ["feedback": ["name": draft.name, "email": draft.email, "message": draft.message]]
        _ = try await send(url: url, method: "POST", token: token, body: body) as APIStatusResponse
    }

    func submitMissingOpportunity(_ draft: MissingOpportunityDraft, token: String?) async throws {
        guard let token, !token.isEmpty else { throw APIError.accountRequired }
        let url = baseURL.appending(path: "missing_opportunity_submissions")
        let body = [
            "missing_opportunity_submission": [
                "title": draft.title,
                "organization": draft.organization,
                "city": draft.city,
                "source_url": draft.sourceURL,
                "notes": draft.notes
            ]
        ]
        _ = try await send(url: url, method: "POST", token: token, body: body) as APIStatusResponse
    }

    private func applyBundledTranslations(from response: OpportunityListResponse) -> OpportunityListResponse {
        let mergedData = response.data.map { augment(withBundledTranslations: $0) }
        return OpportunityListResponse(
            data: mergedData,
            meta: response.meta
        )
    }

    private func augment(withBundledTranslations opportunity: Opportunity) -> Opportunity {
        guard let bundled = Self.bundledTranslationIndex[opportunity.id] else {
            return opportunity
        }
        var translations = bundled
        for (key, remoteTranslation) in opportunity.translations {
            let fallback = bundled[key] ?? bundled[AppLanguage.normalized(key).rawValue]
            translations[key] = remoteTranslation.merged(with: fallback)
            translations[AppLanguage.normalized(key).rawValue] = translations[key]
        }
        let mergedTranslations = translations.compactMapValues { $0.hasContent ? $0 : nil }
        return Opportunity(
            id: opportunity.id,
            title: opportunity.title,
            organization: opportunity.organization,
            description: opportunity.description,
            summary: opportunity.summary,
            category: opportunity.category,
            city: opportunity.city,
            region: opportunity.region,
            address: opportunity.address,
            latitude: opportunity.latitude,
            longitude: opportunity.longitude,
            startDate: opportunity.startDate,
            endDate: opportunity.endDate,
            deadline: opportunity.deadline,
            ageMin: opportunity.ageMin,
            ageMax: opportunity.ageMax,
            language: opportunity.language,
            cost: opportunity.cost,
            sourceUrl: opportunity.sourceUrl,
            registrationUrl: opportunity.registrationUrl,
            status: opportunity.status,
            volunteerHoursEligible: opportunity.volunteerHoursEligible,
            coopEligible: opportunity.coopEligible,
            tags: opportunity.tags,
            distanceKm: opportunity.distanceKm,
            isNewFind: opportunity.isNewFind,
            sourceConfidence: opportunity.sourceConfidence,
            translations: mergedTranslations
        )
    }

    func deleteAccount(token: String?) async throws {
        guard let token, !token.isEmpty else { throw APIError.accountRequired }
        let url = baseURL.appending(path: "account")
        _ = try await send(url: url, method: "DELETE", token: token, body: [String: String]()) as APIStatusResponse
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        guard Self.isTrustedTransport(url) else { throw APIError.insecureConnection }
        let (data, response) = try await session.data(from: url)
        guard data.count <= Self.maxResponseBytes else { throw APIError.invalidResponse }
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw APIError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send<T: Decodable, Body: Encodable>(url: URL, method: String, token: String?, body: Body) async throws -> T {
        guard Self.isTrustedTransport(url) else { throw APIError.insecureConnection }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.accountRequired }
        guard data.count <= Self.maxResponseBytes else { throw APIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else { throw APIError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func isTrustedTransport(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return url.host?.isEmpty == false
    }
}
