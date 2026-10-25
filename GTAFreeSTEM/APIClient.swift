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
            )
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
                guard response.hasValidUniqueIDs, response.hasHealthyDeclaredSources else {
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
            contentRights: response.contentRights
        )
    }

    private func augment(withBundledTranslations opportunity: Opportunity) -> Opportunity {
        guard let bundled = Self.bundledTranslationIndex[opportunity.id] else {
            return opportunity
        }
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
            translations: mergedTranslations
        )
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        try Task.checkCancellation()
        guard Self.isTrustedTransport(url) else { throw APIError.insecureConnection }
        // Use response/data delegate callbacks so a header-only response can be
        // rejected without waiting for AsyncBytes to expose its response.
        let request = BoundedFeedRequest()
        let data = try await request.load(url, configuration: session.configuration)
        try Task.checkCancellation()
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Each request owns a disposable session with the injected configuration.
    /// The lock coordinates cancellation with the serial delegate callbacks and
    /// guarantees the continuation is completed exactly once.
    private final class BoundedFeedRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?
        private var requestTask: URLSessionDataTask?
        private var requestSession: URLSession?
        private var buffer = Data()
        private var completed = false

        func load(_ url: URL, configuration: URLSessionConfiguration) async throws -> Data {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    guard !completed else {
                        lock.unlock()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    self.continuation = continuation
                    let requestSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    self.requestSession = requestSession
                    let task = requestSession.dataTask(with: url)
                    requestTask = task
                    lock.unlock()
                    task.resume()
                }
            } onCancel: {
                self.finish(.failure(CancellationError()))
            }
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
        ) {
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                completionHandler(.cancel)
                finish(.failure(APIError.invalidResponse))
                return
            }
            guard let finalURL = http.url, APIClient.isTrustedTransport(finalURL) else {
                completionHandler(.cancel)
                finish(.failure(APIError.insecureConnection))
                return
            }
            guard response.expectedContentLength <= Int64(APIClient.maxResponseBytes) else {
                completionHandler(.cancel)
                finish(.failure(APIError.invalidResponse))
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            guard data.count <= APIClient.maxResponseBytes - buffer.count else {
                lock.unlock()
                finish(.failure(APIError.invalidResponse))
                return
            }
            buffer.append(data)
            lock.unlock()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                finish(.failure(error))
            } else {
                lock.lock()
                let payload = buffer
                lock.unlock()
                finish(.success(payload))
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            lock.lock()
            guard !completed else { lock.unlock(); return }
            completed = true
            let pending = continuation
            let task = requestTask
            let session = requestSession
            continuation = nil
            requestTask = nil
            requestSession = nil
            buffer = Data()
            lock.unlock()
            // Stop the transfer and break session/delegate ownership before
            // resuming the caller, including early response rejection.
            task?.cancel()
            session?.invalidateAndCancel()
            pending?.resume(with: result)
        }
    }

    private static func isTrustedTransport(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return url.host?.isEmpty == false
    }

}
