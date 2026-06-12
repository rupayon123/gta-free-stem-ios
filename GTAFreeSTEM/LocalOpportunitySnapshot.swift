import Foundation

enum LocalOpportunitySnapshot {
    static func load(query: String, mode: SearchMode) throws -> OpportunityListResponse {
        guard let url = Bundle.main.url(forResource: "opportunities", withExtension: "json") else {
            throw APIError.invalidResponse
        }

        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(OpportunityListResponse.self, from: data)
        let filtered = filter(response.data, query: query, mode: mode)
        return OpportunityListResponse(
            data: filtered,
            meta: OpportunityListResponse.Metadata(
                activeCount: filtered.count,
                lastUpdated: response.meta?.lastUpdated
            )
        )
    }

    private static func filter(_ opportunities: [Opportunity], query: String, mode: SearchMode) -> [Opportunity] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return opportunities.filter { opportunity in
            let matchesQuery = normalizedQuery.isEmpty ||
                opportunity.title.lowercased().contains(normalizedQuery) ||
                opportunity.organization.lowercased().contains(normalizedQuery) ||
                opportunity.description.lowercased().contains(normalizedQuery) ||
                opportunity.city.lowercased().contains(normalizedQuery) ||
                opportunity.tags.contains { $0.lowercased().contains(normalizedQuery) }

            guard matchesQuery else { return false }

            switch mode {
            case .all:
                return true
            case .highSchool:
                return opportunity.volunteerHoursEligible ||
                    opportunity.coopEligible ||
                    opportunity.tags.contains { tag in
                        ["teen", "high school", "shsm", "mentor", "mentorship", "leadership", "volunteer"].contains(tag.lowercased())
                    }
            case .volunteer:
                return opportunity.volunteerHoursEligible
            case .coop:
                return opportunity.coopEligible
            case .mentorship:
                return opportunity.tags.contains { $0.lowercased().contains("mentor") }
            }
        }
    }
}
