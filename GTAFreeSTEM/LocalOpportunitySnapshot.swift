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

    static func filter(_ opportunities: [Opportunity], query: String, mode: SearchMode, filters: OpportunityFilters) -> [Opportunity] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAge = Int(filters.age.trimmingCharacters(in: .whitespacesAndNewlines))

        let filtered = opportunities.filter { opportunity in
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
            if !filters.includeNewFinds {
                guard opportunity.status == "active" else { return false }
            }
            if let normalizedAge {
                let maxAge = opportunity.ageMax ?? 99
                guard opportunity.ageMin <= normalizedAge, normalizedAge <= maxAge else { return false }
            }
            guard filters.language == "all" || opportunity.language.contains(filters.language) else { return false }
            if let latitude = filters.latitude, let longitude = filters.longitude {
                guard let opportunityLatitude = opportunity.latitude, let opportunityLongitude = opportunity.longitude else { return false }
                guard distanceKm(fromLatitude: latitude, longitude: longitude, toLatitude: opportunityLatitude, longitude: opportunityLongitude) <= filters.distanceKm else { return false }
            }
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

        return sort(filtered, query: normalizedQuery, filters: filters)
    }

    private static func containsAny(_ opportunity: Opportunity, _ needles: [String]) -> Bool {
        let haystack = ([opportunity.title, opportunity.organization, opportunity.description, opportunity.category] + opportunity.tags).joined(separator: " ").lowercased()
        return needles.contains { haystack.contains($0) }
    }

    private static func sort(_ opportunities: [Opportunity], query: String, filters: OpportunityFilters) -> [Opportunity] {
        switch filters.sort {
        case .date:
            return opportunities.sorted { dateValue($0) < dateValue($1) }
        case .distance:
            guard let latitude = filters.latitude, let longitude = filters.longitude else {
                return opportunities.sorted { dateValue($0) < dateValue($1) }
            }
            return opportunities.sorted {
                distanceValue($0, latitude: latitude, longitude: longitude) < distanceValue($1, latitude: latitude, longitude: longitude)
            }
        case .relevance:
            guard !query.isEmpty else { return opportunities.sorted { dateValue($0) < dateValue($1) } }
            return opportunities.sorted { relevance($0, query: query) > relevance($1, query: query) }
        }
    }

    private static func dateValue(_ opportunity: Opportunity) -> Date {
        let value = opportunity.startDate ?? opportunity.deadline ?? opportunity.endDate ?? ""
        return ISO8601DateFormatter().date(from: value) ?? .distantFuture
    }

    private static func distanceValue(_ opportunity: Opportunity, latitude: Double, longitude: Double) -> Double {
        guard let opportunityLatitude = opportunity.latitude, let opportunityLongitude = opportunity.longitude else { return .greatestFiniteMagnitude }
        return distanceKm(fromLatitude: latitude, longitude: longitude, toLatitude: opportunityLatitude, longitude: opportunityLongitude)
    }

    private static func distanceKm(fromLatitude latitude: Double, longitude: Double, toLatitude otherLatitude: Double, longitude otherLongitude: Double) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = (otherLatitude - latitude) * .pi / 180
        let dLon = (otherLongitude - longitude) * .pi / 180
        let lat1 = latitude * .pi / 180
        let lat2 = otherLatitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func relevance(_ opportunity: Opportunity, query: String) -> Int {
        let fields = [opportunity.title, opportunity.organization, opportunity.category, opportunity.city, opportunity.description] + opportunity.tags
        return fields.reduce(0) { score, field in
            field.lowercased().contains(query) ? score + 1 : score
        }
    }
}
