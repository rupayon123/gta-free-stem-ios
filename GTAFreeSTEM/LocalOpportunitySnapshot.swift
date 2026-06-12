import Foundation

enum LocalOpportunitySnapshot {
    static func load(query: String, mode: SearchMode, filters: OpportunityFilters) throws -> OpportunityListResponse {
        guard let url = Bundle.main.url(forResource: "opportunities", withExtension: "json") else {
            throw APIError.invalidResponse
        }

        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(OpportunityListResponse.self, from: data)
        let filtered = filter(response.data, query: query, mode: mode, filters: filters)
        return OpportunityListResponse(
            data: filtered,
            meta: OpportunityListResponse.Metadata(
                activeCount: filtered.count,
                lastUpdated: response.meta?.lastUpdated
            )
        )
    }

    private static func filter(_ opportunities: [Opportunity], query: String, mode: SearchMode, filters: OpportunityFilters) -> [Opportunity] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAge = Int(filters.age.trimmingCharacters(in: .whitespacesAndNewlines))

        return opportunities.filter { opportunity in
            let matchesQuery = normalizedQuery.isEmpty ||
                opportunity.title.lowercased().contains(normalizedQuery) ||
                opportunity.organization.lowercased().contains(normalizedQuery) ||
                opportunity.description.lowercased().contains(normalizedQuery) ||
                opportunity.city.lowercased().contains(normalizedQuery) ||
                opportunity.tags.contains { $0.lowercased().contains(normalizedQuery) }

            guard matchesQuery else { return false }
            guard filters.region == "All" || opportunity.region == filters.region else { return false }
            guard filters.city.isEmpty || opportunity.city == filters.city else { return false }
            guard filters.category == "All" || opportunity.category == filters.category else { return false }
            if let normalizedAge {
                let maxAge = opportunity.ageMax ?? 99
                guard opportunity.ageMin <= normalizedAge, normalizedAge <= maxAge else { return false }
            }
            guard filters.language == "all" || opportunity.language.contains(filters.language) else { return false }
            if filters.blackFocused {
                guard containsAny(opportunity, ["black", "african", "caribbean"]) else { return false }
            }
            if filters.girlsFocused {
                guard containsAny(opportunity, ["girl", "girls", "women", "woman", "female"]) else { return false }
            }
            if filters.indigenousFocused {
                guard containsAny(opportunity, ["indigenous", "first nations", "metis", "inuit"]) else { return false }
            }
            if filters.leadership {
                guard containsAny(opportunity, ["leadership", "leader", "youth council"]) else { return false }
            }

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

    private static func containsAny(_ opportunity: Opportunity, _ needles: [String]) -> Bool {
        let haystack = ([opportunity.title, opportunity.organization, opportunity.description, opportunity.category] + opportunity.tags).joined(separator: " ").lowercased()
        return needles.contains { haystack.contains($0) }
    }
}
