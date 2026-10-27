import Foundation

enum APIError: Error, LocalizedError {
    case badURL
    case invalidResponse
    case insecureConnection

    var errorDescription: String? {
        switch self {
        case .badURL: Self.localized("serverAddressInvalid")
        case .invalidResponse: Self.localized("serverResponseInvalid")
        case .insecureConnection: Self.localized("serverAddressInvalid")
        }
    }

    private static func localized(_ key: String) -> String {
        let language = AppLanguage.preferred()
        return AppText.shared.string(key, language: language)
    }
}

final class APIClient: @unchecked Sendable {
    static let primaryPublicFeedURL = URL(string: "https://raw.githubusercontent.com/rupayon123/gta-free-stem-opportunities/main/public/opportunities.json")!
    // A CDN mirror keeps a current, independent retrieval path when the raw
    // GitHub endpoint is temporarily unavailable. Every source is still held
    // to the same HTTPS, payload-size, schema, and freshness checks below.
    static let fallbackPublicFeedURL = URL(string: "https://cdn.jsdelivr.net/gh/rupayon123/gta-free-stem-opportunities@main/public/opportunities.json")!

    let feedURL: URL
    private let fallbackFeedURLs: [URL]
    private let session: URLSession
    private let now: () -> Date
    private static let maxResponseBytes = 10_000_000
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
        feedURL: URL? = nil,
        fallbackFeedURLs: [URL]? = nil,
        session: URLSession? = nil,
        now: @escaping () -> Date = { .now }
    ) {
        let primaryFeedURL = feedURL ?? Self.primaryPublicFeedURL
        self.feedURL = primaryFeedURL
        self.fallbackFeedURLs = (fallbackFeedURLs ?? (feedURL == nil ? [Self.fallbackPublicFeedURL] : []))
            .filter { $0 != primaryFeedURL }
        self.session = session ?? Self.defaultSession
        self.now = now
    }

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        // The app has a retained local snapshot, so an offline device should
        // surface that usable state immediately instead of holding a refresh
        // request open while the system waits for a network path.
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func opportunities(query: String, mode: SearchMode, filters: OpportunityFilters) async throws -> OpportunityListResponse {
        let response = try await opportunityFeed()
        let filtered = LocalOpportunitySnapshot.filter(
            response.data,
            query: query,
            mode: mode,
            filters: filters,
            now: now()
        )
        return OpportunityListResponse(
            data: filtered,
            meta: OpportunityListResponse.Metadata(
                activeCount: filtered.count,
                lastUpdated: response.meta?.lastUpdated
            ),
            publicationRevision: response.publicationRevision
        )
    }

    func opportunityFeed() async throws -> OpportunityListResponse {
        var lastError: Error?

        for source in [feedURL] + fallbackFeedURLs {
            try Task.checkCancellation()
            do {
                let response: OpportunityListResponse = try await get(source)
                try Task.checkCancellation()
                guard FeedFreshness.isCurrent(response.meta?.lastUpdated, now: now()) else {
                    throw APIError.invalidResponse
                }
                // An empty yet recent response is not useful to this discovery
                // app and is most often a partial publisher failure. Retain the
                // last good cache or bundled fallback instead of replacing it.
                guard !response.data.isEmpty else {
                    throw APIError.invalidResponse
                }
                guard response.hasValidUniqueIDs, response.hasHealthyDeclaredSources,
                      response.hasValidPublicationRevision(now: now()) else {
                    throw APIError.invalidResponse
                }
                guard response.hasReleaseReadyContentRights(now: now()) else {
                    throw APIError.invalidResponse
                }
                return applyBundledTranslations(from: response)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
                lastError = error
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    private func applyBundledTranslations(from response: OpportunityListResponse) -> OpportunityListResponse {
        let mergedData = response.data.map { augment(withBundledTranslations: $0) }
        return OpportunityListResponse(
            data: mergedData,
            meta: response.meta,
            sourceHealth: response.sourceHealth,
            contentRights: response.contentRights,
            publicationRevision: response.publicationRevision
        )
    }

    private func augment(withBundledTranslations opportunity: Opportunity) -> Opportunity {
        guard let bundled = Self.bundledTranslationIndex[opportunity.id] else {
            return opportunity
        }
        return Self.mergingBundledTranslations(bundled, into: opportunity)
    }

    static func mergingBundledTranslations(_ bundled: [String: OpportunityTranslation], into opportunity: Opportunity) -> Opportunity {
        var translations = bundled
        for (key, remoteTranslation) in opportunity.translations {
            let supportedLanguage = AppLanguage.supportedLanguage(for: key)
            let fallback = bundled[key] ?? supportedLanguage.flatMap { bundled[$0.rawValue] }
            translations[key] = remoteTranslation.merged(with: fallback)
            if let supportedLanguage {
                translations[supportedLanguage.rawValue] = translations[key]
            }
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
            translations: mergedTranslations,
            virtual: opportunity.virtual
        )
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        try Task.checkCancellation()
        guard Self.isTrustedTransport(url) else { throw APIError.insecureConnection }
        let (bytes, response) = try await session.bytes(from: url)
        let responseTask = bytes.task
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw APIError.invalidResponse
                }
                guard let finalURL = http.url, Self.isTrustedTransport(finalURL) else {
                    throw APIError.insecureConnection
                }
                guard response.expectedContentLength <= Int64(Self.maxResponseBytes) else {
                    throw APIError.invalidResponse
                }

                var data = Data()
                if response.expectedContentLength > 0 {
                    data.reserveCapacity(Int(response.expectedContentLength))
                }
                for try await byte in bytes {
                    // Unknown or understated lengths still cannot grow the
                    // retained payload beyond the cap while the body arrives.
                    guard data.count < Self.maxResponseBytes else { throw APIError.invalidResponse }
                    data.append(byte)
                    if data.count.isMultiple(of: 65_536) {
                        try Task.checkCancellation()
                    }
                }
                try Task.checkCancellation()
                return try JSONDecoder().decode(T.self, from: data)
            } onCancel: {
                responseTask.cancel()
            }
        } catch {
            // Header rejection and byte overflow must stop the transfer, not
            // leave a response downloading after the caller moves to a mirror.
            responseTask.cancel()
            throw error
        }
    }

    private static func isTrustedTransport(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return url.host?.isEmpty == false
    }

}
