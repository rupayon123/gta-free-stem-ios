import Foundation

enum APIError: Error, LocalizedError {
    case badURL
    case invalidResponse
    case accountRequired

    var errorDescription: String? {
        switch self {
        case .badURL: "The server address is not valid."
        case .invalidResponse: "The server response could not be read."
        case .accountRequired: "Please sign in to use this feature."
        }
    }
}

final class APIClient: @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "https://gta-free-stem.onrender.com/api/v1")!, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? Self.defaultSession
    }

    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        return URLSession(configuration: configuration)
    }()

    func opportunities(query: String, mode: SearchMode) async throws -> OpportunityListResponse {
        var components = URLComponents(url: baseURL.appending(path: "opportunities"), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem]()
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "query", value: query))
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
        return try await get(url)
    }

    func save(opportunityID: String, token: String?) async throws {
        guard let token, !token.isEmpty else { throw APIError.accountRequired }
        let url = baseURL.appending(path: "saved_opportunities")
        let body = ["opportunity_id": opportunityID]
        _ = try await send(url: url, method: "POST", token: token, body: body) as APIStatusResponse
    }

    func sendFeedback(_ draft: FeedbackDraft, token: String?) async throws {
        let url = baseURL.appending(path: "feedback")
        let body = ["feedback": ["name": draft.name, "email": draft.email, "message": draft.message]]
        _ = try await send(url: url, method: "POST", token: token, body: body) as APIStatusResponse
    }

    func submitMissingOpportunity(_ draft: MissingOpportunityDraft, token: String?) async throws {
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

    func deleteAccount(token: String?) async throws {
        guard let token, !token.isEmpty else { throw APIError.accountRequired }
        let url = baseURL.appending(path: "account")
        _ = try await send(url: url, method: "DELETE", token: token, body: [String: String]()) as APIStatusResponse
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 400 else { throw APIError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send<T: Decodable, Body: Encodable>(url: URL, method: String, token: String?, body: Body) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.accountRequired }
        guard http.statusCode < 400 else { throw APIError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
