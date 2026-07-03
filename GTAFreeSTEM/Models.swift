import Foundation
import SwiftData

struct OpportunityTranslation: Codable, Hashable {
    let title: String?
    let organization: String?
    let description: String?
    let summary: String?
    let category: String?
    let city: String?
    let region: String?
    let address: String?
    let cost: String?
    let tags: [String]?

    private enum CodingKeys: String, CodingKey {
        case title
        case organization
        case provider
        case description
        case summary
        case category
        case city
        case region
        case address
        case cost
        case tags
    }

    init(
        title: String? = nil,
        organization: String? = nil,
        description: String? = nil,
        summary: String? = nil,
        category: String? = nil,
        city: String? = nil,
        region: String? = nil,
        address: String? = nil,
        cost: String? = nil,
        tags: [String]? = nil
    ) {
        self.title = title
        self.organization = organization
        self.description = description
        self.summary = summary
        self.category = category
        self.city = city
        self.region = region
        self.address = address
        self.cost = cost
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        organization =
            (try? container.decodeIfPresent(String.self, forKey: .organization)) ??
            (try? container.decodeIfPresent(String.self, forKey: .provider))
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        summary = try? container.decodeIfPresent(String.self, forKey: .summary)
        category = try? container.decodeIfPresent(String.self, forKey: .category)
        city = try? container.decodeIfPresent(String.self, forKey: .city)
        region = try? container.decodeIfPresent(String.self, forKey: .region)
        address = try? container.decodeIfPresent(String.self, forKey: .address)
        cost = try? container.decodeIfPresent(String.self, forKey: .cost)
        tags = try? container.decodeIfPresent([String].self, forKey: .tags)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(organization, forKey: .organization)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(cost, forKey: .cost)
        try container.encodeIfPresent(tags, forKey: .tags)
    }

    var hasContent: Bool {
        [
            title,
            organization,
            description,
            summary,
            category,
            city,
            region,
            address,
            cost
        ].contains { Self.nonEmpty($0) != nil } || tags?.contains { Self.nonEmpty($0) != nil } == true
    }

    func merged(with fallback: OpportunityTranslation?) -> OpportunityTranslation {
        guard let fallback else { return self }
        let mergedTags = Self.nonEmptyList(tags) ?? Self.nonEmptyList(fallback.tags)
        return OpportunityTranslation(
            title: Self.preferredValue(title, fallback: fallback.title),
            organization: Self.preferredValue(organization, fallback: fallback.organization),
            description: Self.preferredValue(description, fallback: fallback.description),
            summary: Self.preferredValue(summary, fallback: fallback.summary),
            category: Self.preferredValue(category, fallback: fallback.category),
            city: Self.preferredValue(city, fallback: fallback.city),
            region: Self.preferredValue(region, fallback: fallback.region),
            address: Self.preferredValue(address, fallback: fallback.address),
            cost: Self.preferredValue(cost, fallback: fallback.cost),
            tags: mergedTags
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func preferredValue(_ value: String?, fallback: String?) -> String? {
        if let preferred = nonEmpty(value) {
            return preferred
        }
        return nonEmpty(fallback)
    }

    private static func nonEmptyList(_ values: [String]?) -> [String]? {
        let cleaned = values?.compactMap(nonEmpty)
        return (cleaned?.isEmpty == false) ? cleaned : nil
    }
}

struct Opportunity: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let organization: String
    let description: String
    let summary: String?
    let category: String
    let city: String
    let region: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let startDate: String?
    let endDate: String?
    let deadline: String?
    let ageMin: Int
    let ageMax: Int?
    let language: [String]
    let cost: String
    let sourceUrl: String
    let registrationUrl: String?
    let status: String
    let volunteerHoursEligible: Bool
    let coopEligible: Bool
    let tags: [String]
    let distanceKm: Double?
    let isNewFind: Bool?
    let sourceConfidence: String?
    let translations: [String: OpportunityTranslation]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case organization
        case provider
        case description
        case summary
        case category
        case categories
        case city
        case region
        case address
        case latitude
        case longitude
        case startDate
        case endDate
        case deadline
        case ageMin
        case ageMax
        case ages
        case language
        case languages
        case cost
        case sourceUrl
        case registrationUrl
        case status
        case volunteerHoursEligible
        case coopEligible
        case tags
        case distanceKm
        case isNewFind
        case sourceConfidence
        case translations
        case localizations
        case localized
    }

    private enum AgeKeys: String, CodingKey {
        case min
        case max
    }

    init(
        id: String,
        title: String,
        organization: String,
        description: String,
        summary: String?,
        category: String,
        city: String,
        region: String,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        startDate: String?,
        endDate: String?,
        deadline: String?,
        ageMin: Int,
        ageMax: Int?,
        language: [String],
        cost: String,
        sourceUrl: String,
        registrationUrl: String?,
        status: String,
        volunteerHoursEligible: Bool,
        coopEligible: Bool,
        tags: [String],
        distanceKm: Double?,
        isNewFind: Bool?,
        sourceConfidence: String?,
        translations: [String: OpportunityTranslation] = [:]
    ) {
        self.id = id
        self.title = title
        self.organization = organization
        self.description = description
        self.summary = summary
        self.category = category
        self.city = city
        self.region = region
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.startDate = startDate
        self.endDate = endDate
        self.deadline = deadline
        self.ageMin = ageMin
        self.ageMax = ageMax
        self.language = language
        self.cost = cost
        self.sourceUrl = sourceUrl
        self.registrationUrl = registrationUrl
        self.status = status
        self.volunteerHoursEligible = volunteerHoursEligible
        self.coopEligible = coopEligible
        self.tags = tags
        self.distanceKm = distanceKm
        self.isNewFind = isNewFind
        self.sourceConfidence = sourceConfidence
        self.translations = Self.normalizedTranslations(translations)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let categories = (try? container.decode([String].self, forKey: .categories)) ?? []
        let fallbackSummary = try? container.decode(String.self, forKey: .summary)

        var decodedAgeMin = (try? container.decode(Int.self, forKey: .ageMin)) ?? 0
        var decodedAgeMax = try? container.decodeIfPresent(Int.self, forKey: .ageMax)
        if let ages = try? container.nestedContainer(keyedBy: AgeKeys.self, forKey: .ages) {
            decodedAgeMin = (try? ages.decode(Int.self, forKey: .min)) ?? decodedAgeMin
            decodedAgeMax = (try? ages.decodeIfPresent(Int.self, forKey: .max)) ?? decodedAgeMax
        }

        let decodedTitle = try container.decode(String.self, forKey: .title)
        let decodedOrganization =
            (try? container.decode(String.self, forKey: .organization)) ??
            (try? container.decode(String.self, forKey: .provider)) ??
            "Community provider"
        let decodedDescription =
            (try? container.decode(String.self, forKey: .description)) ??
            fallbackSummary ??
            decodedTitle
        let decodedCategory =
            (try? container.decode(String.self, forKey: .category)) ??
            categories.first ??
            "STEM"
        let decodedLanguage =
            (try? container.decode([String].self, forKey: .language)) ??
            (try? container.decode([String].self, forKey: .languages)) ??
            ["en"]
        let decodedSourceURL =
            (try? container.decode(String.self, forKey: .sourceUrl)) ??
            (try? container.decode(String.self, forKey: .registrationUrl)) ??
            ""
        let decodedTranslations =
            (try? container.decode([String: OpportunityTranslation].self, forKey: .translations)) ??
            (try? container.decode([String: OpportunityTranslation].self, forKey: .localizations)) ??
            (try? container.decode([String: OpportunityTranslation].self, forKey: .localized)) ??
            [:]

        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: decodedTitle,
            organization: decodedOrganization,
            description: decodedDescription,
            summary: fallbackSummary,
            category: decodedCategory,
            city: (try? container.decode(String.self, forKey: .city)) ?? "GTA",
            region: (try? container.decode(String.self, forKey: .region)) ?? "All",
            address: try? container.decodeIfPresent(String.self, forKey: .address),
            latitude: try? container.decodeIfPresent(Double.self, forKey: .latitude),
            longitude: try? container.decodeIfPresent(Double.self, forKey: .longitude),
            startDate: try? container.decodeIfPresent(String.self, forKey: .startDate),
            endDate: try? container.decodeIfPresent(String.self, forKey: .endDate),
            deadline: try? container.decodeIfPresent(String.self, forKey: .deadline),
            ageMin: decodedAgeMin,
            ageMax: decodedAgeMax,
            language: decodedLanguage,
            cost: (try? container.decode(String.self, forKey: .cost)) ?? "Free",
            sourceUrl: decodedSourceURL,
            registrationUrl: try? container.decodeIfPresent(String.self, forKey: .registrationUrl),
            status: (try? container.decode(String.self, forKey: .status)) ?? "active",
            volunteerHoursEligible: (try? container.decode(Bool.self, forKey: .volunteerHoursEligible)) ?? false,
            coopEligible: (try? container.decode(Bool.self, forKey: .coopEligible)) ?? false,
            tags: (try? container.decode([String].self, forKey: .tags)) ?? categories,
            distanceKm: try? container.decodeIfPresent(Double.self, forKey: .distanceKm),
            isNewFind: try? container.decodeIfPresent(Bool.self, forKey: .isNewFind),
            sourceConfidence: try? container.decodeIfPresent(String.self, forKey: .sourceConfidence),
            translations: decodedTranslations
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(organization, forKey: .organization)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(category, forKey: .category)
        try container.encode(city, forKey: .city)
        try container.encode(region, forKey: .region)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encodeIfPresent(deadline, forKey: .deadline)
        try container.encode(ageMin, forKey: .ageMin)
        try container.encodeIfPresent(ageMax, forKey: .ageMax)
        try container.encode(language, forKey: .language)
        try container.encode(cost, forKey: .cost)
        try container.encode(sourceUrl, forKey: .sourceUrl)
        try container.encodeIfPresent(registrationUrl, forKey: .registrationUrl)
        try container.encode(status, forKey: .status)
        try container.encode(volunteerHoursEligible, forKey: .volunteerHoursEligible)
        try container.encode(coopEligible, forKey: .coopEligible)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(distanceKm, forKey: .distanceKm)
        try container.encodeIfPresent(isNewFind, forKey: .isNewFind)
        try container.encodeIfPresent(sourceConfidence, forKey: .sourceConfidence)
        if !translations.isEmpty {
            try container.encode(translations, forKey: .translations)
        }
    }

    func translation(for language: AppLanguage) -> OpportunityTranslation? {
        let candidates = [
            language.rawValue,
            language.localeIdentifier,
            language.localeIdentifier.lowercased()
        ]
        for candidate in candidates {
            if let translation = translations[candidate], translation.hasContent {
                return translation
            }
        }

        return translations.first { AppLanguage.normalized($0.key) == language && $0.value.hasContent }?.value
    }

    func hasTranslation(for language: AppLanguage) -> Bool {
        translation(for: language) != nil
    }

    func localizedTitle(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.title], fallback: title)
    }

    func localizedOrganization(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.organization], fallback: organization)
    }

    func localizedDescription(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.description], fallback: description)
    }

    func localizedSummary(language: AppLanguage) -> String {
        let selectedTranslation = translation(for: language)
        let resolvedSummary = Self.localizedValue(
            [selectedTranslation?.summary, selectedTranslation?.description, summary, description],
            fallback: description
        )
        guard language != .en else { return resolvedSummary }
        guard selectedTranslation == nil else { return resolvedSummary }
        return localizedTemplateSummary(
            baseSummary: resolvedSummary,
            category: localizedCategoryName(language: language),
            provider: localizedOrganization(language: language),
            city: localizedCity(language: language),
            language: language,
            ages: ageMax.map { "\(ageMin)-\($0)" } ?? "\(ageMin)+"
        )
    }

    func localizedCategory(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.category], fallback: category)
    }

    func localizedCity(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.city], fallback: city)
    }

    func localizedRegion(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.region], fallback: region)
    }

    func localizedAddress(language: AppLanguage) -> String? {
        Self.localizedValue([translation(for: language)?.address, address])
    }

    func localizedCost(language: AppLanguage) -> String {
        Self.localizedValue([translation(for: language)?.cost], fallback: cost)
    }

    func localizedTags(language: AppLanguage) -> [String] {
        let translatedTags = translation(for: language)?.tags?.compactMap(Self.nonEmpty) ?? []
        return translatedTags.isEmpty ? tags : translatedTags
    }

    private static func normalizedTranslations(_ translations: [String: OpportunityTranslation]) -> [String: OpportunityTranslation] {
        translations.reduce(into: [String: OpportunityTranslation]()) { result, pair in
            guard pair.value.hasContent else { return }
            let trimmedKey = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { return }
            result[trimmedKey] = pair.value
            result[AppLanguage.normalized(trimmedKey).rawValue] = pair.value
        }
    }

    private func localizedTemplateSummary(
        baseSummary: String,
        category: String,
        provider: String,
        city: String,
        language: AppLanguage,
        ages: String
    ) -> String {
        let template = AppText.shared.string("summaryTemplate", language: language)
        guard template != "summaryTemplate" else { return baseSummary }
        let resolved = template
            .replacingOccurrences(of: "{summary}", with: baseSummary)
            .replacingOccurrences(of: "{category}", with: category)
            .replacingOccurrences(of: "{provider}", with: provider)
            .replacingOccurrences(of: "{city}", with: city)
            .replacingOccurrences(of: "{ages}", with: ages)
        return resolved.contains(baseSummary) ? resolved : "\(resolved)\n\(baseSummary)"
    }

    private func localizedCategoryName(language: AppLanguage) -> String {
        let key = "category" +
            category
            .replacingOccurrences(of: "&", with: "And")
            .replacingOccurrences(of: "/", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
        let localized = AppText.shared.string(key, language: language)
        return localized == key ? category : localized
    }

    private static func localizedValue(_ values: [String?], fallback: String) -> String {
        localizedValue(values) ?? fallback
    }

    private static func localizedValue(_ values: [String?]) -> String? {
        values.lazy.compactMap(nonEmpty).first
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct OpportunityListResponse: Codable {
    struct Metadata: Codable {
        let activeCount: Int?
        let lastUpdated: String?
    }

    let data: [Opportunity]
    let meta: Metadata?

    private enum CodingKeys: String, CodingKey {
        case data
        case opportunities
        case meta
        case count
        case lastDataChange
    }

    init(data: [Opportunity], meta: Metadata?) {
        self.data = data
        self.meta = meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedData =
            (try? container.decode([Opportunity].self, forKey: .data)) ??
            (try? container.decode([Opportunity].self, forKey: .opportunities)) ??
            []
        let decodedMeta = try? container.decode(Metadata.self, forKey: .meta)
        let feedCount = try? container.decode(Int.self, forKey: .count)
        let feedUpdated = try? container.decode(String.self, forKey: .lastDataChange)

        data = decodedData
        meta = decodedMeta ?? Metadata(
            activeCount: feedCount ?? decodedData.count,
            lastUpdated: feedUpdated
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(meta, forKey: .meta)
    }
}

struct OpportunityResponse: Codable {
    let data: Opportunity
}

struct APIStatusResponse: Codable {
    struct Payload: Codable {
        let id: Int?
        let status: String?
        let deleted: Bool?
    }

    let data: Payload
}

@Model
final class OpportunityCacheRecord {
    @Attribute(.unique) var cacheKey: String
    var payload: Data
    var updatedAt: Date

    init(cacheKey: String, payload: Data, updatedAt: Date = .now) {
        self.cacheKey = cacheKey
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class SavedHuntRecord {
    @Attribute(.unique) var cacheKey: String
    var query: String
    var modeRawValue: String
    var region: String
    var city: String
    var category: String
    var age: String
    var language: String
    var latitude: Double?
    var longitude: Double?
    var distanceKm: Double
    var sortRawValue: String
    var includeNewFinds: Bool = true
    var volunteerHours: Bool = false
    var coop: Bool = false
    var mentorship: Bool = false
    var scholarships: Bool = false
    var blackFocused: Bool = false
    var girlsFocused: Bool = false
    var indigenousFocused: Bool = false
    var leadership: Bool = false
    var updatedAt: Date

    init(cacheKey: String, query: String, mode: SearchMode, filters: OpportunityFilters, updatedAt: Date = .now) {
        self.cacheKey = cacheKey
        self.query = query
        self.modeRawValue = mode.rawValue
        self.region = filters.region
        self.city = filters.city
        self.category = filters.category
        self.age = filters.age
        self.language = filters.language
        self.latitude = filters.latitude
        self.longitude = filters.longitude
        self.distanceKm = filters.distanceKm
        self.sortRawValue = filters.sort.rawValue
        self.includeNewFinds = filters.includeNewFinds
        self.volunteerHours = filters.volunteerHours
        self.coop = filters.coop
        self.mentorship = filters.mentorship
        self.scholarships = filters.scholarships
        self.blackFocused = filters.blackFocused
        self.girlsFocused = filters.girlsFocused
        self.indigenousFocused = filters.indigenousFocused
        self.leadership = filters.leadership
        self.updatedAt = updatedAt
    }
}

@Model
final class SeenOpportunityRecord {
    @Attribute(.unique) var opportunityID: String
    var firstSeenAt: Date
    var lastSeenAt: Date

    init(opportunityID: String, firstSeenAt: Date = .now, lastSeenAt: Date = .now) {
        self.opportunityID = opportunityID
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }
}

struct FeedbackDraft {
    var name = ""
    var email = ""
    var message = ""
}

struct MissingOpportunityDraft {
    var title = ""
    var organization = ""
    var city = ""
    var sourceURL = ""
    var notes = ""
}

enum SearchMode: String, CaseIterable, Identifiable {
    case all = "All"
    case highSchool = "High School"
    case volunteer = "Volunteer Hours"
    case coop = "Co-op / SHSM"
    case mentorship = "Mentorship"

    var id: String { rawValue }

    var textKey: String {
        switch self {
        case .all: "all"
        case .highSchool: "highSchool"
        case .volunteer: "volunteerHours"
        case .coop: "coop"
        case .mentorship: "mentorship"
        }
    }
}

enum SearchSort: String, CaseIterable, Identifiable {
    case date
    case distance
    case relevance

    var id: String { rawValue }

    var textKey: String {
        switch self {
        case .date: "sortSoonest"
        case .distance: "sortNearest"
        case .relevance: "sortBestMatch"
        }
    }
}

struct OpportunityFilters: Equatable {
    var region = "All"
    var city = ""
    var category = "All"
    var age = ""
    var language = "all"
    var latitude: Double?
    var longitude: Double?
    var distanceKm = 25.0
    var sort = SearchSort.date
    var includeNewFinds = true
    var volunteerHours = false
    var coop = false
    var mentorship = false
    var scholarships = false
    var blackFocused = false
    var girlsFocused = false
    var indigenousFocused = false
    var leadership = false

    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    var hasActiveFilters: Bool {
        region != "All" ||
            !city.isEmpty ||
            category != "All" ||
            !age.isEmpty ||
            language != "all" ||
            hasLocation ||
            sort != .date ||
            !includeNewFinds ||
            volunteerHours ||
            coop ||
            mentorship ||
            scholarships ||
            blackFocused ||
            girlsFocused ||
            indigenousFocused ||
            leadership
    }
}

enum OpportunityMapProjection {
    static func pins(from opportunities: [Opportunity]) -> [Opportunity] {
        opportunities.filter { $0.latitude != nil && $0.longitude != nil }
    }
}

enum BrowseDisplayMode: String, CaseIterable, Identifiable {
    case list
    case map

    var id: String { rawValue }

    var textKey: String {
        switch self {
        case .list: "list"
        case .map: "map"
        }
    }
}
