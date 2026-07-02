import Foundation

enum LocalOpportunitySnapshot {
    static func load(query: String, mode: SearchMode, filters: OpportunityFilters, displayLanguage: AppLanguage = preferredLanguage) throws -> OpportunityListResponse {
        guard let url = AppResources.url(forResource: "opportunities", withExtension: "json") else {
            throw APIError.invalidResponse
        }

        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(OpportunityListResponse.self, from: data)
        let filtered = filter(response.data, query: query, mode: mode, filters: filters, displayLanguage: displayLanguage)
        return OpportunityListResponse(
            data: filtered,
            meta: OpportunityListResponse.Metadata(
                activeCount: filtered.count,
                lastUpdated: response.meta?.lastUpdated
            )
        )
    }

    static func filter(_ opportunities: [Opportunity], query: String, mode: SearchMode, filters: OpportunityFilters, displayLanguage: AppLanguage = preferredLanguage) -> [Opportunity] {
        let normalizedTerms = normalizedSearchTerms(query)
        let normalizedAge = Int(filters.age.trimmingCharacters(in: .whitespacesAndNewlines))

        let filtered = opportunities.filter { opportunity in
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
            guard languagesMatch(opportunity.language, selected: filters.language) else { return false }
            if let latitude = filters.latitude, let longitude = filters.longitude {
                guard let opportunityLatitude = opportunity.latitude, let opportunityLongitude = opportunity.longitude else { return false }
                guard distanceKm(fromLatitude: latitude, longitude: longitude, toLatitude: opportunityLatitude, longitude: opportunityLongitude) <= filters.distanceKm else { return false }
            }
            if !normalizedTerms.isEmpty {
                let searchable = searchableText(for: opportunity, language: displayLanguage)
                guard normalizedTerms.allSatisfy({ searchable.contains($0) }) else { return false }
            }
            if filters.blackFocused {
                guard containsAny(opportunity, ["black", "african", "caribbean"], language: displayLanguage) else { return false }
            }
            if filters.girlsFocused {
                guard containsAny(opportunity, ["girl", "girls", "women", "woman", "female"], language: displayLanguage) else { return false }
            }
            if filters.indigenousFocused {
                guard containsAny(opportunity, ["indigenous", "first nations", "metis", "inuit"], language: displayLanguage) else { return false }
            }
            if filters.leadership {
                guard containsAny(opportunity, ["leadership", "leader", "youth council"], language: displayLanguage) else { return false }
            }
            if filters.volunteerHours {
                guard matchesVolunteerHours(opportunity, language: displayLanguage) else { return false }
            }
            if filters.coop {
                guard matchesCoop(opportunity, language: displayLanguage) else { return false }
            }
            if filters.mentorship {
                guard matchesMentorship(opportunity, language: displayLanguage) else { return false }
            }
            if filters.scholarships {
                guard matchesScholarship(opportunity, language: displayLanguage) else { return false }
            }

            let tags = searchableTags(for: opportunity, language: displayLanguage)

            switch mode {
            case .all:
                return true
            case .highSchool:
                return matchesVolunteerHours(opportunity, language: displayLanguage) ||
                    matchesCoop(opportunity, language: displayLanguage) ||
                    matchesMentorship(opportunity, language: displayLanguage) ||
                    matchesScholarship(opportunity, language: displayLanguage) ||
                    tags.contains { tag in
                        Self.isHighSchoolTag(tag)
                    }
            case .volunteer:
                return matchesVolunteerHours(opportunity, language: displayLanguage)
            case .coop:
                return matchesCoop(opportunity, language: displayLanguage)
            case .mentorship:
                return matchesMentorship(opportunity, language: displayLanguage)
            }
        }

        return sort(filtered, queryTerms: normalizedTerms, filters: filters, displayLanguage: displayLanguage)
    }

    private static var preferredLanguage: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: "preferredLanguageCode")
        return AppLanguage.normalized(stored ?? AppLanguage.en.rawValue)
    }

    private static func containsAny(_ opportunity: Opportunity, _ needles: [String], language: AppLanguage) -> Bool {
        let haystack = searchableText(for: opportunity, language: language)
        return needles.map(normalizedText).contains { haystack.contains($0) }
    }

    private static func matchesVolunteerHours(_ opportunity: Opportunity, language: AppLanguage) -> Bool {
        opportunity.volunteerHoursEligible ||
            containsAny(opportunity, ["volunteer hours", "community service", "student volunteer"], language: language)
    }

    private static func matchesCoop(_ opportunity: Opportunity, language: AppLanguage) -> Bool {
        opportunity.coopEligible ||
            containsAny(opportunity, ["co-op", "coop", "shsm", "specialist high skills major", "placement"], language: language)
    }

    private static func matchesMentorship(_ opportunity: Opportunity, language: AppLanguage) -> Bool {
        containsAny(opportunity, ["mentor", "mentorship", "career mentor", "role model"], language: language)
    }

    private static func matchesScholarship(_ opportunity: Opportunity, language: AppLanguage) -> Bool {
        containsAny(opportunity, ["scholarship", "bursary", "grant", "award", "financial aid"], language: language)
    }

    private static func languagesMatch(_ opportunityLanguages: [String], selected language: String) -> Bool {
        guard language != "all" else { return true }
        let normalizedSelected = AppLanguage.normalized(language).rawValue
        return opportunityLanguages.contains { AppLanguage.normalized($0).rawValue == normalizedSelected }
    }

    private static func sort(_ opportunities: [Opportunity], queryTerms: [String], filters: OpportunityFilters, displayLanguage: AppLanguage) -> [Opportunity] {
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
            guard !queryTerms.isEmpty else { return opportunities.sorted { dateValue($0) < dateValue($1) } }
            return opportunities.sorted {
                let lhs = relevance($0, queryTerms: queryTerms, language: displayLanguage)
                let rhs = relevance($1, queryTerms: queryTerms, language: displayLanguage)
                return lhs == rhs ? dateValue($0) < dateValue($1) : lhs > rhs
            }
        }
    }

    private static func normalizedSearchTerms(_ query: String) -> [String] {
        normalizedText(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func searchableText(for opportunity: Opportunity, language: AppLanguage) -> String {
        normalizedText(searchableFields(for: opportunity, language: language).joined(separator: " "))
    }

    private static func searchableFields(for opportunity: Opportunity, language: AppLanguage) -> [String] {
        uniqueValues([
            opportunity.localizedTitle(language: language),
            opportunity.title,
            opportunity.localizedOrganization(language: language),
            opportunity.organization,
            opportunity.localizedDescription(language: language),
            opportunity.description,
            searchableSummary(for: opportunity, language: language),
            opportunity.summary ?? "",
            opportunity.localizedCategory(language: language),
            opportunity.category,
            opportunity.localizedCity(language: language),
            opportunity.city,
            opportunity.localizedRegion(language: language),
            opportunity.region
        ] + opportunity.localizedTags(language: language) + opportunity.tags)
    }

    private static func searchableTags(for opportunity: Opportunity, language: AppLanguage) -> [String] {
        uniqueValues(opportunity.localizedTags(language: language) + opportunity.tags)
            .map(normalizedText)
    }

    private static func isHighSchoolTag(_ tag: String) -> Bool {
        let normalized = searchableTagValue(tag)
        let aliases = [
            "teen",
            "high school",
            "shsm",
            "mentor",
            "mentorship",
            "leadership",
            "volunteer",
            "volunteer hours",
            "co op",
            "co-op",
            "coop"
        ]
        return aliases.contains(where: normalized.contains)
    }

    private static func searchableTagValue(_ value: String) -> String {
        normalizedText(
            value
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "/", with: " ")
                .replacingOccurrences(of: "&", with: " ")
                .replacingOccurrences(of: ".", with: " ")
        )
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
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

    private static func relevance(_ opportunity: Opportunity, queryTerms: [String], language: AppLanguage) -> Int {
        let weightedFields = uniqueWeightedFields([
            (opportunity.localizedTitle(language: language), 8),
            (opportunity.title, 8),
            (opportunity.localizedOrganization(language: language), 5),
            (opportunity.organization, 5),
            (opportunity.localizedCategory(language: language), 4),
            (opportunity.category, 4),
            (opportunity.localizedCity(language: language), 3),
            (opportunity.city, 3),
            (searchableSummary(for: opportunity, language: language), 3),
            (opportunity.summary ?? "", 3),
            (opportunity.localizedDescription(language: language), 2),
            (opportunity.description, 2),
            (opportunity.localizedRegion(language: language), 1),
            (opportunity.region, 1)
        ] + opportunity.localizedTags(language: language).map { ($0, 3) } + opportunity.tags.map { ($0, 3) })

        return weightedFields.reduce(0) { score, field in
            let normalizedField = normalizedText(field.0)
            let fieldScore = queryTerms.reduce(0) { termScore, term in
                normalizedField.contains(term) ? termScore + field.1 : termScore
            }
            return score + fieldScore
        }
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = normalizedText(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return value
        }
    }

    private static func uniqueWeightedFields(_ fields: [(String, Int)]) -> [(String, Int)] {
        var seen = Set<String>()
        return fields.compactMap { field in
            let normalized = normalizedText(field.0)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return field
        }
    }

    private static func searchableSummary(for opportunity: Opportunity, language: AppLanguage) -> String {
        guard language == .en || opportunity.translation(for: language) != nil else {
            return Self.localizedValue([opportunity.summary, opportunity.description], fallback: opportunity.description)
        }
        return opportunity.localizedSummary(language: language)
    }

    private static func localizedValue(_ values: [String?], fallback: String) -> String {
        values.lazy.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        }.first ?? fallback
    }
}
