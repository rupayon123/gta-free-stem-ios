import Foundation
import SwiftData

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
        sourceConfidence: String?
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
            sourceConfidence: try? container.decodeIfPresent(String.self, forKey: .sourceConfidence)
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
            blackFocused ||
            girlsFocused ||
            indigenousFocused ||
            leadership
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
